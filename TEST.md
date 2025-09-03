# HighTideLight System Test

## Quick System Test

1. **Load Plugin in Neovim:**
```lua
:lua require('tidal-highlight').setup({debug = true})
```

2. **Test Simulation:**
```vim
:TidalHighlightSimulate
```
This should highlight the current line with different colors for each stream.

3. **Test Bridge Startup:**
```vim
:TidalHighlightStartBridge
```
Should start the Rust OSC bridge.

4. **Test Commands:**
```vim
:TidalHighlightStatus
:TidalHighlightClear
:TidalHighlightTest
```

## Expected Results

- `:TidalHighlightSimulate` should show multi-colored highlights on current line
- Bridge should start without errors
- Debug messages should appear in `:messages`
- Highlights should fade out over time

## Test File Contents

Put some sample Tidal code here for testing:
```haskell
d1 $ sound "bd cp bd cp"
d2 $ sound "hh*8"
d3 $ sound "arpy*4" # lpf 1000
d4 $ s "bass*2" # room 0.3
```

Run `:TidalHighlightSimulate` on each line to test highlighting.