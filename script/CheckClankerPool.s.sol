// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

contract CheckClankerPool is Script {
    using StateLibrary for IPoolManager;
    
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    
    // Pool ID from the Clanker deployment event
    bytes32 constant CLANKER_POOL_ID = 0x08cdf5978d897803bd9e332d742d083f3f52f0a6fdaabca0362fb7b4da619dab;
    
    // Our pool ID
    bytes32 constant OUR_POOL_ID = 0x34fc0d2eb125338f44d3001c5a5fd626aad60d98b763082b7fbdec8a6d501f30;
    
    function run() public view {
        IPoolManager pm = IPoolManager(POOL_MANAGER);
        
        console2.log("=== DIRECT POOL ID COMPARISON ===");
        console2.log("");
        
        console2.log("CLANKER POOL (from event):");
        console2.logBytes32(CLANKER_POOL_ID);
        (uint160 clankerSqrtPrice, int24 clankerTick,,) = pm.getSlot0(PoolId.wrap(CLANKER_POOL_ID));
        uint128 clankerLiquidity = pm.getLiquidity(PoolId.wrap(CLANKER_POOL_ID));
        console2.log("  sqrtPriceX96:", clankerSqrtPrice);
        console2.log("  tick:", clankerTick);
        console2.log("  liquidity:", clankerLiquidity);
        console2.log("");
        
        console2.log("OUR POOL:");
        console2.logBytes32(OUR_POOL_ID);
        (uint160 ourSqrtPrice, int24 ourTick,,) = pm.getSlot0(PoolId.wrap(OUR_POOL_ID));
        uint128 ourLiquidity = pm.getLiquidity(PoolId.wrap(OUR_POOL_ID));
        console2.log("  sqrtPriceX96:", ourSqrtPrice);
        console2.log("  tick:", ourTick);
        console2.log("  liquidity:", ourLiquidity);
        console2.log("");
        
        if (clankerLiquidity > 0 && ourLiquidity > 0) {
            console2.log("Both pools have liquidity!");
        }
    }
}
