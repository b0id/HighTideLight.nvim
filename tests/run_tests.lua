-- Main test runner for HighTideLight.nvim
local M = {}

-- Color output for better visibility
local colors = {
  reset = "\27[0m",
  red = "\27[31m",
  green = "\27[32m",
  yellow = "\27[33m",
  blue = "\27[34m",
  magenta = "\27[35m",
  cyan = "\27[36m"
}

local function colored_print(color, text)
  print(colors[color] .. text .. colors.reset)
end

-- Track test results
local test_results = {
  passed = 0,
  failed = 0,
  errors = {}
}

-- Safe test execution with error handling
local function run_test_suite(name, test_module)
  colored_print("blue", "\n=== Running " .. name .. " ===")
  
  local success, result = pcall(function()
    return test_module.run_all()
  end)
  
  if success then
    test_results.passed = test_results.passed + 1
    colored_print("green", "✅ " .. name .. " completed successfully")
  else
    test_results.failed = test_results.failed + 1
    table.insert(test_results.errors, {suite = name, error = result})
    colored_print("red", "❌ " .. name .. " failed: " .. tostring(result))
  end
end

-- Main test runner
function M.run_all_tests()
  colored_print("cyan", "🚀 Starting HighTideLight.nvim Test Suite")
  colored_print("cyan", "=" .. string.rep("=", 50))
  
  -- Add current directory to Lua path for testing
  local current_dir = vim.fn.getcwd()
  package.path = package.path .. ";" .. current_dir .. "/?.lua;" .. current_dir .. "/lua/?.lua"
  
  -- Reset results
  test_results = {passed = 0, failed = 0, errors = {}}
  
  -- Run unit tests
  local processor_tests = require('tests.unit.processor_test')
  run_test_suite("Processor Unit Tests", processor_tests)
  
  local osc_tests = require('tests.unit.osc_test')
  run_test_suite("OSC Unit Tests", osc_tests)
  
  -- Run integration tests (only if unit tests pass)
  if test_results.failed == 0 then
    local integration_tests = require('tests.integration.plugin_test')
    run_test_suite("Integration Tests", integration_tests)
  else
    colored_print("yellow", "⚠️  Skipping integration tests due to unit test failures")
  end
  
  -- Print final results
  colored_print("cyan", "\n" .. string.rep("=", 50))
  colored_print("cyan", "📊 Test Results Summary")
  colored_print("cyan", string.rep("=", 50))
  
  local total_tests = test_results.passed + test_results.failed
  colored_print("green", "✅ Passed: " .. test_results.passed .. "/" .. total_tests)
  
  if test_results.failed > 0 then
    colored_print("red", "❌ Failed: " .. test_results.failed .. "/" .. total_tests)
    
    colored_print("red", "\n📋 Error Details:")
    for i, error_info in ipairs(test_results.errors) do
      colored_print("red", string.format("%d. %s:", i, error_info.suite))
      colored_print("red", "   " .. error_info.error)
    end
  end
  
  -- Success/failure status
  if test_results.failed == 0 then
    colored_print("green", "\n🎉 All tests passed! Plugin is ready for use.")
    return true
  else
    colored_print("red", "\n💥 Some tests failed. Please fix issues before using plugin.")
    return false
  end
end

-- Individual test runners for debugging
function M.run_unit_tests()
  colored_print("cyan", "Running Unit Tests Only")
  
  -- Add current directory to Lua path for testing
  local current_dir = vim.fn.getcwd()
  package.path = package.path .. ";" .. current_dir .. "/?.lua;" .. current_dir .. "/lua/?.lua"
  
  local processor_tests = require('tests.unit.processor_test')
  run_test_suite("Processor Unit Tests", processor_tests)
  
  local osc_tests = require('tests.unit.osc_test')
  run_test_suite("OSC Unit Tests", osc_tests)
  
  return test_results.failed == 0
end

function M.run_integration_tests()
  colored_print("cyan", "Running Integration Tests Only")
  
  -- Add current directory to Lua path for testing
  local current_dir = vim.fn.getcwd()
  package.path = package.path .. ";" .. current_dir .. "/?.lua;" .. current_dir .. "/lua/?.lua"
  
  local integration_tests = require('tests.integration.plugin_test')
  run_test_suite("Integration Tests", integration_tests)
  
  return test_results.failed == 0
