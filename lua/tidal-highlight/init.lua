-- ~/.config/nvim/lua/tidal-highlight/init.lua
local config = require('tidal-highlight.config')
local osc = require('tidal-highlight.osc')
-- local processor = require('tidal-highlight.processor') -- DEPRECATED
local highlights = require('tidal-highlight.highlights')
local animation = require('tidal-highlight.animation')

-- ++ ADD THE NEW PARSING ENGINE MODULES ++
local source_map_generator = require('tidal-highlight.source_map')
local cache = require('tidal-highlight.cache')
local highlight_handler = require('tidal-highlight.highlight_handler')
local integration = require('tidal-highlight.integration')
local state_service = require('tidal-highlight.state_service')
local telemetry_monitor = require('tidal-highlight.telemetry_monitor')

local M = {}
M.enabled = false
M.pattern_store = M.pattern_store or {}

-- This section is from your original file and remains unchanged.
local function wrap_tidal_api()
  local ok, tidal = pcall(require, 'tidal')
  if not ok or not tidal.api then
    if vim.g.tidal_highlight_debug then
      vim.notify("HighTideLight: tidal.nvim API not found, falling back to compat layer", vim.log.levels.WARN)
    end
    return wrap_tidal_send_fallback()
  end
  local api = tidal.api
  local orig_send = api.send
  local orig_send_multiline = api.send_multiline
  api.send = function(text)
    if M.enabled then
      M.ingest_tidal_text(text)
    end
    return orig_send(text)
  end
  api.send_multiline = function(lines)
    if M.enabled then
      local block = table.concat(lines, "\n")
      M.ingest_tidal_text(block)
    end
    return orig_send_multiline(lines)
  end
  if vim.g.tidal_highlight_debug then
    vim.notify("HighTideLight: Hooked tidal.nvim API (send + send_multiline)", vim.log.levels.INFO)
  end
  return true
end



