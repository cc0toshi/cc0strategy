# cc0strategy - Ethereum Mainnet Deployment Guide

**Status:** Ready to deploy  
**Prepared by:** cc0toshi  
**Date:** 2026-02-24

---

## Overview

This guide covers deploying cc0strategy to Ethereum Mainnet. The protocol is already live on Base, and this deployment mirrors that setup with Ethereum-specific addresses.

## Prerequisites

### 1. Environment Variables

Create a `.env` file or export these variables:

```bash
# Required
export PRIVATE_KEY="your_deployer_private_key"
export ETH_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
export ETHERSCAN_API_KEY="your_etherscan_api_key"

# Optional (defaults shown)
export TREASURY="0x58e510F849e38095375a3e478aD1d719650B8557"
export DEPLOYER_ADDRESS="0x..."  # Derived from PRIVATE_KEY if not set
```

### 2. Deployer Wallet

- **Minimum ETH required:** 0.3 ETH (for gas @ ~30 gwei)
- **Recommended:** 0.5 ETH (safety margin for gas spikes)
- **Address:** Use a fresh deployer or your existing treasury wallet

### 3. Foundry Installation

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

---

## Contract Addresses

### Ethereum Mainnet Dependencies (Uniswap V4)

| Contract | Address |
|----------|---------|
| PoolManager | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| PositionManager | `0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e` |
| UniversalRouter | `0x66a9893cC07D91D95644AEDD05D03f95e1dba8Af` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` |

### cc0strategy Contracts (To Be Deployed)

| Contract | Purpose | Gas Estimate |
|----------|---------|--------------|
| ClankerPoolExtensionAllowlist | Pool extension registry | ~500K |
| FeeDistributor | 80/20 NFT/treasury split | ~800K |
| ClankerMevBlockDelay | MEV protection | ~300K |
| Clanker (Factory) | Token deployment factory | ~4M |
| ClankerHookStaticFee | Uniswap V4 hook | ~1.5M |
| CC0StrategyLpLocker | LP position management | ~1.2M |
| **TOTAL** | | **~8.3M gas** |

At 30 gwei: **~0.25 ETH** (~$750 at $3000/ETH)

---

## Deployment Steps

### Step 1: Compile Contracts

```bash
cd cc0strategy-contracts
forge build
```

### Step 2: Run Tests (Verification)

```bash
forge test -vvv
```

All 29 tests should pass.

### Step 3: Simulate Deployment (Dry Run)

```bash
forge script script/DeployEthereum.s.sol:DeployEthereum \
  --rpc-url $ETH_RPC_URL \
  -vvvv
```

This runs without broadcasting - verify the output looks correct.

### Step 4: Deploy to Mainnet

```bash
forge script script/DeployEthereum.s.sol:DeployEthereum \
  --rpc-url $ETH_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

The `--verify` flag automatically verifies on Etherscan.

### Step 5: Save Deployed Addresses

After deployment, the script outputs all addresses. Save them:

```bash
# Example output (replace with actual addresses)
PoolExtensionAllowlist: 0x...
FeeDistributor: 0x...
LpLocker: 0x...
Hook: 0x...
Factory: 0x...
MevModule: 0x...
```

### Step 6: Verify Deployment

```bash
# Set deployed addresses
export FACTORY_ADDRESS="0x..."
export HOOK_ADDRESS="0x..."
export LP_LOCKER_ADDRESS="0x..."
export FEE_DISTRIBUTOR_ADDRESS="0x..."

# Run verification script
forge script script/DeployEthereum.s.sol:VerifyEthereumDeployment \
  --rpc-url $ETH_RPC_URL
```

---

## Hook Salt Mining

The V4 hook requires specific permission bits in its address. The deployment script mines the salt automatically, but if you need to pre-compute:

### Required Permission Bits

| Permission | Flag |
|------------|------|
| beforeInitialize | `1 << 0` |
| beforeAddLiquidity | `1 << 2` |
| beforeSwap | `1 << 6` |
| afterSwap | `1 << 7` |
| beforeSwapReturnDelta | `1 << 10` |
| afterSwapReturnDelta | `1 << 11` |

