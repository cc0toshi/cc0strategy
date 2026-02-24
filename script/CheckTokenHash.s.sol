// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/ClankerToken.sol";

contract CheckTokenHash is Script {
    address constant FACTORY = 0x70b17db500Ce1746BB34f908140d0279C183f3eb;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    function run() external view {
        // Get the actual init code hash for ClankerToken
        bytes memory initCode = type(ClankerToken).creationCode;
        bytes32 initHash = keccak256(initCode);
        console.log("ClankerToken init code hash:");
        console.logBytes32(initHash);
        
        // Our deployed token
        address ourToken = 0x3b68C3B4e22E35Faf5841D1b5Eef8404D5A3b663;
        console.log("Our token:", ourToken);
        console.log("WETH:", WETH);
        console.log("Our token < WETH?", ourToken < WETH);
        
        // Check what salt gives what address
        for (uint256 salt = 0; salt < 10; salt++) {
            address predicted = address(uint160(uint256(keccak256(abi.encodePacked(
                bytes1(0xff),
                FACTORY,
                bytes32(salt),
                initHash
            )))));
            bool isGood = predicted > WETH;
            console.log("Salt", salt);
            console.log("  Address:", predicted);
            console.log("  currency1 (GOOD)?", isGood);
        }
    }
}
