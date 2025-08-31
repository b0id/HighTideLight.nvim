( 
// Configuration
~highlightOSC = (
    // Neovim OSC address
    editor: NetAddr("127.0.0.1", 6011),

    // Send highlight event to Neovim
    sendHighlight: { |self, eventId, sound, duration, cycle|
        self.editor.sendMsg('/editor/highlight',
            eventId, sound, duration, cycle);
        if(~highlightDebug == true) {
            ("Sent highlight: event=" ++ eventId ++ " sound=" ++ sound ++ " duration=" ++ duration).postln;
        };
    }
);

// Debug toggle
OSCdef(\idalHighlightDebug, { |msg, time, addr, recvPort| 
    ~highlightDebug = msg[1] > 0;
    ("Tidal highlight debug: " ++ ~highlightDebug).postln;
}, '/tidal/debug');

// Test function
~testTidalHighlight = {
    "Testing Tidal highlight OSC...".postln;
    ~highlightOSC.sendHighlight(999, "bd", 0.5, 1);
    "Test highlight sent to Neovim".postln;
};

// Defer the hook until after SuperDirt has started
AppClock.sched(2.0, { 
    if(~dirt.notNil) {
        "Hooking into SuperDirt for real-time highlights...".postln;

        // Store original play function
        ~originalDirtPlay = ~dirt.receiveAction;

        // Wrap with highlight extraction
        ~dirt.receiveAction = { |msg|
            var latency, event, eventId, sound, delta;

            // DEBUG: Post the full message structure
            ("SuperDirt msg structure: " ++ msg).postln;
            ("SuperDirt msg size: " ++ msg.size).postln;
            
            // Correctly extract event information from the OSC message
            latency = msg[0];
            event = msg[1];

            // DEBUG: Post the full event to the console
            ("SuperDirt Event: " ++ event).postln;
            ("SuperDirt Event class: " ++ event.class).postln;

            // Handle different event types
            if(event.notNil and: { event.isKindOf(Dictionary) }) {
                // Find eventId and sound
                event.pairsDo { |key, value| 
                    ("Event key: " ++ key ++ " = " ++ value).postln;
                    if(key == \deltaContext) {
                        eventId = value;
                    };
                    if(key == \s) {
                        sound = value;
                    };
                    if(key == \delta) {
                        delta = value;
                    };
                };

                // If we have both, send the highlight message
                if(eventId.notNil and: { sound.notNil }) {
                    ~highlightOSC.sendHighlight(eventId, sound, delta ? 0.25, 1);
                    ("Sent highlight for: " ++ sound ++ " with eventId: " ++ eventId).postln;
                } {
                    ("Missing data - eventId: " ++ eventId ++ " sound: " ++ sound).postln;
                };
            } {
                ("Event is nil or not a Dictionary: " ++ event).postln;
            };

            // Call original function
            ~originalDirtPlay.(msg);
        };

        "SuperDirt hook installed for real-time highlighting.".postln;
    } {
        "SuperDirt not found after deferral. Highlighting will not work.".postln;
    };
});

"HighTideLight OSC bridge loaded. Use ~testTidalHighlight.() to test.".postln;
"Set ~highlightDebug = true; for verbose output.".postln;
)
