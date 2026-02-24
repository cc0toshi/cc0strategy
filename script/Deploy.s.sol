// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

// Protocol contracts
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {CC0StrategyLpLocker} from "../src/lp-lockers/CC0StrategyLpLocker.sol";
import {ClankerHookStaticFee} from "../src/hooks/ClankerHookStaticFee.sol";
import {Clanker} from "../src/Clanker.sol";

// MEV Module (optional, but needed for full Clanker feature parity)
import {ClankerMevBlockDelay} from "../src/mev-modules/ClankerMevBlockDelay.sol";

/**
 * @title Deploy
 * @notice Deploys the complete cc0strategy protocol to Base Sepolia
 * 
 * Deploy order:
 * 1. FeeDistributor (needs treasury, placeholder lpLocker, placeholder factory)
 * 2. CC0StrategyLpLocker (needs feeDistributor, positionManager, etc)
 * 3. Hook (needs CREATE2 salt mining for permission bits)
 * 4. Factory/Clanker (needs hook, lpLocker, feeDistributor)
 * 5. Update FeeDistributor with real lpLocker and factory addresses
 * 6. Enable hook/locker/mev module in factory
 */
contract DeployCC0Strategy is Script {
    // ═══════════════════════════════════════════════════════════════════════════
    // BASE SEPOLIA ADDRESSES (Chain ID: 84532)
    // ═══════════════════════════════════════════════════════════════════════════
    
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant POSITION_MANAGER = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
    address constant UNIVERSAL_ROUTER = 0x492E6456D9528771018DeB9E87ef7750EF184104;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    // Test utilities (for integration tests)
    address constant POOL_SWAP_TEST = 0x8B5bcC363ddE2614281aD875bad385E0A785D3B9;
    address constant POOL_MODIFY_LIQUIDITY_TEST = 0x37429cD17Cb1454C34E7F50b09725202Fd533039;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Treasury receives 20% of all trading fees
    address public treasury;
    address public deployer;
    
    // Deployed addresses (set after deployment)
    FeeDistributor public feeDistributor;
    CC0StrategyLpLocker public lpLocker;
    ClankerHookStaticFee public hook;
    Clanker public factory;
    ClankerMevBlockDelay public mevModule;
    
    function setUp() public {
        // Load from environment or use defaults for testing
        treasury = vm.envOr("TREASURY", 0x58e510F849e38095375a3e478aD1d719650B8557);
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
    }
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Deploying cc0strategy to Base Sepolia");
        console2.log("=====================================");
        console2.log("Deployer:", deployer);
        console2.log("Treasury:", treasury);
        console2.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy FeeDistributor with placeholder addresses
        console2.log("Step 1: Deploying FeeDistributor...");
        feeDistributor = new FeeDistributor(
            treasury,
            address(1), // placeholder lpLocker
            address(1), // placeholder factory  
            deployer    // owner
        );
        console2.log("  FeeDistributor:", address(feeDistributor));
        
        // Step 2: Deploy MevModule (optional but needed for full feature parity)
        console2.log("Step 2: Deploying MevModule...");
        mevModule = new ClankerMevBlockDelay(1);
        console2.log("  MevModule:", address(mevModule));
        
        // Step 3: Deploy Factory (Clanker)
        console2.log("Step 3: Deploying Factory (Clanker)...");
        factory = new Clanker(deployer, address(feeDistributor));
        console2.log("  Factory:", address(factory));
        
        // Step 4: Deploy Hook with CREATE2 salt mining
        // Hook address must have specific bits set for permissions
        console2.log("Step 4: Deploying Hook...");
        hook = deployHookWithSalt();
        console2.log("  Hook:", address(hook));
        
        // Step 5: Deploy LP Locker
        console2.log("Step 5: Deploying LpLocker...");
        lpLocker = new CC0StrategyLpLocker(
            deployer,              // owner
            address(factory),      // factory
            address(feeDistributor), // feeDistributor
            POSITION_MANAGER,      // positionManager
            PERMIT2,               // permit2
            UNIVERSAL_ROUTER,      // universalRouter
            POOL_MANAGER           // poolManager
        );
        console2.log("  LpLocker:", address(lpLocker));
        
        // Step 6: Update FeeDistributor with real addresses
        console2.log("Step 6: Updating FeeDistributor...");
        feeDistributor.setLpLocker(address(lpLocker));
        feeDistributor.setFactory(address(factory));
        console2.log("  Updated lpLocker and factory in FeeDistributor");
        
        // Step 7: Enable contracts in Factory
        console2.log("Step 7: Enabling contracts in Factory...");
        factory.setTeamFeeRecipient(treasury);
        factory.setHook(address(hook), true);
        factory.setLocker(address(lpLocker), address(hook), true);
        factory.setMevModule(address(mevModule), true);
        factory.setDeprecated(false); // Enable deployments
        console2.log("  Enabled hook, locker, mev module in factory");
        
        vm.stopBroadcast();
        
        // Print summary
        console2.log("");
        console2.log("=====================================");
        console2.log("DEPLOYMENT COMPLETE!");
        console2.log("=====================================");
        console2.log("");
        console2.log("Contract Addresses:");
        console2.log("  FeeDistributor:", address(feeDistributor));
        console2.log("  LpLocker:", address(lpLocker));
        console2.log("  Hook:", address(hook));
        console2.log("  Factory:", address(factory));
        console2.log("  MevModule:", address(mevModule));
        console2.log("");
        console2.log("External Dependencies (Base Sepolia):");
        console2.log("  PoolManager:", POOL_MANAGER);
        console2.log("  PositionManager:", POSITION_MANAGER);
        console2.log("  UniversalRouter:", UNIVERSAL_ROUTER);
        console2.log("  Permit2:", PERMIT2);
        console2.log("  WETH:", WETH);
    }
    
    /**
     * @notice Deploys the hook with CREATE2 salt mining for correct permission bits
     * @dev Hook address must have bits set according to Hooks.Permissions
     * 
     * Required permissions (from ClankerHook.getHookPermissions()):
     * - beforeInitialize: true (bit 0)
     * - beforeAddLiquidity: true (bit 2)
     * - beforeSwap: true (bit 6)
     * - afterSwap: true (bit 7)
     * - beforeSwapReturnDelta: true (bit 10)
     * - afterSwapReturnDelta: true (bit 11)
     */
    function deployHookWithSalt() internal returns (ClankerHookStaticFee) {
        // Calculate required flags
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        
        // Mine for a salt that produces an address with correct permission bits
        bytes memory creationCode = abi.encodePacked(
            type(ClankerHookStaticFee).creationCode,
            abi.encode(POOL_MANAGER, address(factory), WETH)
        );
        
        bytes32 salt = mineSalt(deployer, creationCode, flags);
        
        // Deploy with CREATE2
        ClankerHookStaticFee deployedHook = new ClankerHookStaticFee{salt: salt}(
            POOL_MANAGER,
            address(factory),
            WETH
        );
        
        // Verify the address has correct permission bits
        require(
            uint160(address(deployedHook)) & flags == flags,
            "Hook address does not have correct permission bits"
        );
        
        return deployedHook;
    }
    
    /**
     * @notice Mines a CREATE2 salt that produces an address with required permission bits
     */
    function mineSalt(
        address deployer_,
        bytes memory creationCode,
        uint160 flags
    ) internal pure returns (bytes32) {
        bytes32 initCodeHash = keccak256(creationCode);
        
        for (uint256 i = 0; i < 100000; i++) {
            bytes32 salt = bytes32(i);
            address predicted = address(uint160(uint256(keccak256(abi.encodePacked(
                bytes1(0xff),
                deployer_,
                salt,
                initCodeHash
            )))));
            
            // Check if the address has the required flag bits set
            if (uint160(predicted) & flags == flags) {
                return salt;
            }
        }
        
        revert("Could not find valid salt in 100000 iterations");
    }
}

