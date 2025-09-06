-- lua/tidal-highlight/diagnostics.lua
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
  local server_ok, _ = pcall(function() osc.start(config) end)
  if not server_ok then
    return { success = false, error = "Could not start OSC server", port = port }
  end
  osc.on("/test", function(args) end)
  osc.stop()
  return { success = true, port = port, callback_registered = osc.callbacks["/test"] ~= nil, server_started = server_ok }
end


-- This test uses a polling loop and the core Neovim API
function M.test_parsing_engine(callback)
  print("⚙️  Testing AST Parsing Engine:")
  local source_map_generator = require('tidal-highlight.source_map')

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'haskell')

  local test_lines = {
    'd1 $ sound "bd sd [bd hh]*2"',
    '-- another line',
    'd2 $ sound "cp"',
  }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, test_lines)

  local start_time = vim.loop.now()
  local timeout_ms = 2000 -- Wait up to 2 seconds for the parser

  local function run_the_test()
    local results = {}
    local range1 = { start_line = 1, end_line = 1 }
    local map1 = source_map_generator.generate(bufnr, range1)
    local map1_token_count = 0
    for _ in pairs(map1) do map1_token_count = map1_token_count + 1 end
    table.insert(results, {
      test = "Pattern 1 (bd sd [bd hh]*2)",
      success = map1_token_count == 4,
      details = "Expected 4 tokens, found " .. map1_token_count,
    })

    local range2 = { start_line = 3, end_line = 3 }
    local map2 = source_map_generator.generate(bufnr, range2)
    local map2_token_count = 0
    for _ in pairs(map2) do map2_token_count = map2_token_count + 1 end
    local cp_token = map2 and map2['cp_0'] or nil
    table.insert(results, {
      test = "Pattern 2 (cp)",
      success = map2_token_count == 1 and cp_token ~= nil and cp_token.range.start.col == 13,
      details = "Expected 1 token ('cp_0') at col 13. Found " .. map2_token_count .. " tokens.",
    })

    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    local all_ok = true
    for _, res in ipairs(results) do
      local status = res.success and "✅" or "❌"
      print(string.format("  %s %s: %s", status, res.test, res.details))
      if not res.success then all_ok = false end
    end
    if callback then callback(all_ok, results) end
  end

  local function poll_for_parser()
    -- VVVV MODIFIED LINE VVVV
    -- Use the core Neovim API to get the parser
    local parser = vim.treesitter.get_parser(bufnr, 'haskell')

    if parser and parser.parse then
      run_the_test()
    elseif vim.loop.now() - start_time > timeout_ms then
      print("  ❌ Parser Test: Timed out waiting for Haskell parser to attach.")
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      if callback then callback(false) end
    else
      vim.defer_fn(poll_for_parser, 50)
    end
  end
  poll_for_parser()
end

-- Test Tidal integration (no changes)
function M.test_tidal_integration()
  local compat = require('tidal-highlight.compat')
  local tidal_info, err = compat.get_tidal_info()
  if not tidal_info then return { success = false, error = err } end
  local hook_success, hook_result = compat.hook_tidal_evaluation(function(buffer, line, code) end)
  return { success = hook_success, plugin = tidal_info.plugin, plugin_name = tidal_info.info.name, hook_result = hook_result }
end

-- Test OSC message sending to SuperCollider (no changes)
function M.test_supercollider_connection()
  local osc = require('tidal-highlight.osc')
  local config = require('tidal-highlight.config')
  print("🎛️  Testing SuperCollider Connection:")
  local success, err = pcall(function()
    osc.send("/test/from_neovim", {"hello", "supercollider"}, config.current.supercollider.ip, config.current.supercollider.port)
  end)
  if success then
    print("  Test message sent to SuperCollider ✅")
  else
    print("  Failed to send message ❌")
    print("  Error:", tostring(err))
  end
  return success
end

-- The main diagnostics runner (no changes)
function M.run_diagnostics()
  print("🔍 HighTideLight.nvim Diagnostics")
  print("=" .. string.rep("=", 50))
  print("\n📋 Environment:")
  local env = M.check_environment()
  print("  Neovim:", vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch)
  if env.tidal_plugin then print("  Tidal plugin:", env.tidal_info, "✅") else print("  Tidal plugin:", env.tidal_error or "Not found", "❌") end

  print("\n🌐 OSC Connectivity:")
  local osc_result = M.test_osc_connectivity()
  if osc_result.success then print("  OSC server:", "✅") else print("  OSC server:", "❌") end

  M.test_parsing_engine(function(parser_ok, _)
    print("\n🎵 Tidal Integration:")
    local tidal_result = M.test_tidal_integration()
    if tidal_result.success then print("  Plugin detected:", tidal_result.plugin_name, "✅") else print("  Integration:", "❌") end

    print("\n")
    M.test_supercollider_connection()
    print("\n" .. string.rep("=", 50))
    local all_good = env.has_loop and osc_result.success and parser_ok and tidal_result.success
    if all_good then print("🎉 All systems ready!") else print("⚠️  Some issues detected.") end
  end)
end

return M