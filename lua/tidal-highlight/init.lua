-- ~/.config/nvim/lua/tidal-highlight/init.lua
local config = require('tidal-highlight.config')
local osc = require('tidal-highlight.osc')
local processor = require('tidal-highlight.processor')
local highlights = require('tidal-highlight.highlights')
local animation = require('tidal-highlight.animation')

local M = {}
M.enabled = false

-- Hook into Tidal API to catch ALL evaluation types (not just send_line)
local function wrap_tidal_api()
  -- Check if tidal.nvim is available
  local ok, tidal = pcall(require, 'tidal')
  if not ok or not tidal.api then
    if config.current.debug then
      vim.notify("HighTideLight: tidal.nvim API not found, falling back to compat layer", vim.log.levels.WARN)
    end
    return wrap_tidal_send_fallback()
  end
  
  local api = tidal.api
  
  -- Store original functions
  local orig_send = api.send
  local orig_send_multiline = api.send_multiline
  
  -- Hook api.send (single line evaluations)
  api.send = function(text)
    if M.enabled then
      if config.current.debug then
        vim.notify("[HighTideLight] API HOOK: send() called with: " .. text:sub(1, 50), vim.log.levels.INFO, {timeout = 1000})
      end
      M.ingest_tidal_text(text)
    end
    return orig_send(text)
  end
  
  -- Hook api.send_multiline (block evaluations)
  api.send_multiline = function(lines)
    if M.enabled then
      local block = table.concat(lines, "\n")
      if config.current.debug then
        vim.notify("[HighTideLight] API HOOK: send_multiline() called with: " .. block:sub(1, 50), vim.log.levels.INFO, {timeout = 1000})
      end
      M.ingest_tidal_text(block)
    end
    return orig_send_multiline(lines)
  end
  
  if config.current.debug then
    vim.notify("HighTideLight: Hooked tidal.nvim API (send + send_multiline)", vim.log.levels.INFO)
  end
  
  return true
end

-- Fallback to compatibility layer if tidal.nvim API unavailable
local function wrap_tidal_send_fallback()
  local compat = require('tidal-highlight.compat')
  
  local success, result = compat.hook_tidal_evaluation(function(buffer, line_num, code)
    if M.enabled then
      M.ingest_tidal_text(code)
    end
  end)
  
  if not success then
    if config.current.debug then
      vim.notify("HighTideLight: " .. result, vim.log.levels.WARN)
    end
    return false
  end
  
  return true
end

