-- Diagnostic tools for real-world testing and debugging
local M = {}

-- Check system requirements and environment
function M.check_environment()
  local results = {
    neovim_version = vim.version(),
    lua_version = _VERSION,
    has_loop = vim.loop ~= nil,
    has_bit = pcall(require, 'bit'),
    current_directory = vim.fn.getcwd(),
    runtime_path = vim.o.runtimepath:gsub(',', '\n  '),
  }
  
  -- Check for Tidal plugin
  local compat = require('tidal-highlight.compat')
  local tidal_info, err = compat.get_tidal_info()
  
  if tidal_info then
    results.tidal_plugin = tidal_info.plugin
    results.tidal_info = tidal_info.info.name
    results.tidal_has_send = tidal_info.has_send_function
  else
    results.tidal_error = err
  end
  
  return results
end

-- Test OSC connectivity
function M.test_osc_connectivity(port)
  port = port or 6011
  
  local osc = require('tidal-highlight.osc')
  local config = {
    osc = { ip = "127.0.0.1", port = port },
    debug = true
  }
  
  -- Start OSC server
  local server_ok, server_err = pcall(function()
    osc.start(config)
  end)
  
  if not server_ok then
    return {
      success = false,
      error = "Could not start OSC server: " .. tostring(server_err),
      port = port
    }
  end
  
  -- Test callback registration
  local callback_called = false
  osc.on("/test", function(args)
    callback_called = true
  end)
  
  -- Stop server
  osc.stop()
  
  return {
    success = true,
    port = port,
    callback_registered = osc.callbacks["/test"] ~= nil,
    server_started = server_ok
  }
end

-- Test processor functionality
function M.test_processor()
  local processor = require('tidal-highlight.processor')
  
  local test_patterns = {
    'd1 $ sound "bd sn"',
    'd1 $ sound "bd sn" # gain 0.8',
    'd1 $ jux rev $ sound "[bd sn]*2"'
  }
  
  local results = {}
  
  for i, pattern in ipairs(test_patterns) do
    local processed, event_id = processor.process_line(1, i, pattern)
    local event_info = processor.get_event_info(event_id)
    
    table.insert(results, {
      original = pattern,
      processed = processed,
      event_id = event_id,
      markers_count = event_info and #event_info.markers or 0,
      has_context = processed:match("deltaContext") ~= nil
    })
  end
  
  return results
end

-- Test Tidal integration
function M.test_tidal_integration()
  local compat = require('tidal-highlight.compat')
  
  -- Detect Tidal plugin
  local tidal_info, err = compat.get_tidal_info()
  if not tidal_info then
    return { success = false, error = err }
  end
  
  -- Test hooking
  local hook_success, hook_result = compat.hook_tidal_evaluation(function(buffer, line, code)
    -- Test callback
    print("Tidal evaluation detected:", code)
  end)
  
  return {
    success = hook_success,
    plugin = tidal_info.plugin,
    plugin_name = tidal_info.info.name,
    hook_result = hook_result
  }
end

-- Comprehensive system check
function M.run_diagnostics()
  print("🔍 HighTideLight.nvim Diagnostics")
  print("=" .. string.rep("=", 50))
  
  -- Environment check
  print("\n📋 Environment:")
  local env = M.check_environment()
  print("  Neovim:", vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch)
  print("  Lua:", env.lua_version)
  print("  Loop support:", env.has_loop and "✅" or "❌")
  print("  Bit operations:", env.has_bit and "✅" or "❌")
  
  if env.tidal_plugin then
    print("  Tidal plugin:", env.tidal_info, "✅")
    print("  Send function:", env.tidal_has_send and "✅" or "❌")
  else
    print("  Tidal plugin:", env.tidal_error or "Not found", "❌")
  end
  
  -- OSC test
  print("\n🌐 OSC Connectivity:")
  local osc_result = M.test_osc_connectivity()
  if osc_result.success then
    print("  OSC server:", "✅")
    print("  Port " .. osc_result.port .. ":", "Available")
    print("  Callbacks:", osc_result.callback_registered and "✅" or "❌")
  else
    print("  OSC server:", "❌")
    print("  Error:", osc_result.error)
  end
  
  -- Processor test
  print("\n⚙️  Processor:")
  local proc_results = M.test_processor()
  print("  Pattern processing:", #proc_results > 0 and "✅" or "❌")
  for i, result in ipairs(proc_results) do
    print(string.format("    Pattern %d: %d markers, context: %s", 
          i, result.markers_count, result.has_context and "✅" or "❌"))
  end
  
  -- Tidal integration test
  print("\n🎵 Tidal Integration:")
  local tidal_result = M.test_tidal_integration()
  if tidal_result.success then
    print("  Plugin detected:", tidal_result.plugin_name, "✅")
    print("  Hook installed:", "✅")
    print("  Result:", tidal_result.hook_result)
  else
    print("  Integration:", "❌")
    print("  Error:", tidal_result.error)
  end
  
  print("\n" .. string.rep("=", 50))
  
  -- Overall status
  local all_good = env.has_loop and env.has_bit and osc_result.success and 
                   #proc_results > 0 and tidal_result.success
  
  if all_good then
    print("🎉 All systems ready! Plugin should work in real environment.")
  else
    print("⚠️  Some issues detected. Check above for details.")
  end
  
  return {
    environment = env,
    osc = osc_result,
    processor = proc_results,
    tidal = tidal_result,
    overall_status = all_good and "ready" or "issues_detected"
  }
end

return M