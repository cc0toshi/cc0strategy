// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title CC0StrategyLpLocker
 * @author cc0strategy (forked from Clanker)
 * @notice LP Locker that routes ALL fees to FeeDistributor for NFT holder distribution
 * @dev ONLY modification from ClankerLpLockerFeeConversion:
 *      - Replace ClankerFeeLocker with FeeDistributor
 *      - All fees converted to feeToken and sent to FeeDistributor
 *      - FeeDistributor handles 20/80 treasury/NFT split
 */

import {IClanker} from "../interfaces/IClanker.sol";
import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";

import {IClankerHook} from "../interfaces/IClankerHook.sol";
import {IClankerLpLocker} from "../interfaces/IClankerLPLocker.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

contract CC0StrategyLpLocker is IClankerLpLocker, ReentrancyGuard, Ownable, IERC721Receiver {
    using TickMath for int24;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeERC20 for IERC20;

    string public constant version = "cc0strategy-1.0";

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MAX_LP_POSITIONS = 7;

    IPositionManager public immutable positionManager;
    IPoolManager public immutable poolManager;
    IPermit2 public immutable permit2;
    IUniversalRouter public immutable universalRouter;
    address public immutable factory;
    
    // cc0strategy modification: FeeDistributor instead of ClankerFeeLocker
    IFeeDistributor public immutable feeDistributor;

    // guard to stop recursive collection calls
    bool internal _inCollect;

    // Simplified token info (no per-recipient reward tracking)
    struct TokenInfo {
        address token;
        PoolKey poolKey;
        uint256 positionId;
        uint256 numPositions;
        address feeToken; // the token fees are paid in (usually paired token like WETH)
    }

    mapping(address token => TokenInfo tokenInfo) internal _tokenInfo;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════
    
    error Unauthorized();
    error TokenAlreadyHasRewards();
    error MismatchedPositionInfos();
    error NoPositions();
    error TooManyPositions();
    error TicksBackwards();
    error TicksOutOfTickBounds();
    error TicksNotMultipleOfTickSpacing();
    error TickRangeLowerThanStartingTick();
    error InvalidPositionBps();

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event TokenAdded(
        address indexed token,
        PoolKey poolKey,
        uint256 poolSupply,
        uint256 positionId,
        uint256 numPositions,
        address feeToken,
        int24[] tickLower,
        int24[] tickUpper,
        uint16[] positionBps
    );

    event FeesCollected(
        address indexed token,
        address indexed feeToken,
        uint256 amount
    );

    event FeesSwapped(
        address indexed token,
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut
    );

    event Received(address indexed from, uint256 indexed id);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address owner_,
        address factory_,
        address feeDistributor_,
        address positionManager_,
        address permit2_,
        address universalRouter_,
        address poolManager_
    ) Ownable(owner_) {
        factory = factory_;
        feeDistributor = IFeeDistributor(feeDistributor_);
        positionManager = IPositionManager(positionManager_);
        permit2 = IPermit2(permit2_);
        universalRouter = IUniversalRouter(universalRouter_);
        poolManager = IPoolManager(poolManager_);
    }

    modifier onlyFactory() {
        if (msg.sender != factory) {
            revert Unauthorized();
        }
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function tokenRewards(address token) external view returns (TokenRewardInfo memory) {
        TokenInfo memory info = _tokenInfo[token];
        // Return in Clanker-compatible format (empty arrays for reward fields)
        return TokenRewardInfo({
            token: info.token,
            poolKey: info.poolKey,
            positionId: info.positionId,
            numPositions: info.numPositions,
            rewardBps: new uint16[](0),
            rewardAdmins: new address[](0),
            rewardRecipients: new address[](0)
        });
    }

    function getTokenInfo(address token) external view returns (TokenInfo memory) {
        return _tokenInfo[token];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PLACE LIQUIDITY
    // ═══════════════════════════════════════════════════════════════════════════

    function placeLiquidity(
        IClanker.LockerConfig memory lockerConfig,
        IClanker.PoolConfig memory poolConfig,
        PoolKey memory poolKey,
        uint256 poolSupply,
        address token
    ) external onlyFactory nonReentrant returns (uint256 positionId) {
        // ensure that we don't already have info for this token
        if (_tokenInfo[token].positionId != 0) {
            revert TokenAlreadyHasRewards();
        }

        // Determine the fee token (paired token, usually WETH)
        address feeToken = token < poolConfig.pairedToken
            ? poolConfig.pairedToken  // token is token0, paired is token1
            : poolConfig.pairedToken;

        // Create the token info
        TokenInfo memory tokenInfo = TokenInfo({
            token: token,
            poolKey: poolKey,
            positionId: 0, // set below
            numPositions: lockerConfig.tickLower.length,
            feeToken: feeToken
        });

        // pull in the token and mint liquidity
        IERC20(token).transferFrom(msg.sender, address(this), poolSupply);
        positionId = _mintLiquidity(poolConfig, lockerConfig, poolKey, poolSupply, token);

        // store the token info
        tokenInfo.positionId = positionId;
        _tokenInfo[token] = tokenInfo;

        emit TokenAdded({
            token: tokenInfo.token,
            poolKey: tokenInfo.poolKey,
            poolSupply: poolSupply,
            positionId: tokenInfo.positionId,
            numPositions: tokenInfo.numPositions,
            feeToken: tokenInfo.feeToken,
            tickLower: lockerConfig.tickLower,
            tickUpper: lockerConfig.tickUpper,
            positionBps: lockerConfig.positionBps
        });
    }

    function _mintLiquidity(
        IClanker.PoolConfig memory poolConfig,
        IClanker.LockerConfig memory lockerConfig,
        PoolKey memory poolKey,
        uint256 poolSupply,
        address token
    ) internal returns (uint256 positionId) {
        // check that all position infos are the same length
        if (
            lockerConfig.tickLower.length != lockerConfig.tickUpper.length
                || lockerConfig.tickLower.length != lockerConfig.positionBps.length
        ) {
            revert MismatchedPositionInfos();
        }

        // ensure that there is at least one position
        if (lockerConfig.tickLower.length == 0) {
            revert NoPositions();
        }

        // ensure that the max number of positions is not exceeded
        if (lockerConfig.tickLower.length > MAX_LP_POSITIONS) {
            revert TooManyPositions();
        }

        // make sure the locker position config is valid
        uint256 positionBpsTotal = 0;
        for (uint256 i = 0; i < lockerConfig.tickLower.length; i++) {
            if (lockerConfig.tickLower[i] > lockerConfig.tickUpper[i]) {
                revert TicksBackwards();
            }
            if (
                lockerConfig.tickLower[i] < TickMath.MIN_TICK
                    || lockerConfig.tickUpper[i] > TickMath.MAX_TICK
            ) {
                revert TicksOutOfTickBounds();
            }
            if (
                lockerConfig.tickLower[i] % poolConfig.tickSpacing != 0
                    || lockerConfig.tickUpper[i] % poolConfig.tickSpacing != 0
            ) {
                revert TicksNotMultipleOfTickSpacing();
            }
            if (lockerConfig.tickLower[i] < poolConfig.tickIfToken0IsClanker) {
                revert TickRangeLowerThanStartingTick();
            }

            positionBpsTotal += lockerConfig.positionBps[i];
        }
        if (positionBpsTotal != BASIS_POINTS) {
            revert InvalidPositionBps();
        }

        bool token0IsClanker = token < poolConfig.pairedToken;

        // encode actions
        bytes[] memory params = new bytes[](lockerConfig.tickLower.length + 1);
        bytes memory actions;

        int24 startingTick =
            token0IsClanker ? poolConfig.tickIfToken0IsClanker : -poolConfig.tickIfToken0IsClanker;

        for (uint256 i = 0; i < lockerConfig.tickLower.length; i++) {
            // add mint action
            actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));

            // determine token amount for this position
            uint256 tokenAmount = poolSupply * lockerConfig.positionBps[i] / BASIS_POINTS;
            uint256 amount0 = token0IsClanker ? tokenAmount : 0;
            uint256 amount1 = token0IsClanker ? 0 : tokenAmount;

            // determine tick bounds for this position
            int24 tickLower_ =
                token0IsClanker ? lockerConfig.tickLower[i] : -lockerConfig.tickLower[i];
            int24 tickUpper_ =
                token0IsClanker ? lockerConfig.tickUpper[i] : -lockerConfig.tickUpper[i];
            int24 tickLower = token0IsClanker ? tickLower_ : tickUpper_;
            int24 tickUpper = token0IsClanker ? tickUpper_ : tickLower_;
            uint160 lowerSqrtPrice = TickMath.getSqrtPriceAtTick(tickLower);
            uint160 upperSqrtPrice = TickMath.getSqrtPriceAtTick(tickUpper);

            // determine liquidity amount
            uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                startingTick.getSqrtPriceAtTick(), lowerSqrtPrice, upperSqrtPrice, amount0, amount1
            );

            params[i] = abi.encode(
                poolKey,
                tickLower, // tick lower
                tickUpper, // tick upper
                liquidity, // liquidity
                amount0, // amount0Max
                amount1, // amount1Max
                address(this), // recipient of position
                abi.encode(address(this))
            );
        }

        // add settle action
        actions = abi.encodePacked(actions, uint8(Actions.SETTLE_PAIR));
        params[lockerConfig.tickLower.length] = abi.encode(poolKey.currency0, poolKey.currency1);

        // approvals
        {
            IERC20(token).approve(address(permit2), poolSupply);
            permit2.approve(
                token, address(positionManager), uint160(poolSupply), uint48(block.timestamp)
            );
        }

        // grab position id we're about to mint
        positionId = positionManager.nextTokenId();
        // add liquidity
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE COLLECTION
    // ═══════════════════════════════════════════════════════════════════════════

    // collect rewards while pool is unlocked (e.g. in an afterSwap hook)
    function collectRewardsWithoutUnlock(address token) external {
        _collectRewards(token, true);
    }

    // collect rewards while pool is locked
    function collectRewards(address token) external {
        _collectRewards(token, false);
    }

    function _mevModuleOperating(address token) internal view returns (bool) {
        PoolId poolId = PoolIdLibrary.toId(_tokenInfo[token].poolKey);

        if (!IClankerHook(address(_tokenInfo[token].poolKey.hooks)).mevModuleEnabled(poolId)) {
            return false;
        }

        uint256 poolCreationTimestamp =
            IClankerHook(address(_tokenInfo[token].poolKey.hooks)).poolCreationTimestamp(poolId);
        if (
            poolCreationTimestamp
                + IClankerHook(address(_tokenInfo[token].poolKey.hooks)).MAX_MEV_MODULE_DELAY()
                <= block.timestamp
        ) {
            return false;
        }

        return true;
    }

    // Collect rewards for a token and send to FeeDistributor
    function _collectRewards(address token, bool withoutUnlock) internal {
        if (_inCollect) {
            return;
        }

        if (_mevModuleOperating(token)) {
            return;
        }

        _inCollect = true;

        TokenInfo memory tokenInfo = _tokenInfo[token];

        (uint256 amount0, uint256 amount1) = _bringFeesIntoContract(
            tokenInfo.poolKey,
            tokenInfo.positionId,
            tokenInfo.numPositions,
            withoutUnlock
        );

        address token0 = Currency.unwrap(tokenInfo.poolKey.currency0);
        address token1 = Currency.unwrap(tokenInfo.poolKey.currency1);
        address feeToken = tokenInfo.feeToken;

        uint256 totalFeeTokenAmount = 0;

        if (amount0 > 0) {
            if (token0 == feeToken) {
                totalFeeTokenAmount += amount0;
            } else {
                uint256 swappedAmount = withoutUnlock
                    ? _uniSwapUnlocked(tokenInfo.poolKey, token0, feeToken, uint128(amount0))
                    : _uniSwapLocked(tokenInfo.poolKey, token0, feeToken, uint128(amount0));
                totalFeeTokenAmount += swappedAmount;
                emit FeesSwapped(token, token0, amount0, feeToken, swappedAmount);
            }
        }

        if (amount1 > 0) {
            if (token1 == feeToken) {
                totalFeeTokenAmount += amount1;
            } else {
                uint256 swappedAmount = withoutUnlock
                    ? _uniSwapUnlocked(tokenInfo.poolKey, token1, feeToken, uint128(amount1))
                    : _uniSwapLocked(tokenInfo.poolKey, token1, feeToken, uint128(amount1));
                totalFeeTokenAmount += swappedAmount;
                emit FeesSwapped(token, token1, amount1, feeToken, swappedAmount);
            }
        }

        if (totalFeeTokenAmount > 0) {
            IERC20(feeToken).forceApprove(address(feeDistributor), totalFeeTokenAmount);
            feeDistributor.receiveFees(token, feeToken, totalFeeTokenAmount);
            emit FeesCollected(token, feeToken, totalFeeTokenAmount);
        }

        _inCollect = false;
    }

    function _bringFeesIntoContract(
        PoolKey memory poolKey,
        uint256 positionId,
        uint256 numPositions,
        bool withoutUnlock
    ) internal returns (uint256 amount0, uint256 amount1) {
        bytes memory actions;
        bytes[] memory params = new bytes[](numPositions + 1);

        for (uint256 i = 0; i < numPositions; i++) {
            actions = abi.encodePacked(actions, uint8(Actions.DECREASE_LIQUIDITY));
            params[i] = abi.encode(positionId + i, 0, 0, 0, abi.encode());
        }

        Currency currency0 = poolKey.currency0;
        Currency currency1 = poolKey.currency1;
        actions = abi.encodePacked(actions, uint8(Actions.TAKE_PAIR));
        params[numPositions] = abi.encode(currency0, currency1, address(this));

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        if (withoutUnlock) {
            positionManager.modifyLiquiditiesWithoutUnlock(actions, params);
        } else {
            positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);
        }

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        return (balance0After - balance0Before, balance1After - balance1Before);
    }

    function _uniSwapUnlocked(
        PoolKey memory poolKey,
        address tokenIn,
        address tokenOut,
        uint128 amountIn
    ) internal returns (uint256) {
        bool zeroForOne = tokenIn < tokenOut;

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(int128(amountIn)),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(address(this));

        BalanceDelta delta = poolManager.swap(poolKey, swapParams, abi.encode());

        int128 deltaOut = delta.amount0() < 0 ? delta.amount1() : delta.amount0();

        poolManager.sync(Currency.wrap(tokenIn));
        Currency.wrap(tokenIn).transfer(address(poolManager), amountIn);
        poolManager.settle();

        poolManager.take(Currency.wrap(tokenOut), address(this), uint256(uint128(deltaOut)));

        uint256 tokenOutAfter = IERC20(tokenOut).balanceOf(address(this));
        return tokenOutAfter - tokenOutBefore;
    }

    function _uniSwapLocked(
        PoolKey memory poolKey,
        address tokenIn,
        address tokenOut,
        uint128 amountIn
    ) internal returns (uint256) {
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);

        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: tokenIn < tokenOut,
                amountIn: amountIn,
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );

        params[1] = abi.encode(tokenIn, uint256(amountIn));
        params[2] = abi.encode(tokenOut, 1);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        IERC20(tokenIn).forceApprove(address(permit2), amountIn);
        permit2.approve(tokenIn, address(universalRouter), amountIn, uint48(block.timestamp));

        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(address(this));

        universalRouter.execute(commands, inputs, block.timestamp);

        uint256 tokenOutAfter = IERC20(tokenOut).balanceOf(address(this));

        return tokenOutAfter - tokenOutBefore;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC721 RECEIVER
    // ═══════════════════════════════════════════════════════════════════════════

    function onERC721Received(address, address from, uint256 id, bytes calldata)
        external
        returns (bytes4)
    {
        if (from != factory) {
            revert Unauthorized();
        }

        emit Received(from, id);
        return IERC721Receiver.onERC721Received.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function withdrawETH(address recipient) public onlyOwner nonReentrant {
        payable(recipient).transfer(address(this).balance);
    }

    function withdrawERC20(address _token, address recipient) public onlyOwner nonReentrant {
        IERC20 token_ = IERC20(_token);
        token_.safeTransfer(recipient, token_.balanceOf(address(this)));
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IClankerLpLocker).interfaceId;
    }
}
