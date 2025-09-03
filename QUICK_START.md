# HighTideLight.nvim - Quick Start Guide

## Overview

HighTideLight.nvim provides real-time visual feedback for TidalCycles patterns with stream-specific colors (d1=red, d2=cyan, d3=blue, etc.). The system uses a high-performance Rust OSC bridge to handle dense pattern highlighting efficiently.

## Architecture

```
User evaluates Tidal → Neovim detects → Rust Bridge processes → Visual highlights
TidalCycles patterns → SuperCollider → Audio output
```

- **Rust OSC Bridge**: High-performance async server with 10ms batching for dense patterns
- **Neovim Integration**: Direct position data detection and highlighting
- **Stream Colors**: d1=red, d2=cyan, d3=blue, d4=green, d5=orange, d6=pink, d7=plum, d8=skyblue

## Installation

### 1. Build the Rust Bridge (Required)

```bash
cd tidal-osc-bridge
cargo build --release
```

The bridge handles OSC message processing and batching for optimal performance.

### 2. Plugin Installation

#### Using [Lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "your-username/HighTideLight.nvim",
  dependencies = {
    -- Add your Tidal plugin dependency if you have one
    -- "tidalcycles/tidal.nvim",
  },
  event = "VeryLazy",
  config = function()
    require('tidal-highlight').setup({
      debug = true,  -- Enable for initial testing
      animation = {
        fps = 30,
        duration_ms = 500,
      },
      highlights = {
        groups = {
          { name = "TidalHighlight1", fg = "#ff6b6b", bold = true },  -- d1 red
          { name = "TidalHighlight2", fg = "#4ecdc4", bold = true },  -- d2 cyan  
          { name = "TidalHighlight3", fg = "#45b7d1", bold = true },  -- d3 blue
          { name = "TidalHighlight4", fg = "#96ceb4", bold = true },  -- d4 green
        },
      },
    })
  end,
}
```

#### Using [AstroNvim](https://github.com/AstroNvim/AstroNvim)

Create `~/.config/nvim/lua/plugins/tidal-highlight.lua`:

```lua
return {
  "your-username/HighTideLight.nvim",
  event = "VeryLazy",
  dependencies = {
    -- Add dependencies here if needed
  },
  opts = {
    debug = false,  -- Set to true for debugging
    animation = {
      fps = 30,
      duration_ms = 500,
    },
    highlights = {
      groups = {
        { name = "TidalHighlight1", fg = "#ff6b6b", bold = true },
        { name = "TidalHighlight2", fg = "#4ecdc4", bold = true },
        { name = "TidalHighlight3", fg = "#45b7d1", bold = true },
        { name = "TidalHighlight4", fg = "#96ceb4", bold = true },
        { name = "TidalHighlight5", fg = "#ffa500", bold = true },
        { name = "TidalHighlight6", fg = "#ff69b4", bold = true },
        { name = "TidalHighlight7", fg = "#dda0dd", bold = true },
        { name = "TidalHighlight8", fg = "#87ceeb", bold = true },
      },
    },
  },
}
```

#### Manual Installation

```bash
git clone https://github.com/your-username/HighTideLight.nvim ~/.local/share/nvim/site/pack/plugins/start/HighTideLight.nvim
```

Then add to your `init.lua`:
```lua
require('tidal-highlight').setup()
```

### 3. Configure TidalCycles

Use the provided `BootTidal.hs` file with your TidalCycles setup. This configures the OSC target for the bridge.

### 4. Configure SuperCollider

Load the provided `startup.scd` file in SuperCollider. This sets up SuperDirt for audio output.

## Quick Test

### 1. Start the System

```bash
# In Neovim
:lua require('tidal-highlight').setup({debug = true})
:TidalHighlightStartBridge
```

### 2. Test Highlighting

```vim
# Test the highlighting system
:TidalHighlightSimulate
```

This should show multi-colored highlights on the current line, proving the system works.

### 3. Test with Real TidalCycles

Start SuperCollider with `startup.scd`, then start TidalCycles with `BootTidal.hs`. 

Open a `.tidal` file and evaluate patterns:
```haskell
d1 $ sound "bd cp bd cp"
d2 $ sound "hh*8"  
d3 $ sound "arpy*4" # lpf 1000
```

You should see stream-specific colored highlights appear when evaluating patterns.

## Commands

- `:TidalHighlightStartBridge` - Start the Rust OSC bridge
- `:TidalHighlightSimulate` - Test highlighting with simulated data
- `:TidalHighlightToggle` - Enable/disable highlighting
- `:TidalHighlightClear` - Clear all highlights
- `:TidalHighlightStatus` - Show current status
- `:TidalHighlightTest` - Test highlight on current line

## Configuration Options

```lua
require('tidal-highlight').setup({
  enabled = true,
  debug = false,  -- Set true for debug messages
  
  osc = {
    ip = "127.0.0.1",
    port = 6011,  -- Neovim receives on this port
  },
  
  animation = {
    fps = 30,
    duration_ms = 500,  -- How long highlights last
  },
  
  highlights = {
    groups = {
      -- Customize colors for each stream
      { name = "TidalHighlight1", fg = "#ff6b6b", bold = true },  -- d1
      { name = "TidalHighlight2", fg = "#4ecdc4", bold = true },  -- d2
      -- ... up to d8
    },
    outline_style = "underline", -- "underline", "box", or "bold"
  },
})
```

## Troubleshooting

### Bridge Issues
- **Bridge not found**: Run `cargo build --release` in `tidal-osc-bridge/`
- **Port conflicts**: Ensure ports 6011 and 6013 are available
- **Permission errors**: Check if bridge binary is executable

### No Highlights Appearing
- Enable debug mode: `debug = true`
- Check `:messages` for error output
- Verify bridge is running: `:TidalHighlightStatus`
- Test with simulation: `:TidalHighlightSimulate`

### Performance Issues
- Rust bridge handles batching automatically
- Reduce `fps` if needed: `fps = 15`
- Check CPU usage during dense patterns

## Technical Details

### Port Configuration
- **6013**: Rust bridge receives OSC from Neovim
- **6011**: Neovim receives processed OSC from bridge
- **57120**: SuperCollider (unchanged)

### Message Flow
1. User evaluates Tidal pattern in Neovim
2. Neovim detects positions and sends to bridge (6013)
3. Bridge processes/batches and forwards to Neovim (6011)
4. Neovim creates visual highlights
5. TidalCycles plays audio through SuperCollider

This architecture provides efficient highlighting for complex patterns while maintaining responsive audio performance.