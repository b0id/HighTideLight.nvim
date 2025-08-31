// SuperCollider OSC Bridge for HighTideLight.nvim
// This sends timing and highlighting information back to Neovim

(
// Configuration
~highlightOSC = (
    // Neovim OSC address
    editor: NetAddr("127.0.0.1", 6011),
    
    // Track active patterns and their timing
    activePatterns: IdentityDictionary.new,
    
    // Send highlight event to Neovim
    sendHighlight: { |self, eventId, bufferId, row, startCol, endCol, duration, cycle|
        self.editor.sendMsg('/editor/highlights', 
            eventId, bufferId, row, startCol, endCol, duration, cycle);
        if(~highlightDebug == true) {
            ("Sent highlight: event=" ++ eventId ++ " row=" ++ row ++ 
             " cols=" ++ startCol ++ "-" ++ endCol).postln;
        };
    },
    
    // Register pattern for tracking
    registerPattern: { |self, patternName, eventId, timing|
        self.activePatterns[patternName] = (
            eventId: eventId,
            timing: timing,
            lastTrigger: Main.elapsedTime
        );
    },
    
    // Process Tidal pattern and extract timing
    processPattern: { |self, patternName, code, eventId|
        var words, timing;
        
        // Basic pattern analysis - find quoted sections
        words = code.findRegexp("\"([^\"]+)\"");
        
        if(words.size > 0) {
            // For each match, calculate timing and send highlight
            words.do { |match, index|
                var content = match[1];
                var startPos = match[0];
                
                // Simple word splitting
                content.split($ ).do { |word, wordIndex|
                    if(word.size > 0) {
                        // Calculate rough timing (this needs refinement)
                        var wordStart = startPos + wordIndex;
                        var wordEnd = wordStart + word.size;
                        var delay = wordIndex * 0.25; // Basic timing
                        
                        // Schedule highlight
                        SystemClock.sched(delay, {
                            self.sendHighlight(
                                eventId + wordIndex,
                                0, // buffer ID (Neovim will handle)
                                0, // row (Neovim will handle)
                                wordStart, wordEnd,
                                0.5, // duration
                                index + 1 // cycle
                            );
                            nil;
                        });
                    };
                };
            };
        };
    }
);

// Install OSC listener for pattern registration
OSCdef(\tidalHighlightRegister, { |msg, time, addr, recvPort|
    var eventId = msg[1];
    var code = msg[2];
    var patternName = msg[3] ? "d1";
    
    if(~highlightDebug == true) {
        ("Received pattern registration: " ++ code).postln;
    };
    
    ~highlightOSC.processPattern(patternName, code, eventId);
    
}, '/tidal/register');

// Debug toggle
OSCdef(\tidalHighlightDebug, { |msg, time, addr, recvPort|
    ~highlightDebug = msg[1] > 0;
    ("Tidal highlight debug: " ++ ~highlightDebug).postln;
}, '/tidal/debug');

// Test function
~testTidalHighlight = {
    "Testing Tidal highlight OSC...".postln;
    ~highlightOSC.sendHighlight(999, 0, 0, 10, 20, 1.0, 1);
    "Test highlight sent to Neovim".postln;
};

"HighTideLight OSC bridge loaded. Use ~testTidalHighlight.() to test.".postln;
"Set ~highlightDebug = true; for verbose output.".postln;
)

// Enhanced version that hooks into SuperDirt events
(
// Hook into SuperDirt's event processing
if(~dirt.notNil) {
    "Hooking into SuperDirt for real-time highlights...".postln;
    
    // Store original play function
    ~originalDirtPlay = ~dirt.receiveAction;
    
    // Wrap with highlight extraction
    ~dirt.receiveAction = { |msg|
        var latency, event, eventId, code;
        
        // Extract event information
        latency = msg[1];
        event = msg[2..];
        
        // Check if this is a Tidal event with deltaContext
        event.pairsDo { |key, value|
            if(key == \deltaContext) {
                eventId = value;
                // Look for associated code in our registry
                if(~highlightOSC.activePatterns[eventId].notNil) {
                    var pattern = ~highlightOSC.activePatterns[eventId];
                    // Trigger highlight based on actual playback timing
                    ~highlightOSC.sendHighlight(
                        eventId, 0, 0, 
                        pattern.timing ? 0, (pattern.timing ? 0) + 10,
                        latency + 0.1, // Duration based on latency
                        1
                    );
                };
            };
        };
        
        // Call original function
        ~originalDirtPlay.(msg);
    };
    
    "SuperDirt hook installed for real-time highlighting.".postln;
} {
    "SuperDirt not found. Only basic OSC highlighting available.".postln;
};
)

/*
Usage in Tidal/Haskell:
1. Load this file in SuperCollider
2. In your Tidal code, patterns will automatically trigger highlights
3. The deltaContext injection from the Neovim plugin provides event IDs

Example Tidal code that would trigger highlights:
d1 $ sound "bd sn hh oh"

The plugin processes this, injects deltaContext, and SuperCollider 
sends highlight events back to Neovim with precise timing.
*/