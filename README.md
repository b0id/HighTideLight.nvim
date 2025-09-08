# HighTideLight.nvim

**🚧 ACTIVE DEVELOPMENT** - This plugin is under active development and represents a breakthrough in real-time TidalCycles integration. Core functionality is working, but expect rapid changes as we polish features and add new capabilities.  (There are tons of edge case bugs that are being worked out)

**Real-time surgical-precision highlighting** for TidalCycles patterns in Neovim with exact coordinate matching between SuperCollider audio events and source code tokens.

## Features

### ✅ Current Capabilities
- **Surgical coordinate precision** - Exact token-level highlighting using AST parsing
- **Multi-buffer support** - Simultaneous highlighting across multiple Tidal files  
- **Real-time performance** - 50+ OSC messages/second with no audio dropouts
- **Complex pattern support** - Effects chains, transformations, euclidean rhythms
- **Orbit-aware highlighting** - d1→orbit0, d2→orbit1, intelligent pattern separation
- **Thread-safe async communication** - Non-blocking SuperCollider ↔ Neovim bridge
- **Comprehensive diagnostics** - 13 debug commands for troubleshooting

### 🎯 Architecture Highlights
- **AST-based parsing** for precise token boundaries (30+ tokens per complex pattern)
- **Coordinate matching system** between SuperCollider and Neovim
- **Non-destructive highlighting** using Neovim's extmark API
- **Automatic cleanup** and memory management

## Why grddavies/tidal.nvim?

