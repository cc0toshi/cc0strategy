// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

/**
 * @title SwapHelper
 * @notice Simple helper to swap ETH for DICKSTR token
 * Anyone can call this to buy DICKSTR with ETH
 */
contract SwapHelper {
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TOKEN = 0x3b68C3B4e22E35Faf5841D1b5Eef8404D5A3b663;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    
    PoolKey public poolKey;
    
    constructor() {
        poolKey = PoolKey({
            currency0: Currency.wrap(TOKEN),
            currency1: Currency.wrap(WETH),
            fee: 8388608,
            tickSpacing: 200,
            hooks: IHooks(HOOK)
        });
    }
    
    /**
     * @notice Buy DICKSTR tokens with ETH
     * @param minOut Minimum tokens to receive
     */
    function buyWithEth(uint256 minOut) external payable {
        require(msg.value > 0, "No ETH sent");
        
        uint128 amountIn = uint128(msg.value);
        
        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: amountIn}();
        
        // Approve Permit2
        IERC20(WETH).approve(PERMIT2, amountIn);
        
        // Permit2 approve Universal Router
        IPermit2(PERMIT2).approve(WETH, UNIVERSAL_ROUTER, uint160(amountIn), uint48(block.timestamp + 3600));
        
        // Build swap
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: false,
                amountIn: amountIn,
                amountOutMinimum: uint128(minOut),
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(WETH, uint256(amountIn));
        params[2] = abi.encode(TOKEN, minOut);
        
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        
        // Execute swap
        IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 300);
        
        // Transfer tokens to sender
        uint256 balance = IERC20(TOKEN).balanceOf(address(this));
        IERC20(TOKEN).transfer(msg.sender, balance);
    }
    
    receive() external payable {}
}
