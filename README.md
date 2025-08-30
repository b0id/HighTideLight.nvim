# HighTideLight.nvim

A Neovim plugin that provides real-time visual feedback for Tidal live coding sessions. It highlights and animates Tidal patterns as they are evaluated, enhancing the live coding experience.

## Features

- **Real-time Highlighting**: Automatically highlights Tidal patterns during evaluation
- **OSC Integration**: Uses Open Sound Control for precise synchronization with Tidal
- **Customizable Animations**: Configurable highlight groups, colors, and animation settings
- **Seamless Integration**: Hooks directly into Tidal's evaluation process
- **Neovim Commands**: Toggle, clear, and test highlighting with simple commands

## Requirements

- Neovim 0.5+
- [Tidal](https://tidalcycles.org/) installed and configured
- A Tidal Neovim plugin (e.g., [tidal.nvim](https://github.com/tidalcycles/tidal.nvim)) for basic Tidal integration
- OSC support (built-in with Neovim Lua)

## Installation

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use 'b0id/HighTideLight.nvim'
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim) (AstroNVIM default)

```lua
{
  "b0id/HighTideLight.nvim",
  event = "VeryLazy",
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'b0id/HighTideLight.nvim'
```

### Manual Installation

Clone this repository into your Neovim plugin directory:

```bash
git clone https://github.com/b0id/HighTideLight.nvim.git ~/.local/share/nvim/site/pack/plugins/start/HighTideLight.nvim
```

## Setup

### Standard Neovim Configuration

Add the following to your `init.lua`:

```lua
require('tidal-highlight').setup({
  -- Optional: customize settings
  osc = {
    ip = "127.0.0.1",
    port = 6011,
  },
  animation = {
    fps = 30,
    duration_ms = 200,
  },
  highlights = {
    groups = {
      { name = "TidalEvent1", fg = "#ff6b6b", bg = nil, blend = 30 },
      { name = "TidalEvent2", fg = "#4ecdc4", bg = nil, blend = 30 },
      { name = "TidalEvent3", fg = "#45b7d1", bg = nil, blend = 30 },
      { name = "TidalEvent4", fg = "#96ceb4", bg = nil, blend = 30 },
    },
    outline_style = "underline", -- "underline", "box", or "bold"
  },
  debug = false,
})
```

### AstroNVIM Configuration

For AstroNVIM users, add the plugin to your `plugins` configuration. Create or modify `~/.config/nvim/lua/plugins/tidal-highlight.lua`:

```lua
return {
  "b0id/HighTideLight.nvim",
  event = "VeryLazy",
  dependencies = {
    -- Add your Tidal plugin dependency here, e.g.:
    -- "tidalcycles/tidal.nvim",
  },
  opts = {
    osc = {
      ip = "127.0.0.1",
      port = 6011,
    },
    animation = {
      fps = 30,
      duration_ms = 200,
    },
    highlights = {
      groups = {
        { name = "TidalEvent1", fg = "#ff6b6b", bg = nil, blend = 30 },
        { name = "TidalEvent2", fg = "#4ecdc4", bg = nil, blend = 30 },
        { name = "TidalEvent3", fg = "#45b7d1", bg = nil, blend = 30 },
        { name = "TidalEvent4", fg = "#96ceb4", bg = nil, blend = 30 },
      },
      outline_style = "underline", -- "underline", "box", or "bold"
    },
    debug = false,
  },
  config = function(_, opts)
    require('tidal-highlight').setup(opts)
  end,
}
```

Alternatively, you can add it directly to your `community.lua` or main plugins table:

```lua
{
  "b0id/HighTideLight.nvim",
  event = "VeryLazy",
  opts = {
    -- Your configuration options here
  },
}
```

## Usage

1. Start Tidal in Neovim
2. Evaluate Tidal patterns as usual
3. HighTideLight will automatically highlight and animate the evaluated patterns

### Commands

- `:TidalHighlightToggle` - Enable/disable highlighting
- `:TidalHighlightClear` - Clear all current highlights
- `:TidalHighlightTest` - Test highlighting on the current line

## Configuration

All settings are optional and have sensible defaults. The plugin uses OSC port 6011 by default (different from SuperDirt's 6010).

### Highlight Groups

Customize the highlight groups to match your theme:

```lua
highlights = {
  groups = {
    { name = "TidalEvent1", fg = "#your_color", bg = nil, blend = 30 },
    -- Add more groups as needed
  },
  outline_style = "underline", -- Options: "underline", "box", "bold"
}
```

### Animation Settings

Adjust animation speed and duration:

```lua
animation = {
  fps = 30,        -- Frames per second
  duration_ms = 200, -- Animation duration in milliseconds
}
```

## How It Works

1. **OSC Server**: Starts an OSC server to receive events from Tidal
2. **Pattern Processing**: Intercepts Tidal evaluations and processes pattern lines
3. **Event Handling**: Receives OSC messages with timing and position data
4. **Highlight Animation**: Applies and animates highlights based on received events

## Troubleshooting

- Ensure Tidal is properly installed and the Tidal Neovim plugin is loaded
- Check that OSC port 6011 is not blocked
- Use `:TidalHighlightTest` to verify highlighting is working
- Set `debug = true` in config for additional logging

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
