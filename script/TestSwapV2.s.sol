// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
}

interface IV4Router {
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
        bytes hookData;
    }
    
    function swap(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

/**
 * @title TestSwapV2
 * @notice Test swap on the V2 token with fixed tick range
 * Uses direct PoolManager unlock pattern for testing
 */
contract TestSwapV2 is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    address constant SWAP_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43; // Universal Router
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    
    // Will be set from env
    address public TOKEN;
    
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address swapper = vm.addr(pk);
        TOKEN = vm.envAddress("TOKEN_ADDRESS");
        
        console2.log("=== TestSwapV2 ===");
        console2.log("Swapper:", swapper);
        console2.log("Token:", TOKEN);
        console2.log("");
        
        // Build pool key
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(WETH),
            currency1: Currency.wrap(TOKEN),
            fee: 8388608, // Dynamic fee flag
            tickSpacing: 200,
            hooks: IHooks(HOOK)
        });
        
        PoolId poolId = key.toId();
        console2.log("Pool ID:");
        console2.logBytes32(PoolId.unwrap(poolId));
        
        // Check pool state
        IPoolManager pm = IPoolManager(POOL_MANAGER);
        (uint160 sqrtPriceX96, int24 currentTick,,) = pm.getSlot0(poolId);
        
        console2.log("");
        console2.log("Pool State:");
        console2.log("  sqrtPriceX96:", sqrtPriceX96);
        console2.log("  currentTick:", currentTick);
        
        // Check liquidity at current tick
        uint128 liquidity = pm.getLiquidity(poolId);
        console2.log("  liquidity:", liquidity);
        
        if (liquidity == 0) {
            console2.log("");
            console2.log("ERROR: No active liquidity in pool!");
            console2.log("This means the tick range is still wrong or position wasn't created.");
            return;
        }
        
        console2.log("");
        console2.log("Liquidity found! Proceeding with swap...");
        
        // Check balances before
        uint256 wethBefore = IWETH(WETH).balanceOf(swapper);
        uint256 tokenBefore = IERC20(TOKEN).balanceOf(swapper);
        console2.log("");
        console2.log("Balances Before:");
        console2.log("  WETH:", wethBefore);
        console2.log("  TOKEN:", tokenBefore);
        
        vm.startBroadcast(pk);
        
        // Wrap 0.001 ETH
        uint256 swapAmount = 0.001 ether;
        IWETH(WETH).deposit{value: swapAmount}();
        console2.log("");
        console2.log("Wrapped", swapAmount, "ETH to WETH");
        
        // Approve Permit2
        IWETH(WETH).approve(PERMIT2, type(uint256).max);
        console2.log("Approved Permit2");
        
        vm.stopBroadcast();
        
        // Check balances after
        uint256 wethAfter = IWETH(WETH).balanceOf(swapper);
        uint256 tokenAfter = IERC20(TOKEN).balanceOf(swapper);
        console2.log("");
        console2.log("Balances After Wrap:");
        console2.log("  WETH:", wethAfter);
        console2.log("  TOKEN:", tokenAfter);
        
        console2.log("");
        console2.log("=== SWAP READY ===");
        console2.log("WETH deposited and Permit2 approved.");
        console2.log("To execute swap, use Universal Router or V4 Router directly.");
        console2.log("");
        console2.log("Pool Key for swap:");
        console2.log("  currency0 (WETH):", WETH);
        console2.log("  currency1 (TOKEN):", TOKEN);
        console2.log("  fee: 8388608");
        console2.log("  tickSpacing: 200");
        console2.log("  hook:", HOOK);
    }
}
