// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// MINIMAL MOCK CONTRACTS FOR TESTING
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @notice Mock ERC20 token for fee testing
 */
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @notice Mock ERC721 NFT collection for testing
 */
contract MockERC721 {
    string public name = "Mock NFT";
    string public symbol = "MNFT";
    
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) public balanceOf;
    
    // Track which tokens are burned (for testing burned NFT handling)
    mapping(uint256 => bool) public burned;
    
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    
    function mint(address to, uint256 tokenId) external {
        require(_owners[tokenId] == address(0), "already minted");
        _owners[tokenId] = to;
        balanceOf[to]++;
        emit Transfer(address(0), to, tokenId);
    }
    
    function burn(uint256 tokenId) external {
        address owner = _owners[tokenId];
        require(owner != address(0), "not minted");
        burned[tokenId] = true;
        delete _owners[tokenId];
        balanceOf[owner]--;
        emit Transfer(owner, address(0), tokenId);
    }
    
    function ownerOf(uint256 tokenId) external view returns (address) {
        if (burned[tokenId]) {
            revert("ERC721: invalid token ID");
        }
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }
    
    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_owners[tokenId] == from, "not owner");
        _owners[tokenId] = to;
        balanceOf[from]--;
        balanceOf[to]++;
        emit Transfer(from, to, tokenId);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INLINE FEEDISTRIBUTOR (to avoid import path issues in test environment)
// ═══════════════════════════════════════════════════════════════════════════════

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/**
 * @title FeeDistributor
 * @notice Distributes trading fees to NFT holders (inline version for testing)
 */
