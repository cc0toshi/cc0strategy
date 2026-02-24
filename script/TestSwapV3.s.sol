// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
}

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

interface IPositionManager {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
}

/**
 * @title TestSwapV3
 * @notice Execute test swap on V3 token (currency0)
 */
contract TestSwapV3 is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TOKEN_V3 = 0x3b68C3B4e22E35Faf5841D1b5Eef8404D5A3b663;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address swapper = vm.addr(pk);
        
        console2.log("=== Test Swap V3 ===");
        console2.log("Swapper:", swapper);
        console2.log("Swap: 0.0001 WETH -> DICKSTR");
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
        
        (uint160 sqrtPriceX96, int24 tickBefore,,) = pm.getSlot0(poolId);
        uint128 liquidity = pm.getLiquidity(poolId);
        
        console2.log("Pool State Before:");
        console2.log("  tick:", tickBefore);
        console2.log("  liquidity:", liquidity);
        console2.log("");
        
        // Check balances before
        uint256 tokenBefore = IERC20(TOKEN_V3).balanceOf(swapper);
        console2.log("Token balance before:", tokenBefore);
        
        vm.startBroadcast(pk);
        
        // Build Universal Router V4 swap
        // Command: 0x10 = V4_SWAP
        bytes memory commands = hex"10";
        
        // V4 actions: SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        
        uint128 swapAmount = 0.0001 ether;
        
        // Params for each action
        bytes[] memory params = new bytes[](3);
        
        // SWAP_EXACT_IN_SINGLE: swap WETH for TOKEN
        // zeroForOne = false (currency1 -> currency0, WETH -> TOKEN)
        params[0] = abi.encode(
            key,
            false,           // zeroForOne (false = WETH -> TOKEN)
            swapAmount,      // amountIn
            uint128(0),      // amountOutMinimum
            bytes("")        // hookData
        );
        
        // SETTLE_ALL: settle WETH
        params[1] = abi.encode(
            Currency.wrap(WETH),
            uint256(swapAmount)
        );
        
        // TAKE_ALL: take TOKEN
        params[2] = abi.encode(
            Currency.wrap(TOKEN_V3),
            uint256(0)
        );
        
        bytes memory routerInput = abi.encode(actions, params);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = routerInput;
        
        console2.log("Executing swap via Universal Router...");
        
        IUniversalRouter(UNIVERSAL_ROUTER).execute{value: swapAmount}(
            commands,
            inputs,
            block.timestamp + 300
        );
        
        vm.stopBroadcast();
        
        // Check after
        uint256 tokenAfter = IERC20(TOKEN_V3).balanceOf(swapper);
        (, int24 tickAfter,,) = pm.getSlot0(poolId);
        
        console2.log("");
        console2.log("=== SWAP COMPLETE ===");
        console2.log("Tokens received:", tokenAfter - tokenBefore);
        console2.log("Tick after:", tickAfter);
        console2.log("Tick moved by:", int256(tickAfter) - int256(tickBefore));
    }
}