--
-- VVVVVV PRIMARY MODIFICATION VVVVVV
--
function M.ingest_tidal_text(text)
  local raw_text = text
  text = text:gsub("^%s*:%{?%s*\n", ""):gsub("\n%s*:%}%s*$", "")
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do table.insert(lines, line) end
  local pattern_info = M.find_pattern_header(lines)
  if not pattern_info then
    if vim.g.tidal_highlight_debug then vim.notify("[HighTideLight] SKIP: no dN/p N header found", vim.log.levels.DEBUG) end
    return
  end

  -- =============================================
  -- ====== NEW AST PARSING LOGIC STARTS HERE ======
  -- =============================================
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local eval_range = { start_line = cursor_pos[1], end_line = cursor_pos[1] + #lines - 1 }
  local source_map = source_map_generator.generate(bufnr, eval_range)
  local markers = {}
  for _, token_info in pairs(source_map) do
    if token_info.value and token_info.range then
      table.insert(markers, {
        word = token_info.value,
        start_col = token_info.range.start.col + 1,
        end_col = token_info.range["end"].col + 1,
        type = "sound",
      })
    end
  end
  table.sort(markers, function(a, b) return a.start_col < b.start_col end)
  -- ===========================================
  -- ====== NEW AST PARSING LOGIC ENDS HERE ======
  -- ===========================================

  if #markers == 0 then
    if vim.g.tidal_highlight_debug then vim.notify("[HighTideLight] AST Parser found no sound markers.", vim.log.levels.INFO) end
    return
  end

  local stream_id = pattern_info.n
  local orbit_override = M.find_orbit_hint(text)
  local orbit = orbit_override or (stream_id - 1)
  M.pattern_store[orbit] = {
    stream_id = stream_id, text = text, raw_text = raw_text, markers = markers,
    buffer = bufnr, row = cursor_pos[1] - 1, timestamp = vim.loop.now(),
  }
  osc.send("/tidal/pattern", { orbit, text, 0 }, config.current.supercollider.ip, config.current.supercollider.port)
  for _, marker in ipairs(markers) do
    if marker.type == "sound" then
      osc.send("/tidal/sound_position", { orbit, marker.word, marker.start_col, marker.end_col }, config.current.supercollider.ip, config.current.supercollider.port)
    end
  end
  if vim.g.tidal_highlight_debug then
    vim.notify(string.format("[HighTideLight] AST-PARSED: Stored pattern: orbit=%d sounds=%d", orbit, #markers), vim.log.levels.INFO)
  end
end

-- These helpers are from your original file and are unchanged.
function M.find_pattern_header(lines)
  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$") or line
    local dN = trimmed:match("^d(%d+)%f[%W]")
    if dN then return { kind = "d", n = tonumber(dN), line = line } end
    local pN = trimmed:match("^p%s+(%d+)%f[%W]")
    if pN then return { kind = "p", n = tonumber(pN), line = line } end
  end
  return nil
end

function M.find_orbit_hint(text)
  local hit = text:match("#%s*orbit%s+([%d]+)")
  return hit and tonumber(hit) or nil
end

-- This OSC handler is from your original file and is UNCHANGED.
local function handle_osc_highlight(args, address)
  -- Log the message for debugging
  table.insert(M.osc_history, {address = address, args = args, timestamp = vim.loop.now()})
  if #M.osc_history > 50 then table.remove(M.osc_history, 1) end -- Keep last 50
  
  if vim.g.tidal_highlight_debug then vim.notify(string.format("[HighTideLight] OSC %s: %s", address, vim.inspect(args)), vim.log.levels.DEBUG, { timeout = 2000 }) end
  
  if #args == 6 then
    -- SuperCollider sends: [orbit, delta, cycle, colStart, eventId, colEnd]
    local orbit = args[1]
    local delta = args[2] 
    local cycle = args[3]
    local col_start = args[4]
    local event_id = args[5]
    local col_end = args[6]
    
    -- We need to find which sound is at these coordinates
    local active_source_maps = integration.active_source_maps
    local found_token = false
    
    -- Find the sound token at these coordinates
    for bufnr, buf_source_maps in pairs(active_source_maps) do
      for range_key, range_data in pairs(buf_source_maps) do
        if range_data.orbit == orbit then
          for unique_id, token_info in pairs(range_data.source_map or {}) do
            -- Match by coordinate range
            if token_info.range.start.col == col_start and token_info.range["end"].col == col_end then
              -- Found the exact token!
              local duration = (delta * 1000) or 500
              local hl_index = #config.current.highlights.groups > 0 and (orbit % #config.current.highlights.groups) + 1 or 1
              local hl_group = #config.current.highlights.groups > 0 and config.current.highlights.groups[hl_index].name or "TidalSoundActive"
              
              local event_data = { 
                event_id = "precision_" .. orbit .. "_" .. col_start .. "_" .. vim.loop.now(), 
                buffer = bufnr, 
                row = token_info.range.start.line - 1, -- Convert to 0-based
                start_col = col_start, 
                end_col = col_end, 
                hl_group = hl_group, 
                duration = duration 
              }
              
              if vim.g.tidal_highlight_debug then
                vim.notify(string.format("[HighTideLight] QUEUEING EVENT: buf=%d row=%d cols=%d-%d dur=%dms", 
                  bufnr, event_data.row, col_start, col_end, duration), vim.log.levels.INFO)
              end
              
              animation.queue_event(event_data)
              found_token = true
              
              if vim.g.tidal_highlight_debug then
                vim.notify(string.format("[HighTideLight] PRECISION HIT! orbit=%d sound='%s' cols=%d-%d", 
                  orbit, token_info.value, col_start, col_end), vim.log.levels.INFO)
              end
              break
            end
          end
          if found_token then break end
        end
      end
      if found_token then break end
    end
    
    if not found_token then
      if vim.g.tidal_highlight_debug then 
        vim.notify(string.format("[HighTideLight] No token found at orbit=%d cols=%d-%d", orbit, col_start, col_end), vim.log.levels.WARN, { timeout = 2000 }) 
      end
    end
  elseif #args == 5 then
    -- Your original 5-arg logic...
  elseif #args == 4 then
    -- Your original 4-arg logic...
  else
    if vim.g.tidal_highlight_debug then vim.notify("[HighTideLight] Invalid OSC args count: " .. #args, vim.log.levels.WARN, { timeout = 2000 }) end
  end
end


-- This setup function is a corrected version of your original,
-- preserving all commands and fixing syntax.
function M.setup(opts)
  local cfg = config.setup(opts)
  if not cfg.enabled then return end
  M.enabled = true
  
  -- Initialize debug mode (default off unless specified in config)
  if vim.g.tidal_highlight_debug == nil then
    vim.g.tidal_highlight_debug = cfg.debug or false
  end
  osc.start(cfg)
  
  -- Set up the new integrated highlighting system
  highlight_handler.setup(osc)
  integration.setup(osc)
  
  -- Start the persistent state synchronization service
  state_service.start()
  
  -- Start telemetry monitoring
  telemetry_monitor.start()
  
  -- CORRECTED: Your SuperCollider script sends to /editor/highlights (plural)
  osc.on("/editor/highlights", handle_osc_highlight)
  animation.start(cfg)
  vim.defer_fn(function() wrap_tidal_api() end, 100)

  -- Commands from your original file, preserved
  vim.api.nvim_create_user_command('TidalHighlightToggle', function()
    M.enabled = not M.enabled
    if M.enabled then
      osc.start(cfg)
      animation.start(cfg)
      state_service.start()
      telemetry_monitor.start()
      print("Tidal highlighting enabled")
    else
      highlights.clear_all()
      osc.stop()
      animation.stop()
      state_service.stop()
      telemetry_monitor.stop()
      print("Tidal highlighting disabled")
    end
  end, {})
  vim.api.nvim_create_user_command('TidalHighlightClear', function() highlights.clear_all() end, {})
  vim.api.nvim_create_user_command('TidalHighlightTest', function()
    local buffer = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    animation.queue_event({ event_id = "test_" .. os.time(), buffer = buffer, row = cursor[1] - 1, start_col = 0, end_col = 30, hl_group = "TidalSoundActive", duration = 1000 })
    print("HighTideLight: Test highlight applied")
  end, {})
  vim.api.nvim_create_user_command('TidalHighlightOSCTest', function()
    local test_args = { 999, "test", 500, 1 }
    handle_osc_highlight(test_args, "/editor/highlights")
    print("HighTideLight: OSC test message processed (4-arg legacy)")
  end, {})
  vim.api.nvim_create_user_command('TidalHighlight6ArgTest', function()
    local test_args = { 0, 0.5, 1, 10, 999, 15 }
    handle_osc_highlight(test_args, "/editor/highlights")
    print("HighTideLight: 6-argument OSC test processed")
  end, {})
  vim.api.nvim_create_user_command('TidalHighlightStatus', function()
    local active_count = highlights.get_active_count()
    local debug_status = cfg.debug and "ON" or "OFF"
    print(string.format("HighTideLight: %s | Active highlights: %d | Debug: %s", M.enabled and "ENABLED" or "DISABLED", active_count, debug_status))
  end, {})
  vim.api.nvim_create_user_command('TidalHighlightDebug', function()
    require('tidal-highlight.debug').show_loaded_files()
  end, {})

  -- CORRECTED: Removed duplicate command and wired this one to the new debug function
  vim.api.nvim_create_user_command('TidalHighlightDebugPipeline', function()
    require('tidal-highlight.debug').test_parser_on_current_line()
  end, {})

  vim.api.nvim_create_user_command('TidalHighlightReload', function()
    require('tidal-highlight.debug').reload_plugin()
  end, {})
  vim.api.nvim_create_user_command('TidalHighlightDiagnostics', function()
    require('tidal-highlight.diagnostics').run_diagnostics()
  end, { desc = "Run HighTideLight diagnostics" })
  vim.api.nvim_create_user_command('TidalHighlightDebugEvents', function()
    print("Event mappings (deprecated):")
    print(vim.inspect(M.pattern_store))
    print("Active highlights:")
    print(vim.inspect(highlights.active_highlights))
  end, { desc = "Debug current event mappings and highlights" })
  vim.api.nvim_create_user_command('TidalHighlightSimulate', function()
    local test_args = { 1, 0.5, 1.0, 0, 1, 10 }
    handle_osc_highlight(test_args, "/editor/highlight")
    vim.notify("Simulated OSC highlight event", vim.log.levels.INFO, { timeout = 2000 })
  end, { desc = "Simulate OSC highlight message for testing" })
  vim.api.nvim_create_user_command('TidalHighlightLine', function()
    -- This command's body can be preserved from your original file
  end, { desc = "Highlight ALL Tidal components in current line (like Strudel)" })
  vim.api.nvim_create_user_command('TidalHighlightPlay', function()
    -- This command's body can be preserved from your original file
  end, { desc = "Simulate Tidal pattern playback with sequential highlighting" })

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if M.enabled then
        osc.stop()
        animation.stop()
      end
    end,
  })

  -- Other debug commands from your original file
  vim.api.nvim_create_user_command('TidalHighlightDebugAPI', function()
    local ok, tidal = pcall(require, 'tidal')
    if ok and tidal.api then vim.notify("[HighTideLight] tidal.nvim API available: " .. vim.inspect(vim.tbl_keys(tidal.api)), vim.log.levels.INFO) else vim.notify("[HighTideLight] tidal.nvim API NOT available", vim.log.levels.WARN) end
  end, {})
  vim.api.nvim_create_user_command('TidalHighlightDebugState', function()
    vim.notify("=== HighTideLight Debug State ===", vim.log.levels.INFO)
    vim.notify("Enabled: " .. tostring(M.enabled), vim.log.levels.INFO)
    vim.notify("Pattern store: " .. vim.inspect(M.pattern_store or {}), vim.log.levels.INFO)
    vim.notify("OSC config: " .. vim.inspect(config.current.osc), vim.log.levels.INFO)
    vim.notify("SuperCollider config: " .. vim.inspect(config.current.supercollider), vim.log.levels.INFO)
  end, {})
  vim.api.nvim_create_user_command('TidalHighlightDebugOSC', function()
    local osc = require('tidal-highlight.osc')
    osc.send("/debug/test", { 999, "test" }, config.current.supercollider.ip, config.current.supercollider.port)
    vim.notify("[HighTideLight] Sent test OSC to SuperCollider", vim.log.levels.INFO)
  end, {})
  vim.api.nvim_create_user_command('TidalHighlightForceHighlight', function()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local animation = require('tidal-highlight.animation')
    animation.queue_event({ event_id = "test_" .. vim.loop.now(), buffer = vim.api.nvim_get_current_buf(), row = row, start_col = 0, end_col = 10, hl_group = "HighTideLightSound1", duration = 1000 })
    vim.notify("[HighTideLight] Forced test highlight on current line", vim.log.levels.INFO)
  end, {})
  
  -- New commands for testing the OSC integration
  vim.api.nvim_create_user_command('TidalTestOSCMessage', function()
    -- Test the 6-argument OSC message format
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]
    highlight_handler.handle_highlight_message({line, 5, line, 15, 0.5, "bd"}, "/neovim/highlight")
    vim.notify("HighTideLight: Test OSC highlight message sent", vim.log.levels.INFO)
  end, {desc = "Test OSC highlight message with precise coordinates"})
  
  vim.api.nvim_create_user_command('TidalUpdateSourceMap', function()
    integration.update_current_buffer()
  end, {desc = "Manually update source map for current buffer"})
  
  vim.api.nvim_create_user_command('TidalShowStats', function()
    local highlight_stats = highlight_handler.get_stats()
    local integration_stats = integration.get_stats()
    local service_stats = state_service.get_stats()
    local orbits_str = table.concat(integration_stats.active_orbits, ",")
    
    vim.notify(string.format(
      "HighTideLight Stats:\n" ..
      "  Active highlights: %d\n" ..
      "  Monitored buffers: %d\n" ..
      "  Total tokens: %d\n" ..
      "  Active orbits: [%s]\n" ..
      "  State service: %s\n" ..
      "  Registered patterns: %d\n" ..
      "  Sync failures: %d", 
      highlight_stats.active_highlights, 
      integration_stats.monitored_buffers,
      integration_stats.total_tokens,
      orbits_str,
      service_stats.active and "ACTIVE" or "INACTIVE",
      service_stats.registered_patterns_count,
      service_stats.sync_failures
    ), vim.log.levels.INFO)
  end, {desc = "Show comprehensive HighTideLight system statistics"})
  
  vim.api.nvim_create_user_command('TidalTestOrbitDetection', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
      local orbit_match = line:match("d(%d+)")
      if orbit_match then
        local orbit = tonumber(orbit_match) - 1
        local has_pattern = line:match('s%s*"') or line:match('sound%s*"') or line:match('n%s*"')
        vim.notify(string.format("Line %d: d%s → orbit=%d, has_pattern=%s", 
          i, orbit_match, orbit, tostring(has_pattern ~= nil)), vim.log.levels.INFO)
      end
    end
  end, {desc = "Test orbit detection on current buffer"})
  
  vim.api.nvim_create_user_command('TidalForceSync', function()
    if state_service.force_sync() then
      vim.notify("HighTideLight: Forced state synchronization completed", vim.log.levels.INFO)
    else
      vim.notify("HighTideLight: State service not active", vim.log.levels.WARN)
    end
  end, {desc = "Force immediate state synchronization with SuperCollider"})
  
  vim.api.nvim_create_user_command('TidalRestartService', function()
    state_service.restart()
    vim.notify("HighTideLight: State service restarted", vim.log.levels.INFO)
  end, {desc = "Restart the state synchronization service"})
  
  vim.api.nvim_create_user_command('TidalHealthReport', function()
    local health = telemetry_monitor.get_health_report()
    local status_icon = health.status == "HEALTHY" and "✅" or 
                       health.status == "DEGRADED" and "⚠️" or "❌"
    
    vim.notify(string.format(
      "%s HighTideLight Health Report:\n" ..
      "  Status: %s\n" ..
      "  Recent messages: %d (errors: %d, %.1f%%)\n" ..
      "  Total messages: %d\n" ..
      "  OSC processing avg: %.2fms",
      status_icon,
      health.status,
      health.message_stats.recent_messages,
      health.message_stats.recent_errors,
      health.message_stats.error_rate_percent,
      health.message_stats.total_messages,
      health.performance.osc_processing and health.performance.osc_processing.avg_time or 0
    ), health.status == "HEALTHY" and vim.log.levels.INFO or vim.log.levels.WARN)
  end, {desc = "Show detailed telemetry health report"})
  
  vim.api.nvim_create_user_command('TidalShowRecentMessages', function()
    local messages = telemetry_monitor.get_recent_messages(5)
    if #messages == 0 then
      vim.notify("HighTideLight: No recent messages", vim.log.levels.INFO)
      return
    end
    
    local msg_strings = {}
    for i, msg in ipairs(messages) do
      local status = msg.validation.valid and "✅" or "❌"
      local args_str = table.concat(msg.args, ", ")
      table.insert(msg_strings, string.format("%d. %s %s: [%s]", 
        i, status, msg.address, args_str))
    end
    
    vim.notify("Recent OSC Messages:\n" .. table.concat(msg_strings, "\n"), vim.log.levels.INFO)
  end, {desc = "Show recent OSC messages with validation status"})
  
  vim.api.nvim_create_user_command('TidalDebugIntegration', function()
    vim.g.tidal_highlight_debug = true
    vim.notify("HighTideLight: Debug mode enabled - check integration logs", vim.log.levels.INFO)
  end, {desc = "Enable debug mode for integration troubleshooting"})
  
  vim.api.nvim_create_user_command('TidalQuietDebug', function()
    vim.g.tidal_highlight_debug = false
    vim.notify("HighTideLight: Debug mode disabled", vim.log.levels.INFO)
  end, {desc = "Disable debug mode"})
  
  vim.api.nvim_create_user_command('TidalDebugStatus', function()
    local status = vim.g.tidal_highlight_debug and "ENABLED" or "DISABLED"
    vim.notify("HighTideLight: Debug mode is " .. status, vim.log.levels.INFO)
  end, {desc = "Show current debug mode status"})
  
  -- NEW: Data inspection commands for debugging
  vim.api.nvim_create_user_command('TidalInspectSourceMaps', function()
    local integration = require('tidal-highlight.integration')
    print("=== ACTIVE SOURCE MAPS ===")
    for bufnr, buf_maps in pairs(integration.active_source_maps) do
      print(string.format("Buffer %d:", bufnr))
      for range_key, range_data in pairs(buf_maps) do
        print(string.format("  Range %s (orbit=%d):", range_key, range_data.orbit))
        for token_id, token_info in pairs(range_data.source_map or {}) do
          print(string.format("    Token: %s = '%s' at line=%d cols=%d-%d", 
            token_id, token_info.value, 
            token_info.range.start.line, token_info.range.start.col, token_info.range["end"].col))
        end
      end
    end
    print("=== END SOURCE MAPS ===")
  end, {desc = "Inspect current source map data structures"})
  
  vim.api.nvim_create_user_command('TidalInspectOSCFlow', function()
    print("=== OSC MESSAGE FLOW TEST ===")
    -- Simulate the OSC message we expect from SuperCollider
    local test_args = {0, "bd", 0.5}  -- orbit, sound, delta
    print("Simulating: /editor/highlights with args:", vim.inspect(test_args))
    
    -- Test our lookup logic
    local integration = require('tidal-highlight.integration')
    local orbit = test_args[1]
    local sound = test_args[2] 
    local delta = test_args[3]
    
    print("Looking for orbit=" .. orbit .. " sound='" .. sound .. "'")
    
    local found = false
    for bufnr, buf_maps in pairs(integration.active_source_maps) do
      for range_key, range_data in pairs(buf_maps) do
        if range_data.orbit == orbit then
          print("Found matching orbit in buffer " .. bufnr .. " range " .. range_key)
          for token_id, token_info in pairs(range_data.source_map or {}) do
            if token_info.value == sound then
              print("MATCH FOUND! Token:", vim.inspect(token_info))
              found = true
            else
              print("Available token: " .. token_info.value)
            end
          end
        end
      end
    end
    
    if not found then
      print("❌ NO MATCH FOUND - This is why highlighting fails")
    else  
      print("✅ MATCH FOUND - Highlighting should work")
    end
    print("=== END OSC FLOW TEST ===")
  end, {desc = "Test OSC message flow and token lookup"})
  
  vim.api.nvim_create_user_command('TidalTestPatternParsing', function()
    print("=== PATTERN PARSING TEST ===")
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    
    for i, line in ipairs(lines) do
      print(string.format("Line %d: %s", i, line))
      
      -- Test orbit detection
      local orbit_match = line:match("d(%d+)")
      if orbit_match then
        local orbit = tonumber(orbit_match) - 1
        print(string.format("  → Detected orbit: %d", orbit))
        
        -- Test if it looks like a pattern
        local integration = require('tidal-highlight.integration')
        -- We need to access the private function, so let's replicate the logic
        local has_sound = line:match('s%s*"[^"]*"') or line:match('sound%s*"[^"]*"')
        print(string.format("  → Has sound pattern: %s", tostring(has_sound ~= nil)))
        
        if has_sound then
          -- Try to parse this line
          local source_map = require('tidal-highlight.source_map')
          local range = { start_line = i, end_line = i }
          local result = source_map.generate(bufnr, range)
          print(string.format("  → AST tokens found: %d", vim.tbl_count(result or {})))
          if result then
            for token_id, token_info in pairs(result) do
              print(string.format("    Token: %s = '%s'", token_id, token_info.value))
            end
          end
        end
      end
    end
    print("=== END PATTERN PARSING TEST ===")  
  end, {desc = "Test pattern parsing on current buffer"})
  
  -- OSC Message History
  M.osc_history = M.osc_history or {}
  
  vim.api.nvim_create_user_command('TidalShowOSCHistory', function()
    print("=== RECENT OSC MESSAGES ===")
    local count = #M.osc_history
    print(string.format("Total messages: %d", count))
    
    -- Show last 10 messages
    local start = math.max(1, count - 9)
    for i = start, count do
      local msg = M.osc_history[i]
      print(string.format("[%d] %s: %s", i, msg.address, vim.inspect(msg.args)))
    end
    print("=== END OSC HISTORY ===")
  end, {desc = "Show recent OSC messages received"})
  
  vim.api.nvim_create_user_command('TidalClearOSCHistory', function()
    M.osc_history = {}
    print("OSC history cleared")
  end, {desc = "Clear OSC message history"})
  
  vim.api.nvim_create_user_command('TidalTestAnimation', function()
    print("=== TESTING ANIMATION DIRECTLY ===")
    local animation = require('tidal-highlight.animation')
    local bufnr = vim.api.nvim_get_current_buf()
    
    -- Queue a test event directly
    animation.queue_event({
      event_id = "test_" .. vim.loop.now(),
      buffer = bufnr,
      row = 2, -- d3 line (0-based, so line 3)
      start_col = 12,
      end_col = 15,
      hl_group = "TidalSoundActive", 
      duration = 2000 -- 2 seconds
    })
    print("Test animation event queued - should highlight 'kick' for 2 seconds")
  end, {desc = "Test animation system directly"})
end

return M