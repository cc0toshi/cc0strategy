// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

contract CheckPool is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TOKEN_V3 = 0x3b68C3B4e22E35Faf5841D1b5Eef8404D5A3b663;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    
    function run() public view {
        console2.log("=== V3 Pool Check ===");
        console2.log("");
        
        // Token < WETH, so token is currency0
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
        console2.log("");
        
        (uint160 sqrtPriceX96, int24 currentTick,,) = pm.getSlot0(poolId);
        uint128 liquidity = pm.getLiquidity(poolId);
        
        console2.log("Pool State:");
        console2.log("  currentTick:", currentTick);
        console2.log("  sqrtPriceX96:", sqrtPriceX96);
        console2.log("  ACTIVE LIQUIDITY:", liquidity);
        console2.log("");
        
        if (liquidity > 0) {
            console2.log("SUCCESS! Pool has active liquidity!");
            console2.log("Ready for swaps!");
        } else {
            console2.log("ERROR: No active liquidity");
        }
    }
}
