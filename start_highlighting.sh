#!/bin/bash
# TidalCycles Highlight Setup Script

echo "🌊 TidalCycles Real-time Highlighting Setup"
echo "==========================================="

# Check if Rust bridge exists
BRIDGE_PATH="$(dirname "$0")/tidal-osc-bridge/target/release/tidal-osc-bridge"

if [ ! -f "$BRIDGE_PATH" ]; then
    echo "❌ Rust bridge not found. Building..."
    cd "$(dirname "$0")/tidal-osc-bridge"
    cargo build --release
    cd ..
else
    echo "✅ Rust bridge found"
fi

echo ""
echo "🚀 Starting OSC Bridge..."
echo "   Listening: 127.0.0.1:6013 (from TidalCycles)"
echo "   Forwarding: 127.0.0.1:6011 (to Neovim)"
echo ""
echo "💡 To use in TidalCycles, add this to your BootTidal.hs:"
echo "   tidal <- startTidal (superdirtTarget {oTargets = [superdirtTarget, oscTarget \"127.0.0.1\" 6013]}) defaultConfig"
echo ""
echo "🎹 In Neovim, run: :TidalHighlightToggle"
echo ""
echo "Press Ctrl+C to stop the bridge"
echo "================================"

# Start the bridge (will run until Ctrl+C)
"$BRIDGE_PATH" --port 6013 --neovim-port 6011 --debug
