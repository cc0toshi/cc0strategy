// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Clanker} from "../src/Clanker.sol";
import {IClanker} from "../src/interfaces/IClanker.sol";

/**
 * @title DeployTokenV3
 * @notice Deploy DICKSTR with:
 *  - Salt 3 for address < WETH (token will be currency0)
 *  - Correct tick config that ensures active liquidity from start
 */
contract DeployTokenV3 is Script {
    // cc0strategy mainnet contracts
    address constant FACTORY = 0x70b17db500Ce1746BB34f908140d0279C183f3eb;
    address constant LP_LOCKER = 0x45e1D9bb68E514565710DEaf2567B73EF86638e0;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    address constant MEV_MODULE = 0xDe6DBe5957B617fda4b2dcA4dd45a32B87a54BfE;
    
    // Based MferDickButts NFT collection
    address constant NFT_COLLECTION = 0x5c5D3CBaf7a3419af8E6661486B2D5Ec3AccfB1B;
    
    string constant NAME = "BasedMferdickbuttStrategy";
    string constant SYMBOL = "DICKSTR";
    string constant IMAGE = "ipfs://QmBasedMferDickButts";
    string constant METADATA = "cc0strategy token - trading fees go to Based MferDickButts holders";
    
    struct PoolStaticConfigVars {
        uint24 clankerFee;
        uint24 pairedFee;
    }
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Deploying DICKSTR V3 - Currency0 Edition");
        console2.log("=========================================");
        console2.log("Deployer:", deployer);
        console2.log("");
        console2.log("Salt 3 -> Token 0x408a... < WETH 0x4200...");
        console2.log("Token is currency0, WETH is currency1");
        console2.log("");
        console2.log("For currency0:");
        console2.log("  startingTick = tickIfToken0IsClanker = -230400");
        console2.log("  NO tick transformation");
        console2.log("  Position [-230400, 887200] contains currentTick");
        console2.log("  Liquidity ACTIVE from start!");
        console2.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        Clanker factory = Clanker(FACTORY);
        
        IClanker.DeploymentConfig memory config;
        
        // Salt 3 gives address < WETH
        config.tokenConfig = IClanker.TokenConfig({
            name: NAME,
            symbol: SYMBOL,
            salt: bytes32(uint256(3)),
            image: IMAGE,
            metadata: METADATA,
            context: "cc0strategy v3",
            originatingChainId: 8453,
            tokenAdmin: deployer
        });
        
        // 1% fees
        PoolStaticConfigVars memory feeConfig = PoolStaticConfigVars({
            clankerFee: 10000,
            pairedFee: 10000
        });
        
        config.poolConfig = IClanker.PoolConfig({
            hook: HOOK,
            pairedToken: 0x4200000000000000000000000000000000000006,
            tickIfToken0IsClanker: -230400,
            tickSpacing: 200,
            poolData: abi.encode(feeConfig)
        });
        
        // Position containing the starting tick
        config.lockerConfig.locker = LP_LOCKER;
        config.lockerConfig.rewardAdmins = new address[](0);
        config.lockerConfig.rewardRecipients = new address[](0);
        config.lockerConfig.rewardBps = new uint16[](0);
        config.lockerConfig.tickLower = new int24[](1);
        config.lockerConfig.tickUpper = new int24[](1);
        config.lockerConfig.positionBps = new uint16[](1);
        
        // For currency0: ticks are used directly
        // tickLower = -230400 (= starting tick, minimum allowed by validation)
        // tickUpper = 887200 (max tick, aligned to spacing 200)
        config.lockerConfig.tickLower[0] = -230400;
        config.lockerConfig.tickUpper[0] = 887200;
        config.lockerConfig.positionBps[0] = 10000;
        config.lockerConfig.lockerData = "";
        
        config.mevModuleConfig.mevModule = MEV_MODULE;
        config.mevModuleConfig.mevModuleData = "";
        
        config.extensionConfigs = new IClanker.ExtensionConfig[](0);
        config.nftCollection = NFT_COLLECTION;
        
        console2.log("Deploying token...");
        address token = factory.deployToken(config);
        
        console2.log("");
        console2.log("=========================================");
        console2.log("TOKEN DEPLOYED!");
        console2.log("=========================================");
        console2.log("Token:", token);
        
        vm.stopBroadcast();
    }
}
