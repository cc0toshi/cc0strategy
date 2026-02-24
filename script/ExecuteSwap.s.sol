// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IPositionManager {
    function initializePool(PoolKey calldata key, uint160 sqrtPriceX96) external payable returns (int24);
}

interface IV4Router {
    struct SwapExactInSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }
    
    function swapExactInSingle(SwapExactInSingleParams memory params) external payable;
}

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

/**
 * @title ExecuteSwap
 * @notice Actually execute a swap via Universal Router on Base mainnet
 */
contract ExecuteSwap is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant V4_ROUTER = 0x5Dc88340E1c5c6366864Ee415d6034cadd1A9897;
    
    address public TOKEN;
    
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address swapper = vm.addr(pk);
        TOKEN = vm.envAddress("TOKEN_ADDRESS");
        
        console2.log("=== Execute Swap ===");
        console2.log("Swapper:", swapper);
        console2.log("Token:", TOKEN);
        console2.log("Swap: 0.001 ETH -> DICKSTR");
        console2.log("");
        
        // Build pool key
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(WETH),
            currency1: Currency.wrap(TOKEN),
            fee: 8388608, // Dynamic fee flag
            tickSpacing: 200,
            hooks: IHooks(HOOK)
        });
        
        // Check pool state first
        IPoolManager pm = IPoolManager(POOL_MANAGER);
        PoolId poolId = key.toId();
        
        (uint160 sqrtPriceX96, int24 currentTick,,) = pm.getSlot0(poolId);
        uint128 liquidity = pm.getLiquidity(poolId);
        
        console2.log("Pool State:");
        console2.log("  sqrtPriceX96:", sqrtPriceX96);
        console2.log("  currentTick:", currentTick);
        console2.log("  liquidity:", liquidity);
        console2.log("");
        
        if (liquidity == 0) {
            console2.log("ERROR: No liquidity! Cannot swap.");
            return;
        }
        
        uint256 swapAmount = 0.001 ether;
        
        // Check balances before
        uint256 ethBefore = swapper.balance;
        uint256 tokenBefore = IERC20(TOKEN).balanceOf(swapper);
        console2.log("Balances Before:");
        console2.log("  ETH:", ethBefore);
        console2.log("  TOKEN:", tokenBefore);
        console2.log("");
        
        vm.startBroadcast(pk);
        
        // Build Universal Router commands for V4 swap
        // Command 0x10 = V4_SWAP
        bytes memory commands = hex"10"; // V4_SWAP command
        
        // Build V4 actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        
        // Encode swap params
        bytes[] memory params = new bytes[](3);
        
        // SWAP_EXACT_IN_SINGLE params
        params[0] = abi.encode(
            key,           // poolKey
            true,          // zeroForOne (WETH -> TOKEN)
            uint128(swapAmount), // amountIn
            uint128(0),    // amountOutMinimum
            bytes("")      // hookData
        );
        
        // SETTLE_ALL params (currency, maxAmount)
        params[1] = abi.encode(
            Currency.wrap(WETH),
            uint256(swapAmount)
        );
        
        // TAKE_ALL params (currency, minAmount)
        params[2] = abi.encode(
            Currency.wrap(TOKEN),
            uint256(0)
        );
        
        // Combine into V4Router input
        bytes memory v4RouterInput = abi.encode(actions, params);
        
        // Universal Router inputs array
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = v4RouterInput;
        
        console2.log("Executing swap via Universal Router...");
        
        // Execute with ETH value (will be wrapped to WETH)
        IUniversalRouter(UNIVERSAL_ROUTER).execute{value: swapAmount}(
            commands,
            inputs,
            block.timestamp + 300
        );
        
        vm.stopBroadcast();
        
        // Check balances after
        uint256 ethAfter = swapper.balance;
        uint256 tokenAfter = IERC20(TOKEN).balanceOf(swapper);
        console2.log("");
        console2.log("Balances After:");
        console2.log("  ETH:", ethAfter);
        console2.log("  TOKEN:", tokenAfter);
        console2.log("");
        console2.log("Tokens received:", tokenAfter - tokenBefore);
        console2.log("ETH spent:", ethBefore - ethAfter);
    }
}
