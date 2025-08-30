-- ~/.config/nvim/lua/tidal-highlight/init.lua
local config = require('tidal-highlight.config')
local osc = require('tidal-highlight.osc')
local processor = require('tidal-highlight.processor')
local highlights = require('tidal-highlight.highlights')
local animation = require('tidal-highlight.animation')

local M = {}
M.enabled = false

-- Hook into Tidal evaluation
local function wrap_tidal_send()
  local tidal = require('tidal')
  if not tidal then return end
  
  -- Store original send function
  local original_send = tidal.send or tidal.send_line
  if not original_send then return end
  
  -- Wrap the send function
  local wrapper = function(lines, ...)
    if not M.enabled then
      return original_send(lines, ...)
    end
    
    -- Get current buffer and cursor position
    local buffer = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line_num = cursor[1]
    
    -- Process lines if it's a pattern evaluation
    local processed_lines = {}
    for i, line in ipairs(lines) do
      local processed, event_id = processor.process_line(
        buffer, 
        line_num + i - 1, 
        line
      )
      table.insert(processed_lines, processed)
    end
    
    -- Send processed lines
    return original_send(processed_lines, ...)
  end
  
  -- Replace the function
  if tidal.send then
    tidal.send = wrapper
  else
    tidal.send_line = wrapper
  end
end

-- Handle incoming OSC highlight events
local function handle_osc_highlight(args)
  -- Expected args: [event_id, buffer_id, row, start_col, end_col, duration, cycle, ...]
  if #args < 5 then return end
  
  local event_id = args[1]
  local buffer_id = args[2]
  local row = args[3]
  local start_col = args[4]
  local end_col = args[5]
  
  -- Get event info from processor
  local event_info = processor.get_event_info(event_id)
  if not event_info then
    -- Fallback to buffer_id if we don't have the event
    event_info = {
      buffer = buffer_id,
      row = row
    }
  end
  
  -- Choose highlight group based on cycle or event_id
  local hl_index = (event_id % #config.current.highlights.groups) + 1
  local hl_group = config.current.highlights.groups[hl_index].name
  
  -- Queue the highlight
  animation.queue_event({
    event_id = event_id,
    buffer = event_info.buffer,
    row = event_info.row,
    start_col = start_col,
    end_col = end_col,
    hl_group = hl_group
  })
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
    highlights.clear_all()
  end, {})
  
  vim.api.nvim_create_user_command('TidalHighlightTest', function()
    -- Test highlight on current line
    local buffer = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    animation.queue_event({
      event_id = 999,
      buffer = buffer,
      row = cursor[1] - 1,
      start_col = 0,
      end_col = 30,
      hl_group = "TidalEvent1"
    })
  end, {})
  
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