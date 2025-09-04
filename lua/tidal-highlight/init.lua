-- ~/.config/nvim/lua/tidal-highlight/init.lua
local config = require('tidal-highlight.config')
local osc = require('tidal-highlight.osc')
local processor = require('tidal-highlight.processor')
local highlights = require('tidal-highlight.highlights')
local animation = require('tidal-highlight.animation')

local M = {}
M.enabled = false

-- Hook into Tidal evaluation using compatibility layer
local function wrap_tidal_send()
  local compat = require('tidal-highlight.compat')
  
  local success, result = compat.hook_tidal_evaluation(function(buffer, line_num, code)
    if not M.enabled then return end
    
    -- Clear existing highlights on this line before processing
    processor.clear_line_highlights(buffer, line_num)
    
    -- Check if this is a hush/silence command
    if processor.is_hush_command(code) then
      processor.clear_all_highlights()
      if config.current.debug then
        vim.notify("[HighTideLight] Cleared all highlights (hush command)", vim.log.levels.INFO, {timeout = 2000})
      end
      return
    end
    
    -- Process the code
    local processed, event_id = processor.process_line(buffer, line_num, code)
    
    -- Send position data directly to Rust bridge if we have processed code
    if processed ~= code then
      local event_info = processor.get_event_info(event_id)
      if event_info and #event_info.markers > 0 then
        -- Send position data for each detected component to Rust bridge
        for _, marker in ipairs(event_info.markers) do
          if marker.type == "sound" then
            -- Extract stream from line (d1, d2, etc.)
            local stream_id = 1 -- Default to d1
            local stream_match = code:match("^d(%d+)")
            if stream_match then
              stream_id = tonumber(stream_match)
            end
            
            -- Send to Rust bridge in expected format: 
            -- [stream_id, start_row, start_col, end_row, end_col, duration]
            osc.send("/editor/highlights",
                     {stream_id, line_num, marker.start_col, line_num, marker.end_col, 0.5},
                     "127.0.0.1", 6013)
                     
            if config.current.debug then
              vim.notify(string.format("[HighTideLight] Sent to bridge: stream=%d, row=%d, cols=%d..%d", 
                        stream_id, line_num, marker.start_col, marker.end_col), vim.log.levels.INFO, {timeout = 2000})
            end
          end
        end
      end
    end
  end)
  
  if not success then
    if config.current.debug then
      vim.notify("HighTideLight: " .. result, vim.log.levels.WARN)
    end
    return false
  end
  
  if config.current.debug then
    vim.notify("HighTideLight: " .. result, vim.log.levels.INFO)
  end
  
  return true
end

