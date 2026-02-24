// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

interface IFeeDistributor {
    function tokenToCollection(address token) external view returns (address);
    function tokenToNftSupply(address token) external view returns (uint256);
    function tokenToFeeToken(address token) external view returns (address);
}

contract CheckFeeDistributor is Script {
    address constant FEE_DISTRIBUTOR = 0x9Ce2AB2769CcB547aAcE963ea4493001275CD557;
    address constant TOKEN_V3 = 0x3b68C3B4e22E35Faf5841D1b5Eef8404D5A3b663;
    address constant NFT_COLLECTION = 0x5c5D3CBaf7a3419af8E6661486B2D5Ec3AccfB1B;
    
    function run() public view {
        IFeeDistributor fd = IFeeDistributor(FEE_DISTRIBUTOR);
        
        console2.log("=== FeeDistributor Check ===");
        console2.log("");
        console2.log("Token V3:", TOKEN_V3);
        console2.log("Expected NFT:", NFT_COLLECTION);
        console2.log("");
        
        address registeredNft = fd.tokenToCollection(TOKEN_V3);
        uint256 nftSupply = fd.tokenToNftSupply(TOKEN_V3);
        address feeToken = fd.tokenToFeeToken(TOKEN_V3);
        
        console2.log("Registered NFT:", registeredNft);
        console2.log("NFT Supply:", nftSupply);
        console2.log("Fee Token:", feeToken);
        console2.log("");
        
        if (registeredNft == NFT_COLLECTION && nftSupply > 0) {
            console2.log("SUCCESS: Token registered with FeeDistributor!");
            console2.log("NFT holders can claim trading fees!");
        } else if (registeredNft == address(0)) {
            console2.log("WARNING: Token not registered yet");
        } else {
            console2.log("WARNING: NFT supply = 0");
        }
    }
}
