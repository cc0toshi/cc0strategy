// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// MINIMAL MOCKS FOR LPLOCKER TESTING
// ═══════════════════════════════════════════════════════════════════════════════

contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        if (allowance[from][msg.sender] < type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "insufficient allowance");
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function forceApprove(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/**
 * @notice Mock FeeDistributor to track calls from LpLocker
 */
contract MockFeeDistributor {
    struct FeeCall {
        address token;
        address feeToken;
        uint256 amount;
    }
    
    FeeCall[] public feeCalls;
    
    function receiveFees(address token, address feeToken, uint256 amount) external {
        feeCalls.push(FeeCall({
            token: token,
            feeToken: feeToken,
            amount: amount
        }));
        // Pull the tokens (like the real contract does)
        MockERC20(feeToken).transferFrom(msg.sender, address(this), amount);
    }
    
    function getCallCount() external view returns (uint256) {
        return feeCalls.length;
    }
    
    function getLastCall() external view returns (address token, address feeToken, uint256 amount) {
        require(feeCalls.length > 0, "no calls");
        FeeCall memory last = feeCalls[feeCalls.length - 1];
        return (last.token, last.feeToken, last.amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIMPLIFIED LPLOCKER FOR TESTING FEE ROUTING LOGIC
// This is a simplified version that focuses on the fee distribution modification
// ═══════════════════════════════════════════════════════════════════════════════

interface IFeeDistributor {
    function receiveFees(address token, address feeToken, uint256 amount) external;
}

/**
 * @title SimplifiedLpLocker
 * @notice Simplified version of CC0StrategyLpLocker for testing fee routing
 * @dev Removes Uniswap V4 dependencies while preserving the fee distribution logic
 */
contract SimplifiedLpLocker {
    address public immutable factory;
    IFeeDistributor public immutable feeDistributor;
    address public owner;
    
    struct TokenInfo {
        address token;
        address feeToken;
        bool hasLiquidity;
    }
    
    mapping(address => TokenInfo) public tokenInfo;
    
    error Unauthorized();
    
    event FeesCollected(address indexed token, address indexed feeToken, uint256 amount);
    
    constructor(address _owner, address _factory, address _feeDistributor) {
        owner = _owner;
        factory = _factory;
        feeDistributor = IFeeDistributor(_feeDistributor);
    }
    
    modifier onlyFactory() {
        if (msg.sender != factory) revert Unauthorized();
        _;
    }
    
    /**
     * @notice Simplified placeLiquidity - just records the token info
     */
    function placeLiquidity(
        address token,
        address feeToken,
        uint256 /* poolSupply */
    ) external onlyFactory returns (uint256) {
        tokenInfo[token] = TokenInfo({
            token: token,
            feeToken: feeToken,
            hasLiquidity: true
        });
        return 1; // position ID
    }
    
    /**
     * @notice Simulate collecting fees and forwarding to FeeDistributor
     * @dev In real contract, this pulls fees from Uniswap V4 position
     *      Here we simulate by requiring tokens to be pre-sent to this contract
     */
    function collectRewards(address token) external {
        TokenInfo memory info = tokenInfo[token];
        require(info.hasLiquidity, "No liquidity");
        
        uint256 feeBalance = MockERC20(info.feeToken).balanceOf(address(this));
        if (feeBalance > 0) {
            // Forward all fees to FeeDistributor
            MockERC20(info.feeToken).approve(address(feeDistributor), feeBalance);
            feeDistributor.receiveFees(token, info.feeToken, feeBalance);
            emit FeesCollected(token, info.feeToken, feeBalance);
        }
    }
    
    function getTokenInfo(address token) external view returns (TokenInfo memory) {
        return tokenInfo[token];
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

contract CC0StrategyLpLockerTest is Test {
    SimplifiedLpLocker public lpLocker;
    MockFeeDistributor public feeDistributor;
    MockERC20 public strategyToken;
    MockERC20 public feeToken;
    
    address public owner = address(0x1111);
    address public factory;
    address public randomUser = address(0xB001);
    
    function setUp() public {
        factory = address(this); // Test contract acts as factory
        
        // Deploy mock contracts
        feeDistributor = new MockFeeDistributor();
        strategyToken = new MockERC20();
        feeToken = new MockERC20();
        
        // Deploy LpLocker
        lpLocker = new SimplifiedLpLocker(owner, factory, address(feeDistributor));
        
        // Set up token with liquidity
        lpLocker.placeLiquidity(address(strategyToken), address(feeToken), 1_000_000 ether);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // collectRewards Tests
    // ═══════════════════════════════════════════════════════════════════════════
    
    function test_collectRewards_forwardsToFeeDistributor() public {
        // Simulate fees being collected (in real contract, comes from Uniswap V4)
        uint256 feeAmount = 100 ether;
        feeToken.mint(address(lpLocker), feeAmount);
        
        // Collect rewards - should forward to FeeDistributor
        lpLocker.collectRewards(address(strategyToken));
        
        // Verify FeeDistributor received the call
        assertEq(feeDistributor.getCallCount(), 1, "FeeDistributor should be called once");
        
        (address token, address fToken, uint256 amount) = feeDistributor.getLastCall();
        assertEq(token, address(strategyToken), "Token should match");
        assertEq(fToken, address(feeToken), "FeeToken should match");
        assertEq(amount, feeAmount, "Amount should match");
        
        // FeeDistributor should have the tokens
        assertEq(feeToken.balanceOf(address(feeDistributor)), feeAmount, "FeeDistributor should hold fees");
        assertEq(feeToken.balanceOf(address(lpLocker)), 0, "LpLocker should have no fees left");
    }
    
    function test_collectRewards_noFeesDoesNothing() public {
        // No fees to collect
        lpLocker.collectRewards(address(strategyToken));
        
        // FeeDistributor should not be called
        assertEq(feeDistributor.getCallCount(), 0, "FeeDistributor should not be called");
    }
    
    function test_collectRewards_multipleRounds() public {
        // Round 1
        feeToken.mint(address(lpLocker), 50 ether);
        lpLocker.collectRewards(address(strategyToken));
        
        // Round 2
        feeToken.mint(address(lpLocker), 75 ether);
        lpLocker.collectRewards(address(strategyToken));
        
        // Round 3
        feeToken.mint(address(lpLocker), 25 ether);
        lpLocker.collectRewards(address(strategyToken));
        
        // Should have called FeeDistributor 3 times
        assertEq(feeDistributor.getCallCount(), 3, "FeeDistributor should be called 3 times");
        
        // Total should be 150 ether
        assertEq(feeToken.balanceOf(address(feeDistributor)), 150 ether, "Total fees should be 150 ether");
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // placeLiquidity Tests
    // ═══════════════════════════════════════════════════════════════════════════
    
    function test_placeLiquidity_onlyFactory() public {
        MockERC20 newToken = new MockERC20();
        
        vm.prank(randomUser);
        vm.expectRevert(SimplifiedLpLocker.Unauthorized.selector);
        lpLocker.placeLiquidity(address(newToken), address(feeToken), 1000 ether);
    }
    
    function test_placeLiquidity_success() public {
        MockERC20 newToken = new MockERC20();
        
        // Factory (this contract) can place liquidity
        lpLocker.placeLiquidity(address(newToken), address(feeToken), 1000 ether);
        
        SimplifiedLpLocker.TokenInfo memory info = lpLocker.getTokenInfo(address(newToken));
        assertEq(info.token, address(newToken));
        assertEq(info.feeToken, address(feeToken));
        assertTrue(info.hasLiquidity);
    }
    
    function test_collectRewards_requiresLiquidity() public {
        MockERC20 newToken = new MockERC20();
        
        // Try to collect rewards for unregistered token
        vm.expectRevert("No liquidity");
        lpLocker.collectRewards(address(newToken));
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // Integration Test: Full Flow
    // ═══════════════════════════════════════════════════════════════════════════
    
    function test_fullFlow_feeDistribution() public {
        // 1. Token is already registered via setUp
        
        // 2. Simulate trading fees accumulating (in real: from Uniswap V4 swaps)
        feeToken.mint(address(lpLocker), 1000 ether);
        
        // 3. Collect rewards
        lpLocker.collectRewards(address(strategyToken));
        
        // 4. Verify FeeDistributor received fees
        assertEq(feeToken.balanceOf(address(feeDistributor)), 1000 ether);
        
        // 5. At this point, FeeDistributor would split 20/80 and track for NFT holders
        // (tested in FeeDistributor.t.sol)
    }
}
