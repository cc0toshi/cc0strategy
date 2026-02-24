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

/**
 * @title SimSwap
 * @notice Just check pool state and simulate what a swap would do
 */
contract SimSwap is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TOKEN_V3 = 0x3b68C3B4e22E35Faf5841D1b5Eef8404D5A3b663;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    
    function run() public view {
        console2.log("=== Pool Analysis ===");
        console2.log("");
        console2.log("Token (currency0):", TOKEN_V3);
        console2.log("WETH (currency1):", WETH);
        console2.log("");
        
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(TOKEN_V3),
            currency1: Currency.wrap(WETH),
            fee: 8388608,
            tickSpacing: 200,
            hooks: IHooks(HOOK)
        });
        
        IPoolManager pm = IPoolManager(POOL_MANAGER);
        PoolId poolId = key.toId();
        
        console2.log("Pool ID:");
        console2.logBytes32(PoolId.unwrap(poolId));
        
        (uint160 sqrtPriceX96, int24 currentTick,,) = pm.getSlot0(poolId);
        uint128 liquidity = pm.getLiquidity(poolId);
        
        console2.log("");
        console2.log("Pool State:");
        console2.log("  sqrtPriceX96:", sqrtPriceX96);
        console2.log("  currentTick:", currentTick);
        console2.log("  liquidity:", liquidity);
        
        // Calculate price
        // For currency0/currency1: price = (sqrtPriceX96 / 2^96)^2
        // This gives currency1 per currency0 = WETH per TOKEN
        uint256 price_num = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        // Divide by 2^192 to get actual ratio
        console2.log("");
        console2.log("Price Analysis:");
        console2.log("  sqrtPriceX96^2:", price_num);
        
        // At tick -230400:
        // price = 1.0001^(-230400) = very small number
        // This means TOKEN is very cheap relative to WETH
        // Buying 0.0001 WETH worth should give a LOT of tokens
        
        console2.log("");
        console2.log("For swap WETH -> TOKEN (zeroForOne = false):");
        console2.log("  - You give WETH (currency1)");
        console2.log("  - You receive TOKEN (currency0)");
        console2.log("  - Tick should DECREASE (TOKEN gets more expensive)");
        console2.log("");
        
        console2.log("Position info:");
        console2.log("  tickLower: -230400 (= startingTick)");
        console2.log("  tickUpper: 887200");
        console2.log("  currentTick in range: ", currentTick >= -230400 && currentTick < 887200 ? "YES" : "NO");
        console2.log("");
        
        if (liquidity > 0) {
            console2.log("SUCCESS: Pool has active liquidity!");
            console2.log("");
            console2.log("To swap, use a frontend or direct PoolManager interaction.");
            console2.log("The cc0strategy pool is LIVE!");
        }
    }
}