We chose [grddavies/tidal.nvim](https://github.com/grddavies/tidal.nvim) as our foundation because:

- **Modern Architecture** - Built with Neovim's latest APIs and Lua
- **Clean API Hooks** - Provides `tidal.api.send()` and `tidal.api.send_multiline()` for pattern interception
- **Active Maintenance** - Well-maintained with regular updates
- **Extensible Design** - Allows plugins like HighTideLight to hook into the evaluation pipeline
- **Zero Modification Required** - We can intercept patterns without changing TidalCycles workflow

**Alternative Options:**
- `tidalcycles/vim-tidal` - Older Vimscript implementation, harder to extend
- Custom GHCI integration - Would require reinventing REPL communication
- Direct TidalCycles modification - Would break compatibility and updates

## Installation & Setup

### Prerequisites

**Neovim Setup:**
- **Neovim** ≥ 0.7 (for extmark API)
- **TreeSitter** with Haskell grammar: `:TSInstall haskell`

**TidalCycles Environment:**
- **TidalCycles** properly installed and working
- **SuperCollider** + **SuperDirt** functioning
- **GHCI** accessible in PATH

**Package Manager:**
This setup uses [lazy.nvim](https://github.com/folke/lazy.nvim), the modern Neovim package manager with lazy loading and dependency management.

### Lazy.nvim Configuration

Add this to your Neovim configuration:

```lua
{
  "grddavies/tidal.nvim",
  opts = {
    boot = {
      tidal = {
        cmd = "ghci",
        args = { "-v0" },
        file = vim.api.nvim_get_runtime_file("bootfiles/BootTidal.hs", false)[1],
        enabled = true,
      },
      sclang = {
        cmd = "sclang", 
        args = {},
        file = vim.api.nvim_get_runtime_file("bootfiles/BootSuperDirt.scd", false)[1],
        enabled = false, -- Set to true for auto-start SuperCollider
      },
      split = "v", -- Vertical split for REPL
    },
    mappings = {
      send_line = { mode = { "i", "n" }, key = "<S-CR>" },
      send_visual = { mode = { "x" }, key = "<S-CR>" },
      send_block = { mode = { "i", "n", "x" }, key = "<M-CR>" },
      send_node = { mode = "n", key = "<leader><CR>" },
      send_silence = { mode = "n", key = "<leader>m" },
      send_hush = { mode = "n", key = "<leader><Esc>" },
    },
    selection_highlight = {
      highlight = { link = "IncSearch" },
      timeout = 150,
    },
  },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "haskell", "supercollider" } },
  },
},

-- HighTideLight.nvim configuration  
{
  "b0id/HighTideLight.nvim", -- Replace with your GitHub username
  branch = "main", -- or "feature/ast-parsing" for latest development
  lazy = false,
  dependencies = { "grddavies/tidal.nvim" },
  config = function()
    require('tidal-highlight').setup({
      debug = true, -- Enable for development/troubleshooting
      enabled = true,
      osc = {
        ip = "127.0.0.1",
        port = 6011,
      },
      animation = {
        fps = 30,
      },
      highlights = {
        groups = {
          { name = "TidalEvent1", fg = "#ff0000", bg = "#000000", blend = 20 },
          { name = "TidalEvent2", fg = "#00ff00", bg = "#000000", blend = 20 }, 
          { name = "TidalEvent3", fg = "#0000ff", bg = "#000000", blend = 20 },
        },
        outline_style = "underline",
      },
    })
  end,
},
```

### SuperCollider Integration

Add this line to your SuperCollider startup file or evaluate manually:

```supercollider
"/path/to/HighTideLight.nvim/supercollider/HighTideLightOSC.scd".load;
```

**SuperCollider Startup File Locations:**
- **Linux/macOS**: `~/.local/share/SuperCollider/startup.scd`
- **Windows**: `%USERPROFILE%/AppData/Local/SuperCollider/startup.scd`

## Configuration Options

### Basic Setup
```lua
require('tidal-highlight').setup({
  debug = false,           -- Disable debug messages in production
  enabled = true,          -- Enable highlighting system
  osc = {
    ip = "127.0.0.1",     -- OSC server IP
    port = 6011,          -- OSC server port  
  },
  animation = {
    fps = 30,             -- Highlight refresh rate
  },
  highlights = {
    groups = {
      { name = "TidalEvent1", fg = "#ff6b6b", blend = 25 },
      { name = "TidalEvent2", fg = "#4ecdc4", blend = 25 },
      { name = "TidalEvent3", fg = "#45b7d1", blend = 25 },
      { name = "TidalEvent4", fg = "#f9ca24", blend = 25 },
    },
  },
})
```

### Advanced Configuration
```lua
require('tidal-highlight').setup({
  debug = true,
  supercollider = {
    ip = "127.0.0.1",
    port = 57120, -- SuperCollider OSC port
  },
  highlights = {
    groups = {
      -- Custom highlight groups per orbit
      { name = "TidalDrums", fg = "#ff0000", bold = true },
      { name = "TidalBass", fg = "#00ff00", italic = true },
      { name = "TidalMelody", fg = "#0000ff", underline = true },
    },
    outline_style = "underline", -- or "border"
  },
  animation = {
    fps = 60, -- Higher refresh rate for smoother animation
    fade_duration = 200, -- Fade out time in ms
  },
})
```

## Usage & Commands

### Basic Workflow
1. **Start SuperCollider** with SuperDirt running
2. **Open Neovim** with a `.tidal` or `.hs` file
3. **Evaluate Tidal patterns** using `grddavies/tidal.nvim` commands
4. **Watch real-time highlights** appear as patterns play

### Debug Commands
- `:TidalTestPatternParsing` - Test AST parsing on current buffer
- `:TidalInspectSourceMaps` - View token coordinate mappings
- `:TidalShowOSCHistory` - Display recent SuperCollider messages
- `:TidalInspectOSCFlow` - Test coordinate matching logic
- `:TidalShowStats` - System performance and statistics
- :TidalQuietDebug - Disable debug notifications
- :TidalDebugIntegration - Re-enable debug notifications

### Diagnostic Commands  
- `:TidalHealthReport` - Overall system health check
- `:TidalDebugIntegration` - Enable verbose debug logging
- `:TidalTestAnimation` - Test highlight system directly

## Development Status

### ✅ Working Features
- **Precision highlighting** with exact coordinate matching
- **Multi-buffer support** for complex projects
- **Real-time performance** optimized for live coding
- **Complex pattern parsing** including effects and transformations
- **Comprehensive debugging tools** for troubleshooting

### 🚧 Known Issues
- **Right-edge precision** - Highlights may be missing the last character
- **Custom themes** - Limited highlight customization currently
- **Documentation** - Some advanced features need better docs

### 🔮 Planned Features
- **Pattern visualization** beyond highlighting  
- **Custom animation styles** and effects
- **Multi-channel highlighting** for surround/spatial audio
- **Export/import** of pattern coordinate data
- **Additional live coding environment** integrations

## Contributing

This is an active development project welcoming contributions! Areas of interest:

- **Performance optimization** for even larger patterns
- **UI/UX improvements** and custom themes
- **Additional diagnostic tools** and debugging features
- **Documentation** and setup guides
- **Testing infrastructure** and automated validation

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for complete technical documentation of the system design, data flow, and component interactions.

## Troubleshooting

### Common Issues
1. **No highlights appearing**
   - Check `:TidalShowOSCHistory` for SuperCollider communication
   - Verify SuperCollider script is loaded: `HighTideLightOSC.scd`
   - Test with `:TidalTestAnimation` to verify highlight system

2. **Pattern parsing not working**
   - Run `:TidalTestPatternParsing` to check AST extraction
   - Ensure TreeSitter Haskell grammar is installed: `:TSInstall haskell`

3. **SuperCollider connection issues**
   - Check OSC port configuration (default: 6011)
   - Verify SuperCollider and SuperDirt are running
   - Use `:TidalHealthReport` for system diagnostics

### Getting Help
- **Enable debug mode**: `debug = true` in configuration
- **Check system status**: `:TidalShowStats` command
- **Review logs**: `:TidalShowOSCHistory` and `:TidalHealthReport`
- **Test components**: Use individual test commands to isolate issues

---

**🚧 This plugin represents a breakthrough in live coding tool integration - precision, performance, and extensibility for the Neovim TidalCycles community.**
