// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC7802
 * @notice Stub interface for crosschain token interface (Base L2)
 */
interface IERC7802 {
    /// @notice Emitted when a crosschain transfer mints tokens.
    event CrosschainMint(address indexed to, uint256 amount, address indexed sender);
    
    /// @notice Emitted when a crosschain transfer burns tokens.
    event CrosschainBurn(address indexed from, uint256 amount, address indexed sender);
    
    /// @notice Mint tokens through a crosschain transfer.
    function crosschainMint(address _to, uint256 _amount) external;
    
    /// @notice Burn tokens through a crosschain transfer.
    function crosschainBurn(address _from, uint256 _amount) external;
    
    /// @notice Returns true if the contract supports crosschain functionality.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
