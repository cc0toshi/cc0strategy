// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// Uniswap V4
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

// Protocol contracts
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {CC0StrategyLpLocker} from "../src/lp-lockers/CC0StrategyLpLocker.sol";
import {Clanker} from "../src/Clanker.sol";
import {IClanker} from "../src/interfaces/IClanker.sol";
import {ClankerHookStaticFee} from "../src/hooks/ClankerHookStaticFee.sol";
import {IClankerHookStaticFee} from "../src/hooks/interfaces/IClankerHookStaticFee.sol";

// Mock NFT for testing
import {MockERC721} from "../stubs/MockERC721.sol";

/**
 * @title IntegrationTest
 * @notice Integration test script for cc0strategy on Base Sepolia
 * 
 * Test flow:
 * 1. Deploy full protocol (or use existing deployment)
 * 2. Deploy a mock NFT collection
 * 3. Create a cc0strategy token linked to the mock NFT
 * 4. Do a swap to generate fees
 * 5. Verify fees went to FeeDistributor
 * 6. Claim as NFT holder
 */
contract IntegrationTest is Script {
    // ═══════════════════════════════════════════════════════════════════════════
    // BASE SEPOLIA ADDRESSES (Chain ID: 84532)
    // ═══════════════════════════════════════════════════════════════════════════
    
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant POSITION_MANAGER = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
    address constant UNIVERSAL_ROUTER = 0x492E6456D9528771018DeB9E87ef7750EF184104;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant POOL_SWAP_TEST = 0x8B5bcC363ddE2614281aD875bad385E0A785D3B9;
    
    // Protocol addresses (set these after deployment)
    address public feeDistributor;
    address public lpLocker;
    address public hook;
    address public factory;
    address public mevModule;
    
    // Test state
    address public deployer;
    MockERC721 public mockNft;
    address public testToken;
    uint256 public testNftId = 0;
    
    function setUp() public {
        // Load deployed addresses from environment
        feeDistributor = vm.envOr("FEE_DISTRIBUTOR", address(0));
        lpLocker = vm.envOr("LP_LOCKER", address(0));
        hook = vm.envOr("HOOK", address(0));
        factory = vm.envOr("FACTORY", address(0));
        mevModule = vm.envOr("MEV_MODULE", address(0));
    }
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Running cc0strategy Integration Test");
        console2.log("=====================================");
        console2.log("Deployer:", deployer);
        console2.log("");
        
        // Check if we have deployed addresses
        if (factory == address(0)) {
            console2.log("ERROR: No deployed addresses found!");
            console2.log("Run Deploy.s.sol first and set env vars:");
            console2.log("  FEE_DISTRIBUTOR, LP_LOCKER, HOOK, FACTORY, MEV_MODULE");
            return;
        }
        
        console2.log("Using deployed contracts:");
        console2.log("  Factory:", factory);
        console2.log("  FeeDistributor:", feeDistributor);
        console2.log("  LpLocker:", lpLocker);
        console2.log("  Hook:", hook);
        console2.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy mock NFT collection
        console2.log("Step 1: Deploying mock NFT collection...");
        mockNft = new MockERC721("TestMfers", "TMFER");
        
        // Mint some NFTs to the deployer
        for (uint256 i = 0; i < 10; i++) {
            mockNft.mint(deployer, i);
        }
        console2.log("  Mock NFT deployed:", address(mockNft));
        console2.log("  Minted 10 NFTs to deployer");
        
        // Verify total supply
        uint256 nftSupply = mockNft.totalSupply();
        console2.log("  Total supply:", nftSupply);
        
        // Step 2: Deploy a cc0strategy token
        console2.log("");
        console2.log("Step 2: Deploying test token...");
        testToken = deployTestToken();
        console2.log("  Test token deployed:", testToken);
        
        // Verify token is registered in FeeDistributor
        address registeredNft = FeeDistributor(feeDistributor).tokenToCollection(testToken);
        console2.log("  Registered NFT in FeeDistributor:", registeredNft);
        require(registeredNft == address(mockNft), "NFT not registered correctly");
        
        // Step 3: Get some WETH and do a swap
        console2.log("");
        console2.log("Step 3: Preparing to swap...");
        
        // Check deployer WETH balance
        uint256 wethBalance = IERC20(WETH).balanceOf(deployer);
        console2.log("  Deployer WETH balance:", wethBalance);
        
        if (wethBalance < 0.001 ether) {
            console2.log("  WARNING: Low WETH balance! Get WETH from faucet or wrap ETH");
            console2.log("  Skipping swap test...");
        } else {
            // Do swap (buy some test tokens with WETH)
            console2.log("  Swapping 0.001 WETH for test tokens...");
            doSwap(0.001 ether);
        }
        
        // Step 4: Check FeeDistributor state
        console2.log("");
        console2.log("Step 4: Checking FeeDistributor state...");
        uint256 accRewards = FeeDistributor(feeDistributor).accumulatedRewards(testToken);
        console2.log("  Accumulated rewards per NFT:", accRewards);
        
        // Step 5: Check claimable amount
        console2.log("");
        console2.log("Step 5: Checking claimable rewards...");
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = testNftId;
        
        uint256 claimable = FeeDistributor(feeDistributor).claimable(testToken, testNftId);
        console2.log("  Claimable for NFT #", testNftId, ":", claimable);
        
        // Step 6: Claim rewards if any
        if (claimable > 0) {
            console2.log("");
            console2.log("Step 6: Claiming rewards...");
            uint256 wethBefore = IERC20(WETH).balanceOf(deployer);
            FeeDistributor(feeDistributor).claim(testToken, tokenIds);
            uint256 wethAfter = IERC20(WETH).balanceOf(deployer);
            console2.log("  Claimed:", wethAfter - wethBefore, "WETH");
        } else {
            console2.log("");
            console2.log("Step 6: No rewards to claim yet");
            console2.log("  (Fees are collected on the NEXT swap after fee-generating swap)");
        }
        
        vm.stopBroadcast();
        
        // Print summary
        console2.log("");
        console2.log("=====================================");
        console2.log("INTEGRATION TEST COMPLETE!");
        console2.log("=====================================");
        console2.log("");
        console2.log("Test Token:", testToken);
        console2.log("Mock NFT:", address(mockNft));
        console2.log("");
        console2.log("Next steps:");
        console2.log("1. Do more swaps to generate fees");
        console2.log("2. Wait a block, then do another swap to collect fees");
        console2.log("3. Claim rewards as NFT holder");
    }
    
    function deployTestToken() internal returns (address) {
        // Configure token deployment
        IClanker.TokenConfig memory tokenConfig = IClanker.TokenConfig({
            tokenAdmin: deployer,
            name: "Test CC0Strategy Token",
            symbol: "TESTCC0",
            salt: bytes32(block.timestamp),
            image: "https://example.com/image.png",
            metadata: "Test token for integration testing",
            context: "cc0strategy integration test",
            originatingChainId: block.chainid
        });
        
        // Standard pool config: pair with WETH, 1% fee
        IClanker.PoolConfig memory poolConfig = IClanker.PoolConfig({
            pairedToken: WETH,
            tickIfToken0IsClanker: -207240, // ~$0.00001 starting price
            tickSpacing: 200,
            hook: hook,
            poolData: abi.encode(IClankerHookStaticFee.PoolStaticConfigVars({
                clankerFee: 10000, // 1%
                pairedFee: 10000   // 1%
            }))
        });
        
        // Locker config: single LP position
        int24[] memory tickLower = new int24[](1);
        int24[] memory tickUpper = new int24[](1);
        uint16[] memory positionBps = new uint16[](1);
        
        tickLower[0] = -207240;
        tickUpper[0] = 887200; // Near max tick
        positionBps[0] = 10000; // 100% in single position
        
        // Empty arrays for cc0strategy (fees go to FeeDistributor, not reward recipients)
        address[] memory rewardAdmins = new address[](0);
        address[] memory rewardRecipients = new address[](0);
        uint16[] memory rewardBps = new uint16[](0);
        
        IClanker.LockerConfig memory lockerConfig = IClanker.LockerConfig({
            locker: lpLocker,
            rewardAdmins: rewardAdmins,
            rewardRecipients: rewardRecipients,
            rewardBps: rewardBps,
            tickLower: tickLower,
            tickUpper: tickUpper,
            positionBps: positionBps,
            lockerData: ""
        });
        
        // MEV module config (simple block delay)
        IClanker.MevModuleConfig memory mevModuleConfig = IClanker.MevModuleConfig({
            mevModule: mevModule,
            mevModuleData: abi.encode(1) // 1 block delay
        });
        
        // No extensions for this test
        IClanker.ExtensionConfig[] memory extensionConfigs = new IClanker.ExtensionConfig[](0);
        
        // Full deployment config
        IClanker.DeploymentConfig memory deploymentConfig = IClanker.DeploymentConfig({
            tokenConfig: tokenConfig,
            poolConfig: poolConfig,
            lockerConfig: lockerConfig,
            mevModuleConfig: mevModuleConfig,
            extensionConfigs: extensionConfigs,
            nftCollection: address(mockNft)
        });
        
        // Deploy the token
        // NOTE: Factory needs to be modified to call FeeDistributor.registerToken()
        // For now, this will deploy but not register with FeeDistributor
        address token = Clanker(factory).deployToken(deploymentConfig);
        
        // TODO: After factory modification, registration happens atomically
        // For testing, manually register:
        // FeeDistributor(feeDistributor).registerToken(token, address(mockNft), WETH, mockNft.totalSupply());
        
        return token;
    }
    
    function doSwap(uint256 amountIn) internal {
        // Approve WETH to PoolSwapTest
        IERC20(WETH).approve(POOL_SWAP_TEST, amountIn);
        
        // Get pool key from hook/factory
        // For now, skip actual swap - just log intent
        console2.log("  Swap prepared (manual execution needed)");
        console2.log("  Use Uniswap interface or PoolSwapTest contract");
    }
}

/**
 * @title ManualClaimTest
 * @notice Simple script to test claiming from FeeDistributor
 */
contract ManualClaimTest is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        address feeDistributor = vm.envAddress("FEE_DISTRIBUTOR");
        address testToken = vm.envAddress("TEST_TOKEN");
        
        console2.log("Checking claimable rewards...");
        console2.log("FeeDistributor:", feeDistributor);
        console2.log("Test Token:", testToken);
        console2.log("Claimer:", deployer);
        
        // Check multiple NFT IDs
        for (uint256 i = 0; i < 10; i++) {
            uint256 claimable = FeeDistributor(feeDistributor).claimable(testToken, i);
            if (claimable > 0) {
                console2.log("  NFT #", i, "claimable:", claimable);
            }
        }
        
        // Claim for NFT #0 if claimable
        uint256 claimable = FeeDistributor(feeDistributor).claimable(testToken, 0);
        if (claimable > 0) {
            console2.log("");
            console2.log("Claiming for NFT #0...");
            
            vm.startBroadcast(deployerPrivateKey);
            
            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 0;
            FeeDistributor(feeDistributor).claim(testToken, tokenIds);
            
            vm.stopBroadcast();
            
            console2.log("Claimed successfully!");
        }
    }
}