end

-- Performance test runner
function M.run_performance_tests()
  colored_print("cyan", "🏃 Running Performance Tests")
  
  -- Add current directory to Lua path for testing
  local current_dir = vim.fn.getcwd()
  package.path = package.path .. ";" .. current_dir .. "/?.lua;" .. current_dir .. "/lua/?.lua"
  
  local fixtures = require('tests.fixtures.tidal_patterns')
  local processor = require('tidal-highlight.processor')
  
  -- Test processing speed
  local start_time = vim.loop.hrtime()
  
  for i = 1, 1000 do
    local pattern = fixtures.get_random_pattern()
    processor.process_line(1, i, pattern)
  end
  
  local end_time = vim.loop.hrtime()
  local duration_ms = (end_time - start_time) / 1000000
  
  colored_print("green", string.format("✅ Processed 1000 patterns in %.2f ms", duration_ms))
  colored_print("green", string.format("   Average: %.3f ms per pattern", duration_ms / 1000))
  
  -- Test memory usage (basic check)
  processor.cleanup_old_events(50)
  local event_count = 0
  for _ in pairs(processor.event_ids) do
    event_count = event_count + 1
  end
  
  colored_print("green", string.format("✅ Memory cleanup: %d events remaining", event_count))
  
  if duration_ms > 1000 then
    colored_print("yellow", "⚠️  Processing seems slow, consider optimization")
  end
  
  return true
end

-- Interactive test mode for manual testing
function M.run_interactive_tests()
  colored_print("cyan", "🎮 Interactive Test Mode")
  colored_print("yellow", "Use the following commands to test manually:")
  colored_print("yellow", "  :TidalTestSingleHighlight - Test single highlight")
  colored_print("yellow", "  :TidalTestPatternHighlight - Test pattern highlighting") 
  colored_print("yellow", "  :TidalTestStressHighlight - Stress test with many highlights")
  colored_print("yellow", "  :TidalHighlightTest - Test current line highlighting")
  colored_print("yellow", "  :TidalHighlightToggle - Toggle plugin on/off")
  colored_print("yellow", "  :TidalHighlightClear - Clear all highlights")
  
  -- Add current directory to Lua path for testing
  local current_dir = vim.fn.getcwd()
  package.path = package.path .. ";" .. current_dir .. "/?.lua;" .. current_dir .. "/lua/?.lua"
  
  -- Set up mock server for interactive testing
  local osc_mock = require('tests.osc_mock')
  osc_mock.setup_test_commands()
  
  colored_print("green", "✅ Interactive test commands registered")
  colored_print("cyan", "Try typing some Tidal patterns and using the test commands!")
end

-- Command registration for Neovim
function M.setup_test_commands()
  vim.api.nvim_create_user_command('TidalRunTests', function()
    M.run_all_tests()
  end, {desc = "Run all HighTideLight tests"})
  
  vim.api.nvim_create_user_command('TidalRunUnitTests', function()
    M.run_unit_tests()
  end, {desc = "Run unit tests only"})
  
  vim.api.nvim_create_user_command('TidalRunIntegrationTests', function()
    M.run_integration_tests()
  end, {desc = "Run integration tests only"})
  
  vim.api.nvim_create_user_command('TidalRunPerformanceTests', function()
    M.run_performance_tests()
  end, {desc = "Run performance tests"})
  
  vim.api.nvim_create_user_command('TidalInteractiveTests', function()
    M.run_interactive_tests()
  end, {desc = "Start interactive test mode"})
  
  colored_print("green", "✅ Test commands registered:")
  colored_print("yellow", "  :TidalRunTests")
  colored_print("yellow", "  :TidalRunUnitTests") 
  colored_print("yellow", "  :TidalRunIntegrationTests")
  colored_print("yellow", "  :TidalRunPerformanceTests")
  colored_print("yellow", "  :TidalInteractiveTests")
end

return M