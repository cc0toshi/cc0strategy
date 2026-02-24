# cc0strategy Contracts

Uniswap V4 hook-based token factory with NFT-gated fee distribution.

## V2 Contracts (2026-02-24)

### Fee Structure
- **1% total swap fee**
- **0.2%** → Team (via Factory.claimTeamFees)
- **0.8%** → NFT holders (100% of LP fees via FeeDistributor)

### Base Mainnet
| Contract | Address |
|----------|---------|
| Factory | `0xDbbC0A64fFe2a23b4543b0731CF61ef0d5d4E265` |
| FeeDistributor | `0x498bcfdbd724989fc37259faba75168c8f47080d` |
| LpLocker | `0x5821e651D6fBF096dB3cBD9a21FaE4F5A1E2620A` |
| Hook | `0x5eE3602f499cFEAa4E13D27b4F7D2661906b28cC` |
| MevModule | `0x9EbA427CE82A4A780871D5AB098eF5EB6c590ffd` |

### Ethereum Mainnet
| Contract | Address |
|----------|---------|
| Factory | `0x1dc68bc05ecb132059fb45b281dbfa92b6fab610` |
| FeeDistributor | `0xdcfb59f2d41c58a1325b270c2f402c1884338d0d` |
| LpLocker | `0x05492c0091e49374e71c93e74739d3f650b59077` |
| Hook | `0xEfd2F889eD9d7A2Bf6B6C9c2b20c5AEb6EBEe8Cc` |
| MevModule | `0x47bee4a3b92caa86009e00dbeb4d43e8dcc1e955` |

## Build

\`\`\`bash
forge build
\`\`\`

## Forked From

This is a fork of [Clanker](https://github.com/clanker-devco/v4-contracts) with modifications for cc0strategy.
