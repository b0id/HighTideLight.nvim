● Line-by-Line Debugging in a Multi-Component Live-Coding System

This is a fascinating debugging challenge because you have 4 separate processes
with 3 different languages communicating via OSC:

Component Flow Breakdown:

[Neovim/Lua] → [Rust Bridge] → [SuperCollider] → [Audio Output]
↓
[TidalCycles/Haskell] → [SuperCollider] → [Audio Output]

Debugging Layers:

1. Neovim Plugin Layer (Lua)

# Enable debug mode

:lua require('tidal-highlight').setup({debug = true})

# Watch OSC messages being sent

:messages # Shows plugin debug output
:TidalHighlightStatus
:TidalHighlightDebugEvents
What you'll see: Pattern parsing, event IDs, OSC message construction, highlight
queue events

2. Rust OSC Bridge (Binary)

# Run bridge with debug logging

./tidal-osc-bridge --port 6013 --neovim-port 6011 --debug

# Or monitor with network tools

sudo tcpdump -i lo -A 'port 6011 or port 6013'
netstat -an | grep -E '601[13]'
What you'll see: Raw OSC packet bytes, message parsing, forwarding decisions

3. TidalCycles/GHCi (Haskell)

-- In your TidalCycles session
-- Enable verbose output (if available)
:set -v

-- Monitor stream state
streamGetcps tidal -- Check if streaming
list -- Show active patterns
What you'll see: Pattern compilation, stream target confirmation, timing info

4. SuperCollider IDE

// Enable OSC monitoring
OSCdef.trace(true) // Shows ALL incoming OSC messages
s.dumpOSC(1) // Dump OSC to post window

// Monitor specific paths
OSCdef('highlight_monitor', { |msg, time, addr, port|
("HIGHLIGHT MSG: " ++ msg).postln;
}, '/editor/highlight');

// Check server status
s.plotTree // Visual node tree
s.meter // Audio levels
What you'll see: Every OSC message, audio node creation, sample loading

Debugging Workflow:

Step 1: Verify Each Component

# 1. Test Neovim plugin in isolation

:TidalHighlightSimulate

# 2. Test Rust bridge connectivity

nc -u 127.0.0.1 6013 # Try sending raw data

# 3. Test SuperCollider reception

// In SuperCollider: OSCdef.trace(true)

# 4. Test TidalCycles independently

d1 $ sound "bd" -- Does audio work?

Step 2: Trace a Single Pattern

1. Enable all debug modes
2. Send one simple pattern: d1 $ sound "bd"
3. Watch logs in order:


    - Neovim: Pattern detected, OSC sent
    - Rust: Message received, forwarded
    - SuperCollider: OSC received, audio triggered

Step 3: Network-Level Monitoring

# Monitor all OSC traffic

sudo tcpdump -i lo -X 'port 57120 or port 6011 or port 6013'

# Or use dedicated OSC tools

oscdump 6011 # If available
wireshark # Filter: udp.port in {6011,6013,57120}

Common Debug Scenarios:

"Highlighting Not Working":

1. Check Neovim plugin loads: :TidalHighlightStatus
2. Check Rust bridge runs: ps aux | grep tidal-osc-bridge
3. Check OSC flow: Enable debug = true in plugin config
4. Test with simulation: :TidalHighlightSimulate

"Audio Works, No Highlights":

- Issue is likely in Neovim → Rust → Neovim path
- Check ports 6011/6013 specifically

"Highlights Work, No Audio":

- Issue is in TidalCycles → SuperCollider path
- Check port 57120, SuperCollider server status

Advanced Debugging:

Message Content Inspection:

# Decode OSC messages

od -t x1 /path/to/osc/capture.bin # Hex dump
strings /path/to/osc/capture.bin # Extract strings

Timing Analysis:

// In SuperCollider - timestamp all messages
OSCdef('timer', { |msg, time|
("Time: " ++ time ++ " Msg: " ++ msg).postln;
}, '/editor/highlight');

The key is enabling debug output in ALL components simultaneously, then tracing
a single pattern through the entire pipeline. Each component should log what it
receives, processes, and sends.