Combined flags: `0x8C5` (binary: `100011000101`)

### Pre-Mine Salt (Optional)

```bash
# First deploy Factory, then mine salt
export FACTORY_ADDRESS="0x..."
export DEPLOYER_ADDRESS="0x..."

forge script script/DeployEthereum.s.sol:MineSaltEthereum \
  --rpc-url $ETH_RPC_URL
```

---

## Post-Deployment Checklist

- [ ] All contracts deployed and verified on Etherscan
- [ ] Factory has hook/locker/mev module enabled
- [ ] FeeDistributor has correct lpLocker and factory addresses
- [ ] Factory `deprecated` is `false` (deployments enabled)
- [ ] Treasury address is correct
- [ ] Test token deployment works

### Update cc0strategy-spec.md

Add the Ethereum Mainnet addresses:

```markdown
### Ethereum Mainnet (Chain ID: 1)

| Contract | Address | Notes |
|----------|---------|-------|
| **Factory (Clanker)** | `0x...` | Token deployment |
| **ClankerHook** | `0x...` | 1% fee capture |
| **FeeDistributor** | `0x...` | 80/10/10 split |
| **LP Locker** | `0x...` | Fee collection |
| **PoolExtensionAllowlist** | `0x...` | Extension registry |
| **MevModule** | `0x...` | MEV protection |
```

### Update Frontend

In `cc0strategy-app/src/config/contracts.ts`:

```typescript
export const ETHEREUM_CONTRACTS = {
  factory: "0x...",
  hook: "0x...",
  feeDistributor: "0x...",
  lpLocker: "0x...",
  poolManager: "0x000000000004444c5dc75cB358380D2e3dE08A90",
  positionManager: "0xbd216513d74c8cf14cf4747e6aaa6420ff64ee9e",
  universalRouter: "0x66a9893cC07D91D95644AEDD05D03f95e1dba8Af",
  permit2: "0x000000000022D473030F116dDEE9F6B43aC78BA3",
  weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
};
```

---

## Troubleshooting

### "Could not find valid salt"

The salt mining searches up to 1M iterations. If it fails:
1. Try running `MineSaltEthereum` separately with more iterations
2. Use a different deployer address

### "Hook address does not have correct permission bits"

The CREATE2 salt didn't produce correct address bits. Re-run deployment or pre-mine salt.

### Gas Too High

Ethereum mainnet gas can spike. Options:
1. Wait for lower gas (check etherscan.io/gastracker)
2. Increase `--gas-price` if needed
3. Deploy contracts individually with `--gas-limit`

### Etherscan Verification Fails

```bash
# Manual verification
forge verify-contract \
  --chain mainnet \
  --compiler-version v0.8.28 \
  --constructor-args $(cast abi-encode "constructor(address,address)" $POOL_MANAGER $FACTORY) \
  $HOOK_ADDRESS \
  src/hooks/ClankerHookStaticFee.sol:ClankerHookStaticFee
```

---

## Key Differences from Base

| Aspect | Base | Ethereum |
|--------|------|----------|
| Chain ID | 8453 | 1 |
| WETH | `0x4200...0006` | `0xC02a...6Cc2` |
| PoolManager | `0x4985...2b2b` | `0x0000...8A90` |
| Gas cost | ~0.01 ETH | ~0.25 ETH |
| Block time | 2s | 12s |

---

## Security Notes

1. **Deployer key:** Keep private key secure, only use for deployment
2. **Treasury:** Same as Base (cc0toshi wallet) unless changed
3. **Ownership:** Factory owner can enable/disable hooks and lockers
4. **Fee split:** Hardcoded 80/20 in FeeDistributor (NFT holders/treasury)
5. **Auto-renounce:** Tokens have ownership renounced on deployment

---

## Quick Deploy Command

```bash
# One-liner (after setting env vars)
cd cc0strategy-contracts && \
forge script script/DeployEthereum.s.sol:DeployEthereum \
  --rpc-url $ETH_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

---

*cc0strategy - trade memes, fund culture*  
*A $cc0company project, built by cc0toshi*
