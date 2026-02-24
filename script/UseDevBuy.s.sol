// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
}

interface IClankerDevBuy {
    function buyWithEth(
        address token,
        PoolKey calldata key,
        address recipient,
        uint256 minAmountOut
    ) external payable;
}

/**
 * @title UseDevBuy
 * @notice Try using Clanker's DevBuy contract to swap
 */
contract UseDevBuy is Script {
    address constant CLANKER_DEVBUY = 0x1331f0788F9c08C8F38D52c7a1152250A9dE00be;
    address constant TOKEN = 0x3b68C3B4e22E35Faf5841D1b5Eef8404D5A3b663;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address swapper = vm.addr(pk);
        
        console2.log("=== Trying Clanker DevBuy Contract ===");
        console2.log("Swapper:", swapper);
        console2.log("DevBuy:", CLANKER_DEVBUY);
        
        // Token < WETH
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(TOKEN),
            currency1: Currency.wrap(WETH),
            fee: 8388608,
            tickSpacing: 200,
            hooks: IHooks(HOOK)
        });
        
        uint256 tokenBefore = IERC20(TOKEN).balanceOf(swapper);
        console2.log("Token balance before:", tokenBefore);
        
        vm.startBroadcast(pk);
        
        console2.log("Calling buyWithEth with 0.0003 ETH...");
        IClankerDevBuy(CLANKER_DEVBUY).buyWithEth{value: 0.0003 ether}(
            TOKEN,
            key,
            swapper,
            0 // minAmountOut
        );
        
        vm.stopBroadcast();
        
        uint256 tokenAfter = IERC20(TOKEN).balanceOf(swapper);
        console2.log("Token balance after:", tokenAfter);
        console2.log("Tokens received:", tokenAfter - tokenBefore);
    }
}
