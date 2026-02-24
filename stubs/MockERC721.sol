// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC721
 * @notice Simple mock NFT collection for testing cc0strategy
 */
contract MockERC721 is ERC721, Ownable {
    uint256 private _totalSupply;
    
    constructor(string memory name_, string memory symbol_) 
        ERC721(name_, symbol_) 
        Ownable(msg.sender) 
    {}
    
    function mint(address to, uint256 tokenId) external onlyOwner {
        _mint(to, tokenId);
        _totalSupply++;
    }
    
    function batchMint(address to, uint256 startId, uint256 count) external onlyOwner {
        for (uint256 i = 0; i < count; i++) {
            _mint(to, startId + i);
            _totalSupply++;
        }
    }
    
    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        _burn(tokenId);
        _totalSupply--;
    }
    
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
}
