// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Simple CREATE2 deployer for hooks
contract HookDeployer {
    event Deployed(address indexed addr, bytes32 indexed salt);
    
    function deploy(bytes32 salt, bytes memory creationCode) external returns (address addr) {
        assembly {
            addr := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
        emit Deployed(addr, salt);
    }
    
    function computeAddress(bytes32 salt, bytes32 initCodeHash) external view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            initCodeHash
        )))));
    }
}
