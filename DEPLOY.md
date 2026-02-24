# cc0strategy Deployment Guide

Deployment guide for cc0strategy protocol on Base Sepolia testnet.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Base Sepolia Addresses](#base-sepolia-addresses)
- [Quick Start](#quick-start)
- [Step-by-Step Deployment](#step-by-step-deployment)
- [Verification](#verification)
- [Integration Testing](#integration-testing)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### 1. Install Dependencies

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
cd cc0strategy-contracts
forge install
```

### 2. Get Base Sepolia ETH

Get testnet ETH from Base Sepolia faucets:
- https://www.alchemy.com/faucets/base-sepolia
- https://faucet.quicknode.com/base/sepolia
- https://basefaucet.com/

### 3. Configure Environment

```bash
cp .env.example .env
# Edit .env and set PRIVATE_KEY and TREASURY
```

---

## Base Sepolia Addresses

| Contract | Address |
|----------|---------|
| **Uniswap V4 PoolManager** | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` |
| **Uniswap V4 PositionManager** | `0x4b2c77d209d3405f41a037ec6c77f7f5b8e2ca80` |
| **Universal Router** | `0x492e6456d9528771018deb9e87ef7750ef184104` |
| **Permit2** | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| **StateView** | `0x571291b572ed32ce6751a2cb2486ebee8defb9b4` |
| **Quoter** | `0x4a6513c898fe1b2d0e78d3b0e0a4a151589b1cba` |
| **PoolSwapTest** | `0x8b5bcc363dde2614281ad875bad385e0a785d3b9` |
| **PoolModifyLiquidityTest** | `0x37429cd17cb1454c34e7f50b09725202fd533039` |
| **WETH** | `0x4200000000000000000000000000000000000006` |

---

## Quick Start

```bash
# Deploy everything in one command
forge script script/Deploy.s.sol:DeployCC0Strategy \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --verify \
  -vvvv
```

---

## Step-by-Step Deployment

### Deploy Order

The contracts must be deployed in this specific order due to dependencies:

```
1. FeeDistributor (needs treasury, placeholder lpLocker, placeholder factory)
       ↓
2. MevModule (standalone)
       ↓
3. Factory/Clanker (needs deployer as owner)
       ↓
4. Hook (needs factory address, requires CREATE2 salt mining)
       ↓
5. LpLocker (needs factory, feeDistributor, external addresses)
       ↓
6. Update FeeDistributor (set real lpLocker and factory)
       ↓
7. Enable contracts in Factory (hook, locker, mev module)
```

### 1. Deploy FeeDistributor

```bash
# Deploys with placeholder addresses (will update later)
forge script script/Deploy.s.sol:DeployCC0Strategy \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  -vvvv
```

### 2. Verify Deployments

After deployment, verify all contracts on BaseScan:

```bash
# Verify FeeDistributor
forge verify-contract <FEE_DISTRIBUTOR_ADDRESS> \
  src/FeeDistributor.sol:FeeDistributor \
  --chain-id 84532 \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address)" \
    $TREASURY $LP_LOCKER $FACTORY $OWNER)

# Verify Factory
forge verify-contract <FACTORY_ADDRESS> \
  src/Clanker.sol:Clanker \
  --chain-id 84532 \
  --constructor-args $(cast abi-encode "constructor(address)" $OWNER)

# Verify Hook
forge verify-contract <HOOK_ADDRESS> \
  src/hooks/ClankerHookStaticFee.sol:ClankerHookStaticFee \
  --chain-id 84532 \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" \
    0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408 $FACTORY $WETH)

# Verify LpLocker
forge verify-contract <LP_LOCKER_ADDRESS> \
  src/lp-lockers/CC0StrategyLpLocker.sol:CC0StrategyLpLocker \
  --chain-id 84532 \
  --constructor-args $(cast abi-encode \
    "constructor(address,address,address,address,address,address,address)" \
    $OWNER $FACTORY $FEE_DISTRIBUTOR \
    0x4b2c77d209d3405f41a037ec6c77f7f5b8e2ca80 \
    0x000000000022D473030F116dDEE9F6B43aC78BA3 \
    0x492e6456d9528771018deb9e87ef7750ef184104 \
    0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408)
```

---

## Verification

### Check Deployment State

```bash
# Check FeeDistributor configuration
cast call $FEE_DISTRIBUTOR "treasury()(address)" --rpc-url https://sepolia.base.org
cast call $FEE_DISTRIBUTOR "lpLocker()(address)" --rpc-url https://sepolia.base.org
cast call $FEE_DISTRIBUTOR "factory()(address)" --rpc-url https://sepolia.base.org

# Check Factory state
cast call $FACTORY "deprecated()(bool)" --rpc-url https://sepolia.base.org
cast call $FACTORY "enabledHooks(address)(bool)" $HOOK --rpc-url https://sepolia.base.org

# Check Hook permissions (should match getHookPermissions)
cast call $HOOK "getHookPermissions()(bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool)" \
  --rpc-url https://sepolia.base.org
```

### Expected Hook Permissions

```
beforeInitialize: true
afterInitialize: false
beforeAddLiquidity: true
afterAddLiquidity: false
beforeRemoveLiquidity: false
afterRemoveLiquidity: false
beforeSwap: true
afterSwap: true
beforeDonate: false
afterDonate: false
beforeSwapReturnDelta: true
afterSwapReturnDelta: true
afterAddLiquidityReturnDelta: false
afterRemoveLiquidityReturnDelta: false
```

---

## Integration Testing

### 1. Set Environment Variables

After deployment, update `.env` with deployed addresses:

```bash
FEE_DISTRIBUTOR=0x...
LP_LOCKER=0x...
HOOK=0x...
FACTORY=0x...
MEV_MODULE=0x...
```

### 2. Run Integration Test

```bash
forge script script/IntegrationTest.s.sol:IntegrationTest \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  -vvvv
```

### 3. Manual Testing Flow

1. **Deploy a test token** via Factory
2. **Get WETH** (wrap ETH or use faucet)
3. **Approve WETH** to UniversalRouter
4. **Execute swap** (buy test tokens)
5. **Wait 1 block**
6. **Execute another swap** (this collects fees from first swap)
7. **Check claimable** via FeeDistributor
8. **Claim rewards** as NFT holder

### Testing Commands

```bash
# Check claimable rewards
cast call $FEE_DISTRIBUTOR \
  "claimable(address,uint256)(uint256)" \
  $TEST_TOKEN \
  0 \
  --rpc-url https://sepolia.base.org

# Claim rewards
cast send $FEE_DISTRIBUTOR \
  "claim(address,uint256[])" \
  $TEST_TOKEN \
  "[0]" \
  --rpc-url https://sepolia.base.org \
  --private-key $PRIVATE_KEY
```

---

## Troubleshooting

### Hook Address Doesn't Have Correct Permission Bits

The hook address must have specific bits set based on permissions. The Deploy script mines for a valid salt automatically, but if it fails:

1. Increase the mining iterations in `Deploy.s.sol`
2. Or run the standalone `DeploySaltMiner` script first

### Factory Shows "Deprecated"

Call `setDeprecated(false)` as owner:

```bash
cast send $FACTORY "setDeprecated(bool)" false \
  --rpc-url https://sepolia.base.org \
  --private-key $PRIVATE_KEY
```

### Hook/Locker Not Enabled

Enable them in Factory:

```bash
# Enable hook
cast send $FACTORY "setHook(address,bool)" $HOOK true \
  --rpc-url https://sepolia.base.org \
  --private-key $PRIVATE_KEY

# Enable locker for hook
cast send $FACTORY "setLocker(address,address,bool)" $LP_LOCKER $HOOK true \
  --rpc-url https://sepolia.base.org \
  --private-key $PRIVATE_KEY
```

### Fees Not Appearing in FeeDistributor

Remember: Uniswap V4 fees are collected on the **NEXT** swap, not the current one. After a fee-generating swap, do another swap to trigger fee collection.

### Token Not Registered in FeeDistributor

The Factory must call `FeeDistributor.registerToken()` during `deployToken()`. This requires modifying the Factory contract (see spec for details).

---

## Known Addresses After Deploy

Update this section after deployment:

| Contract | Address |
|----------|---------|
| FeeDistributor | `TBD` |
| CC0StrategyLpLocker | `TBD` |
| ClankerHookStaticFee | `TBD` |
| Clanker (Factory) | `TBD` |
| ClankerMevBlockDelay | `TBD` |

---

## Security Notes

1. **Owner Controls**: FeeDistributor owner can update treasury, lpLocker, factory addresses
2. **Factory Controls**: Only enabled hooks/lockers can be used
3. **Fee Split**: Hardcoded 20% treasury / 80% NFT holders
4. **NFT Supply**: Cached at registration, immutable after

---

## Next Steps

1. Deploy to Base Sepolia
2. Run integration tests
3. Verify all contracts on BaseScan
4. Test with real users
5. Audit
6. Deploy to Base Mainnet
