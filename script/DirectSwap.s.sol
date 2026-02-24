// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
}

/**
 * @title DirectSwap
 * @notice Try swap using PoolSwapTest (if deployed) or IV4Router
 */
contract DirectSwap is Script {
    // Base mainnet V4 test contracts (from Uniswap deployment)
    address constant POOL_SWAP_TEST = 0xd962b16F4ec712D705106674E944B04614F077be;
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TOKEN = 0x3b68C3B4e22E35Faf5841D1b5Eef8404D5A3b663;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address swapper = vm.addr(pk);
        
        console2.log("=== Direct Swap via PoolSwapTest ===");
        console2.log("Swapper:", swapper);
        console2.log("PoolSwapTest:", POOL_SWAP_TEST);
        
        // Token < WETH, so token is currency0
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(TOKEN),
            currency1: Currency.wrap(WETH),
            fee: 8388608,
            tickSpacing: 200,
            hooks: IHooks(HOOK)
        });
        
        // Check balance before
        uint256 tokenBefore = IERC20(TOKEN).balanceOf(swapper);
        console2.log("Token balance before:", tokenBefore);
        
        vm.startBroadcast(pk);
        
        // Wrap ETH
        uint256 swapAmount = 0.0003 ether;
        IWETH(WETH).deposit{value: swapAmount}();
        console2.log("Wrapped ETH:", swapAmount);
        
        // Approve PoolSwapTest
        IWETH(WETH).approve(POOL_SWAP_TEST, type(uint256).max);
        console2.log("Approved PoolSwapTest");
        
        // Build swap params
        // We want to swap WETH (currency1) for TOKEN (currency0)
        // So zeroForOne = false
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,  // WETH -> TOKEN
            amountSpecified: -int256(swapAmount), // Exact input
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 // Min price limit for buying token0
        });
        
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        console2.log("Executing swap...");
        PoolSwapTest(POOL_SWAP_TEST).swap(key, params, settings, "");
        
        vm.stopBroadcast();
        
        uint256 tokenAfter = IERC20(TOKEN).balanceOf(swapper);
        console2.log("Token balance after:", tokenAfter);
        console2.log("Tokens received:", tokenAfter - tokenBefore);
    }
}
