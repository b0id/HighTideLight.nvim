// FIXED startup.scd for HighTideLight.nvim (Pulsar 6-argument format)
(
s.reboot {
    // Server options
    s.options.numBuffers = 1024 * 256;
    s.options.memSize = 8192 * 32;
    s.options.numWireBufs = 2048;
    s.options.maxNodes = 1024 * 32;
    s.options.numOutputBusChannels = 2;
    s.options.numInputBusChannels = 2;
    
    s.waitForBoot {
        ~dirt.stop;
        ~dirt = SuperDirt(2, s);
        ~dirt.loadSoundFiles;
        ~dirt.loadSoundFiles("/home/b0id/Music/synth/samples-extra/*");
        ~dirt.loadSoundFiles("/home/b0id/Music/synth/Horror_SFX/Guns/");
        ~dirt.loadSoundFiles("/home/b0id/Music/synth/DrumSamples/*");
        ~dirt.loadSoundFiles("/home/b0id/Music/synth/FLESH_SIMULATORYAMAHAPSS-680/*");
        ~dirt.loadSoundFiles("/home/b0id/Music/synth/ClassicArcadeSFXComplete/*");
        ~dirt.loadSoundFiles("/home/b0id/Music/synth/FleshSimulatorSovietDrums/*");

        ~dirt.start(57120, 0 ! 12);
        SuperDirt.default = ~dirt;

        // Orbit assignments
        (
            ~d1 = ~dirt.orbits[0]; ~d2 = ~dirt.orbits[1]; ~d3 = ~dirt.orbits[2];
            ~d4 = ~dirt.orbits[3]; ~d5 = ~dirt.orbits[4]; ~d6 = ~dirt.orbits[5];
            ~d7 = ~dirt.orbits[6]; ~d8 = ~dirt.orbits[7]; ~d9 = ~dirt.orbits[8];
            ~d10 = ~dirt.orbits[9]; ~d11 = ~dirt.orbits[10]; ~d12 = ~dirt.orbits[11];
        );

        // ===== HIGHTIDELIGHT INTEGRATION (UPDATED) =====
        ~hightidelight = (
            neovimIP: "127.0.0.1",
            neovimPort: 6011,  // Match tidal.nvim default
            enabled: true,
            debug: true
        );

        ~neovimOSC = NetAddr(~hightidelight.neovimIP, ~hightidelight.neovimPort);

        // Hook into SuperDirt for Pulsar 6-argument format
        ~originalDirtReceive = ~dirt.receiveAction;

        ~dirt.receiveAction = { |msg|
            var orbit, sound, delta, cycle, args, id, duration, colStart, eventId, colEnd;

            if(msg[0] == '/dirt/play', {
                args = msg[1..];
                
                // Default values
                orbit = 0;
                sound = nil;
                delta = 0.5;
                cycle = 0;
                id = 1;

                // Parse SuperDirt parameters
                args.pairsDo({ |key, value|
                    switch(key,
                        \orbit, { orbit = value },
                        \s, { sound = value.asString },
                        \sound, { sound = value.asString },
                        \delta, { delta = value },
                        \cycle, { cycle = value }
                    );
                });

                if(sound.notNil and: ~hightidelight.enabled, {
                    // Calculate Pulsar-style parameters
                    duration = delta;  // Use delta as duration
                    colStart = 0;      // Will be determined by Neovim markers
                    eventId = 0;       // Will be determined by deltaContext
                    colEnd = sound.size;  // Approximate word length

                    if(~hightidelight.debug, {
                        "🎵 HighTideLight (Pulsar): id=% duration=% cycle=% colStart=% eventId=% colEnd=%"
                            .format(id, duration, cycle, colStart, eventId, colEnd).postln;
                    });

                    // Send 6-argument Pulsar format to Neovim
                    ~neovimOSC.sendMsg('/editor/highlights', id, duration, cycle, colStart, eventId, colEnd);
                });
            });

            // Call original SuperDirt handler
            ~originalDirtReceive.(msg);
        };

        "✅ HighTideLight.nvim integration active (Pulsar format)".postln;
        "   Neovim target: %:%".format(~hightidelight.neovimIP, ~hightidelight.neovimPort).postln;
        "   Format: 6-argument Pulsar compatible".postln;

        // Control functions
        ~hightidelight.toggle = {
            ~hightidelight.enabled = ~hightidelight.enabled.not;
            "HighTideLight %".format(if(~hightidelight.enabled, "ENABLED", "DISABLED")).postln;
        };

        ~hightidelight.test = {
            "🧪 Testing HighTideLight (Pulsar format)...".postln;
            ~neovimOSC.sendMsg('/editor/highlights', 1, 0.5, 1.0, 5, 0, 10);
            "Test: [id=1, duration=0.5, cycle=1.0, colStart=5, eventId=0, colEnd=10]".postln;
        };
    };
    
    s.latency = 0.3;
};
);
