# HighTideLight.nvim Setup for AstroNvim + grddavies/tidal.nvim

## Real-World Testing Guide

### Prerequisites Check
```bash
# Verify your stack is working
ghci --version              # GHC for Tidal
sclang --version           # SuperCollider  
nvim --version             # Neovim 0.5+
```

### Phase 1: Basic Integration Test

#### 1. Add to your AstroNvim configuration

In your `user/plugins/tidal.lua` or `user.lua`, modify your existing tidal plugin:

```lua
{
  "grddavies/tidal.nvim",
  opts = {
    -- Your existing config...
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
        enabled = false,
      },
      split = "v",
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

-- ADD THE HIGHLIGHTING PLUGIN
{
  "b0id/HighTideLight.nvim",
  dependencies = { "grddavies/tidal.nvim" },
  config = function()
    require('tidal-highlight').setup({
      debug = true,  -- IMPORTANT: Enable for initial testing
      osc = {
        ip = "127.0.0.1",
        port = 6011,  -- Different from SuperDirt's 6010
      },
      animation = {
        fps = 30,
        duration_ms = 500,  -- Longer for testing
      },
      highlights = {
        groups = {
          { name = "TidalEvent1", fg = "#ff6b6b", bg = nil, blend = 30 },
          { name = "TidalEvent2", fg = "#4ecdc4", bg = nil, blend = 30 },
          { name = "TidalEvent3", fg = "#45b7d1", bg = nil, blend = 30 },
        },
      },
    })
  end,
},
```

#### 2. Install and restart AstroNvim
```bash
# Start AstroNvim - it should install the plugin
nvim
```

### Phase 2: Diagnostics

Before testing with real Tidal, run diagnostics:

```vim
:TidalHighlightDiagnostics
```

This will check:
- ✅ Environment compatibility  
- ✅ Tidal plugin detection (`grddavies/tidal.nvim`)
- ✅ OSC connectivity
- ✅ Pattern processor
- ✅ Integration hooks

**Expected Output:**
```
🔍 HighTideLight.nvim Diagnostics
==================================================

📋 Environment:
  Neovim: 0.9.x ✅
  Lua: Lua 5.1 ✅  
  Loop support: ✅
  Bit operations: ✅
  Tidal plugin: grddavies/tidal.nvim ✅
  Send function: ❌  (Expected - grddavies uses different API)

🌐 OSC Connectivity:
  OSC server: ✅
  Port 6011: Available
  Callbacks: ✅

⚙️  Processor:
  Pattern processing: ✅
    Pattern 1: 2 markers, context: ✅
    Pattern 2: 4 markers, context: ✅
    Pattern 3: 3 markers, context: ✅

🎵 Tidal Integration:
  Plugin detected: grddavies/tidal.nvim ✅
  Hook installed: ✅
  Result: Wrapped X evaluation functions

==================================================
🎉 All systems ready! Plugin should work in real environment.
```

### Phase 3: Basic Plugin Test

Test the highlighting system works:

```vim
:TidalHighlightTest
```

You should see highlighting on the current line. If this works, the plugin can render highlights.

### Phase 4: SuperCollider Bridge (Critical)

#### 1. Load the OSC bridge in SuperCollider

In SuperCollider, evaluate this code:

```supercollider
// Load the HighTideLight OSC bridge
(
~highlightDebug = true;  // Enable verbose output
"path/to/HighTideLight.nvim/supercollider/HighTideLightOSC.scd".load;
)
```

#### 2. Test OSC communication

```supercollider
// Test that SuperCollider can send to Neovim
~testTidalHighlight.();
```

You should see a test highlight in Neovim.

### Phase 5: Real Tidal Integration Test

#### 1. Create test file

Create `test.tidal`:
```haskell
d1 $ sound "bd sn"
d1 $ sound "bd sn hh oh"
d1 $ sound "bd sn" # gain 0.8
```

#### 2. Test evaluation with debugging

1. Open `test.tidal` in Neovim
2. Start Tidal with `:TidalStart` (or your usual method)
3. Position cursor on first line
4. Evaluate with `<S-CR>` (your mapping)

**Watch for debug output:**
- Neovim should show: "HighTideLight: Wrapped X evaluation functions"
- SuperCollider should show: "Received pattern registration: d1 $ sound \"bd sn\""
- You should see highlights appear on the Tidal code

### Phase 6: Troubleshooting

#### Common Issues:

1. **No hook detected**
   ```vim
   :lua vim.notify(vim.inspect(require('tidal-highlight.compat').get_tidal_info()))
   ```

2. **OSC port conflicts**
   ```bash
   netstat -ln | grep 6011
   ```

3. **SuperCollider not sending**
   ```supercollider
   // Check if bridge is loaded
   ~highlightOSC.postln;
   ```

4. **No highlights appearing**
   ```vim
   :TidalHighlightClear  " Clear old highlights
   :TidalHighlightTest   " Test basic highlighting
   ```

#### Debug Commands:
```vim
:TidalHighlightToggle      " Toggle on/off
:TidalHighlightClear       " Clear all highlights  
:TidalHighlightDiagnostics " Run full diagnostics
:TidalHighlightTest        " Test basic highlighting
```

### Expected Behavior

When working correctly:

1. **Code Evaluation**: You evaluate `d1 $ sound "bd sn"` 
2. **Processing**: Plugin processes the code, finds `"bd"` and `"sn"` 
3. **Registration**: SuperCollider receives the pattern
4. **Playback**: When Tidal plays the pattern, SuperCollider sends highlight events
5. **Highlighting**: Words `bd` and `sn` highlight in sync with audio

### Next Steps

If basic integration works, we can:
1. **Improve timing precision** - sync highlights with actual beat timing
2. **Add more pattern types** - handle complex Tidal constructs
3. **Enhance visual effects** - fade animations, color coding
4. **Add configuration** - customize highlight styles per pattern type

Let me know what happens when you run the diagnostics!