# HighTideLight.nvim Testing Guide

This document outlines the comprehensive testing protocol for developing and maintaining the HighTideLight.nvim plugin locally, without dependencies on external services or Tidal itself.

## Overview

HighTideLight.nvim uses OSC (Open Sound Control) to communicate with Tidal for real-time highlighting. The testing system provides:

1. **OSC Mock Server** - Simulate Tidal events without running Tidal
2. **Unit Tests** - Test individual components in isolation
3. **Integration Tests** - Test complete plugin workflow
4. **Performance Tests** - Verify plugin performance under load
5. **Interactive Testing** - Manual testing with visual feedback

## Quick Start

```lua
-- In Neovim, run all tests
:lua require('tests.run_tests').run_all_tests()

-- Or use the command (after setup)
:TidalRunTests
```

## Test Structure

```
tests/
├── run_tests.lua           # Main test runner
├── osc_mock.lua           # OSC mock server for testing
├── unit/
│   ├── processor_test.lua  # Tests for pattern processing
│   └── osc_test.lua       # Tests for OSC communication
├── integration/
│   └── plugin_test.lua    # End-to-end plugin tests
└── fixtures/
    └── tidal_patterns.lua  # Sample Tidal patterns and test data
```

## Setting Up Tests

### 1. Enable Test Commands

Add to your Neovim config:

```lua
-- Setup test commands
require('tests.run_tests').setup_test_commands()
```

### 2. Plugin Configuration for Testing

```lua
require('tidal-highlight').setup({
  enabled = true,
  osc = {
    ip = "127.0.0.1",
    port = 6011,  -- Default port
  },
  debug = true,  -- Enable for testing
  animation = {
    fps = 30,
    duration_ms = 200,
  }
})
```

## Running Tests

### Automated Test Suites

```lua
-- Run all tests
:TidalRunTests

-- Run only unit tests
:TidalRunUnitTests

-- Run only integration tests  
:TidalRunIntegrationTests

-- Run performance tests
:TidalRunPerformanceTests
```

### Interactive Testing

```lua
-- Start interactive test mode
:TidalInteractiveTests
```

This provides manual testing commands:
- `:TidalTestSingleHighlight` - Test single highlight
- `:TidalTestPatternHighlight` - Highlight current line as pattern
- `:TidalTestStressHighlight` - Stress test with many highlights

## Test Categories

### 1. Unit Tests

Test individual modules in isolation:

**Processor Tests** (`tests/unit/processor_test.lua`):
- Pattern parsing and analysis
- Mini-notation detection (e.g., "bd sn hh")
- Control pattern detection (e.g., "# gain 0.8")
- Event ID generation and tracking
- Memory cleanup

**OSC Tests** (`tests/unit/osc_test.lua`):
- OSC message parsing
- Callback registration
- Server lifecycle
- Malformed message handling

### 2. Integration Tests

Test complete plugin workflow (`tests/integration/plugin_test.lua`):
- Plugin setup and initialization
- Command registration and execution
- Highlight application and clearing
- OSC event processing
- Multi-buffer support

### 3. Performance Tests

Verify plugin performance:
- Process 1000+ patterns and measure timing
- Memory usage and cleanup verification
- Stress testing with rapid highlight events

## Testing Without Tidal

The plugin can be fully tested without Tidal running:

### 1. OSC Mock Server

```lua
local osc_mock = require('tests.osc_mock')

-- Send single highlight event
osc_mock.send_highlight_event({
  event_id = 1,
  buffer_id = vim.api.nvim_get_current_buf(),
  row = 0,
  start_col = 10,
  end_col = 20,
  duration = 0.5
})

-- Highlight current line as Tidal pattern
osc_mock.send_pattern_highlights("d1 $ sound \"bd sn hh\"")
```

### 2. Manual Pattern Testing

Create test files with Tidal patterns:

```tidal
-- test.tidal
d1 $ sound "bd sn"
d2 $ sound "hh*8" # gain 0.6
d3 $ jux rev $ sound "[bd sn]*2"
```

Use `:TidalHighlightTest` on each line to verify highlighting.

## Development Workflow

### 1. Test-Driven Development

1. Write failing test for new feature
2. Implement feature to make test pass
3. Refactor and ensure all tests pass

### 2. Debugging Failed Tests

```lua
-- Run specific test suite with debug output
:lua require('tidal-highlight.config').current.debug = true
:TidalRunUnitTests
```

### 3. Adding New Tests

**For new processor features:**
```lua
-- Add to tests/unit/processor_test.lua
function M.test_new_feature()
  local result = processor.new_function(input)
  assert_eq(result, expected, "Should handle new feature")
  print("✓ test_new_feature passed")
end
```

**For new OSC events:**
```lua
-- Add to tests/fixtures/tidal_patterns.lua
M.osc_test_events = {
  {
    address = "/new/event",
    args = {1, 2, 3},
    types = "iii",
    description = "New event type"
  }
}
```

## Continuous Integration

### Local CI Script

Create `scripts/test.sh`:

```bash
#!/bin/bash
nvim --headless -c "lua require('tests.run_tests').run_all_tests()" -c "qa"
```

### Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit
echo "Running HighTideLight tests..."
nvim --headless -c "lua if not require('tests.run_tests').run_all_tests() then vim.cmd('cquit') end" -c "qa"
```

## Troubleshooting Tests

### Common Issues

1. **OSC Port Conflicts**
   ```lua
   -- Use different port for testing
   config.osc.port = 6012
   ```

2. **Timing Issues**
   ```lua
   -- Add longer waits for slow systems
   vim.wait(500)  -- Instead of vim.wait(100)
   ```

3. **Buffer Cleanup**
   ```lua
   -- Always clean up test buffers
   vim.api.nvim_buf_delete(buf, {force = true})
   ```

### Debug Output

Enable debug mode for verbose logging:

```lua
require('tidal-highlight').setup({debug = true})
```

## Performance Benchmarks

Expected performance targets:
- Pattern processing: < 1ms per pattern
- OSC event handling: < 10ms latency
- Memory usage: < 100MB for 1000+ events
- Highlight rendering: 60fps smooth animation

## Test Data

The `tests/fixtures/tidal_patterns.lua` provides:
- Basic drum patterns
- Complex multi-line patterns
- Patterns with controls and effects
- Error cases for robustness testing
- Performance test datasets

## Coverage Goals

- **Unit Tests**: 90%+ code coverage
- **Integration Tests**: All major workflows
- **Edge Cases**: Error handling and malformed input
- **Performance**: Under realistic load conditions

## Contributing Tests

When adding features:
1. Add unit tests for core functionality
2. Add integration tests for user-facing features
3. Update test fixtures with relevant examples
4. Ensure all tests pass before submitting

This testing protocol ensures HighTideLight.nvim works reliably in all environments without requiring Tidal or external services for development and verification.