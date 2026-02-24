// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

/**
 * @title ClankerStyleSwap
 * @notice Use exact same swap pattern as Clanker DevBuy
 */
contract ClankerStyleSwap is Script {
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TOKEN = 0x3b68C3B4e22E35Faf5841D1b5Eef8404D5A3b663;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address swapper = vm.addr(pk);
        
        console2.log("=== Clanker-Style Swap ===");
        console2.log("Swapper:", swapper);
        
        // Token < WETH, so token is currency0
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(TOKEN),
            currency1: Currency.wrap(WETH),
            fee: 8388608,
            tickSpacing: 200,
            hooks: IHooks(HOOK)
        });
        
        uint256 tokenBefore = IERC20(TOKEN).balanceOf(swapper);
        console2.log("Token balance before:", tokenBefore);
        
        uint128 amountIn = 0.0003 ether;
        
        vm.startBroadcast(pk);
        
        // 1. Wrap ETH to WETH
        IWETH(WETH).deposit{value: amountIn}();
        console2.log("Wrapped ETH to WETH:", amountIn);
        
        // 2. Approve WETH to Permit2
        IERC20(WETH).approve(PERMIT2, amountIn);
        console2.log("Approved Permit2");
        
        // 3. Permit2 approve Universal Router
        IPermit2(PERMIT2).approve(WETH, UNIVERSAL_ROUTER, uint160(amountIn), uint48(block.timestamp + 3600));
        console2.log("Permit2 approved Universal Router");
        
        // 4. Build Universal Router V4 swap (exactly like Clanker)
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        
        bytes[] memory params = new bytes[](3);
        
        // SWAP_EXACT_IN_SINGLE - using IV4Router.ExactInputSingleParams
        // We're swapping WETH (currency1) for TOKEN (currency0)
        // So zeroForOne = false
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: false, // WETH -> TOKEN
                amountIn: amountIn,
                amountOutMinimum: 1,
                hookData: bytes("")
            })
        );
        
        // SETTLE_ALL - tokenIn, amountIn
        params[1] = abi.encode(WETH, uint256(amountIn));
        
        // TAKE_ALL - tokenOut, minAmount (1)
        params[2] = abi.encode(TOKEN, uint256(1));
        
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        
        console2.log("Executing swap...");
        IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 300);
        
        vm.stopBroadcast();
        
        uint256 tokenAfter = IERC20(TOKEN).balanceOf(swapper);
        console2.log("Token balance after:", tokenAfter);
        console2.log("Tokens received:", tokenAfter - tokenBefore);
    }
}
