# Development Notes

## Current State (v0.1.0-rudimentary)

### Working Features:
- Basic OSC communication between Neovim and SuperDirt
- Crude highlighting functionality
- AstroNVIM installation instructions in README
- Core plugin structure with modules:
  - `init.lua` - Main plugin entry point
  - `osc.lua` - OSC communication handling
  - `config.lua` - Configuration management
  - `highlights.lua` - Highlight management
  - `animation.lua` - Animation system
  - `processor.lua` - Pattern processing

### Known Issues:
- OSC library compatibility issues with different Neovim setups
- Server creation methods vary between OSC implementations
- Need better error handling for missing dependencies

### Testing Status:
- Basic plugin loading works
- OSC communication partially functional
- Need comprehensive integration tests with actual Tidal setup

### Next Steps for Development:
1. Fix OSC server compatibility across different setups
2. Improve error handling and graceful degradation
3. Add comprehensive testing suite
4. Document installation requirements better
5. Create example configurations for different setups

### Branches:
- `master` - Stable rudimentary version (tagged as v0.1.0-rudimentary)
- `dev/osc-fixes` - Active development for OSC compatibility fixes

### Quick Reversion Command:
```bash
git checkout v0.1.0-rudimentary
```
Stable Version Tagged
Tag: v0.1.0-rudimentary
Status: Stable rudimentary version with basic OSC communication and highlighting
Branch: master (pushed to origin)
Development Branch Created
Branch: dev/osc-fixes (active branch, pushed to origin)
Purpose: Continue OSC compatibility fixes and improvements
Documentation: Added DEVELOPMENT_NOTES.md with current state
Quick Commands for Later
At work, to continue development:


git clone https://github.com/b0id/HighTideLight.nvim.gitcd HighTideLight.nvimgit checkout dev/osc-fixes

At work, to continue development:

git clone https://github.com/b0id/HighTideLight.nvim.git
cd HighTideLight.nvim
git checkout dev/osc-fixes