-- Handle incoming OSC highlight events with precise position mapping
local function handle_osc_highlight(args, address)
  if config.current.debug then
    -- Make debug messages transient (disappear after 2 seconds)
    vim.notify(string.format("[HighTideLight] OSC %s: %s", address, vim.inspect(args)), vim.log.levels.DEBUG, {timeout = 2000})
  end
  
  -- Handle both formats: current SC format [eventId, sound, delta, 1] and new Tidal format
  if #args == 4 then
    -- Current SuperCollider format: [eventId, sound, delta, 1]
    local event_id = args[1]
    local sound = tostring(args[2])
    local duration = (args[3] * 1000) or 500  -- Convert delta to milliseconds
    
    if config.current.debug then
      vim.notify(string.format("[HighTideLight] Sound-based highlight: %s", sound), vim.log.levels.INFO, {timeout = 2000})
    end
    
    -- Get event info from processor
    local event_info = processor.get_event_info(event_id)
    if not event_info then 
      -- Create a fallback highlight on current line since we don't have deltaContext working yet
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
          vim.notify(string.format("[HighTideLight] Fallback highlight applied for: %s", sound), vim.log.levels.INFO, {timeout = 2000})
        end
      end
      return
    end
    
    -- Find and highlight the specific sound in markers
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
    -- New Tidal format from Rust bridge: [stream_id, duration, cycle, start_col, event_id, end_col]
    local stream_id = args[1]        -- d1=1, d2=2, etc
    local duration = args[2] * 1000  -- Convert to milliseconds
    local cycle = args[3]
    local start_col = args[4]
    local event_id = args[5]         -- Event ID from deltaContext
    local end_col = args[6]
    
    if config.current.debug then
      vim.notify(string.format("[HighTideLight] Position-based highlight: stream=%d, cols=%d..%d, duration=%.1fms", 
                stream_id, start_col, end_col, duration), vim.log.levels.INFO, {timeout = 2000})
    end
    
    -- Find the current Tidal buffer (look for .tidal files or tidalcycles filetype)
    local target_buffer = nil
    local target_row = 0
    
    -- Try to find open Tidal buffers
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
        local filetype = vim.api.nvim_buf_get_option(buf, 'filetype')
        local filename = vim.api.nvim_buf_get_name(buf)
        
        if filetype == 'haskell' or filetype == 'tidalcycles' or filename:match('%.tidal$') then
          target_buffer = buf
          -- For now, highlight on the current cursor line or line 1
          local windows = vim.fn.win_findbuf(buf)
          if #windows > 0 then
            local cursor = vim.api.nvim_win_get_cursor(windows[1])
            target_row = cursor[1] - 1  -- Convert to 0-indexed
          else
            target_row = 0  -- Default to first line
          end
          break
        end
      end
    end
    
    -- Fallback to current buffer if no Tidal buffer found
    if not target_buffer then
      target_buffer = vim.api.nvim_get_current_buf()
      local cursor = vim.api.nvim_win_get_cursor(0)
      target_row = cursor[1] - 1
    end
    
    -- Choose highlight group based on stream ID
    local hl_index = ((stream_id - 1) % 8) + 1  -- Support streams 1-8
    local hl_group = "TidalHighlight" .. hl_index
    
    -- Queue the precise highlight (convert 1-indexed Tidal to 0-indexed Neovim)
    animation.queue_event({
      event_id = string.format("tidal_%d_%d_%d_%d", stream_id, target_row, start_col, end_col),
      buffer = target_buffer,
      row = target_row,
      start_col = math.max(0, start_col - 1),  -- Convert to 0-indexed, ensure >= 0
      end_col = math.max(start_col, end_col - 1),  -- Ensure end >= start
      hl_group = hl_group,
      duration = duration
    })
    
    if config.current.debug then
      vim.notify(string.format("[HighTideLight] Applied position highlight: row=%d, cols=%d..%d", 
                target_row, start_col - 1, end_col - 1), vim.log.levels.INFO, {timeout = 2000})
    end
    
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
  osc.on("/editor/highlights", handle_osc_highlight)
  
  -- Start animation loop
  animation.start(cfg)
  
  -- Hook into Tidal
  vim.defer_fn(function()
    wrap_tidal_send()
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
    processor.clear_all_highlights()
  end, {})
  
  -- New command to clear highlights for current line only
  vim.api.nvim_create_user_command('TidalHighlightClearLine', function()
    local buffer = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    processor.clear_line_highlights(buffer, cursor[1])
    vim.notify("Cleared highlights for current line", vim.log.levels.INFO)
  end, {})
  
  -- Command to start the Rust OSC bridge
  vim.api.nvim_create_user_command('TidalHighlightStartBridge', function()
    local bridge_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h") .. "/tidal-osc-bridge/target/release/tidal-osc-bridge"
    
    if vim.fn.executable(bridge_path) == 0 then
      vim.notify("Rust bridge not found at: " .. bridge_path .. "\nPlease run: cd tidal-osc-bridge && cargo build --release", vim.log.levels.ERROR)
      return
    end
    
    -- Start the bridge in background
    local cmd = string.format("%s --port 6013 --neovim-port %d", bridge_path, cfg.osc.port)
    if cfg.debug then
      cmd = cmd .. " --debug"
    end
    
    vim.fn.jobstart(cmd, {
      on_stdout = function(_, data)
        if cfg.debug then
          for _, line in ipairs(data) do
            if line ~= "" then
              vim.notify("[Bridge] " .. line, vim.log.levels.INFO, {timeout = 3000})
            end
          end
        end
      end,
      on_stderr = function(_, data)
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.notify("[Bridge Error] " .. line, vim.log.levels.ERROR)
          end
        end
      end,
    })
    
    vim.notify("Started Tidal OSC bridge on port 6013 → " .. cfg.osc.port, vim.log.levels.INFO)
  end, {desc = "Start the Rust OSC bridge for Tidal highlights"})
  
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
    -- Test both OSC message formats
    vim.notify("Testing OSC communication...", vim.log.levels.INFO)
    
    -- Test new Tidal format: [stream_id, duration, cycle, start_col, event_id, end_col]
    local test_args_new = {1, 0.5, 1.0, 5, 999, 15}  -- Stream 1, 500ms, cols 5-15
    handle_osc_highlight(test_args_new, "/editor/highlights")
    
    -- Test legacy format for backward compatibility
    vim.defer_fn(function()
      local test_args_legacy = {999, "test", 0.5, 1}
      handle_osc_highlight(test_args_legacy, "/editor/highlights")
    end, 1000)
    
    vim.notify("OSC test messages sent (new format + legacy format)", vim.log.levels.INFO)
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
    -- Simulate new Tidal format with stream-specific highlights
    local buffer = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line_content = vim.api.nvim_buf_get_lines(buffer, cursor[1] - 1, cursor[1], false)[1] or ""
    
    if line_content == "" then
      vim.notify("No content on current line to highlight", vim.log.levels.WARN)
      return
    end
    
    -- Clear existing highlights on this line
    processor.clear_line_highlights(buffer, cursor[1])
    
    -- Create multiple highlights for different streams to show the effect
    local streams = {1, 2, 3, 4}
    local line_length = #line_content
    local segment_size = math.max(1, math.floor(line_length / #streams))
    
    for i, stream_id in ipairs(streams) do
      local start_col = (i - 1) * segment_size + 1
      local end_col = math.min(i * segment_size, line_length)
      
      -- Simulate OSC message: [stream_id, duration, cycle, start_col, event_id, end_col]
      local test_args = {stream_id, 1.0, 1.0, start_col, 1000 + i, end_col}
      
      vim.defer_fn(function()
        handle_osc_highlight(test_args, "/editor/highlights")
      end, (i - 1) * 200)  -- Stagger the highlights
    end
    
    vim.notify("Simulated multi-stream OSC highlight events on current line", vim.log.levels.INFO)
  end, {desc = "Simulate multi-stream OSC highlight messages for testing"})
  
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
end

return M