// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IFeeDistributor
 * @notice Interface for the cc0strategy FeeDistributor contract
 */
interface IFeeDistributor {
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
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Receives fees from LpLocker and distributes them
     * @param token The cc0strategy token the fees are for
     * @param feeToken The token fees are paid in (usually WETH)
     * @param amount The amount of fees received
     */
    function receiveFees(address token, address feeToken, uint256 amount) external;

    /**
     * @notice Claims accumulated rewards for multiple NFTs
     * @param token The cc0strategy token to claim rewards from
     * @param tokenIds Array of NFT token IDs to claim for
     */
    function claim(address token, uint256[] calldata tokenIds) external;

    /**
     * @notice Get claimable amount for a single NFT
     */
    function claimable(address token, uint256 tokenId) external view returns (uint256);

    /**
     * @notice Get claimable amount for multiple NFTs
     */
    function claimableMultiple(address token, uint256[] calldata tokenIds) external view returns (uint256 total);

    // ═══════════════════════════════════════════════════════════════════════════
    // FACTORY FUNCTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Registers a new cc0strategy token (called atomically by Factory)
     */
    function registerToken(
        address token,
        address nftCollection,
        address feeToken,
        uint256 nftSupply
    ) external;

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function treasury() external view returns (address);
    function lpLocker() external view returns (address);
    function factory() external view returns (address);
    function tokenToCollection(address token) external view returns (address);
    function tokenToNftSupply(address token) external view returns (uint256);
    function tokenToFeeToken(address token) external view returns (address);
    function accumulatedRewards(address token) external view returns (uint256);
    function claimed(address token, uint256 tokenId) external view returns (uint256);
    function totalOwed(address feeToken) external view returns (uint256);
    function rescuableBalance(address feeToken) external view returns (uint256);
}
