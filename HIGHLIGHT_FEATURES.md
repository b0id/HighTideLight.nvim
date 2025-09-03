# Real-time Tidal Event Highlighting

## Overview

This extension adds real-time visual feedback to TidalCycles code by highlighting parts of patterns as they play. When TidalCycles sends OSC messages containing position data, the corresponding code sections light up in Neovim with stream-specific colors.

## How It Works

1. **OSC Bridge**: A Rust bridge receives OSC messages from TidalCycles on `/editor/highlights`
2. **Message Format**: `[stream_id, start_row, start_col, end_row, end_col, duration]`
3. **Visual Feedback**: Code highlights with colors specific to each stream (d1=red, d2=cyan, etc.)
4. **Fade Animation**: Highlights fade out over the specified duration

## Setup

### 1. Build the OSC Bridge
```bash
cd tidal-osc-bridge
cargo build --release
```

### 2. Configure TidalCycles
Add this to your TidalCycles startup (BootTidal.hs):
```haskell
-- Enable editor highlighting
:set -XPackageImports
import qualified "tidal" Sound.Tidal.Context as T
import qualified "tidal" Sound.Tidal.Editor as E

-- Configure OSC target for highlights
tidal <- startTidal (superdirtTarget {oTargets = [superdirtTarget, oscTarget "127.0.0.1" 6013]}) defaultConfig
```

### 3. Start the Bridge
```vim
:TidalHighlightStartBridge
```

## Commands

- `:TidalHighlightToggle` - Enable/disable highlighting
- `:TidalHighlightClear` - Clear all highlights
- `:TidalHighlightClearLine` - Clear highlights on current line
- `:TidalHighlightStartBridge` - Start the Rust OSC bridge
- `:TidalHighlightSimulate` - Test with simulated highlights
- `:TidalHighlightOSCTest` - Test OSC communication
- `:TidalHighlightStatus` - Show current status

## Stream Colors

- **d1**: Red (`#ff6b6b`)
- **d2**: Cyan (`#4ecdc4`) 
- **d3**: Blue (`#45b7d1`)
- **d4**: Green (`#96ceb4`)
- **d5**: Orange (`#ffa500`)
- **d6**: Pink (`#ff69b4`)
- **d7**: Plum (`#dda0dd`)
- **d8**: Sky Blue (`#87ceeb`)

## Testing

Open `test_highlights.tidal` and run:
```vim
:TidalHighlightSimulate
```

This will show multi-stream highlighting on the current line.

## Architecture

```
TidalCycles -> OSC /editor/highlights -> Rust Bridge -> Neovim OSC -> Lua Handler -> Visual Highlights
```

The implementation leverages existing infrastructure:
- `osc.lua` - OSC communication
- `highlights.lua` - Visual highlighting with fade effects  
- `animation.lua` - Smooth animation system
- `processor.lua` - Code analysis and position mapping

## Integration Points

- **Line Clearing**: Highlights are cleared before re-evaluation
- **Hush Commands**: `hush`, `silence`, `stop` clear all highlights
- **Stream Detection**: Automatic buffer detection for `.tidal` files
- **Position Mapping**: Converts 1-indexed Tidal positions to 0-indexed Neovim

This creates a live coding experience where you can see exactly which parts of your patterns are playing in real-time.
