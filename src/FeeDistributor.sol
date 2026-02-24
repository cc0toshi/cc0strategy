// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FeeDistributor
 * @author cc0strategy
 * @notice Distributes trading fees from cc0strategy tokens to NFT holders
 * @dev Uses Synthetix-style accumulator pattern for gas-efficient reward distribution
 * 
 * Fee Split:
 *   - 20% → Treasury (cc0toshi)
 *   - 80% → NFT holders (distributed equally per NFT)
 */
contract FeeDistributor is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 public constant TREASURY_BPS = 2000;      // 20%
    uint256 public constant NFT_HOLDERS_BPS = 8000;   // 80%
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant PRECISION = 1e18;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    address public treasury;
    address public lpLocker;
    address public factory;

    mapping(address token => address nftCollection) public tokenToCollection;
    mapping(address token => uint256 totalSupply) public tokenToNftSupply;
    mapping(address token => address feeToken) public tokenToFeeToken;
    mapping(address token => uint256 accRewardPerNFT) public accumulatedRewards;
    mapping(address token => mapping(uint256 tokenId => uint256 lastClaimed)) public claimed;
    
    /// @notice Tracks total owed to NFT holders per fee token (rescueTokens protection)
    mapping(address feeToken => uint256 totalOwed) public totalOwed;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event FeesReceived(
        address indexed token,
        address indexed feeToken,
        uint256 totalAmount,
        uint256 treasuryAmount,
        uint256 nftHoldersAmount,
        uint256 newAccRewardPerNFT
    );

    event RewardsClaimed(
        address indexed token,
        address indexed claimer,
        uint256[] tokenIds,
        uint256 totalReward
    );
    
    event TokenIdSkipped(address indexed token, uint256 indexed tokenId, string reason);
    event TokenRegistered(address indexed token, address indexed nftCollection, address indexed feeToken, uint256 nftSupply);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event LpLockerUpdated(address indexed oldLpLocker, address indexed newLpLocker);
    event FactoryUpdated(address indexed oldFactory, address indexed newFactory);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address _treasury,
        address _lpLocker,
        address _factory,
        address _owner
    ) Ownable(_owner) {
        if (_treasury == address(0)) revert ZeroAddress();
        if (_lpLocker == address(0)) revert ZeroAddress();
        if (_factory == address(0)) revert ZeroAddress();
        
        treasury = _treasury;
        lpLocker = _lpLocker;
        factory = _factory;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Receives fees from LpLocker and distributes them
     * @dev Only callable by lpLocker. Splits 20/80 between treasury and NFT rewards.
     */
    function receiveFees(
        address token,
        address feeToken,
        uint256 amount
    ) external nonReentrant {
        if (msg.sender != lpLocker) revert NotAuthorized();
        if (amount == 0) revert ZeroAmount();
        if (tokenToCollection[token] == address(0)) revert TokenNotRegistered();
        if (feeToken != tokenToFeeToken[token]) revert FeeTokenMismatch();
        
        IERC20(feeToken).safeTransferFrom(msg.sender, address(this), amount);
        
        uint256 treasuryAmount = (amount * TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 nftHoldersAmount = amount - treasuryAmount;
        
        IERC20(feeToken).safeTransfer(treasury, treasuryAmount);
        
        // Track owed for rescueTokens protection
        totalOwed[feeToken] += nftHoldersAmount;
        
        uint256 nftSupply = tokenToNftSupply[token];
        uint256 rewardPerNFT = (nftHoldersAmount * PRECISION) / nftSupply;
        accumulatedRewards[token] += rewardPerNFT;
        
        emit FeesReceived(token, feeToken, amount, treasuryAmount, nftHoldersAmount, accumulatedRewards[token]);
    }

    /**
     * @notice Claims accumulated rewards for multiple NFTs
     * @dev Uses try/catch on ownerOf to handle burned NFTs gracefully
     */
    function claim(
        address token,
        uint256[] calldata tokenIds
    ) external nonReentrant {
        if (tokenIds.length == 0) revert EmptyTokenIds();
        if (tokenToCollection[token] == address(0)) revert TokenNotRegistered();
        
        address nftCollection = tokenToCollection[token];
        address feeToken = tokenToFeeToken[token];
        uint256 currentAcc = accumulatedRewards[token];
        uint256 totalReward = 0;
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            
            // Try to get owner - skip if NFT is burned or ownerOf reverts
            address owner;
            try IERC721(nftCollection).ownerOf(tokenId) returns (address _owner) {
                owner = _owner;
            } catch {
                emit TokenIdSkipped(token, tokenId, "ownerOf reverted");
                continue;
            }
            
            // Skip if caller doesn't own this NFT
            if (owner != msg.sender) {
                emit TokenIdSkipped(token, tokenId, "not owner");
                continue;
            }
            
            // Calculate reward for this NFT
            uint256 lastClaimed = claimed[token][tokenId];
            uint256 reward = (currentAcc - lastClaimed) / PRECISION;
            
            if (reward > 0) {
                claimed[token][tokenId] = currentAcc;
                totalReward += reward;
            }
        }
        
        if (totalReward == 0) revert NoRewardsToClaim();
        
        // Reduce owed amount
        totalOwed[feeToken] -= totalReward;
        
        IERC20(feeToken).safeTransfer(msg.sender, totalReward);
        
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

    // ═══════════════════════════════════════════════════════════════════════════
    // FACTORY FUNCTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Registers a new cc0strategy token (called atomically by Factory)
     * @dev NFT supply is cached and immutable - no updates allowed
     */
    function registerToken(
        address token,
        address nftCollection,
        address feeToken,
        uint256 nftSupply
    ) external {
        if (msg.sender != factory) revert NotAuthorized();
        if (token == address(0) || nftCollection == address(0) || feeToken == address(0)) revert ZeroAddress();
        if (nftSupply == 0) revert InvalidNftSupply();
        if (tokenToCollection[token] != address(0)) revert TokenAlreadyRegistered();
        
        tokenToCollection[token] = nftCollection;
        tokenToFeeToken[token] = feeToken;
        tokenToNftSupply[token] = nftSupply;
        
        emit TokenRegistered(token, nftCollection, feeToken, nftSupply);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        emit TreasuryUpdated(treasury, _treasury);
        treasury = _treasury;
    }

    function setLpLocker(address _lpLocker) external onlyOwner {
        if (_lpLocker == address(0)) revert ZeroAddress();
        emit LpLockerUpdated(lpLocker, _lpLocker);
        lpLocker = _lpLocker;
    }
    
    function setFactory(address _factory) external onlyOwner {
        if (_factory == address(0)) revert ZeroAddress();
        emit FactoryUpdated(factory, _factory);
        factory = _factory;
    }

    /**
     * @notice Emergency withdrawal of EXCESS tokens only (not a rug vector)
     * @dev Can only withdraw balance above what's owed to NFT holders
     */
    function rescueTokens(address _feeToken, address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        
        uint256 balance = IERC20(_feeToken).balanceOf(address(this));
        uint256 owed = totalOwed[_feeToken];
        uint256 excess = balance > owed ? balance - owed : 0;
        
        if (_amount > excess) revert InsufficientExcessBalance();
        
        IERC20(_feeToken).safeTransfer(_to, _amount);
    }
    
    function rescuableBalance(address _feeToken) external view returns (uint256) {
        uint256 balance = IERC20(_feeToken).balanceOf(address(this));
        uint256 owed = totalOwed[_feeToken];
        return balance > owed ? balance - owed : 0;
    }
}
