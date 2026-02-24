// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

contract TestSwap is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TOKEN = 0xCBBbF8158A5B41c09ec8dE9e69F90E878bCec203;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    
    function run() public view {
        IPoolManager pm = IPoolManager(POOL_MANAGER);
        
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(WETH),
            currency1: Currency.wrap(TOKEN),
            fee: 8388608, // dynamic fee flag
            tickSpacing: 200,
            hooks: IHooks(HOOK)
        });
        
        PoolId poolId = key.toId();
        console2.log("Pool ID:");
        console2.logBytes32(PoolId.unwrap(poolId));
        
        // Get slot0
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = pm.getSlot0(poolId);
        console2.log("sqrtPriceX96:", sqrtPriceX96);
        console2.log("Current tick:", tick);
        console2.log("Protocol fee:", protocolFee);
        console2.log("LP fee:", lpFee);
        
        // Get liquidity
        uint128 liquidity = pm.getLiquidity(poolId);
        console2.log("Pool liquidity:", liquidity);
    }
}
