// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ClankerHookStaticFee} from "../src/hooks/ClankerHookStaticFee.sol";
import {HookDeployer} from "../src/utils/HookDeployer.sol";

/**
 * @title DeployHook
 * @notice Deploy hook using HookDeployer for CREATE2 with EXACT permission bits
 */
contract DeployHook is Script {
    // Base Mainnet
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    // Deployed contracts from Phase 1
    address constant FACTORY = 0x70b17db500Ce1746BB34f908140d0279C183f3eb;
    
    // Hook permission flags (EXACT - no extra bits!)
    uint160 constant REQUIRED_FLAGS = uint160(
        Hooks.BEFORE_INITIALIZE_FLAG |       // 1 << 13 = 0x2000
        Hooks.BEFORE_ADD_LIQUIDITY_FLAG |    // 1 << 11 = 0x0800
        Hooks.BEFORE_SWAP_FLAG |             // 1 << 7  = 0x0080
        Hooks.AFTER_SWAP_FLAG |              // 1 << 6  = 0x0040
        Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | // 1 << 3 = 0x0008
        Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG    // 1 << 2 = 0x0004
    ); // Total = 0x28CC
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Deploying Hook");
        console2.log("===============");
        console2.log("Deployer:", deployer);
        console2.log("Required flags (exact):", uint256(REQUIRED_FLAGS));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy HookDeployer first
        HookDeployer hookDeployer = new HookDeployer();
        console2.log("HookDeployer:", address(hookDeployer));
        
        // Compute creation code
        bytes memory creationCode = abi.encodePacked(
            type(ClankerHookStaticFee).creationCode,
            abi.encode(POOL_MANAGER, FACTORY, WETH)
        );
        bytes32 initCodeHash = keccak256(creationCode);
        
        // Mine salt for EXACT permission bits match (last 16 bits must equal REQUIRED_FLAGS)
        console2.log("Mining salt for exact bit match...");
        bytes32 salt;
        address predictedAddress;
        bool found = false;
        
        for (uint256 i = 0; i < 10000000; i++) {
            salt = bytes32(i);
            predictedAddress = hookDeployer.computeAddress(salt, initCodeHash);
            
            // EXACT match: last 16 bits must equal REQUIRED_FLAGS exactly
            if (uint160(predictedAddress) & 0xFFFF == REQUIRED_FLAGS) {
                console2.log("Found salt at iteration:", i);
                found = true;
                break;
            }
            
            if (i > 0 && i % 500000 == 0) {
                console2.log("Checked", i, "salts...");
            }
        }
        
        require(found, "Could not find valid salt");
        console2.log("Salt:", uint256(salt));
        console2.log("Predicted address:", predictedAddress);
        console2.log("Address last 16 bits:", uint160(predictedAddress) & 0xFFFF);
        
        // Deploy hook via HookDeployer
        address hookAddress = hookDeployer.deploy(salt, creationCode);
        console2.log("Hook deployed:", hookAddress);
        
        vm.stopBroadcast();
        
        // Verify
        require(hookAddress == predictedAddress, "Address mismatch!");
        require(uint160(hookAddress) & 0xFFFF == REQUIRED_FLAGS, "Invalid hook permissions!");
        
        console2.log("");
        console2.log("SUCCESS!");
        console2.log("HookDeployer:", address(hookDeployer));
        console2.log("Hook:", hookAddress);
    }
}
