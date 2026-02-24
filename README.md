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
    ├── 0.2% → Factory (team)
    │
    └── 0.8% → LpLocker → FeeDistributor
                              │
                              ├── 20% → Treasury
                              │
                              └── 80% → NFT Holders (equal per NFT)
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
| Factory | `0x70b17db500Ce1746BB34f908140d0279C183f3eb` |
| Hook | `0x18aD8c9b72D33E69d8f02fDA61e3c7fAe4e728cc` |
| LpLocker | `0x45e1D9bb68E514565710DEaf2567B73EF86638e0` |
| FeeDistributor | `0x9Ce2AB2769CcB547aAcE963ea4493001275CD557` |
| MevModule | `0xDe6DBe5957B617fda4b2dcA4dd45a32B87a54BfE` |

**Example Token (DICKSTR):**
- Token: `0x3b68C3B4e22E35Faf5841D1b5Eef8404D5A3b663`
- Pool ID: `0x34fc0d2eb125338f44d3001c5a5fd626aad60d98b763082b7fbdec8a6d501f30`
- Linked NFT: MferDickButts

### Ethereum Mainnet (Chain ID: 1)

| Contract | Address |
|----------|---------|
| Factory | `0xBbeBcC4aa7DDb4BeA65C86A2eB4147A6f39F10d3` |
| Hook | `0x9bEbE14d85375634c723EB5DC7B7E07C835dE8CC` |
| LpLocker | `0xb43aaEe744c46822C7f9209ECD5468C97B937030` |
| FeeDistributor | `0xF8bFB6aED4A5Bd1c7E4ADa231c0EdDeB49618989` |
| MevModule | `0x1cfEd8302B995De1254e4Ff08623C516f8B36Bf6` |

**Example Token (MFERSTR):**
- Token: `0x2fc106ff12267ae1bfe5bbbd273498df8147315a`
- Pool ID: `0xa71a02df3172aa341b25df4fd4f9aeafd972ebb94f3f022a63e19c8ff528d038`
- Linked NFT: mfers (`0x79fcdef22feed20eddacbb2587640e45491b757f`)

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
