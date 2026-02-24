// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract DoSwap is Script {
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TOKEN = 0xCBBbF8158A5B41c09ec8dE9e69F90E878bCec203;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        
        console2.log("Swapper:", deployer);
        console2.log("Attempting to buy DICKSTR with 0.0004 ETH (~$1)");
        
        vm.startBroadcast(pk);
        
        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: 0.0004 ether}();
        console2.log("Wrapped ETH to WETH");
        
        // Approve PoolManager
        IWETH(WETH).approve(POOL_MANAGER, type(uint256).max);
        console2.log("Approved PoolManager");
        
        vm.stopBroadcast();
        
        console2.log("");
        console2.log("WETH deposited and approved. Need to use Universal Router for actual swap.");
        console2.log("Universal Router:", UNIVERSAL_ROUTER);
    }
}
