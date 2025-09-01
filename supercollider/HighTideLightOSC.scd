// HighTideLightOSC.scd
// SuperCollider helper for testing HighTideLight.nvim OSC communication

( 
// Configuration
~neovimOSC = NetAddr("127.0.0.1", 6011);  // Send to Neovim plugin
~testEventId = 1001;

// Test function: Send highlight event to Neovim
~sendHighlight = { |eventId, startCol, endCol, duration|
    eventId = eventId ? ~testEventId;
    startCol = startCol ? 10;
    endCol = endCol ? 20;
    duration = duration ? 200;
    
    ~neovimOSC.sendMsg("/editor/highlights", eventId, startCol, endCol, duration);
    "Sent highlight event: ID=%, cols=%-%, duration=%ms".format(eventId, startCol, endCol, duration).postln;
};

// Test function: Send 6-argument format highlight
~send6ArgHighlight = { |streamId, duration, cycle, colStart, eventId, colEnd|
    streamId = streamId ? 0;        // d1=0, d2=1, etc
    duration = duration ? 0.25;     // delta duration
    cycle = cycle ? 1;              // cycle number
    colStart = colStart ? 10;       // start column
    eventId = eventId ? ~testEventId; // event ID
    colEnd = colEnd ? 15;           // end column
    
    ~neovimOSC.sendMsg("/editor/highlights", streamId, duration, cycle, colStart, eventId, colEnd);
    "Sent 6-arg highlight: stream=% dur=% cycle=% cols=%-% eventId=%".format(
        streamId, duration, cycle, colStart, colEnd, eventId).postln;
};

// Pattern position storage - NOW KEYED BY ORBIT (what SuperDirt reports)
~tidalPatterns = Dictionary.new;    // orbit -> pattern data
~soundPositions = Dictionary.new;   // orbit -> sound position mapping

// NEW: Listen for pattern registration from Neovim (orbit-based)
OSCdef(\tidalPattern, { |msg, time, addr, recvPort|
    var orbit, originalText, colOffset;
    orbit = msg[1];  // Changed from eventId to orbit
    originalText = msg[2];
    colOffset = msg[3];
    
    ~tidalPatterns[orbit] = (
        text: originalText,
        colOffset: colOffset,
        timestamp: time
    );
    
    if(~highlightDebug == true) {
        ("📝 Stored pattern mapping: orbit=% text='%' colOffset=%".format(orbit, originalText, colOffset)).postln;
    };
}, '/tidal/pattern');

// NEW: Listen for sound position data from Neovim (orbit-based)
OSCdef(\tidalSoundPosition, { |msg, time, addr, recvPort|
    var orbit, sound, startCol, endCol;
    orbit = msg[1];  // Changed from eventId to orbit
    sound = msg[2];
    startCol = msg[3];
    endCol = msg[4];
    
    if(~soundPositions[orbit].isNil) {
        ~soundPositions[orbit] = Dictionary.new;
    };
    
    ~soundPositions[orbit][sound] = (
        startCol: startCol,
        endCol: endCol
    );
    
    if(~highlightDebug == true) {
        ("🎵 Stored sound position: orbit=% sound='%' cols=%-% ".format(orbit, sound, startCol, endCol)).postln;
    };
}, '/tidal/sound_position');

// Test function
~testTidalHighlight = {
    "Testing Tidal highlight OSC...".postln;
    ~highlightOSC.sendHighlight(999, "bd", 0.5, 1);
    "Test highlight sent to Neovim".postln;
};

// Defer the hook until after SuperDirt has started
AppClock.sched(5.0, {  // Increased delay from 2 to 5 seconds
    if(~dirt.notNil) {
        "Hooking into SuperDirt for real-time highlights...".postln;

        // Store original play function
        ~originalDirtPlay = ~dirt.receiveAction;

        // Wrap with highlight extraction using stored position data
        ~dirt.receiveAction = { |msg|
            var latency, event, eventId, sound, delta, cycle, colStart, colEnd, streamId;
            var patternInfo, soundInfo, matchingEventId, mostRecentTime;

            // DEBUG: Post the message structure if needed
            if(~highlightDebug == true) {
                ("SuperDirt event: orbit=% sound=% cycle=%".format(msg[\orbit], msg[\s], msg[\cycle])).postln;
            };
            
            // Keep the original working extraction
            latency = msg[0];
            event = msg[1];

            // Extract basic event data
            if(msg.isKindOf(Dictionary)) {
                sound = msg[\s];
                eventId = msg[\eventId] ? msg[\id] ? msg[\_id_] ? 1;
                delta = msg[\delta] ? 0.25;
                cycle = msg[\cycle] ? 1;
                streamId = msg[\orbit] ? 0; // orbit is what we key by
                
                // NEW: Direct orbit-based lookup (matches what Neovim sends)
                if(~soundPositions[streamId].notNil) {
                    soundInfo = ~soundPositions[streamId][sound.asSymbol];
                    
                    if(soundInfo.notNil) {
                        // We have precise position data!
                        colStart = soundInfo.startCol;
                        colEnd = soundInfo.endCol;
                        
                        // Send 6-argument format: [streamId, duration, cycle, colStart, eventId, colEnd]
                        ~neovimOSC.sendMsg("/editor/highlights", 
                            streamId,           // orbit (d1=0, d2=1, etc)
                            delta,              // duration
                            cycle,              // cycle
                            colStart,           // start column in pattern
                            eventId,            // event ID from SuperDirt
                            colEnd              // end column in pattern
                        );
                        
                        ("🚀 PRECISION HIT! orbit=% sound='%' cols=%-% eventId=%".format(
                            streamId, sound, colStart, colEnd, eventId)).postln;
                    } {
                        if(~highlightDebug == true) {
                            ("❌ No position data for sound: " ++ sound).postln;
                        };
                        
                        // Fallback to 4-argument format
                        ~neovimOSC.sendMsg("/editor/highlights", eventId, sound, delta, cycle);
                        ("Fallback 4-arg highlight for: " ++ sound).postln;
                    };
                } {
                    if(~highlightDebug == true) {
                        ("❌ No stored pattern data for orbit: " ++ streamId).postln;
                    };
                    
                    // Fallback to 4-argument format
                    ~neovimOSC.sendMsg("/editor/highlights", eventId, sound, delta, cycle);
                    ("Fallback 4-arg highlight for: " ++ sound).postln;
                };
            } {
                if(~highlightDebug == true) {
                    ("Message is not a Dictionary: " ++ msg.class).postln;
                };
            };

            // Call original function
            ~originalDirtPlay.(msg);
        };

        "SuperDirt hook installed for real-time highlighting.".postln;
    } {
        "SuperDirt not found after 5 second deferral. Trying manual initialization...".postln;
        
        // Try to initialize SuperDirt manually
        if(SuperDirt.isKindOf(Class)) {
            "SuperDirt class found, attempting to create instance...".postln;
            // Let user manually start SuperDirt
        } {
            "SuperDirt class not available. Please ensure SuperDirt is properly installed.".postln;
        };
    };
});

// Test function to simulate pattern registration from Neovim (orbit-based)
~simulatePatternRegistration = {
    var orbit = 0;  // d1 = orbit 0
    var testPatternData = "d1 $ s 'bd cp bd cp' # room 0.3";  // Simple test pattern
    var soundPositions;
    
    "🔬 TESTING: Simulating orbit-based pattern registration...".postln;
    
    // Simulate position data that would come from deltaContext injection
    soundPositions = Dictionary.new;
    soundPositions[\bd] = (startCol: 7, endCol: 9);      // "bd" at positions 7-9
    soundPositions[\cp] = (startCol: 10, endCol: 12);    // "cp" at positions 10-12
    
    // Store the test data by ORBIT
    ~tidalPatterns[orbit] = (
        text: testPatternData,
        timestamp: SystemClock.seconds
    );
    
    ~soundPositions[orbit] = soundPositions;
    
    ("✅ Stored test pattern with orbit: " ++ orbit).postln;
    ("📍 Sound positions: bd=7-9, cp=10-12").postln;
    ("📋 Data stored in ~tidalPatterns and ~soundPositions").postln;
    
    // Show what we stored
    ~showPatternData.();
};

// Function to display stored pattern and position data (orbit-based)
~showPatternData = {
    "📋 STORED PATTERN DATA (by orbit):".postln;
    ~tidalPatterns.keysValuesDo({ |orbit, data|
        ("Orbit: % | Pattern: %".format(orbit, data.text)).postln;
    });
    
    "📍 STORED POSITION DATA (by orbit):".postln;
    ~soundPositions.keysValuesDo({ |orbit, positions|
        ("Orbit: %".format(orbit)).postln;
        positions.keysValuesDo({ |sound, pos|
            ("  Sound: % -> cols %-% ".format(sound, pos.startCol, pos.endCol)).postln;
        });
    });
};

"HighTideLight OSC bridge loaded with pattern position tracking.".postln;
"Usage:".postln;
"  ~sendHighlight.(eventId, startCol, endCol, duration)     // Legacy position-based".postln;
"  ~send6ArgHighlight.(streamId, duration, cycle, colStart, eventId, colEnd) // Manual 6-arg format".postln;
"  ~simulatePatternRegistration.()                          // Test pattern data storage".postln;
"  ~showPatternData.()                                      // Show stored position mappings".postln;
"Set ~highlightDebug = true; for verbose output.".postln;
"Now listening for /tidal/pattern and /tidal/sound_position from Neovim.".postln;
)
