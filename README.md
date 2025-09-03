# HighTideLight.nvim

A high-performance Neovim plugin that provides real-time visual feedback for TidalCycles live coding sessions. Features stream-specific highlighting with colors (d1=red, d2=cyan, d3=blue, etc.) and smooth fade animations synchronized with your patterns.

![TidalCycles Highlighting Demo](https://via.placeholder.com/800x400?text=TidalCycles+Real-time+Highlighting)

## ✨ Features

- **🌈 Stream-Specific Colors**: Each TidalCycles stream (d1-d8) gets its own color
- **⚡ High Performance**: Rust OSC bridge with async batching handles dense patterns
- **🎨 Smooth Animations**: Configurable fade effects and timing
- **🔌 Seamless Integration**: Works with existing TidalCycles and Neovim setups
- **🎵 Real-time Sync**: Highlights appear exactly when patterns are evaluated
- **⚙️ Fully Configurable**: Customize colors, animations, and behavior

## 🚀 Quick Start

### Prerequisites

- Neovim 0.5+
- [TidalCycles](https://tidalcycles.org/) installed and working
- [Rust](https://rustup.rs/) for building the OSC bridge
- SuperCollider with SuperDirt

### Installation

#### Using [Lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "your-username/HighTideLight.nvim",
  event = "VeryLazy",
  build = "cd tidal-osc-bridge && cargo build --release",
  dependencies = {
    -- Add your Tidal plugin if you have one
    -- "tidalcycles/tidal.nvim",
  },
  config = function()
    require('tidal-highlight').setup({
      debug = false,  -- Set to true for debugging
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
          { name = "TidalHighlight5", fg = "#ffa500", bold = true },  -- d5 orange
          { name = "TidalHighlight6", fg = "#ff69b4", bold = true },  -- d6 pink
          { name = "TidalHighlight7", fg = "#dda0dd", bold = true },  -- d7 plum
          { name = "TidalHighlight8", fg = "#87ceeb", bold = true },  -- d8 skyblue
        },
      },
    })
  end,
}
```

#### Using [AstroNvim](https://github.com/AstroNvim/AstroNvim)

Create or edit `~/.config/nvim/lua/plugins/tidal-highlight.lua`:

```lua
return {
  "your-username/HighTideLight.nvim",
  event = "VeryLazy",
  build = "cd tidal-osc-bridge && cargo build --release",
  dependencies = {
    -- Add dependencies here if needed
  },
  opts = {
    debug = false,
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

For AstroNvim Community Packs, you can also add it directly to your `plugins/community.lua`:

```lua
{ import = "astrocommunity.pack.lua" },
{ 
  "your-username/HighTideLight.nvim",
  event = "VeryLazy",
  build = "cd tidal-osc-bridge && cargo build --release",
  opts = {},
},
```

#### Using [Packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'your-username/HighTideLight.nvim',
  run = 'cd tidal-osc-bridge && cargo build --release',
  config = function()
    require('tidal-highlight').setup()
  end
}
```

#### Manual Installation

```bash
git clone https://github.com/your-username/HighTideLight.nvim ~/.local/share/nvim/site/pack/plugins/start/HighTideLight.nvim
cd ~/.local/share/nvim/site/pack/plugins/start/HighTideLight.nvim/tidal-osc-bridge
cargo build --release
```

Then add to your `init.lua`:
```lua
require('tidal-highlight').setup()
```

### Setup

1. **Configure TidalCycles**: Use the provided `BootTidal.hs` file
2. **Configure SuperCollider**: Load the provided `startup.scd` file
3. **Test the system**:
   ```vim
   :TidalHighlightStartBridge
   :TidalHighlightSimulate  -- Test highlighting
   ```

## 📖 Usage

### Basic Commands

- `:TidalHighlightStartBridge` - Start the Rust OSC bridge
- `:TidalHighlightToggle` - Enable/disable highlighting
- `:TidalHighlightSimulate` - Test with simulated highlights
- `:TidalHighlightClear` - Clear all current highlights
- `:TidalHighlightStatus` - Show current status

### Live Coding Workflow

1. Start SuperCollider and load `startup.scd`
2. Start TidalCycles with the provided `BootTidal.hs`
3. In Neovim: `:TidalHighlightStartBridge`
4. Start coding! Highlights appear automatically:

```haskell
d1 $ sound "bd cp bd cp"        -- Red highlights
d2 $ sound "hh*8"               -- Cyan highlights  
d3 $ sound "arpy*4" # lpf 1000  -- Blue highlights
d4 $ s "bass*2" # room 0.3      -- Green highlights
```

## ⚙️ Configuration

### Full Configuration Example

```lua
require('tidal-highlight').setup({
  enabled = true,
  debug = false,
  
  osc = {
    ip = "127.0.0.1",
    port = 6011,  -- Port for receiving highlights
  },
  
  animation = {
    fps = 30,              -- Animation frame rate
    duration_ms = 500,     -- How long highlights last
  },
  
  highlights = {
    groups = {
      -- Customize colors for each stream (d1-d8)
      { name = "TidalHighlight1", fg = "#ff6b6b", bg = "#2a1a1a", bold = true },
      { name = "TidalHighlight2", fg = "#4ecdc4", bg = "#1a2a2a", bold = true },
      { name = "TidalHighlight3", fg = "#45b7d1", bg = "#1a1a2a", bold = true },
      { name = "TidalHighlight4", fg = "#96ceb4", bg = "#1a2a1a", bold = true },
      { name = "TidalHighlight5", fg = "#ffa500", bg = "#2a2a1a", bold = true },
      { name = "TidalHighlight6", fg = "#ff69b4", bg = "#2a1a2a", bold = true },
      { name = "TidalHighlight7", fg = "#dda0dd", bg = "#2a1a2a", bold = true },
      { name = "TidalHighlight8", fg = "#87ceeb", bg = "#1a2a2a", bold = true },
    },
    outline_style = "underline", -- "underline", "box", or "bold"
  },
})
```

### Theme Integration

The plugin works well with popular themes. For dark themes like [tokyonight](https://github.com/folke/tokyonight.nvim):

```lua
highlights = {
  groups = {
    { name = "TidalHighlight1", fg = "#f7768e", bold = true },  -- Tokyo Night red
    { name = "TidalHighlight2", fg = "#7dcfff", bold = true },  -- Tokyo Night cyan
    { name = "TidalHighlight3", fg = "#7aa2f7", bold = true },  -- Tokyo Night blue
    { name = "TidalHighlight4", fg = "#9ece6a", bold = true },  -- Tokyo Night green
  },
}
```

## 🏗️ Architecture

The plugin uses a high-performance architecture designed for live coding:

```
User evaluates Tidal pattern → Neovim detects positions → Rust Bridge processes → Visual highlights
                              TidalCycles → SuperCollider → Audio output
```

### Components

- **Neovim Plugin**: Detects pattern evaluation and manages highlighting
- **Rust OSC Bridge**: High-performance async message processing with 10ms batching
- **TidalCycles Integration**: Audio synthesis continues normally
- **SuperCollider**: Handles audio output (unchanged)

### Performance Benefits

- **Async Processing**: Never blocks Neovim's event loop
- **Smart Batching**: Handles hundreds of events per second efficiently
- **Minimal Latency**: ~10ms typical response time for highlights
- **Memory Efficient**: Automatic cleanup of expired highlights

## 🔧 Troubleshooting

### Common Issues

#### Bridge Not Starting
```bash
# Build the bridge
cd tidal-osc-bridge && cargo build --release

# Check if executable exists
ls -la tidal-osc-bridge/target/release/tidal-osc-bridge
```

#### No Highlights Appearing
```vim
" Enable debug mode
:lua require('tidal-highlight').setup({debug = true})

" Check status
:TidalHighlightStatus

" Test highlighting
:TidalHighlightSimulate
```

#### Port Conflicts
- Ensure ports 6011 and 6013 are available
- Check with: `netstat -an | grep 601`
- Customize ports in configuration if needed

#### Performance Issues
- Reduce animation FPS: `fps = 15`
- Decrease highlight duration: `duration_ms = 250`
- Check CPU usage during dense patterns

### Debug Mode

Enable debug mode for detailed logging:
```lua
require('tidal-highlight').setup({debug = true})
```

Check Neovim messages with `:messages` for detailed output.

## 🤝 Contributing

Contributions are welcome! Please check out the [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
git clone https://github.com/your-username/HighTideLight.nvim
cd HighTideLight.nvim
cd tidal-osc-bridge && cargo build --release
```

### Running Tests

```bash
# Lua tests
nvim --headless -c "luafile tests/run_tests.lua" -c "qa"

# Rust tests
cd tidal-osc-bridge && cargo test
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [TidalCycles](https://tidalcycles.org/) community for inspiration
- [Pulsar](https://pulsar-edit.dev/) editor for highlighting research
- Neovim community for excellent plugin ecosystem

---

**Made with ❤️ for the live coding community**