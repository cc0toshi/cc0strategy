// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

contract ComparePool is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    // Our token
    address constant OUR_TOKEN = 0x3b68C3B4e22E35Faf5841D1b5Eef8404D5A3b663;
    address constant OUR_HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    
    // Recent working Clanker token (from logs above)
    address constant CLANKER_TOKEN = 0x3A23ACC7677e25F85754C9880F5557539dC29B70;
    address constant CLANKER_HOOK = 0xb429d62f8f3bFFb98CdB9569533eA23bF0Ba28CC;
    
    function run() public view {
        console2.log("=== POOL COMPARISON ===");
        console2.log("");
        
        // 1. Compare hook addresses and permission bits
        console2.log("1. HOOK COMPARISON");
        console2.log("-------------------");
        console2.log("Our hook:", OUR_HOOK);
        console2.log("Clanker hook:", CLANKER_HOOK);
        console2.log("");
        
        uint160 ourFlags = uint160(OUR_HOOK);
        uint160 clankerFlags = uint160(CLANKER_HOOK);
        
        console2.log("Our hook low bits (permissions):", ourFlags & 0xFFFF);
        console2.log("Clanker hook low bits:", clankerFlags & 0xFFFF);
        console2.log("");
        
        // Check specific flags
        console2.log("Permission flags breakdown:");
        console2.log("  BEFORE_INITIALIZE:", 
            (ourFlags & Hooks.BEFORE_INITIALIZE_FLAG) != 0 ? "YES" : "NO",
            "/",
            (clankerFlags & Hooks.BEFORE_INITIALIZE_FLAG) != 0 ? "YES" : "NO"
        );
        console2.log("  AFTER_INITIALIZE:", 
            (ourFlags & Hooks.AFTER_INITIALIZE_FLAG) != 0 ? "YES" : "NO",
            "/",
            (clankerFlags & Hooks.AFTER_INITIALIZE_FLAG) != 0 ? "YES" : "NO"
        );
        console2.log("  BEFORE_ADD_LIQUIDITY:", 
            (ourFlags & Hooks.BEFORE_ADD_LIQUIDITY_FLAG) != 0 ? "YES" : "NO",
            "/",
            (clankerFlags & Hooks.BEFORE_ADD_LIQUIDITY_FLAG) != 0 ? "YES" : "NO"
        );
        console2.log("  BEFORE_SWAP:", 
            (ourFlags & Hooks.BEFORE_SWAP_FLAG) != 0 ? "YES" : "NO",
            "/",
            (clankerFlags & Hooks.BEFORE_SWAP_FLAG) != 0 ? "YES" : "NO"
        );
        console2.log("  AFTER_SWAP:", 
            (ourFlags & Hooks.AFTER_SWAP_FLAG) != 0 ? "YES" : "NO",
            "/",
            (clankerFlags & Hooks.AFTER_SWAP_FLAG) != 0 ? "YES" : "NO"
        );
        console2.log("  BEFORE_SWAP_RETURNS_DELTA:", 
            (ourFlags & Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG) != 0 ? "YES" : "NO",
            "/",
            (clankerFlags & Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG) != 0 ? "YES" : "NO"
        );
        console2.log("  AFTER_SWAP_RETURNS_DELTA:", 
            (ourFlags & Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG) != 0 ? "YES" : "NO",
            "/",
            (clankerFlags & Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG) != 0 ? "YES" : "NO"
        );
        console2.log("");
        
        // 2. Build pool keys
        IPoolManager pm = IPoolManager(POOL_MANAGER);
        
        // Our pool (token is currency0 since OUR_TOKEN < WETH)
        bool ourTokenIsCurrency0 = OUR_TOKEN < WETH;
        PoolKey memory ourKey = PoolKey({
            currency0: Currency.wrap(ourTokenIsCurrency0 ? OUR_TOKEN : WETH),
            currency1: Currency.wrap(ourTokenIsCurrency0 ? WETH : OUR_TOKEN),
            fee: 8388608,
            tickSpacing: 200,
            hooks: IHooks(OUR_HOOK)
        });
        
        // Clanker pool (determine currency order)
        bool clankerTokenIsCurrency0 = CLANKER_TOKEN < WETH;
        PoolKey memory clankerKey = PoolKey({
            currency0: Currency.wrap(clankerTokenIsCurrency0 ? CLANKER_TOKEN : WETH),
            currency1: Currency.wrap(clankerTokenIsCurrency0 ? WETH : CLANKER_TOKEN),
            fee: 8388608,
            tickSpacing: 200,
            hooks: IHooks(CLANKER_HOOK)
        });
        
        console2.log("2. POOL CONFIGURATION");
        console2.log("----------------------");
        console2.log("Our token is currency0:", ourTokenIsCurrency0);
        console2.log("Clanker token is currency0:", clankerTokenIsCurrency0);
        console2.log("");
        
        console2.log("Our pool ID:");
        console2.logBytes32(PoolId.unwrap(ourKey.toId()));
        console2.log("Clanker pool ID:");
        console2.logBytes32(PoolId.unwrap(clankerKey.toId()));
        console2.log("");
        
        // 3. Get pool states
        console2.log("3. POOL STATES");
        console2.log("--------------");
        
        (uint160 ourSqrtPrice, int24 ourTick,,) = pm.getSlot0(ourKey.toId());
        uint128 ourLiquidity = pm.getLiquidity(ourKey.toId());
        
        console2.log("OUR POOL:");
        console2.log("  sqrtPriceX96:", ourSqrtPrice);
        console2.log("  tick:", ourTick);
        console2.log("  liquidity:", ourLiquidity);
        console2.log("");
        
        (uint160 clankerSqrtPrice, int24 clankerTick,,) = pm.getSlot0(clankerKey.toId());
        uint128 clankerLiquidity = pm.getLiquidity(clankerKey.toId());
        
        console2.log("CLANKER POOL:");
        console2.log("  sqrtPriceX96:", clankerSqrtPrice);
        console2.log("  tick:", clankerTick);
        console2.log("  liquidity:", clankerLiquidity);
        console2.log("");
        
        // 4. Check fee encoding
        console2.log("4. FEE ENCODING");
        console2.log("---------------");
        console2.log("Both pools should have fee = 8388608 (0x800000)");
        console2.log("This is the DYNAMIC_FEE_FLAG");
        console2.log("Our fee:", ourKey.fee);
        console2.log("Clanker fee:", clankerKey.fee);
    }
}
