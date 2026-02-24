// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Clanker} from "../src/Clanker.sol";
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {CC0StrategyLpLocker} from "../src/lp-lockers/CC0StrategyLpLocker.sol";

/**
 * @title Finalize
 * @notice Enable hook/locker in factory and transfer ownership to bankr wallet
 */
contract Finalize is Script {
    // Deployed contracts (checksummed)
    address constant FEE_DISTRIBUTOR = 0x9Ce2AB2769CcB547aAcE963ea4493001275CD557;
    address constant FACTORY = 0x70b17db500Ce1746BB34f908140d0279C183f3eb;
    address constant LP_LOCKER = 0x45e1D9bb68E514565710DEaf2567B73EF86638e0;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    
    // Final owner (bankr wallet)
    address constant BANKR_WALLET = 0x58e510F849e38095375a3e478aD1d719650B8557;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Finalizing cc0strategy deployment");
        console2.log("==================================");
        console2.log("Deployer:", deployer);
        console2.log("New Owner:", BANKR_WALLET);
        
        Clanker factory = Clanker(FACTORY);
        FeeDistributor feeDistributor = FeeDistributor(FEE_DISTRIBUTOR);
        CC0StrategyLpLocker lpLocker = CC0StrategyLpLocker(payable(LP_LOCKER));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Enable hook in factory
        console2.log("Step 1: Enabling hook in factory...");
        factory.setHook(HOOK, true);
        console2.log("  Hook enabled:", HOOK);
        
        // Step 2: Enable locker with hook
        console2.log("Step 2: Enabling locker with hook...");
        factory.setLocker(LP_LOCKER, HOOK, true);
        console2.log("  Locker enabled:", LP_LOCKER);
        
        // Step 3: Enable deployments (undeprecate)
        console2.log("Step 3: Enabling deployments...");
        factory.setDeprecated(false);
        console2.log("  Factory enabled for deployments");
        
        // Step 4: Transfer ownership
        console2.log("Step 4: Transferring ownership to bankr wallet...");
        factory.transferOwnership(BANKR_WALLET);
        feeDistributor.transferOwnership(BANKR_WALLET);
        lpLocker.transferOwnership(BANKR_WALLET);
        console2.log("  Ownership transferred");
        
        vm.stopBroadcast();
        
        console2.log("");
        console2.log("==================================");
        console2.log("CC0STRATEGY DEPLOYMENT COMPLETE!");
        console2.log("==================================");
        console2.log("");
        console2.log("Contract Addresses:");
        console2.log("  FeeDistributor:", FEE_DISTRIBUTOR);
        console2.log("  Factory:", FACTORY);
        console2.log("  LpLocker:", LP_LOCKER);
        console2.log("  Hook:", HOOK);
        console2.log("");
        console2.log("Owner:", BANKR_WALLET);
    }
}
