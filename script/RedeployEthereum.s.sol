// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

// Protocol contracts
import {ClankerPoolExtensionAllowlist} from "../src/hooks/ClankerPoolExtensionAllowlist.sol";
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {CC0StrategyLpLocker} from "../src/lp-lockers/CC0StrategyLpLocker.sol";
import {ClankerHookStaticFee} from "../src/hooks/ClankerHookStaticFee.sol";
import {Clanker} from "../src/Clanker.sol";
import {ClankerMevBlockDelay} from "../src/mev-modules/ClankerMevBlockDelay.sol";
import {HookDeployer} from "../src/utils/HookDeployer.sol";

/**
 * @title RedeployEthereum
 * @notice Fresh deployment of cc0strategy protocol to Ethereum Mainnet
 * @dev Does NOT transfer ownership - keeps burner as owner
 */
contract RedeployEthereum is Script {
    // Ethereum Mainnet addresses
    address constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address constant UNIVERSAL_ROUTER = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    address public treasury = 0x58e510F849e38095375a3e478aD1d719650B8557;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("=====================================");
        console2.log("cc0strategy - Ethereum Mainnet REDEPLOY");
        console2.log("=====================================");
        console2.log("Deployer:", deployer);
        console2.log("Balance:", deployer.balance);
        console2.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy PoolExtensionAllowlist
        console2.log("Step 1: Deploying PoolExtensionAllowlist...");
        ClankerPoolExtensionAllowlist poolExtensionAllowlist = new ClankerPoolExtensionAllowlist(deployer);
        console2.log("  PoolExtensionAllowlist:", address(poolExtensionAllowlist));
        
        // Step 2: Deploy FeeDistributor
        console2.log("Step 2: Deploying FeeDistributor...");
        FeeDistributor feeDistributor = new FeeDistributor(
            treasury,
            address(1), // placeholder lpLocker
            address(1), // placeholder factory  
            deployer    // owner
        );
        console2.log("  FeeDistributor:", address(feeDistributor));
        
        // Step 3: Deploy MevModule
        console2.log("Step 3: Deploying MevModule...");
        ClankerMevBlockDelay mevModule = new ClankerMevBlockDelay(1);
        console2.log("  MevModule:", address(mevModule));
        
        // Step 4: Deploy Factory
        console2.log("Step 4: Deploying Factory...");
        Clanker factory = new Clanker(deployer, address(feeDistributor));
        console2.log("  Factory:", address(factory));
        
        // Step 5: Deploy HookDeployer
        console2.log("Step 5: Deploying HookDeployer...");
        HookDeployer hookDeployer = new HookDeployer();
        console2.log("  HookDeployer:", address(hookDeployer));
        
        // Step 6: Mine salt and deploy Hook
        console2.log("Step 6: Mining salt and deploying Hook...");
        ClankerHookStaticFee hook = deployHookWithSalt(hookDeployer, address(factory));
        console2.log("  Hook:", address(hook));
        
        // Step 7: Deploy LpLocker
        console2.log("Step 7: Deploying LpLocker...");
        CC0StrategyLpLocker lpLocker = new CC0StrategyLpLocker(
            deployer,
            address(factory),
            address(feeDistributor),
            POSITION_MANAGER,
            PERMIT2,
            UNIVERSAL_ROUTER,
            POOL_MANAGER
        );
        console2.log("  LpLocker:", address(lpLocker));
        
        // Step 8: Update FeeDistributor
        console2.log("Step 8: Updating FeeDistributor...");
        feeDistributor.setLpLocker(address(lpLocker));
        feeDistributor.setFactory(address(factory));
        
        // Step 9: Configure Factory (CRITICAL - this was missed before!)
        console2.log("Step 9: Configuring Factory...");
        factory.setTeamFeeRecipient(treasury);
        factory.setHook(address(hook), true);
        factory.setLocker(address(lpLocker), address(hook), true);
        factory.setMevModule(address(mevModule), true);
        factory.setDeprecated(false);
        console2.log("  Factory configured!");
        
        // Step 10: Verify Hook factory
        console2.log("Step 10: Verifying Hook...");
        console2.log("  Hook.factory():", hook.factory());
        require(hook.factory() == address(factory), "Hook factory mismatch!");
        
        vm.stopBroadcast();
        
        // Verify configuration
        console2.log("");
        console2.log("=====================================");
        console2.log("VERIFICATION");
        console2.log("=====================================");
        console2.log("factory.enabledLockers(locker,hook):", factory.enabledLockers(address(lpLocker), address(hook)));
        console2.log("factory.deprecated():", factory.deprecated());
        console2.log("hook.factory():", hook.factory());
        
        // Verify critical config
        require(factory.enabledLockers(address(lpLocker), address(hook)), "Locker not enabled!");
        require(!factory.deprecated(), "Factory still deprecated!");
        require(hook.factory() == address(factory), "Hook factory mismatch!");
        
        // Print summary
        console2.log("");
        console2.log("=====================================");
        console2.log("DEPLOYMENT COMPLETE!");
        console2.log("=====================================");
        console2.log("PoolExtensionAllowlist:", address(poolExtensionAllowlist));
        console2.log("FeeDistributor:", address(feeDistributor));
        console2.log("MevModule:", address(mevModule));
        console2.log("Factory:", address(factory));
        console2.log("HookDeployer:", address(hookDeployer));
        console2.log("Hook:", address(hook));
        console2.log("LpLocker:", address(lpLocker));
        console2.log("");
        console2.log("Owner (burner - NOT transferred):", deployer);
    }
    
    function deployHookWithSalt(HookDeployer hookDeployer, address factory_) internal returns (ClankerHookStaticFee) {
        // Hook permission flags - must match EXACTLY (no extra bits allowed)
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        
        // ALL_HOOK_MASK = 14 bits for hook permissions
        uint160 ALL_HOOK_MASK = uint160((1 << 14) - 1);
        
        bytes memory creationCode = abi.encodePacked(
            type(ClankerHookStaticFee).creationCode,
            abi.encode(POOL_MANAGER, factory_, WETH)
        );
        bytes32 initCodeHash = keccak256(creationCode);
        
        console2.log("  Required flags:", uint256(flags));
        console2.log("  ALL_HOOK_MASK:", uint256(ALL_HOOK_MASK));
        console2.log("  Mining salt...");
        
        // Mine for valid salt - address must have EXACTLY the required flags (no extra bits)
        for (uint256 i = 0; i < 50000000; i++) {
            bytes32 salt = bytes32(i);
            address predicted = hookDeployer.computeAddress(salt, initCodeHash);
            
            // Check that ONLY the required flag bits are set (exact match)
            if ((uint160(predicted) & ALL_HOOK_MASK) == flags) {
                console2.log("  Found salt:", i);
                console2.log("  Predicted address:", predicted);
                console2.log("  Address flags:", uint256(uint160(predicted) & ALL_HOOK_MASK));
                
                address hookAddress = hookDeployer.deploy(salt, creationCode);
                require(hookAddress == predicted, "Address mismatch!");
                require((uint160(hookAddress) & ALL_HOOK_MASK) == flags, "Invalid permissions!");
                
                return ClankerHookStaticFee(hookAddress);
            }
        }
        
        revert("No valid salt found!");
    }
}