contract FeeDistributor {
    uint256 public constant TREASURY_BPS = 2000;      // 20%
    uint256 public constant NFT_HOLDERS_BPS = 8000;   // 80%
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant PRECISION = 1e18;

    address public treasury;
    address public lpLocker;
    address public factory;
    address public owner;

    mapping(address token => address nftCollection) public tokenToCollection;
    mapping(address token => uint256 totalSupply) public tokenToNftSupply;
    mapping(address token => address feeToken) public tokenToFeeToken;
    mapping(address token => uint256 accRewardPerNFT) public accumulatedRewards;
    mapping(address token => mapping(uint256 tokenId => uint256 lastClaimed)) public claimed;
    mapping(address feeToken => uint256 totalOwed) public totalOwed;

    // Reentrancy guard
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "ReentrancyGuard: reentrant call");
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    event FeesReceived(address indexed token, address indexed feeToken, uint256 totalAmount, uint256 treasuryAmount, uint256 nftHoldersAmount, uint256 newAccRewardPerNFT);
    event RewardsClaimed(address indexed token, address indexed claimer, uint256[] tokenIds, uint256 totalReward);
    event TokenIdSkipped(address indexed token, uint256 indexed tokenId, string reason);
    event TokenRegistered(address indexed token, address indexed nftCollection, address indexed feeToken, uint256 nftSupply);

    error ZeroAddress();
    error ZeroAmount();
    error NotAuthorized();
    error TokenNotRegistered();
    error TokenAlreadyRegistered();
    error NoRewardsToClaim();
    error InvalidNftSupply();
    error EmptyTokenIds();
    error FeeTokenMismatch();
    error InsufficientExcessBalance();

    constructor(address _treasury, address _lpLocker, address _factory, address _owner) {
        require(_treasury != address(0) && _lpLocker != address(0) && _factory != address(0), "zero address");
        treasury = _treasury;
        lpLocker = _lpLocker;
        factory = _factory;
        owner = _owner;
    }

    function receiveFees(address token, address feeToken, uint256 amount) external nonReentrant {
        if (msg.sender != lpLocker) revert NotAuthorized();
        if (amount == 0) revert ZeroAmount();
        if (tokenToCollection[token] == address(0)) revert TokenNotRegistered();
        if (feeToken != tokenToFeeToken[token]) revert FeeTokenMismatch();
        
        IERC20(feeToken).transferFrom(msg.sender, address(this), amount);
        
        uint256 treasuryAmount = (amount * TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 nftHoldersAmount = amount - treasuryAmount;
        
        IERC20(feeToken).transfer(treasury, treasuryAmount);
        
        totalOwed[feeToken] += nftHoldersAmount;
        
        uint256 nftSupply = tokenToNftSupply[token];
        uint256 rewardPerNFT = (nftHoldersAmount * PRECISION) / nftSupply;
        accumulatedRewards[token] += rewardPerNFT;
        
        emit FeesReceived(token, feeToken, amount, treasuryAmount, nftHoldersAmount, accumulatedRewards[token]);
    }

    function claim(address token, uint256[] calldata tokenIds) external nonReentrant {
        if (tokenIds.length == 0) revert EmptyTokenIds();
        if (tokenToCollection[token] == address(0)) revert TokenNotRegistered();
        
        address nftCollection = tokenToCollection[token];
        address feeToken = tokenToFeeToken[token];
        uint256 currentAcc = accumulatedRewards[token];
        uint256 totalReward = 0;
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            
            address tokenOwner;
            try IERC721(nftCollection).ownerOf(tokenId) returns (address _owner) {
                tokenOwner = _owner;
            } catch {
                emit TokenIdSkipped(token, tokenId, "ownerOf reverted");
                continue;
            }
            
            if (tokenOwner != msg.sender) {
                emit TokenIdSkipped(token, tokenId, "not owner");
                continue;
            }
            
            uint256 lastClaimed = claimed[token][tokenId];
            uint256 reward = (currentAcc - lastClaimed) / PRECISION;
            
            if (reward > 0) {
                claimed[token][tokenId] = currentAcc;
                totalReward += reward;
            }
        }
        
        if (totalReward == 0) revert NoRewardsToClaim();
        
        totalOwed[feeToken] -= totalReward;
        IERC20(feeToken).transfer(msg.sender, totalReward);
        
        emit RewardsClaimed(token, msg.sender, tokenIds, totalReward);
    }

    function claimable(address token, uint256 tokenId) external view returns (uint256) {
        if (tokenToCollection[token] == address(0)) return 0;
        return (accumulatedRewards[token] - claimed[token][tokenId]) / PRECISION;
    }

    function claimableMultiple(address token, uint256[] calldata tokenIds) external view returns (uint256 total) {
        if (tokenToCollection[token] == address(0)) return 0;
        uint256 currentAcc = accumulatedRewards[token];
        for (uint256 i = 0; i < tokenIds.length; i++) {
            total += (currentAcc - claimed[token][tokenIds[i]]) / PRECISION;
        }
    }

    function registerToken(address token, address nftCollection, address feeToken, uint256 nftSupply) external {
        if (msg.sender != factory) revert NotAuthorized();
        if (token == address(0) || nftCollection == address(0) || feeToken == address(0)) revert ZeroAddress();
        if (nftSupply == 0) revert InvalidNftSupply();
        if (tokenToCollection[token] != address(0)) revert TokenAlreadyRegistered();
        
        tokenToCollection[token] = nftCollection;
        tokenToFeeToken[token] = feeToken;
        tokenToNftSupply[token] = nftSupply;
        
        emit TokenRegistered(token, nftCollection, feeToken, nftSupply);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "zero address");
        treasury = _treasury;
    }

    function setLpLocker(address _lpLocker) external onlyOwner {
        require(_lpLocker != address(0), "zero address");
        lpLocker = _lpLocker;
    }
    
    function setFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "zero address");
        factory = _factory;
    }

    function rescueTokens(address _feeToken, address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "zero address");
        
        uint256 balance = IERC20(_feeToken).balanceOf(address(this));
        uint256 owed = totalOwed[_feeToken];
        uint256 excess = balance > owed ? balance - owed : 0;
        
        if (_amount > excess) revert InsufficientExcessBalance();
        
        IERC20(_feeToken).transfer(_to, _amount);
    }
    
    function rescuableBalance(address _feeToken) external view returns (uint256) {
        uint256 balance = IERC20(_feeToken).balanceOf(address(this));
        uint256 owed = totalOwed[_feeToken];
        return balance > owed ? balance - owed : 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

contract FeeDistributorTest is Test {
    FeeDistributor public distributor;
    MockERC20 public feeToken;
    MockERC721 public nftCollection;
    MockERC20 public strategyToken;
    
    address public treasury = address(0x1111);
    address public lpLocker;
    address public factory;
    address public owner = address(0x4444);
    
    address public nftHolder1 = address(0xA001);
    address public nftHolder2 = address(0xA002);
    address public randomUser = address(0xB001);
    
    uint256 constant NFT_SUPPLY = 100;
    
    function setUp() public {
        lpLocker = address(this); // Use test contract as lpLocker for easy testing
        factory = address(this);  // Use test contract as factory for registration
        
        // Deploy contracts
        feeToken = new MockERC20();
        nftCollection = new MockERC721();
        strategyToken = new MockERC20();
        
        distributor = new FeeDistributor(treasury, lpLocker, factory, owner);
        
        // Mint NFTs to holders
        for (uint256 i = 1; i <= 10; i++) {
            nftCollection.mint(nftHolder1, i);
        }
        for (uint256 i = 11; i <= 20; i++) {
            nftCollection.mint(nftHolder2, i);
        }
        
        // Register the strategy token
        distributor.registerToken(
            address(strategyToken),
            address(nftCollection),
            address(feeToken),
            NFT_SUPPLY
        );
        
        // Mint fee tokens to lpLocker for distributing
        feeToken.mint(lpLocker, 1_000_000 ether);
        feeToken.approve(address(distributor), type(uint256).max);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // receiveFees Tests
    // ═══════════════════════════════════════════════════════════════════════════
    
    function test_receiveFees_splits20_80() public {
        uint256 amount = 1000 ether;
        uint256 expectedTreasury = 200 ether;  // 20%
        uint256 expectedNftHolders = 800 ether; // 80%
        
        uint256 treasuryBefore = feeToken.balanceOf(treasury);
        
        distributor.receiveFees(address(strategyToken), address(feeToken), amount);
        
        uint256 treasuryAfter = feeToken.balanceOf(treasury);
        
        // Check treasury got 20%
        assertEq(treasuryAfter - treasuryBefore, expectedTreasury, "Treasury should receive 20%");
        
        // Check distributor holds 80% for NFT holders
        assertEq(feeToken.balanceOf(address(distributor)), expectedNftHolders, "Distributor should hold 80%");
        
        // Check totalOwed tracking
        assertEq(distributor.totalOwed(address(feeToken)), expectedNftHolders, "totalOwed should track NFT portion");
        
        // Check accumulatedRewards updated correctly
        // 800 ether / 100 NFTs = 8 ether per NFT
        // Stored with PRECISION (1e18), so 8 ether * 1e18 = 8e36
        uint256 expectedAccReward = (expectedNftHolders * 1e18) / NFT_SUPPLY;
        assertEq(distributor.accumulatedRewards(address(strategyToken)), expectedAccReward, "accumulatedRewards should be correct");
    }
    
    function test_receiveFees_onlyLpLocker() public {
        vm.prank(randomUser);
        vm.expectRevert(FeeDistributor.NotAuthorized.selector);
        distributor.receiveFees(address(strategyToken), address(feeToken), 100 ether);
    }
    
    function test_receiveFees_revertsZeroAmount() public {
        vm.expectRevert(FeeDistributor.ZeroAmount.selector);
        distributor.receiveFees(address(strategyToken), address(feeToken), 0);
    }
    
    function test_receiveFees_revertsUnregisteredToken() public {
        address fakeToken = address(0x9999);
        vm.expectRevert(FeeDistributor.TokenNotRegistered.selector);
        distributor.receiveFees(fakeToken, address(feeToken), 100 ether);
    }
    
    function test_receiveFees_revertsFeeTokenMismatch() public {
        MockERC20 wrongFeeToken = new MockERC20();
        vm.expectRevert(FeeDistributor.FeeTokenMismatch.selector);
        distributor.receiveFees(address(strategyToken), address(wrongFeeToken), 100 ether);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // claim Tests
    // ═══════════════════════════════════════════════════════════════════════════
    
    function test_claim_singleNFT() public {
        // Distribute some fees first
        distributor.receiveFees(address(strategyToken), address(feeToken), 1000 ether);
        
        // Each NFT should be able to claim: 800 ether / 100 = 8 ether
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        
        uint256 balanceBefore = feeToken.balanceOf(nftHolder1);
        
        vm.prank(nftHolder1);
        distributor.claim(address(strategyToken), tokenIds);
        
        uint256 balanceAfter = feeToken.balanceOf(nftHolder1);
        assertEq(balanceAfter - balanceBefore, 8 ether, "Should claim 8 ether for 1 NFT");
    }
    
    function test_claim_batchNFTs() public {
        // Distribute some fees
        distributor.receiveFees(address(strategyToken), address(feeToken), 1000 ether);
        
        // holder1 has NFTs 1-10 (10 NFTs)
        // Each gets 8 ether, so batch should get 80 ether
        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            tokenIds[i] = i + 1;
        }
        
        uint256 balanceBefore = feeToken.balanceOf(nftHolder1);
        
        vm.prank(nftHolder1);
        distributor.claim(address(strategyToken), tokenIds);
        
        uint256 balanceAfter = feeToken.balanceOf(nftHolder1);
        assertEq(balanceAfter - balanceBefore, 80 ether, "Should claim 80 ether for 10 NFTs");
    }
    
    function test_claim_burnedNFT_skipped() public {
        // Distribute fees
        distributor.receiveFees(address(strategyToken), address(feeToken), 1000 ether);
        
        // Burn NFT #1
        nftCollection.burn(1);
        
        // Try to claim for NFTs 1-3 (1 is burned)
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1; // burned
        tokenIds[1] = 2; // valid
        tokenIds[2] = 3; // valid
        
        uint256 balanceBefore = feeToken.balanceOf(nftHolder1);
        
        vm.prank(nftHolder1);
        distributor.claim(address(strategyToken), tokenIds);
        
        uint256 balanceAfter = feeToken.balanceOf(nftHolder1);
        // Should only claim for 2 valid NFTs: 2 * 8 = 16 ether
        assertEq(balanceAfter - balanceBefore, 16 ether, "Should claim 16 ether for 2 valid NFTs");
    }
    
    function test_claim_notOwner_skipped() public {
        // Distribute fees
        distributor.receiveFees(address(strategyToken), address(feeToken), 1000 ether);
        
        // holder1 tries to claim NFT #11 (owned by holder2)
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;  // owned by holder1
        tokenIds[1] = 11; // owned by holder2 - should be skipped
        
        uint256 balanceBefore = feeToken.balanceOf(nftHolder1);
        
        vm.prank(nftHolder1);
        distributor.claim(address(strategyToken), tokenIds);
        
        uint256 balanceAfter = feeToken.balanceOf(nftHolder1);
        // Should only claim for 1 owned NFT: 8 ether
        assertEq(balanceAfter - balanceBefore, 8 ether, "Should claim 8 ether for 1 owned NFT");
    }
    
    function test_claim_noRewards_reverts() public {
        // Try to claim without any fees being distributed
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        
        vm.prank(nftHolder1);
        vm.expectRevert(FeeDistributor.NoRewardsToClaim.selector);
        distributor.claim(address(strategyToken), tokenIds);
    }
    
    function test_claim_alreadyClaimed_reverts() public {
        // Distribute fees
        distributor.receiveFees(address(strategyToken), address(feeToken), 1000 ether);
        
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        
        // First claim works
        vm.prank(nftHolder1);
        distributor.claim(address(strategyToken), tokenIds);
        
        // Second claim should revert (no new rewards)
        vm.prank(nftHolder1);
        vm.expectRevert(FeeDistributor.NoRewardsToClaim.selector);
        distributor.claim(address(strategyToken), tokenIds);
    }
    
    function test_claim_emptyTokenIds_reverts() public {
        uint256[] memory tokenIds = new uint256[](0);
        
        vm.prank(nftHolder1);
        vm.expectRevert(FeeDistributor.EmptyTokenIds.selector);
        distributor.claim(address(strategyToken), tokenIds);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // registerToken Tests
    // ═══════════════════════════════════════════════════════════════════════════
    
    function test_registerToken_onlyFactory() public {
        MockERC20 newToken = new MockERC20();
        MockERC721 newNft = new MockERC721();
        
        vm.prank(randomUser);
        vm.expectRevert(FeeDistributor.NotAuthorized.selector);
        distributor.registerToken(address(newToken), address(newNft), address(feeToken), 1000);
    }
    
    function test_registerToken_success() public {
        MockERC20 newToken = new MockERC20();
        MockERC721 newNft = new MockERC721();
        
        distributor.registerToken(address(newToken), address(newNft), address(feeToken), 500);
        
        assertEq(distributor.tokenToCollection(address(newToken)), address(newNft));
        assertEq(distributor.tokenToFeeToken(address(newToken)), address(feeToken));
        assertEq(distributor.tokenToNftSupply(address(newToken)), 500);
    }
    
    function test_registerToken_alreadyRegistered_reverts() public {
        // strategyToken is already registered in setUp
        vm.expectRevert(FeeDistributor.TokenAlreadyRegistered.selector);
        distributor.registerToken(address(strategyToken), address(nftCollection), address(feeToken), NFT_SUPPLY);
    }
    
    function test_registerToken_zeroSupply_reverts() public {
        MockERC20 newToken = new MockERC20();
        MockERC721 newNft = new MockERC721();
        
        vm.expectRevert(FeeDistributor.InvalidNftSupply.selector);
        distributor.registerToken(address(newToken), address(newNft), address(feeToken), 0);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // rescueTokens Tests
    // ═══════════════════════════════════════════════════════════════════════════
    
    function test_rescueTokens_onlyExcess() public {
        // Distribute fees (800 ether owed to NFT holders)
        distributor.receiveFees(address(strategyToken), address(feeToken), 1000 ether);
        
        // Send extra tokens directly to distributor (simulating accidental transfer)
        feeToken.mint(address(distributor), 50 ether);
        
        // Now distributor has 850 ether total, but only 800 is owed
        // Excess is 50 ether
        
        assertEq(distributor.rescuableBalance(address(feeToken)), 50 ether, "Should have 50 ether rescuable");
        
        // Owner should be able to rescue the excess
        vm.prank(owner);
        distributor.rescueTokens(address(feeToken), owner, 50 ether);
        
        assertEq(feeToken.balanceOf(owner), 50 ether, "Owner should receive rescued tokens");
    }
    
    function test_rescueTokens_cannotRescueOwed() public {
        // Distribute fees (800 ether owed to NFT holders)
        distributor.receiveFees(address(strategyToken), address(feeToken), 1000 ether);
        
        // No excess tokens - all 800 is owed
        assertEq(distributor.rescuableBalance(address(feeToken)), 0, "Should have 0 rescuable");
        
        // Try to rescue more than excess (which is 0)
        vm.prank(owner);
        vm.expectRevert(FeeDistributor.InsufficientExcessBalance.selector);
        distributor.rescueTokens(address(feeToken), owner, 1 ether);
    }
    
    function test_rescueTokens_onlyOwner() public {
        feeToken.mint(address(distributor), 50 ether);
        
        vm.prank(randomUser);
        vm.expectRevert("not owner");
        distributor.rescueTokens(address(feeToken), randomUser, 50 ether);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // View Function Tests
    // ═══════════════════════════════════════════════════════════════════════════
    
    function test_claimable_returnsCorrectAmount() public {
        distributor.receiveFees(address(strategyToken), address(feeToken), 1000 ether);
        
        // Each NFT should have 8 ether claimable
        assertEq(distributor.claimable(address(strategyToken), 1), 8 ether);
        assertEq(distributor.claimable(address(strategyToken), 50), 8 ether);
    }
    
    function test_claimableMultiple_returnsCorrectSum() public {
        distributor.receiveFees(address(strategyToken), address(feeToken), 1000 ether);
        
        uint256[] memory tokenIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            tokenIds[i] = i + 1;
        }
        
        // 5 NFTs * 8 ether = 40 ether
        assertEq(distributor.claimableMultiple(address(strategyToken), tokenIds), 40 ether);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // Multi-round Claiming Tests
    // ═══════════════════════════════════════════════════════════════════════════
    
    function test_multiRound_accumulatesCorrectly() public {
        // Round 1: 1000 ether (800 for NFTs, 8 each)
        distributor.receiveFees(address(strategyToken), address(feeToken), 1000 ether);
        
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        
        // Claim round 1
        vm.prank(nftHolder1);
        distributor.claim(address(strategyToken), tokenIds);
        assertEq(feeToken.balanceOf(nftHolder1), 8 ether);
        
        // Round 2: Another 500 ether (400 for NFTs, 4 each)
        distributor.receiveFees(address(strategyToken), address(feeToken), 500 ether);
        
        // NFT #1 should now have 4 ether claimable
        assertEq(distributor.claimable(address(strategyToken), 1), 4 ether);
        
        // NFT #2 should have 8 + 4 = 12 ether claimable (never claimed)
        assertEq(distributor.claimable(address(strategyToken), 2), 12 ether);
        
        // Claim for NFT #1 again
        vm.prank(nftHolder1);
        distributor.claim(address(strategyToken), tokenIds);
        assertEq(feeToken.balanceOf(nftHolder1), 12 ether); // 8 + 4
    }
}
