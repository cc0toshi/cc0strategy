// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ClankerToken} from "../src/ClankerToken.sol";

/**
 * @title FindCurrency0Salt
 * @notice Find a salt that produces token address < WETH (so token is currency0)
 */
contract FindCurrency0Salt is Script {
    address constant FACTORY = 0x70b17db500Ce1746BB34f908140d0279C183f3eb;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    function run() public {
        address tokenAdmin = 0x9fc58FdfE6B2C8EC6688aE74bda0a3A269EF1201;
        
        console2.log("Mining for token address < WETH (currency0)...");
        console2.log("WETH:", WETH);
        console2.log("");
        
        // Calculate init code hash
        bytes memory initCode = abi.encodePacked(
            type(ClankerToken).creationCode,
            abi.encode(
                "BasedMferdickbuttStrategy",
                "DICKSTR",
                100_000_000_000 * 1e18,
                tokenAdmin,
                "ipfs://QmBasedMferDickButts",
                "cc0strategy token",
                "cc0strategy v3",
                uint256(8453)
            )
        );
        bytes32 initCodeHash = keccak256(initCode);
        
        uint256 found = 0;
        for (uint256 i = 0; i < 50000; i++) {
            bytes32 userSalt = bytes32(i);
            bytes32 actualSalt = keccak256(abi.encode(tokenAdmin, userSalt));
            
            address predicted = address(uint160(uint256(keccak256(abi.encodePacked(
                bytes1(0xff),
                FACTORY,
                actualSalt,
                initCodeHash
            )))));
            
            if (predicted < WETH) {
                console2.log("=== FOUND ===");
                console2.log("Salt (decimal):", i);
                console2.log("Token address:", predicted);
                found++;
                if (found >= 3) return; // Show first 3
            }
        }
        
        if (found == 0) {
            console2.log("No valid salt found in first 50000");
        }
    }
}
