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
 * @title DeployEthereum
 * @notice Deploys the complete cc0strategy protocol to Ethereum Mainnet
 * @author cc0toshi
 * 
 * IMPORTANT: Do NOT run this script without first:
 * 1. Mining the CREATE2 salt for the hook (run MineSaltEthereum.s.sol first)
 * 2. Setting environment variables (see ETHEREUM_DEPLOYMENT.md)
 * 3. Having sufficient ETH for gas (~0.25 ETH @ 30 gwei)
 * 
 * Deploy order:
 * 1. ClankerPoolExtensionAllowlist (for hook pool extensions)
 * 2. FeeDistributor (with placeholder lpLocker/factory)
 * 3. ClankerMevBlockDelay (MEV protection module)
 * 4. Clanker Factory (needs feeDistributor)
 * 5. ClankerHookStaticFee (CREATE2 with mined salt)
 * 6. CC0StrategyLpLocker (needs factory, feeDistributor, etc.)
 * 7. Update FeeDistributor with real addresses
 * 8. Enable hook/locker/mev module in factory
 */
contract DeployEthereum is Script {
    // ═══════════════════════════════════════════════════════════════════════════
    // ETHEREUM MAINNET ADDRESSES (Chain ID: 1)
    // ═══════════════════════════════════════════════════════════════════════════
    
    address constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address constant UNIVERSAL_ROUTER = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Treasury receives 20% of all trading fees
    // Using same treasury as Base (cc0toshi wallet)
    address public treasury = 0x58e510F849e38095375a3e478aD1d719650B8557;
    
    // cc0toshi's bankr wallet - will own all contracts after deployment
    address public cc0toshiWallet = 0x58e510F849e38095375a3e478aD1d719650B8557;
    
    address public deployer;
    
    // Deployed addresses (set after deployment)
    ClankerPoolExtensionAllowlist public poolExtensionAllowlist;
    FeeDistributor public feeDistributor;
    CC0StrategyLpLocker public lpLocker;
    ClankerHookStaticFee public hook;
    Clanker public factory;
    ClankerMevBlockDelay public mevModule;
    HookDeployer public hookDeployer;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        
        // Allow treasury override
        treasury = vm.envOr("TREASURY", treasury);
        
        console2.log("=====================================");
        console2.log("cc0strategy - Ethereum Mainnet Deploy");
        console2.log("=====================================");
        console2.log("Chain ID: 1 (Ethereum Mainnet)");
        console2.log("Deployer:", deployer);
        console2.log("Treasury:", treasury);
        console2.log("");
        
        // Check deployer balance
        uint256 balance = deployer.balance;
        console2.log("Deployer Balance:", balance / 1e18, "ETH");
        require(balance >= 0.001 ether, "Need at least 0.001 ETH for deployment");
        console2.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy PoolExtensionAllowlist
        console2.log("Step 1: Deploying PoolExtensionAllowlist...");
        poolExtensionAllowlist = new ClankerPoolExtensionAllowlist(deployer);
        console2.log("  PoolExtensionAllowlist:", address(poolExtensionAllowlist));
        
        // Step 2: Deploy FeeDistributor with placeholder addresses
        console2.log("Step 2: Deploying FeeDistributor...");
        feeDistributor = new FeeDistributor(
            treasury,
            address(1), // placeholder lpLocker
            address(1), // placeholder factory  
            deployer    // owner
        );
        console2.log("  FeeDistributor:", address(feeDistributor));
        
        // Step 3: Deploy MevModule
        console2.log("Step 3: Deploying MevModule...");
        mevModule = new ClankerMevBlockDelay(1); // 1 block delay
        console2.log("  MevModule:", address(mevModule));
        
        // Step 4: Deploy Factory (Clanker)
        console2.log("Step 4: Deploying Factory (Clanker)...");
        factory = new Clanker(deployer, address(feeDistributor));
        console2.log("  Factory:", address(factory));
        
        // Step 5: Deploy Hook with CREATE2 salt mining
        console2.log("Step 5: Deploying Hook...");
        hook = deployHookWithSalt();
        console2.log("  Hook:", address(hook));
        
        // Verify hook permissions
        verifyHookPermissions();
        
        // Step 6: Deploy LP Locker
        console2.log("Step 6: Deploying LpLocker...");
        lpLocker = new CC0StrategyLpLocker(
            deployer,                // owner
            address(factory),        // factory
            address(feeDistributor), // feeDistributor
            POSITION_MANAGER,        // positionManager
            PERMIT2,                 // permit2
            UNIVERSAL_ROUTER,        // universalRouter
            POOL_MANAGER             // poolManager
        );
        console2.log("  LpLocker:", address(lpLocker));
        
        // Step 7: Update FeeDistributor with real addresses
        console2.log("Step 7: Updating FeeDistributor...");
        feeDistributor.setLpLocker(address(lpLocker));
        feeDistributor.setFactory(address(factory));
        console2.log("  Updated lpLocker and factory in FeeDistributor");
        
        // Step 8: Enable contracts in Factory
        console2.log("Step 8: Enabling contracts in Factory...");
        factory.setTeamFeeRecipient(treasury);
        factory.setHook(address(hook), true);
        factory.setLocker(address(lpLocker), address(hook), true);
        factory.setMevModule(address(mevModule), true);
        factory.setDeprecated(false); // Enable deployments
        console2.log("  Enabled hook, locker, mev module in factory");
        
        // Step 9: Transfer ownership to cc0toshi's bankr wallet
        console2.log("Step 9: Transferring ownership to cc0toshi...");
        cc0toshiWallet = vm.envOr("CC0TOSHI_WALLET", cc0toshiWallet);
        
        poolExtensionAllowlist.transferOwnership(cc0toshiWallet);
        console2.log("  PoolExtensionAllowlist ownership -> cc0toshi");
        
        feeDistributor.transferOwnership(cc0toshiWallet);
        console2.log("  FeeDistributor ownership -> cc0toshi");
        
        lpLocker.transferOwnership(cc0toshiWallet);
        console2.log("  LpLocker ownership -> cc0toshi");
        
        factory.transferOwnership(cc0toshiWallet);
        console2.log("  Factory ownership -> cc0toshi");
        
        console2.log("  All contracts now owned by:", cc0toshiWallet);
        
        vm.stopBroadcast();
        
        // Print summary
        printSummary();
    }
    
    /**
     * @notice Deploys the hook with CREATE2 using pre-mined salt
     * @dev Salt was pre-mined offline for deterministic deployment
     * 
     * Required permissions (from ClankerHook.getHookPermissions()):
     * - beforeInitialize: true
     * - beforeAddLiquidity: true
     * - beforeSwap: true
     * - afterSwap: true
     * - beforeSwapReturnDelta: true
     * - afterSwapReturnDelta: true
     *
     * Pre-computed values:
     * - HookDeployer will be at nonce 5: 0x25fCbdB55A1A42d2219D1DCF89aC44220fEe41d7
     * - Factory will be at nonce 4: 0x45e1D9bb68E514565710DEaf2567B73EF86638e0
     * - Salt: 15249 (0x3b91)
     * - Hook address: 0x9f4a65977fbe6acb9eee50cef8319c397c8628cc
     */
    function deployHookWithSalt() internal returns (ClankerHookStaticFee) {
        // Required flags for verification
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        
        console2.log("  Required hook flags:", uint256(flags));
        
        // Deploy HookDeployer (will be at nonce 4)
        hookDeployer = new HookDeployer();
        console2.log("  HookDeployer:", address(hookDeployer));
        
        // Verify HookDeployer is at expected address (nonce 5)
        require(
            address(hookDeployer) == 0x25fCbdB55A1A42d2219D1DCF89aC44220fEe41d7,
            "HookDeployer not at expected address - nonces changed!"
        );
        
        // Verify Factory is at expected address (nonce 4)
        require(
            address(factory) == 0x45e1D9bb68E514565710DEaf2567B73EF86638e0,
            "Factory not at expected address - nonces changed!"
        );
        
        // Compute creation code
        bytes memory creationCode = abi.encodePacked(
            type(ClankerHookStaticFee).creationCode,
            abi.encode(POOL_MANAGER, address(factory), WETH)
        );
        bytes32 initCodeHash = keccak256(creationCode);
        console2.log("  InitCodeHash:");
        console2.logBytes32(initCodeHash);
        
        // Use pre-mined salt: 15249 (0x3b91)
        bytes32 salt = bytes32(uint256(15249));
        console2.log("  Using pre-mined salt: 15249");
        
        // Verify predicted address
        address predictedAddress = hookDeployer.computeAddress(salt, initCodeHash);
        console2.log("  Predicted address:", predictedAddress);
        require(
            predictedAddress == 0x9f4A65977FbE6ACb9Eee50cEf8319c397C8628cC,
            "Predicted hook address mismatch - init code changed!"
        );
        
        // Deploy hook via HookDeployer
        address hookAddress = hookDeployer.deploy(salt, creationCode);
        console2.log("  Hook deployed at:", hookAddress);
        
        // Verify
        require(hookAddress == predictedAddress, "Address mismatch!");
        require(uint160(hookAddress) & 0xFFFF == flags, "Invalid hook permissions!");
        
        return ClankerHookStaticFee(hookAddress);
    }
    
    function verifyHookPermissions() internal view {
        Hooks.Permissions memory perms = hook.getHookPermissions();
        
        require(perms.beforeInitialize, "Missing beforeInitialize");
        require(perms.beforeAddLiquidity, "Missing beforeAddLiquidity");
        require(perms.beforeSwap, "Missing beforeSwap");
        require(perms.afterSwap, "Missing afterSwap");
        require(perms.beforeSwapReturnDelta, "Missing beforeSwapReturnDelta");
        require(perms.afterSwapReturnDelta, "Missing afterSwapReturnDelta");
        
        console2.log("  Hook permissions verified!");
    }
    
    function printSummary() internal view {
        console2.log("");
        console2.log("=====================================");
        console2.log("DEPLOYMENT COMPLETE!");
        console2.log("=====================================");
        console2.log("");
        console2.log("cc0strategy Contract Addresses (Ethereum Mainnet):");
        console2.log("--------------------------------------------------");
        console2.log("  PoolExtensionAllowlist:", address(poolExtensionAllowlist));
        console2.log("  FeeDistributor:", address(feeDistributor));
        console2.log("  LpLocker:", address(lpLocker));
        console2.log("  Hook:", address(hook));
        console2.log("  Factory:", address(factory));
        console2.log("  MevModule:", address(mevModule));
        console2.log("");
        console2.log("External Dependencies (Ethereum Mainnet):");
        console2.log("------------------------------------------");
        console2.log("  PoolManager:", POOL_MANAGER);
        console2.log("  PositionManager:", POSITION_MANAGER);
        console2.log("  UniversalRouter:", UNIVERSAL_ROUTER);
        console2.log("  Permit2:", PERMIT2);
        console2.log("  WETH:", WETH);
        console2.log("");
        console2.log("Configuration:");
        console2.log("--------------");
        console2.log("  Treasury:", treasury);
        console2.log("  Owner (cc0toshi):", cc0toshiWallet);
        console2.log("  Deployer:", deployer);
        console2.log("");
        console2.log("Next Steps:");
        console2.log("-----------");
        console2.log("1. Verify contracts on Etherscan");
        console2.log("2. Update cc0strategy-spec.md with new addresses");
        console2.log("3. Update frontend config for Ethereum chain");
        console2.log("4. Test token deployment on mainnet");
    }
}