/**
 * @title DeploySaltMiner
 * @notice Standalone script to mine CREATE2 salt for hook deployment
 * Run this first if you want to pre-compute the salt
 */
contract DeploySaltMiner is Script {
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    
    function run() public view {
        address deployer_ = vm.envAddress("DEPLOYER_ADDRESS");
        address factory_ = vm.envOr("FACTORY_ADDRESS", address(0));
        
        if (factory_ == address(0)) {
            console2.log("Set FACTORY_ADDRESS env var (or run full deploy)");
            return;
        }
        
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        
        address weth = 0x4200000000000000000000000000000000000006;
        
        bytes memory creationCode = abi.encodePacked(
            type(ClankerHookStaticFee).creationCode,
            abi.encode(POOL_MANAGER, factory_, weth)
        );
        bytes32 initCodeHash = keccak256(creationCode);
        
        console2.log("Mining salt for hook deployment...");
        console2.log("Deployer:", deployer_);
        console2.log("Required flags:", uint256(flags));
        
        for (uint256 i = 0; i < 1000000; i++) {
            bytes32 salt = bytes32(i);
            address predicted = address(uint160(uint256(keccak256(abi.encodePacked(
                bytes1(0xff),
                deployer_,
                salt,
                initCodeHash
            )))));
            
            if (uint160(predicted) & flags == flags) {
                console2.log("Found salt!");
                console2.log("Salt (decimal):", i);
                console2.logBytes32(salt);
                console2.log("Predicted address:", predicted);
                return;
            }
            
            if (i % 100000 == 0) {
                console2.log("Checked", i, "salts...");
            }
        }
        
        console2.log("No valid salt found in search range");
    }
}
