# cc0strategy

NFT-linked token protocol built on Uniswap V4. Deploy tokens that distribute trading fees to NFT holders.

## Overview

cc0strategy enables anyone to launch a token linked to an existing NFT collection. 1% of all trading fees are automatically distributed to NFT holders.

**Key Features:**
- Launch tokens linked to any ERC-721 collection
- 1% trading fee on all swaps
- 80% of fees distributed to NFT holders
- 20% of fees to treasury
- MEV protection via block delay
- LP permanently locked (no rugs)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER SWAP                               │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Uniswap V4 PoolManager                       │
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │ ClankerHook │───▶│  LpLocker   │───▶│   FeeDistributor    │ │
│  │  (1% fee)   │    │(collect LP) │    │ (split to NFT/trea) │ │
│  └─────────────┘    └─────────────┘    └─────────────────────┘ │
│         │                                        │              │
│         ▼                                        ▼              │
│  ┌─────────────┐                         ┌──────────────┐       │
│  │  MevModule  │                         │ NFT Holders  │       │
│  │(block delay)│                         │   can claim  │       │
│  └─────────────┘                         └──────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

## Fee Structure

Every swap incurs a **1% LP fee**, distributed as follows:

```
1% swap fee
    │
    ├── 0.2% → Factory (team) - claimed via Factory.claimTeamFees()
    │
    └── 0.8% → LpLocker → FeeDistributor
                              │
                              └── 100% → NFT Holders (equal per NFT)
```

**One-Swap-Delay Pattern:** Fees from swap N are collected during swap N+1's `beforeSwap` hook. This is intentional Uniswap V4 behavior, not a bug.

## Contracts

### Core Contracts

| Contract | Description |
|----------|-------------|
| `Clanker.sol` | Factory for deploying new tokens with linked NFT collections |
| `ClankerToken.sol` | ERC-20 token with ERC-7802 cross-chain support, votes, and metadata |
| `ClankerHook.sol` | Uniswap V4 hook that handles fee collection and MEV protection |
| `CC0StrategyLpLocker.sol` | Locks LP positions permanently, collects fees, routes to FeeDistributor |
| `FeeDistributor.sol` | Distributes fees to NFT holders using Synthetix-style accumulators |
| `ClankerMevBlockDelay.sol` | MEV protection - blocks trading for N blocks after launch |

## Deployed Addresses

### Base Mainnet (Chain ID: 8453)

| Contract | Address |
|----------|---------|
| Factory | `0xDbbC0A64fFe2a23b4543b0731CF61ef0d5d4E265` |
| Hook | `0x5eE3602f499cFEAa4E13D27b4F7D2661906b28cC` |
| LpLocker | `0x5821e651D6fBF096dB3cBD9a21FaE4F5A1E2620A` |
| FeeDistributor | `0x498bcfdbd724989fc37259faba75168c8f47080d` |
| MevModule | `0x9EbA427CE82A4A780871D5AB098eF5EB6c590ffd` |

**Example Token (DICKSTR):**
- Token: `0x15ed6b4b7b675a454188dd991b9d0361c5b44dc1`
- Linked NFT: MferDickButts (`0x5c5D3CBaf7a3419af8E6661486B2D5Ec3AccfB1B`)

### Ethereum Mainnet (Chain ID: 1)

| Contract | Address |
|----------|---------|
| Factory | `0x1dc68bc05ecb132059fb45b281dbfa92b6fab610` |
| Hook | `0xEfd2F889eD9d7A2Bf6B6C9c2b20c5AEb6EBEe8Cc` |
| LpLocker | `0x05492c0091e49374e71c93e74739d3f650b59077` |
| FeeDistributor | `0xdcfb59f2d41c58a1325b270c2f402c1884338d0d` |
| MevModule | `0x47bee4a3b92caa86009e00dbeb4d43e8dcc1e955` |

**Example Tokens:**
- MFERSTR: `0x83297bf9fd8b6f961015a39cc025895c25890fce` - Linked to mfers (`0x79fcdef22feed20eddacbb2587640e45491b757f`)
- MFERDICKBUTT: `0x6a4a59fb9fc6ad207a977c6e803fee90ac12450a` - Linked to MferDickButts (`0x0cc1cf477d41d864854074c2bde160dc88d17160`)

### External Dependencies (Uniswap V4)

| Contract | Base | Ethereum |
|----------|------|----------|
| PoolManager | `0x498581fF718922c3f8e6A244956aF099B2652b2b` | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| PositionManager | `0x7C5f5A4bBd8fD63184577525326123B519429bDc` | `0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e` |
| UniversalRouter | `0x6fF5693b99212Da76ad316178A184AB56D299b43` | `0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af` |
| WETH | `0x4200000000000000000000000000000000000006` | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` |

## Building

```bash
# Install dependencies
forge install

# Build
forge build

# Run tests
forge test

# Run tests with verbosity
forge test -vvv
```

## Testing

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/FeeDistributor.t.sol

# Run with gas report
forge test --gas-report
```

## Deployment

See `script/` for deployment scripts:

- `DeployEthereum.s.sol` - Full deployment to Ethereum mainnet
- `Deploy.s.sol` - Generic deployment script
- `DeployFirstToken.s.sol` - Deploy a new token after factory is set up

```bash
# Deploy to Ethereum
forge script script/DeployEthereum.s.sol --rpc-url $ETH_RPC_URL --broadcast

# Verify contracts
forge verify-contract <address> <contract> --chain-id 1
```

## Security Considerations

### Immutable Parameters
- LP positions are permanently locked (no rug pulls)
- Token admin can be renounced (set to address(0))
- Factory owner cannot access locked LP

### MEV Protection
- Block delay prevents sandwich attacks on launch
- Configurable delay period (default: 2 blocks)

### Fee Distribution
- Uses Synthetix-style accumulator pattern
- NFT holders can claim anytime
- No front-running risk on claims

## License

MIT

## Credits

Forked from [Clanker](https://github.com/clanker-devco/clanker) by clanker.world.

Modified for cc0strategy by cc0toshi.
