// Clean startup.scd for HighTideLight.nvim
// SuperCollider handles audio only - highlighting is managed by Neovim
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
        // Load your sample paths here as needed
        // ~dirt.loadSoundFiles("/path/to/your/samples/*");

        ~dirt.start(57120, 0 ! 12);
        SuperDirt.default = ~dirt;

        // Orbit assignments for easy access
        (
            ~d1 = ~dirt.orbits[0]; ~d2 = ~dirt.orbits[1]; ~d3 = ~dirt.orbits[2];
            ~d4 = ~dirt.orbits[3]; ~d5 = ~dirt.orbits[4]; ~d6 = ~dirt.orbits[5];
            ~d7 = ~dirt.orbits[6]; ~d8 = ~dirt.orbits[7]; ~d9 = ~dirt.orbits[8];
            ~d10 = ~dirt.orbits[9]; ~d11 = ~dirt.orbits[10]; ~d12 = ~dirt.orbits[11];
        );

        "✅ SuperDirt ready for HighTideLight.nvim".postln;
        "   Audio: SuperDirt listening on port 57120".postln;
        "   Highlighting: Managed by Neovim plugin".postln;
    };
    
    s.latency = 0.3;
};
);
