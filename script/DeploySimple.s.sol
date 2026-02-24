// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {CC0StrategyLpLocker} from "../src/lp-lockers/CC0StrategyLpLocker.sol";
import {Clanker} from "../src/Clanker.sol";
import {ClankerMevBlockDelay} from "../src/mev-modules/ClankerMevBlockDelay.sol";

/**
 * @title DeploySimple
 * @notice Simplified deployment - skip hook for now, deploy core contracts
 */
contract DeploySimple is Script {
    // BASE MAINNET ADDRESSES (Chain ID: 8453)
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    address public treasury = 0x58e510F849e38095375a3e478aD1d719650B8557;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Deploying cc0strategy to Base Mainnet");
        console2.log("=====================================");
        console2.log("Deployer:", deployer);
        console2.log("Treasury:", treasury);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy FeeDistributor
        console2.log("Step 1: Deploying FeeDistributor...");
        FeeDistributor feeDistributor = new FeeDistributor(
            treasury,
            address(1), // placeholder lpLocker
            address(1), // placeholder factory  
            deployer    // owner (will transfer later)
        );
        console2.log("  FeeDistributor:", address(feeDistributor));
        
        // Step 2: Deploy MevModule
        console2.log("Step 2: Deploying MevModule...");
        ClankerMevBlockDelay mevModule = new ClankerMevBlockDelay(1);
        console2.log("  MevModule:", address(mevModule));
        
        // Step 3: Deploy Factory
        console2.log("Step 3: Deploying Factory (Clanker)...");
        Clanker factory = new Clanker(deployer, address(feeDistributor));
        console2.log("  Factory:", address(factory));
        
        // Step 4: Deploy LP Locker (skip hook for now - will add later)
        console2.log("Step 4: Deploying LpLocker...");
        CC0StrategyLpLocker lpLocker = new CC0StrategyLpLocker(
            deployer,                // owner (will transfer later)
            address(factory),        // factory
            address(feeDistributor), // feeDistributor
            POSITION_MANAGER,        // positionManager
            PERMIT2,                 // permit2
            UNIVERSAL_ROUTER,        // universalRouter
            POOL_MANAGER             // poolManager
        );
        console2.log("  LpLocker:", address(lpLocker));
        
        // Step 5: Update FeeDistributor
        console2.log("Step 5: Updating FeeDistributor...");
        feeDistributor.setLpLocker(address(lpLocker));
        feeDistributor.setFactory(address(factory));
        console2.log("  Updated lpLocker and factory");
        
        // Step 6: Configure Factory
        console2.log("Step 6: Configuring Factory...");
        factory.setTeamFeeRecipient(treasury);
        factory.setMevModule(address(mevModule), true);
        // Note: Hook + Locker will be enabled after hook deployment
        console2.log("  Factory configured");
        
        vm.stopBroadcast();
        
        console2.log("");
        console2.log("=====================================");
        console2.log("DEPLOYMENT COMPLETE (Phase 1)");
        console2.log("=====================================");
        console2.log("FeeDistributor:", address(feeDistributor));
        console2.log("MevModule:", address(mevModule));
        console2.log("Factory:", address(factory));
        console2.log("LpLocker:", address(lpLocker));
        console2.log("");
        console2.log("NEXT: Deploy hook with CREATE2 salt mining");
    }
}