-- Process incoming Tidal text (from API hooks or compat layer)
function M.ingest_tidal_text(text)
  local raw_text = text
  
  -- Strip GHCi wrappers (:{  :})
  text = text:gsub("^%s*:%{?%s*\n", "")
  text = text:gsub("\n%s*:%}%s*$", "")
  
  -- Split into lines and find first pattern header
  local lines = {}
  for line in (text.."\n"):gmatch("(.-)\n") do 
    table.insert(lines, line) 
  end
  
  local pattern_info = M.find_pattern_header(lines)
  if not pattern_info then
    if config.current.debug then
      vim.notify("[HighTideLight] SKIP: no dN/p N header found in: " .. text:sub(1, 50), vim.log.levels.DEBUG, {timeout = 1000})
    end
    return
  end
  
  -- Compute orbit (what SuperCollider actually reports)
  local stream_id = pattern_info.n
  local orbit_override = M.find_orbit_hint(text)
  local orbit = orbit_override or (stream_id - 1)  -- default: d1=0, d2=1, etc.
  
  -- Process the pattern text
  local processed, event_id = processor.process_line(1, 1, text)
  
  if processed ~= text then
    local event_info = processor.get_event_info(event_id)
    if event_info and event_info.markers then
      
      -- Store by ORBIT (what SuperDirt reports) not eventId
      M.pattern_store = M.pattern_store or {}
      M.pattern_store[orbit] = {
        stream_id = stream_id,
        event_id = event_id,
        text = text,
        raw_text = raw_text,
        markers = event_info.markers,
        buffer = vim.api.nvim_get_current_buf(),
        row = vim.api.nvim_win_get_cursor(0)[1] - 1,  -- 0-indexed row
        timestamp = vim.loop.now()
      }
      
      -- Send to SuperCollider with orbit as key
      osc.send("/tidal/pattern", 
               {orbit, text, event_info.col_offset or 0}, 
               config.current.supercollider.ip, 
               config.current.supercollider.port)
      
      -- Send individual sound positions
      for i, marker in ipairs(event_info.markers) do
        if marker.type == "sound" then
          osc.send("/tidal/sound_position", 
                   {orbit, marker.word, marker.start_col, marker.end_col}, 
                   config.current.supercollider.ip, 
                   config.current.supercollider.port)
        end
      end
      
      if config.current.debug then
        vim.notify(string.format("[HighTideLight] Stored pattern: orbit=%d stream=d%d sounds=%d", 
                  orbit, stream_id, #event_info.markers), vim.log.levels.INFO, {timeout = 1000})
      end
    end
  end
end

-- Find first pattern header in lines (dN or p N)
function M.find_pattern_header(lines)
  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$") or line
    
    -- dN form: d1, d2, etc.
    local dN = trimmed:match("^d(%d+)%f[%W]")
    if dN then 
      return {kind="d", n=tonumber(dN), line=line} 
    end
    
    -- p N form: p 1, p 2, etc.
    local pN = trimmed:match("^p%s+(%d+)%f[%W]")
    if pN then 
      return {kind="p", n=tonumber(pN), line=line} 
    end
  end
  return nil
end

-- Find orbit override hint (# orbit N)
function M.find_orbit_hint(text)
  local hit = text:match("#%s*orbit%s+([%d]+)")
  return hit and tonumber(hit) or nil
end

-- Handle incoming OSC highlight events with precise position mapping
local function handle_osc_highlight(args, address)
  -- ALWAYS log OSC reception for debugging
  vim.notify(string.format("[HighTideLight] OSC RECEIVED: %s with %d args: %s", 
    address, #args, vim.inspect(args)), vim.log.levels.INFO, {timeout = 3000})
  
  if config.current.debug then
    -- Make debug messages transient (disappear after 2 seconds)
    vim.notify(string.format("[HighTideLight] OSC %s: %s", address, vim.inspect(args)), vim.log.levels.DEBUG, {timeout = 2000})
  end
  
  -- Handle both old 4-arg and new 6-arg formats
  if #args == 6 then
    -- NEW 6-argument format: [streamId, delta, cycle, colStart, eventId, colEnd]
    -- This matches what SuperCollider actually sends
    local stream_id = args[1]      -- orbit (d1=0, d2=1, etc)
    local duration = (args[2] * 1000) or 500  -- Convert delta to milliseconds
    local cycle = args[3]          -- cycle
    local col_start = args[4]      -- start column (already 0-indexed from processor)
    local event_id = args[5]       -- event ID from SuperDirt
    local col_end = args[6]        -- end column (already 0-indexed from processor)
    
    if config.current.debug then
      vim.notify(string.format("[HighTideLight] 6-arg PRECISION: stream=%d eventId=%d cols=%d-%d", 
        stream_id, event_id, col_start, col_end), vim.log.levels.INFO, {timeout = 2000})
    end
    
    -- Find the event info by orbit in our pattern store
    if M.pattern_store and M.pattern_store[stream_id] then
      local stored_pattern = M.pattern_store[stream_id]
      
      -- Create animation event
      local hl_index = (stream_id % #config.current.highlights.groups) + 1
      local hl_group = config.current.highlights.groups[hl_index].name
      
      animation.queue_event({
        event_id = "precision_" .. stream_id .. "_" .. col_start .. "_" .. vim.loop.now(),
        buffer = stored_pattern.buffer or vim.api.nvim_get_current_buf(),
        row = stored_pattern.row or 0,  -- We'll need to track this better
        start_col = col_start,
        end_col = col_end,
        hl_group = hl_group,
        duration = duration
      })
      
      if config.current.debug then
        vim.notify(string.format("[HighTideLight] PRECISION highlight applied: orbit=%d cols=%d-%d", 
          stream_id, col_start, col_end), vim.log.levels.INFO, {timeout = 1000})
      end
    else
      if config.current.debug then
        vim.notify(string.format("[HighTideLight] No pattern store for orbit: %d", stream_id), 
          vim.log.levels.WARN, {timeout = 2000})
      end
    end
    
  elseif #args == 5 then
    -- NEW 5-argument stream-correlated format: [streamId, sound, delta, cycle, superdirtEventId]
    local stream_id = args[1]    -- d1=0, d2=1, etc.
    local sound = tostring(args[2])
    local duration = (args[3] * 1000) or 500  -- Convert delta to milliseconds
    local cycle = args[4]
    local superdirt_event_id = args[5]
    
    if config.current.debug then
      vim.notify(string.format("[HighTideLight] 5-arg stream-correlated: stream=%d sound='%s'", 
        stream_id, sound), vim.log.levels.INFO, {timeout = 2000})
    end
    
    -- Find most recent pattern for this stream
    local event_info = nil
    local most_recent_time = 0
    
    for stored_event_id, stored_info in pairs(processor.event_ids or {}) do
      if stored_info.stream_id == stream_id and stored_info.timestamp > most_recent_time then
        most_recent_time = stored_info.timestamp
        event_info = stored_info
      end
    end
    
    if event_info then
      -- Find and highlight the specific sound in markers
      for i, marker in ipairs(event_info.markers) do
        if marker.word == sound and marker.type == "sound" then
          local hl_index = ((stream_id) % #config.current.highlights.groups) + 1
          local hl_group = config.current.highlights.groups[hl_index].name
          
          animation.queue_event({
            event_id = "stream_" .. stream_id .. "_" .. sound .. "_" .. superdirt_event_id,
            buffer = event_info.buffer,
            row = event_info.row,
            start_col = marker.start_col - 1,  -- Convert to 0-indexed
            end_col = marker.end_col - 1,
            hl_group = hl_group,
            duration = duration
          })
          
          if config.current.debug then
            vim.notify(string.format("[HighTideLight] ✨ PRECISION HIT! stream=%d sound='%s' cols=%d-%d", 
              stream_id, sound, marker.start_col - 1, marker.end_col - 1), vim.log.levels.INFO, {timeout = 2000})
          end
          return
        end
      end
      
      if config.current.debug then
        vim.notify(string.format("[HighTideLight] Sound '%s' not found in stream %d pattern", 
          sound, stream_id), vim.log.levels.WARN, {timeout = 2000})
      end
    else
      if config.current.debug then
        vim.notify(string.format("[HighTideLight] No pattern data for stream %d", 
          stream_id), vim.log.levels.WARN, {timeout = 2000})
      end
    end
    
  elseif #args == 4 then
    -- LEGACY 4-argument format: [eventId, sound, delta, 1] - maintain compatibility
    local event_id = args[1]
    local sound = tostring(args[2])
    local duration = (args[3] * 1000) or 500  -- Convert delta to milliseconds
    
    if config.current.debug then
      vim.notify(string.format("[HighTideLight] Legacy 4-arg sound-based highlight: %s", sound), 
        vim.log.levels.INFO, {timeout = 2000})
    end
    
    -- NEW: Find event info by stream correlation instead of event ID
    local event_info = nil
    local stream_id = 0  -- d1 = 0, d2 = 1, etc.
    
    -- First try direct event ID lookup
    event_info = processor.get_event_info(event_id)
    
    -- If not found, find most recent pattern for this stream
    if not event_info then
      local processor_module = processor
      local most_recent_time = 0
      
      for stored_event_id, stored_info in pairs(processor_module.event_ids or {}) do
        if stored_info.stream_id == stream_id and stored_info.timestamp > most_recent_time then
          most_recent_time = stored_info.timestamp
          event_info = stored_info
        end
      end
    end
    
    if not event_info then 
      -- Create a fallback highlight on current line
      local buffer = vim.api.nvim_get_current_buf()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1] - 1
      local line_content = vim.api.nvim_buf_get_lines(buffer, row, row + 1, false)[1] or ""
      
      -- Find the sound in the current line
      local sound_start, sound_end = line_content:find(sound, 1, true)
      if sound_start then
        local hl_index = ((event_id - 1) % #config.current.highlights.groups) + 1
        local hl_group = config.current.highlights.groups[hl_index].name
        
        animation.queue_event({
          event_id = "fallback_" .. event_id .. "_" .. sound,
          buffer = buffer,
          row = row,
          start_col = sound_start - 1,  -- 0-indexed
          end_col = sound_end - 1,
          hl_group = hl_group,
          duration = duration
        })
        
        if config.current.debug then
          vim.notify(string.format("[HighTideLight] Fallback highlight applied for: %s", sound), 
            vim.log.levels.INFO, {timeout = 2000})
        end
      end
      return
    end
    
    -- Find and highlight the specific sound in markers (existing logic)
    for i, marker in ipairs(event_info.markers) do
      if marker.word == sound and marker.type == "sound" then
        local hl_index = ((i - 1) % #config.current.highlights.groups) + 1
        local hl_group = config.current.highlights.groups[hl_index].name
        
        animation.queue_event({
          event_id = event_id .. "_" .. sound .. "_" .. i,
          buffer = event_info.buffer,
          row = event_info.row,
          start_col = marker.start_col - 1,  -- Convert to 0-indexed
          end_col = marker.end_col - 1,
          hl_group = hl_group,
          duration = duration
        })
        
        if config.current.debug then
          vim.notify(string.format("[HighTideLight] Marker-based highlight: %s", sound), vim.log.levels.INFO, {timeout = 2000})
        end
        return
      end
    end
    
  elseif #args == 6 then
    -- Future Pulsar format: [id, duration, cycle, colStart, eventId, colEnd]
    local stream_id = args[1]        -- d1=1, d2=2, etc
    local duration = args[2] * 1000  -- Convert to milliseconds
    local cycle = args[3]
    local col_start = args[4]
    local event_id = args[5]         -- Event ID from deltaContext
    local col_end = args[6]
    
    -- Get event info from processor
    local event_info = processor.get_event_info(event_id)
    if not event_info then 
      if config.current.debug then
        vim.notify("[HighTideLight] No event info for ID: " .. tostring(event_id), vim.log.levels.WARN, {timeout = 2000})
      end
      return
    end
    
    -- Calculate actual column positions using the stored offset
    local actual_start = event_info.col_offset + col_start
    local actual_end = event_info.col_offset + col_end
    
    -- Choose highlight group based on stream ID
    local hl_index = ((stream_id - 1) % #config.current.highlights.groups) + 1
    local hl_group = config.current.highlights.groups[hl_index].name
    
    -- Queue the precise highlight
    animation.queue_event({
      event_id = event_id .. "_" .. col_start .. "_" .. col_end,
      buffer = event_info.buffer,
      row = event_info.row,
      start_col = math.max(0, actual_start),
      end_col = math.min(#event_info.original_text, actual_end),
      hl_group = hl_group,
      duration = duration
    })
  else
    if config.current.debug then
      vim.notify("[HighTideLight] Invalid OSC args count: " .. #args, vim.log.levels.WARN, {timeout = 2000})
    end
  end
end

-- Setup function
function M.setup(opts)
  -- Configure
  local cfg = config.setup(opts)
  
  if not cfg.enabled then
    return
  end
  
  M.enabled = true
  
  -- Start OSC server
  osc.start(cfg)
  
  -- Register OSC handler
  osc.on("/editor/highlight", handle_osc_highlight)
  
  -- Start animation loop
  animation.start(cfg)
  
  -- Hook into Tidal
  vim.defer_fn(function()
    wrap_tidal_api()
  end, 100)
  
  -- Commands
  vim.api.nvim_create_user_command('TidalHighlightToggle', function()
    M.enabled = not M.enabled
    if M.enabled then
      osc.start(cfg)
      animation.start(cfg)
      print("Tidal highlighting enabled")
    else
      highlights.clear_all()
      osc.stop()
      animation.stop()
      print("Tidal highlighting disabled")
    end
  end, {})
  
  vim.api.nvim_create_user_command('TidalHighlightClear', function()
    highlights.clear_all()
  end, {})
  
  vim.api.nvim_create_user_command('TidalHighlightTest', function()
    -- Test highlight on current line
    local buffer = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    animation.queue_event({
      event_id = "test_" .. os.time(),
      buffer = buffer,
      row = cursor[1] - 1,
      start_col = 0,
      end_col = 30,
      hl_group = "TidalSoundActive",
      duration = 1000
    })
    print("HighTideLight: Test highlight applied")
  end, {})

  vim.api.nvim_create_user_command('TidalHighlightOSCTest', function()
    -- Test OSC communication by sending a test message to ourselves
    local test_args = {999, "test", 500, 1}
    handle_osc_highlight(test_args, "/editor/highlights")
    print("HighTideLight: OSC test message processed (4-arg legacy)")
  end, {})
  
  vim.api.nvim_create_user_command('TidalHighlight6ArgTest', function()
    -- Test new 6-argument format
    local test_args = {0, 0.5, 1, 10, 999, 15}  -- [streamId, duration, cycle, colStart, eventId, colEnd]
    handle_osc_highlight(test_args, "/editor/highlights")
    print("HighTideLight: 6-argument OSC test processed")
  end, {})
  
  vim.api.nvim_create_user_command('TidalHighlightStatus', function()
    local active_count = highlights.get_active_count()
    local debug_status = cfg.debug and "ON" or "OFF"
    print(string.format("HighTideLight: %s | Active highlights: %d | Debug: %s", 
          M.enabled and "ENABLED" or "DISABLED", active_count, debug_status))
  end, {})
  
  vim.api.nvim_create_user_command('TidalHighlightDebug', function()
    local debug_module = require('tidal-highlight.debug')
    debug_module.show_loaded_files()
  end, {})
  
  vim.api.nvim_create_user_command('TidalHighlightDebugPipeline', function()
    print("=== HighTideLight Debug Pipeline ===")
    
    -- Test processor
    local buffer = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line_content = vim.api.nvim_buf_get_lines(buffer, cursor[1] - 1, cursor[1], false)[1] or ""
    
    print("Current line: " .. line_content)
    
    if line_content:match("^d%d+") then
      local processed, event_id = processor.process_line(buffer, cursor[1], line_content)
      print("Processed line: " .. processed)
      print("Event ID: " .. event_id)
      
      local event_info = processor.get_event_info(event_id)
      if event_info then
        print("Event info stored: " .. vim.inspect(event_info))
        print("Column offset: " .. (event_info.col_offset or "nil"))
        print("Injection offset: " .. (event_info.injection_offset or "nil"))
      end
    else
      print("Line doesn't match Tidal pattern (d1, d2, etc.)")
    end
    
    print("Active highlights: " .. highlights.get_active_count())
    print("=== End Debug ===")
  end, {})
  
  vim.api.nvim_create_user_command('TidalHighlightReload', function()
    local debug_module = require('tidal-highlight.debug')
    debug_module.reload_plugin()
  end, {})
  
  vim.api.nvim_create_user_command('TidalHighlightDiagnostics', function()
    local diagnostics = require('tidal-highlight.diagnostics')
    diagnostics.run_diagnostics()
  end, {desc = "Run HighTideLight diagnostics"})
  
  -- Debug command from Pulsar notes
  vim.api.nvim_create_user_command('TidalHighlightDebugEvents', function()
    -- Show current event mappings
    print("Event mappings:")
    print(vim.inspect(processor.event_ids))
    
    -- Show active highlights
    print("Active highlights:")
    print(vim.inspect(highlights.active_highlights))
  end, {desc = "Debug current event mappings and highlights"})

  -- Simulate OSC message for testing
  vim.api.nvim_create_user_command('TidalHighlightSimulate', function()
    -- Simulate Pulsar format: [id, duration, cycle, colStart, eventId, colEnd]
    local test_args = {1, 0.5, 1.0, 0, 1, 10}  -- Stream 1, 500ms duration, positions 0-10 in event 1
    handle_osc_highlight(test_args, "/editor/highlight")
    vim.notify("Simulated OSC highlight event", vim.log.levels.INFO, {timeout = 2000})
  end, {desc = "Simulate OSC highlight message for testing"})
  
  vim.api.nvim_create_user_command('TidalHighlightLine', function()
    -- Highlight ALL components in the current line (like Strudel)
    local buffer = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line_num = cursor[1]
    local line_content = vim.api.nvim_buf_get_lines(buffer, line_num - 1, line_num, false)[1]
    
    if not line_content or line_content == "" then
      vim.notify("No content on current line", vim.log.levels.WARN)
      return
    end
    
    -- Process the line to find ALL components
    local processed, event_id = processor.process_line(buffer, line_num, line_content)
    local event_info = processor.get_event_info(event_id)
    
    if not event_info or #event_info.markers == 0 then
      vim.notify("No Tidal components found on current line", vim.log.levels.INFO)
      return
    end
    
    -- Clear any existing highlights on this line first
    highlights.clear_line(buffer, line_num - 1)
    
    -- Highlight each component type with appropriate colors
    for i, marker in ipairs(event_info.markers) do
      local hl_group = "TidalSoundActive" -- Default
      
      -- Choose highlight based on component type
      if marker.type == "sound" then
        local active_groups = {"TidalSoundActive", "TidalSoundActive2", "TidalSoundActive3", "TidalSoundActive4"}
        hl_group = active_groups[((i - 1) % #active_groups) + 1]
      elseif marker.type == "function" then
        hl_group = "TidalFunction"
      elseif marker.type == "number" then
        hl_group = "TidalNumber"
      elseif marker.type == "operator" then
        hl_group = "TidalOperator"
      elseif marker.type == "quoted_string" then
        hl_group = "TidalQuotedString"
      elseif marker.type == "separator" then
        hl_group = "TidalSeparator"
      end
      
      -- Add slight delay for visual cascade effect
      vim.defer_fn(function()
        animation.queue_event({
          event_id = event_id .. "-preview-" .. i,
          buffer = buffer,
          row = line_num - 1, -- 0-indexed for Neovim
          start_col = marker.start_col - 1, -- 0-indexed for Neovim
          end_col = marker.end_col - 1,
          hl_group = hl_group,
          duration = 2000 -- Show for 2 seconds
        })
      end, i * 50) -- Stagger by 50ms
    end
    
    -- Show summary
    local by_type = {}
    for _, marker in ipairs(event_info.markers) do
      by_type[marker.type] = (by_type[marker.type] or 0) + 1
    end
    
    local summary_parts = {}
    for type_name, count in pairs(by_type) do
      table.insert(summary_parts, count .. " " .. type_name .. (count > 1 and "s" or ""))
    end
    
    vim.notify(string.format("Highlighted %d components: %s", 
              #event_info.markers, 
              table.concat(summary_parts, ", ")), 
              vim.log.levels.INFO)
  end, {desc = "Highlight ALL Tidal components in current line (like Strudel)"})
  
  vim.api.nvim_create_user_command('TidalHighlightPlay', function()
    -- Simulate real-time pattern playback highlighting
    local buffer = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line_num = cursor[1]
    local line_content = vim.api.nvim_buf_get_lines(buffer, line_num - 1, line_num, false)[1]
    
    if not line_content or line_content == "" then
      vim.notify("No content on current line", vim.log.levels.WARN)
      return
    end
    
    -- Process the line to find patterns
    local processed, event_id = processor.process_line(buffer, line_num, line_content)
    local event_info = processor.get_event_info(event_id)
    
    if not event_info or #event_info.markers == 0 then
      vim.notify("No Tidal patterns found on current line", vim.log.levels.INFO)
      return
    end
    
    -- Clear any existing highlights
    highlights.clear_line(buffer, line_num - 1)
    
    vim.notify("Playing pattern with " .. #event_info.markers .. " sounds...", vim.log.levels.INFO)
    
    -- Create sequential highlights with timing (like Strudel)
    for i, marker in ipairs(event_info.markers) do
      local delay = (i - 1) * 600 -- 600ms between highlights (adjust for tempo)
      local hl_group_index = ((i - 1) % #config.current.highlights.groups) + 1
      local hl_group = config.current.highlights.groups[hl_group_index].name
      
      vim.defer_fn(function()
        -- Clear previous highlight
        if i > 1 then
          animation.queue_event({
            event_id = event_id + i - 1,
            buffer = buffer,
            row = line_num - 1,
            start_col = 0,
            end_col = 0,
            hl_group = "Normal", -- Clear previous
            duration = 0
          })
        end
        
        -- Add current highlight
        animation.queue_event({
          event_id = event_id + i + 100,
          buffer = buffer,
          row = line_num - 1,
          start_col = marker.start_col - 1,
          end_col = marker.end_col - 1,
          hl_group = hl_group
        })
        
        -- Show which sound is playing
        vim.notify("♪ " .. marker.word .. " (" .. marker.type .. ")", vim.log.levels.INFO)
        
      end, delay)
    end
    
  end, {desc = "Simulate Tidal pattern playback with sequential highlighting"})
  
  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if M.enabled then
        osc.stop()
        animation.stop()
      end
    end
  })

  -- Debug commands
  vim.api.nvim_create_user_command('TidalHighlightDebugPipeline', function()
    -- Test the orbit-based pipeline
    M.ingest_tidal_text('d1 $ sound "bd sn hh"')
    vim.notify("[HighTideLight] Debug pipeline triggered", vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command('TidalHighlightDebugAPI', function()
    local ok, tidal = pcall(require, 'tidal')
    if ok and tidal.api then
      vim.notify("[HighTideLight] tidal.nvim API available: " .. vim.inspect(vim.tbl_keys(tidal.api)), vim.log.levels.INFO)
    else
      vim.notify("[HighTideLight] tidal.nvim API NOT available", vim.log.levels.WARN)
    end
  end, {})

  vim.api.nvim_create_user_command('TidalHighlightDebugState', function()
    vim.notify("=== HighTideLight Debug State ===", vim.log.levels.INFO)
    vim.notify("Enabled: " .. tostring(M.enabled), vim.log.levels.INFO)
    vim.notify("Pattern store: " .. vim.inspect(M.pattern_store or {}), vim.log.levels.INFO)
    vim.notify("OSC config: " .. vim.inspect(config.current.osc), vim.log.levels.INFO)
    vim.notify("SuperCollider config: " .. vim.inspect(config.current.supercollider), vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command('TidalHighlightDebugOSC', function()
    -- Send a test OSC message to SuperCollider
    local osc = require('tidal-highlight.osc')
    osc.send("/debug/test", {999, "test"}, config.current.supercollider.ip, config.current.supercollider.port)
    vim.notify("[HighTideLight] Sent test OSC to SuperCollider", vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command('TidalHighlightForceHighlight', function()
    -- Force a highlight on current line for testing
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local animation = require('tidal-highlight.animation')
    animation.queue_event({
      event_id = "test_" .. vim.loop.now(),
      buffer = vim.api.nvim_get_current_buf(),
      row = row,
      start_col = 0,
      end_col = 10,
      hl_group = "HighTideLightSound1",
      duration = 1000
    })
    vim.notify("[HighTideLight] Forced test highlight on current line", vim.log.levels.INFO)
  end, {})
end

return M