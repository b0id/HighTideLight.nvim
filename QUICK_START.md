# HighTideLight.nvim - Quick Start

## Overview

HighTideLight.nvim is a companion plugin for TidalCycles that provides real-time syntax highlighting synchronized with pattern evaluation. Based on comprehensive research of the Pulsar implementation.

## Architecture

- **Rust OSC Bridge**: High-performance UDP server for OSC message handling
- **Companion Plugin**: Clean Lua implementation that doesn't interfere with tidal.nvim
- **6-Argument OSC Format**: `[stream_id, start_row, start_col, end_row, end_col, duration]`

## Installation

### 1. Build the Rust Bridge

```bash
cd tidal-osc-bridge
cargo build --release
```

### 2. Configure tidal.nvim to use our BootTidal.hs

Point your tidal.nvim configuration to use the provided `BootTidal.hs` file.

### 3. Setup the Companion Plugin

```lua
-- In your Neovim configuration
require('tidal-highlights').setup({
  debug = true,  -- Enable for initial testing
  animation = {
    duration_ms = 500,
    fade_steps = 5,
  },
})
```

## Testing

### 1. Start the Bridge Manually

```bash
./tidal-osc-bridge/target/release/tidal-osc-bridge --debug
```

### 2. Test OSC Message Parsing

Send a test OSC message to port 6013:

```bash
# Example OSC message for testing (if you have oscsend)
oscsend localhost 6013 /editor/highlights iiiiii 1 1 5 1 10 500
```

### 3. Expected Behavior

- Tidal pattern evaluation should trigger OSC messages
- Highlights should appear with fade animation
- Debug messages should show OSC parsing

## Commands

- `:TidalHighlightsStart` - Start the bridge
- `:TidalHighlightsStop` - Stop the bridge  
- `:TidalHighlightsClear` - Clear all highlights

## Troubleshooting

1. **Bridge not found**: Ensure `cargo build --release` completed successfully
2. **No highlights**: Check that ports 6013 are available and debug is enabled
3. **OSC parsing errors**: Verify the 6-argument message format

## Technical Details

### OSC Message Flow

1. TidalCycles evaluates pattern with deltaContext
2. Sends OSC to port 6013 with `/editor/highlights` address
3. Rust bridge parses and forwards as JSON to Neovim
4. Companion plugin creates animated extmarks

### Port Configuration

- **6013**: OSC communication (Tidal → Bridge)
- **6010**: tidal.nvim control port (unchanged)
- **57120**: SuperDirt (unchanged)

## Next Steps

This implementation provides a clean foundation for TidalCycles highlighting based on the Pulsar research. The architecture is designed for extension and performance.