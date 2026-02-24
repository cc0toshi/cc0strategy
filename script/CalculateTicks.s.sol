// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @title CalculateTicks
 * @notice Calculate proper tick ranges for cc0strategy deployment
 * Based on Clanker's multi-position liquidity distribution
 */
contract CalculateTicks is Script {
    uint256 constant TOKEN_SUPPLY = 100_000_000_000 * 1e18; // 100B tokens
    int24 constant TICK_SPACING = 200;
    
    function run() public pure {
        console2.log("=== Clanker-style Tick Calculation ===");
        console2.log("Token Supply: 100B");
        console2.log("Tick Spacing: 200");
        console2.log("");
        
        // For a 10 ETH starting mcap with 100B tokens:
        // Price = 10 ETH / 100B = 1e-10 ETH per token
        // In sqrtPriceX96 terms, this corresponds to tick around -230400
        
        // The tickIfToken0IsClanker is NEGATIVE if clanker < WETH (alphabetically)
        // Our token 0xCBBb... > 0x4200... so token is currency1
        // Starting tick is POSITIVE 230400
        
        int24 startingTick = -230400; // For token0 = clanker (if clanker < WETH)
        // But our token > WETH, so actual pool tick will be +230400
        
        console2.log("Starting tick (tickIfToken0IsClanker):", startingTick);
        console2.log("");
        
        // Clanker uses MULTIPLE positions spread across tick ranges
        // Each position represents a "price band" where liquidity is active
        
        // Position 1: Just above starting tick (catches early buys)
        // Position 2: Higher range (medium buys)  
        // Position 3: Even higher (large buys)
        // Position 4: Wide range to max tick (moon scenario)
        
        // Example 4-position config (these need to be >= startingTick)
        console2.log("=== Suggested Multi-Position Config ===");
        console2.log("(All tickLower values must be >= -230400)");
        console2.log("");
        
        // Position 1: 40% of supply, narrow range near start
        console2.log("Position 1 (40% supply):");
        console2.log("  tickLower: -230400 (starting tick)");
        console2.log("  tickUpper: -200000 (roughly 20x from start)");
        console2.log("");
        
        // Position 2: 30% of supply, medium range
        console2.log("Position 2 (30% supply):");
        console2.log("  tickLower: -200000");
        console2.log("  tickUpper: -150000 (roughly 100x from start)");
        console2.log("");
        
        // Position 3: 20% of supply, higher range
        console2.log("Position 3 (20% supply):");
        console2.log("  tickLower: -150000");
        console2.log("  tickUpper: -100000 (roughly 1000x)");
        console2.log("");
        
        // Position 4: 10% of supply, to max
        console2.log("Position 4 (10% supply):");
        console2.log("  tickLower: -100000");
        console2.log("  tickUpper: 887200 (max tick)");
        console2.log("");
        
        console2.log("NOTE: Tick values must be divisible by tickSpacing (200)");
    }
}
