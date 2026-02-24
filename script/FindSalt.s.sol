// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

contract FindSalt is Script {
    address constant FACTORY = 0x70b17db500Ce1746BB34f908140d0279C183f3eb;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    // From Clanker.sol - token init code hash
    bytes32 constant TOKEN_INIT_HASH = 0x30c23d91a33d5e6c53b4e57b2a8bdd73ab74516d029cbb25767e78973e7e877c;
    
    function run() external view {
        console.log("Finding salt where token > WETH...");
        console.log("WETH:", WETH);
        
        for (uint256 salt = 0; salt < 1000; salt++) {
            address predicted = computeTokenAddress(salt);
            if (predicted > WETH) {
                console.log("FOUND! Salt:", salt);
                console.log("Token address:", predicted);
                return;
            }
        }
        console.log("No salt found in range 0-999");
    }
    
    function computeTokenAddress(uint256 salt) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            FACTORY,
            bytes32(salt),
            TOKEN_INIT_HASH
        )))));
    }
}
