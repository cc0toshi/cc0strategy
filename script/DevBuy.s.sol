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
    function approve(address spender, uint256 amount) external returns (bool);
}

/**
 * @title DevBuy
 * @notice Execute a devbuy on the V1 token to push tick into range
 * 
 * Current state:
 * - Token: 0xCBBbF8158A5B41c09ec8dE9e69F90E878bCec203 (currency1, > WETH)
 * - Pool tick: +230400
 * - Position: actual ticks [-887200, -230400]  
 * - Liquidity is OUTSIDE range (tick > tickUpper)
 * 
 * Problem: For currency1, buying TOKEN moves tick DOWN.
 * But tick needs to go DOWN into [-887200, -230400] from +230400.
 * That's a HUGE gap! Would need massive buy to move tick by 230400 + 230400 = 460800 ticks.
 * 
 * Actually... the issue is deeper. The position [-887200, -230400] is in NEGATIVE ticks.
 * CurrentTick +230400 needs to decrease to enter that range.
 * Each tick = 0.01% price move. 460800 ticks = 10^(460800 * log10(1.0001)) = impossible amount.
 * 
 * CONCLUSION: The V1 position is fundamentally broken. Need new deployment with correct ticks.
 */
contract DevBuy is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TOKEN_V1 = 0xCBBbF8158A5B41c09ec8dE9e69F90E878bCec203;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    
    function run() public view {
        console2.log("=== DevBuy Analysis ===");
        console2.log("");
        
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(WETH),
            currency1: Currency.wrap(TOKEN_V1),
            fee: 8388608,
            tickSpacing: 200,
            hooks: IHooks(HOOK)
        });
        
        IPoolManager pm = IPoolManager(POOL_MANAGER);
        PoolId poolId = key.toId();
        
        (uint160 sqrtPriceX96, int24 currentTick,,) = pm.getSlot0(poolId);
        uint128 liquidity = pm.getLiquidity(poolId);
        
        console2.log("Pool State:");
        console2.log("  currentTick:", currentTick);
        console2.log("  sqrtPriceX96:", sqrtPriceX96);
        console2.log("  active liquidity:", liquidity);
        console2.log("");
        
        console2.log("Position Analysis:");
        console2.log("  Config tickLower: 230400");
        console2.log("  Config tickUpper: 887200");
        console2.log("  Actual tickLower (after transform): -887200");
        console2.log("  Actual tickUpper (after transform): -230400");
        console2.log("");
        
        console2.log("Problem:");
        console2.log("  Current tick (+230400) is ABOVE position's tickUpper (-230400)");
        console2.log("  Tick needs to decrease by ~460800 ticks to enter range");
        console2.log("  This would require buying essentially infinite tokens");
        console2.log("");
        
        console2.log("CONCLUSION:");
        console2.log("  V1 position is fundamentally broken due to tick transformation.");
        console2.log("  Need to deploy new locker with fixed tick validation.");
    }
}