/**
 * @title MineSaltEthereum
 * @notice Pre-compute CREATE2 salt for hook deployment on Ethereum
 * 
 * Usage:
 *   DEPLOYER_ADDRESS=... FACTORY_ADDRESS=... forge script script/DeployEthereum.s.sol:MineSaltEthereum --rpc-url $ETH_RPC_URL
 */
contract MineSaltEthereum is Script {
    address constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    function run() public view {
        address deployer_ = vm.envAddress("DEPLOYER_ADDRESS");
        address factory_ = vm.envOr("FACTORY_ADDRESS", address(0));
        
        if (factory_ == address(0)) {
            console2.log("ERROR: Set FACTORY_ADDRESS env var");
            console2.log("(Factory must be deployed first, or use full deploy script)");
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
        
        bytes memory creationCode = abi.encodePacked(
            type(ClankerHookStaticFee).creationCode,
            abi.encode(POOL_MANAGER, factory_, WETH)
        );
        bytes32 initCodeHash = keccak256(creationCode);
        
        console2.log("=====================================");
        console2.log("Mining CREATE2 Salt for Ethereum Hook");
        console2.log("=====================================");
        console2.log("Chain: Ethereum Mainnet");
        console2.log("Deployer:", deployer_);
        console2.log("Factory:", factory_);
        console2.log("Required flags:", uint256(flags));
        console2.log("");
        console2.log("Searching...");
        
        for (uint256 i = 0; i < 10000000; i++) {
            bytes32 salt = bytes32(i);
            address predicted = address(uint160(uint256(keccak256(abi.encodePacked(
                bytes1(0xff),
                deployer_,
                salt,
                initCodeHash
            )))));
            
            if (uint160(predicted) & flags == flags) {
                console2.log("");
                console2.log("SUCCESS! Found valid salt");
                console2.log("========================");
                console2.log("Salt (decimal):", i);
                console2.log("Salt (bytes32):");
                console2.logBytes32(salt);
                console2.log("Predicted hook address:", predicted);
                console2.log("");
                console2.log("Save this salt for deployment!");
                return;
            }
            
            if (i % 500000 == 0 && i > 0) {
                console2.log("Checked", i, "salts...");
            }
        }
        
        console2.log("ERROR: No valid salt found in search range");
    }
}

/**
 * @title VerifyEthereumDeployment
 * @notice Verify all contracts are properly configured after deployment
 */
contract VerifyEthereumDeployment is Script {
    function run() public view {
        address factory_ = vm.envAddress("FACTORY_ADDRESS");
        address feeDistributor_ = vm.envAddress("FEE_DISTRIBUTOR_ADDRESS");
        
        console2.log("=====================================");
        console2.log("Verifying Ethereum Deployment");
        console2.log("=====================================");
        
        Clanker factory = Clanker(factory_);
        FeeDistributor feeDistributor = FeeDistributor(feeDistributor_);
        
        // Check factory configuration
        console2.log("");
        console2.log("Factory Configuration:");
        console2.log("  Deprecated:", factory.deprecated());
        console2.log("  TeamFeeRecipient:", factory.teamFeeRecipient());
        
        // Check FeeDistributor configuration
        console2.log("");
        console2.log("FeeDistributor Configuration:");
        console2.log("  Treasury:", feeDistributor.treasury());
        console2.log("  LpLocker:", feeDistributor.lpLocker());
        console2.log("  Factory:", feeDistributor.factory());
        
        console2.log("");
        console2.log("Verification complete!");
    }
}
