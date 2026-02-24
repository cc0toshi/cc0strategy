// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

contract MineSalt is Script {
    address constant FACTORY = 0x70b17db500Ce1746BB34f908140d0279C183f3eb;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    // ClankerToken creation code hash (from factory deployment)
    bytes32 constant INIT_CODE_HASH = 0x0e55e4b4402f16e3ab7a2fc986cfc9c3a40e3b04b18b51e76c1dc5b4b1d67a2d;
    
    function run() public view {
        console2.log("Mining for token address > WETH...");
        console2.log("WETH:", WETH);
        console2.log("");
        
        // The token is deployed via CREATE2 from factory
        // address = keccak256(0xff ++ factory ++ salt ++ initCodeHash)[12:]
        
        // Need to find salt where resulting address > WETH
        // WETH = 0x4200000000000000000000000000000000000006
        // So we need address > 0x42...
        
        for (uint256 i = 0; i < 1000; i++) {
            bytes32 salt = bytes32(i);
            address predicted = address(uint160(uint256(keccak256(abi.encodePacked(
                bytes1(0xff),
                FACTORY,
                salt,
                INIT_CODE_HASH
            )))));
            
            if (predicted > WETH) {
                console2.log("Found valid salt!");
                console2.log("Salt (decimal):", i);
                console2.log("Predicted address:", predicted);
                return;
            }
        }
        
        console2.log("No valid salt found in first 1000");
    }
}
