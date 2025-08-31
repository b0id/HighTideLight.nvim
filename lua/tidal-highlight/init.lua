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
      local osc_msg = string.format("/tidal/register %d %s d1", event_id, code:gsub('"', '\\"'))
      -- This would send to SuperCollider, but we need a different approach
      -- For now, just store the information
      vim.g.tidal_last_processed = {
        event_id = event_id,
        code = code,
        buffer = buffer,
        line = line_num
      }
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
  
  vim.api.nvim_create_user_command('TidalHighlightDiagnostics', function()
    local diagnostics = require('tidal-highlight.diagnostics')
    diagnostics.run_diagnostics()
  end, {desc = "Run HighTideLight diagnostics"})
  
  vim.api.nvim_create_user_command('TidalHighlightLine', function()
    -- Highlight patterns in the current line
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
    
    -- Clear any existing highlights on this line first
    highlights.clear_line(buffer, line_num - 1)
    
    -- Create highlight events for each pattern
    for i, marker in ipairs(event_info.markers) do
      local hl_group_index = ((i - 1) % #config.current.highlights.groups) + 1
      local hl_group = config.current.highlights.groups[hl_group_index].name
      
      animation.queue_event({
        event_id = event_id + i,
        buffer = buffer,
        row = line_num - 1, -- 0-indexed for Neovim
        start_col = marker.start_col - 1, -- 0-indexed for Neovim
        end_col = marker.end_col - 1,
        hl_group = hl_group
      })
      
      -- Stagger the highlights slightly for visual effect
      vim.defer_fn(function() end, i * 100)
    end
    
    vim.notify(string.format("Highlighted %d patterns: %s", 
              #event_info.markers, 
              table.concat(vim.tbl_map(function(m) return m.word end, event_info.markers), ", ")), 
              vim.log.levels.INFO)
  end, {desc = "Highlight Tidal patterns in current line"})
  
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