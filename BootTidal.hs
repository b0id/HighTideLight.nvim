:set -XOverloadedStrings
:set prompt ""

import Sound.Tidal.Context
import System.IO (hSetEncoding, stdout, utf8)
hSetEncoding stdout utf8

let editorTarget = Target { oName = "Neovim HighTideLight", oAddress = "127.0.0.1", oPort = 6013, oLatency = 0.02, oSchedule = Pre BundleStamp, oWindow = Nothing, oHandshake = False, oBusPort = Nothing }

let editorShape = OSCContext "/editor/highlights"

-- deltaContext function for editor communication (from research)
-- This will be automatically replaced by pattern munging in the companion plugin
let deltaContext offset eventId pattern = pattern

tidal <- startStream (defaultConfig {cFrameTimespan = 1/50}) [(superdirtTarget {oLatency = 0.2, oAddress = "127.0.0.1", oPort = 57120}, [superdirtShape]), (editorTarget, [editorShape])]

let only = (hush >>)
let p = streamReplace tidal
let hush = streamHush tidal
let panic = do hush; once $ sound "superpanic"
let list = streamList tidal
let mute = streamMute tidal
let unmute = streamUnmute tidal
let unmuteAll = streamUnmuteAll tidal
let unsoloAll = streamUnsoloAll tidal
let solo = streamSolo tidal
let unsolo = streamUnsolo tidal
let once = streamOnce tidal
let first = streamFirst tidal
let asap = once
let nudgeAll = streamNudgeAll tidal
let all = streamAll tidal
let resetCycles = streamResetCycles tidal
let setCycle = streamSetCycle tidal
let setcps = asap . cps
let getcps = streamGetcps tidal
let getnow = streamGetnow tidal
let xfade i = transition tidal True (Sound.Tidal.Transition.xfadeIn 4) i
let xfadeIn i t = transition tidal True (Sound.Tidal.Transition.xfadeIn t) i
let histpan i t = transition tidal True (Sound.Tidal.Transition.histpan t) i
let wait i t = transition tidal True (Sound.Tidal.Transition.wait t) i
let waitT i f t = transition tidal True (Sound.Tidal.Transition.waitT f t) i
let jump i = transition tidal True (Sound.Tidal.Transition.jump) i
let jumpIn i t = transition tidal True (Sound.Tidal.Transition.jumpIn t) i
let jumpIn' i t = transition tidal True (Sound.Tidal.Transition.jumpIn' t) i
let jumpMod i t = transition tidal True (Sound.Tidal.Transition.jumpMod t) i
let jumpMod' i t p = transition tidal True (Sound.Tidal.Transition.jumpMod' t p) i
let mortal i lifespan release = transition tidal True (Sound.Tidal.Transition.mortal lifespan release) i
let interpolate i = transition tidal True (Sound.Tidal.Transition.interpolate) i
let interpolateIn i t = transition tidal True (Sound.Tidal.Transition.interpolateIn t) i
let clutch i = transition tidal True (Sound.Tidal.Transition.clutch) i
let clutchIn i t = transition tidal True (Sound.Tidal.Transition.clutchIn t) i
let anticipate i = transition tidal True (Sound.Tidal.Transition.anticipate) i
let anticipateIn i t = transition tidal True (Sound.Tidal.Transition.anticipateIn t) i
let forId i t = transition tidal False (Sound.Tidal.Transition.mortalOverlay t) i
let d1 = p 1 . (|< orbit 0)
let d2 = p 2 . (|< orbit 1)
let d3 = p 3 . (|< orbit 2)
let d4 = p 4 . (|< orbit 3)
let d5 = p 5 . (|< orbit 4)
let d6 = p 6 . (|< orbit 5)
let d7 = p 7 . (|< orbit 6)
let d8 = p 8 . (|< orbit 7)
let d9 = p 9 . (|< orbit 8)
let d10 = p 10 . (|< orbit 9)
let d11 = p 11 . (|< orbit 10)
let d12 = p 12 . (|< orbit 11)
let d13 = p 13
let d14 = p 14
let d15 = p 15
let d16 = p 16

let setI = streamSetI tidal
let setF = streamSetF tidal
let setS = streamSetS tidal
let setR = streamSetR tidal
let setB = streamSetB tidal

:set prompt "tidal> "
:set prompt-cont ""
