# HighTideLight.nvim Architecture

## Overview
HighTideLight.nvim provides **real-time, coordinate-precise highlighting** for TidalCycles patterns in Neovim. It achieves surgical precision by combining AST parsing, orbit-aware data mapping, and asynchronous OSC communication between Neovim and SuperCollider.

## Core Architecture

### Data Flow Pipeline
```
Tidal Pattern → AST Parser → Source Maps → SuperCollider → OSC Messages → Precise Highlights
```

### Key Components

#### 1. **AST Parsing Engine** (`source_map.lua`)
- **Purpose**: Extracts precise token boundaries from Haskell/Tidal code
- **Output**: `{token_id: {value: "bd", range: {start: {line, col}, end: {line, col}}}}`
- **Handles**: Complex patterns, effects chains, euclidean rhythms, nested structures

#### 2. **Integration Layer** (`integration.lua`) 
- **Purpose**: Bridges AST data with OSC communication
- **Key Feature**: Orbit-aware coordinate mapping (d1→orbit0, d2→orbit1, etc.)
- **Data Structure**: `active_source_maps[bufnr][range_key] = {orbit, source_map, timestamp}`
- **Auto-monitoring**: Tracks Haskell buffers, updates on text changes

#### 3. **OSC Communication** (`osc.lua`)
- **Server**: Listens on 127.0.0.1:6011 for SuperCollider messages
- **Client**: Sends pattern/coordinate data to SuperCollider
- **Protocol**: Binary OSC with proper type handling (int32, float32, strings)
- **Thread Safety**: All UI operations scheduled on main thread via `vim.schedule()`

#### 4. **Highlight Handler** (`highlight_handler.lua`)
- **Rendering**: Uses Neovim's extmark API for non-destructive highlighting
- **Coordinate System**: Precise token-level positioning
- **Lifecycle**: Automatic cleanup with configurable durations
- **Thread Safety**: All buffer operations properly scheduled

#### 5. **Animation System** (`animation.lua`)
- **Event Queue**: Handles multiple simultaneous highlights
- **Timing**: Delta-based durations from SuperCollider
- **Performance**: 30fps refresh rate, optimized for real-time use

#### 6. **State Management** (`state_service.lua`, `telemetry_monitor.lua`)
- **Persistence**: Maintains pattern-to-coordinate mappings
- **Monitoring**: Health checks, error tracking, performance metrics
- **Diagnostics**: Comprehensive debugging and inspection tools

## Data Contracts

### Neovim → SuperCollider
```
/tidal/pattern [orbit, text, colOffset]
/tidal/sound_position [orbit, sound, startCol, endCol, bufnr, line]
/tidal/buffer_map [orbit, bufnr, line]
```

### SuperCollider → Neovim  
```
/editor/highlights [orbit, delta, cycle, colStart, eventId, colEnd]
```

### Internal Source Map Format
```lua
active_source_maps[bufnr][range_key] = {
  orbit = 2,                    -- d3 → orbit 2
  source_map = {
    token_id = {
      value = "kick",
      range = {
        start = {line = 3, col = 12},
        end = {line = 3, col = 15}
      }
    }
  },
  line_content = "d3 $ sound \"kick snare\"",
  last_updated = timestamp
}
```

## Key Features Achieved

### ✅ Multi-Buffer Support
- Simultaneous highlighting across multiple Tidal files
- Buffer-specific orbit tracking and coordinate mapping
- Automatic buffer monitoring and cleanup

### ✅ Complex Pattern Support  
- **30+ tokens** parsed from single complex patterns
- Effects chains: `# gain 0.8 # room 0.3 # speed 1.5`
- Transformations: `every 2 (fast 2) $ rev $ chop 4`
- Euclidean rhythms: `"[0,2,4] 3 5"`
- Mini-notation: `"bd ~ sn ~"`, `"[bd sn]*2"`

### ✅ Real-Time Performance
- **50+ OSC messages/second** handled smoothly
- Asynchronous processing with proper thread safety  
- Debounced updates (500ms) to prevent excessive parsing
- Automatic memory management and cleanup

### ✅ Surgical Coordinate Precision
- **Exact token boundaries** from AST parsing
- **Coordinate matching** between SuperCollider and Neovim
- **Sub-character precision** for complex nested patterns

## Debug and Diagnostic Tools

### Core Commands
- `:TidalTestPatternParsing` - AST parsing verification
- `:TidalInspectSourceMaps` - View token coordinate mappings  
- `:TidalShowOSCHistory` - Recent OSC message inspection
- `:TidalInspectOSCFlow` - Test coordinate lookup logic

### Statistics and Monitoring
- `:TidalShowStats` - Comprehensive system metrics
- `:TidalHealthReport` - Performance and error monitoring
- `:TidalShowRecentMessages` - OSC message validation status

## SuperCollider Integration

### Required Files
- `HighTideLightOSC.scd` - OSC bridge and pattern position tracking
- Startup script integration for automatic loading

### Key SuperCollider Functions
- `~simulatePatternRegistration()` - Test pattern data storage
- `~showPatternData()` - Display stored coordinate mappings
- Automatic SuperDirt hook for real-time coordinate extraction

## Configuration

### Minimal Setup (Lazy.nvim)
```lua
{
  dir = "/path/to/HighTideLight.nvim",
  dependencies = { "grddavies/tidal.nvim" },
  config = function()
    require('tidal-highlight').setup({
      debug = true,
      osc = { ip = "127.0.0.1", port = 6011 },
      animation = { fps = 30 },
      highlights = {
        groups = {
          { name = "TidalEvent1", fg = "#ff0000", blend = 20 },
          { name = "TidalEvent2", fg = "#00ff00", blend = 20 },
          { name = "TidalEvent3", fg = "#0000ff", blend = 20 },
        }
      }
    })
  end
}
```

## Performance Characteristics

### Benchmarked Capabilities
- **Complex patterns**: 30+ tokens parsed per pattern
- **Multiple orbits**: Simultaneous d1-d12 tracking
- **High throughput**: 50+ OSC messages/second processing
- **Multi-buffer**: 3+ concurrent Tidal files
- **Memory efficient**: Automatic cleanup and LRU caching

### Thread Safety
- All UI operations via `vim.schedule()`
- OSC processing on background threads
- Proper cleanup of background timers and listeners

## Technical Innovations

1. **Orbit-Aware Architecture**: Maps Tidal's d1-d12 to SuperCollider's orbit system
2. **Coordinate Precision**: AST-level token boundary extraction  
3. **Async OSC Bridge**: Non-blocking communication with proper error handling
4. **Multi-Buffer State**: Per-buffer source map tracking with cleanup
5. **Real-Time Performance**: Optimized for live coding with minimal latency

## Dependencies

### Runtime
- **Neovim** ≥ 0.7 (for extmark API)
- **grddavies/tidal.nvim** (API hooks)
- **SuperCollider** + **SuperDirt** (audio engine)
- **TidalCycles** (pattern language)

### Development  
- **nvim-treesitter** (Haskell parsing support)
- **TreeSitter Haskell grammar** (syntax analysis)

## Future Extensions

- **Pattern visualization** graphs
- **Multi-channel highlighting** (stereo/surround)
- **Custom highlight themes** and animations
- **Export/import** of pattern coordinate data
- **Integration** with other live coding environments