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

            // DEBUG: Post the full message structure (this was working!)
            ("SuperDirt msg structure: " ++ msg).postln;
            ("SuperDirt msg size: " ++ msg.size).postln;
            
            // Keep the original working extraction
            latency = msg[0];
            event = msg[1];

            // DEBUG: Post the full event to the console
            ("SuperDirt Event: " ++ event).postln;
            ("SuperDirt Event class: " ++ event.class).postln;

            // The actual event data seems to be in the message structure itself!
            // Let's extract from msg directly since we can see the data there
            if(msg.isKindOf(Dictionary)) {
                sound = msg[\s];
                eventId = msg[\_id_] ? msg[\id] ? 1;
                delta = msg[\delta] ? 0.25;
                
                ("Extracted from msg - sound: " ++ sound ++ " eventId: " ++ eventId).postln;
                
                // Send highlight if we have sound
                if(sound.notNil) {
                    ~highlightOSC.sendHighlight(eventId, sound, delta, 1);
                    ("Sent highlight for: " ++ sound).postln;
                };
            } {
                ("Message is not a Dictionary: " ++ msg.class).postln;
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
