// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Clanker} from "../src/Clanker.sol";
import {IClanker} from "../src/interfaces/IClanker.sol";

/**
 * @title DeployTokenV2
 * @notice Deploy DICKSTR with FIXED tick config
 * 
 * The fix: tickLower must be BELOW starting tick
 * - Token is currency1 (DICKSTR > WETH alphabetically)
 * - Starting tick: +230400 (from tickIfToken0IsClanker = -230400)
 * - When someone BUYS DICKSTR, tick DECREASES
 * - Position must have room below current tick for buys to work
 * 
 * Original (broken): [230400, 887200] - no room to decrease
 * Fixed: [-887200, 230400] - tick can decrease into range
 */
contract DeployTokenV2 is Script {
    // cc0strategy mainnet contracts
    address constant FACTORY = 0x70b17db500Ce1746BB34f908140d0279C183f3eb;
    address constant LP_LOCKER = 0x45e1D9bb68E514565710DEaf2567B73EF86638e0;
    address constant HOOK = 0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc;
    address constant MEV_MODULE = 0xDe6DBe5957B617fda4b2dcA4dd45a32B87a54BfE;
    
    // Based MferDickButts NFT collection
    address constant NFT_COLLECTION = 0x5c5D3CBaf7a3419af8E6661486B2D5Ec3AccfB1B;
    
    // Token config
    string constant NAME = "BasedMferdickbuttStrategy";
    string constant SYMBOL = "DICKSTR";
    string constant IMAGE = "ipfs://QmBasedMferDickButts";
    string constant METADATA = "cc0strategy token - trading fees go to Based MferDickButts holders";
    
    // Fee config struct
    struct PoolStaticConfigVars {
        uint24 clankerFee;
        uint24 pairedFee;
    }
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Deploying DICKSTR V2 with fixed tick config");
        console2.log("============================================");
        console2.log("Deployer:", deployer);
        console2.log("NFT Collection:", NFT_COLLECTION);
        console2.log("");
        console2.log("Tick Fix:");
        console2.log("  Starting tick: 230400");
        console2.log("  Old tickLower: 230400 (broken - no room for buys)");
        console2.log("  New tickLower: -887200 (fixed - full range below start)");
        console2.log("  tickUpper: 230400 (starting tick)");
        console2.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        Clanker factory = Clanker(FACTORY);
        
        IClanker.DeploymentConfig memory config;
        
        // Token config - use different salt for new token
        config.tokenConfig = IClanker.TokenConfig({
            name: NAME,
            symbol: SYMBOL,
            salt: bytes32(uint256(2)), // Different salt for V2
            image: IMAGE,
            metadata: METADATA,
            context: "cc0strategy v2 - fixed tick range",
            originatingChainId: 8453,
            tokenAdmin: deployer
        });
        
        // Fee config: 6.9% fee on both directions
        PoolStaticConfigVars memory feeConfig = PoolStaticConfigVars({
            clankerFee: 69000, // 6.9%
            pairedFee: 69000   // 6.9%
        });
        
        // Pool config
        config.poolConfig = IClanker.PoolConfig({
            hook: HOOK,
            pairedToken: 0x4200000000000000000000000000000000000006, // WETH
            tickIfToken0IsClanker: -230400,
            tickSpacing: 200,
            poolData: abi.encode(feeConfig)
        });
        
        // FIXED: Locker config with correct tick range
        // For single-sided token1 liquidity at tickUpper:
        // - tickLower = min tick (aligned to spacing)
        // - tickUpper = starting tick
        // - This puts all liquidity ABOVE current price
        // - When buys happen, tick decreases INTO the range
        config.lockerConfig.locker = LP_LOCKER;
        config.lockerConfig.rewardAdmins = new address[](0);
        config.lockerConfig.rewardRecipients = new address[](0);
        config.lockerConfig.rewardBps = new uint16[](0);
        config.lockerConfig.tickLower = new int24[](1);
        config.lockerConfig.tickUpper = new int24[](1);
        config.lockerConfig.positionBps = new uint16[](1);
        
        // KEY FIX: tickLower below starting tick, tickUpper AT starting tick
        config.lockerConfig.tickLower[0] = -887200; // Min tick (aligned to 200)
        config.lockerConfig.tickUpper[0] = 230400;  // Starting tick
        config.lockerConfig.positionBps[0] = 10000; // 100% in this position
        config.lockerConfig.lockerData = "";
        
        // MEV protection
        config.mevModuleConfig.mevModule = MEV_MODULE;
        config.mevModuleConfig.mevModuleData = "";
        
        // No extensions
        config.extensionConfigs = new IClanker.ExtensionConfig[](0);
        
        // NFT collection
        config.nftCollection = NFT_COLLECTION;
        
        console2.log("Deploying token...");
        address token = factory.deployToken(config);
        
        console2.log("");
        console2.log("============================================");
        console2.log("TOKEN DEPLOYED!");
        console2.log("============================================");
        console2.log("Token:", token);
        console2.log("Name:", NAME);
        console2.log("Symbol:", SYMBOL);
        console2.log("");
        console2.log("Next: run TestSwapV2 to verify liquidity works");
        
        vm.stopBroadcast();
    }
}
