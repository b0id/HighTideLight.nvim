# Tomorrow's Debug Plan

## 🎯 **Quick Start Protocol**

### **1. Restart Both Systems**
```bash
# SuperCollider: Reload HighTideLightOSC.scd
# Neovim: Restart completely
```

### **2. Run Diagnostic Sequence**
```vim
:lua require('tidal-highlight.config').current.debug = true
:TidalHighlightDebugState    " Check initial state
:TidalHighlightDebugAPI      " Verify tidal.nvim availability
```

### **3. Test Both Patterns**
```haskell
d1 $ sound "bd sn hh"        " Should see: 6 args or consistent format
d2 $ sound "kick clap"       " Compare format with d1
```

### **4. Check Results**
```vim
:TidalHighlightDebugState    " Compare pattern store: orbit 0 vs orbit 1
```

## 🔍 **Key Questions to Answer**

1. **Pattern Store Contents:** Are both orbit 0 and orbit 1 populated?
2. **OSC Format:** Why d1=3args vs d2=4args difference?
3. **API Hook:** Is `tidal.nvim` API detected, or falling back to compat?
4. **Buffer Tracking:** Are buffer/row correctly stored for highlighting?

## 🎯 **Expected Fix**

The issue is likely **OSC argument format mismatch**. Once aligned:
- SuperCollider: `[streamId, delta, cycle, colStart, eventId, colEnd]` 
- Neovim: Should receive exactly same 6 arguments
- Result: Pixel-perfect highlighting at columns 34-35, 37-38, 40-41

## 🧰 **Debug Tools Ready**

- `:TidalHighlightForceHighlight` - Test animation system
- `:TidalHighlightDebugOSC` - Test OSC communication  
- All OSC messages logged with "OSC RECEIVED" prefix
- Pattern store inspection with orbit-based lookup

**We're 95% there! Just need to sync the final OSC format.** 🚀
