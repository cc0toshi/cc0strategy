// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Predeploys
 * @notice Stub library for Base/OP Stack predeploy addresses
 */
library Predeploys {
    /// @notice Address of the L2ToL2CrossDomainMessenger predeploy
    address internal constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = 0x4200000000000000000000000000000000000023;
    
    /// @notice Address of the SuperchainTokenBridge predeploy
    address internal constant SUPERCHAIN_TOKEN_BRIDGE = 0x4200000000000000000000000000000000000028;
}
