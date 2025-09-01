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
    
    -- Process the code
    local processed, event_id = processor.process_line(buffer, line_num, code)
    
    -- Send registration to SuperCollider if we have processed code
    if processed ~= code then
      -- Notify SuperCollider about this pattern
      osc.send("/tidal/register", 
               {event_id, code, "d1"}, 
               config.current.supercollider.ip, 
               config.current.supercollider.port)
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
  
  -- Handle both formats: current SC format [eventId, sound, delta, 1] and future Pulsar format
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
    print("HighTideLight: OSC test message processed")
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
end

return M