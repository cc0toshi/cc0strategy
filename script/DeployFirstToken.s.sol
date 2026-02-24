// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Clanker} from "../src/Clanker.sol";
import {IClanker} from "../src/interfaces/IClanker.sol";
import {FeeDistributor} from "../src/FeeDistributor.sol";

/**
 * @title DeployFirstToken
 * @notice Deploy BasedMferdickbuttStrategy (DICKSTR) - first cc0strategy token
 */
contract DeployFirstToken is Script {
    // cc0strategy contracts
    address constant FACTORY = 0x70b17db500Ce1746BB34f908140d0279C183f3eb;
    address constant FEE_DISTRIBUTOR = 0x9Ce2AB2769CcB547aAcE963ea4493001275CD557;
    address constant LP_LOCKER = 0x45e1D9bb68E514565710DEaf2567B73EF86638e0;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    address constant MEV_MODULE = 0xDe6DBe5957B617fda4b2dcA4dd45a32B87a54BfE;
    
    // Based MferDickButts NFT collection (checksummed)
    address constant NFT_COLLECTION = 0x5c5D3CBaf7a3419af8E6661486B2D5Ec3AccfB1B;
    
    // Token config
    string constant NAME = "BasedMferdickbuttStrategy";
    string constant SYMBOL = "DICKSTR";
    string constant IMAGE = "ipfs://QmBasedMferDickButts";
    string constant METADATA = "First cc0strategy token - trading fees go to Based MferDickButts holders";
    
    // Fee config struct (must match IClankerHookStaticFee.PoolStaticConfigVars)
    struct PoolStaticConfigVars {
        uint24 clankerFee;
        uint24 pairedFee;
    }
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Deploying first cc0strategy token");
        console2.log("==================================");
        console2.log("Deployer:", deployer);
        console2.log("NFT Collection:", NFT_COLLECTION);
        
        vm.startBroadcast(deployerPrivateKey);
        
        Clanker factory = Clanker(FACTORY);
        
        // Build DeploymentConfig
        IClanker.DeploymentConfig memory config;
        
        // Token config
        config.tokenConfig = IClanker.TokenConfig({
            name: NAME,
            symbol: SYMBOL,
            salt: bytes32(uint256(1)),
            image: IMAGE,
            metadata: METADATA,
            context: "cc0strategy genesis token",
            originatingChainId: 8453,
            tokenAdmin: deployer
        });
        
        // Fee config: 1% fee on both directions (10000 = 1%)
        PoolStaticConfigVars memory feeConfig = PoolStaticConfigVars({
            clankerFee: 10000, // 1%
            pairedFee: 10000   // 1%
        });
        
        // Pool config with encoded fee data
        config.poolConfig = IClanker.PoolConfig({
            hook: HOOK,
            pairedToken: 0x4200000000000000000000000000000000000006, // WETH
            tickIfToken0IsClanker: -230400,
            tickSpacing: 200,
            poolData: abi.encode(feeConfig)
        });
        
        // Locker config
        config.lockerConfig.locker = LP_LOCKER;
        config.lockerConfig.rewardAdmins = new address[](0);
        config.lockerConfig.rewardRecipients = new address[](0);
        config.lockerConfig.rewardBps = new uint16[](0);
        config.lockerConfig.tickLower = new int24[](1);
        config.lockerConfig.tickUpper = new int24[](1);
        config.lockerConfig.positionBps = new uint16[](1);
        config.lockerConfig.tickLower[0] = 230400;
        config.lockerConfig.tickUpper[0] = 887200;
        config.lockerConfig.positionBps[0] = 10000;
        config.lockerConfig.lockerData = "";
        
        // Use the deployed MevModule
        config.mevModuleConfig.mevModule = MEV_MODULE;
        config.mevModuleConfig.mevModuleData = "";
        
        // No extensions
        config.extensionConfigs = new IClanker.ExtensionConfig[](0);
        
        // NFT collection for fee distribution
        config.nftCollection = NFT_COLLECTION;
        
        console2.log("Deploying token with 1% fees...");
        address token = factory.deployToken(config);
        
        console2.log("Token deployed:", token);
        
        vm.stopBroadcast();
        
        console2.log("");
        console2.log("==================================");
        console2.log("FIRST TOKEN DEPLOYED!");
        console2.log("==================================");
        console2.log("Token:", token);
        console2.log("Name:", NAME);
        console2.log("Symbol:", SYMBOL);
        console2.log("NFT Collection:", NFT_COLLECTION);
    }
}
