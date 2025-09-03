-- Rendering module for tidal-highlights.nvim
-- Implements extmark-based highlighting as identified in research

local M = {}
local state = require('tidal-highlights.state')

-- Namespace for our extmarks
local ns = vim.api.nvim_create_namespace('tidal-highlights')

-- Add a highlight with automatic cleanup
function M.add_highlight(stream_id, start_row, start_col, end_row, end_col, duration_ms)
  local buf = vim.api.nvim_get_current_buf()
  
  -- Validate buffer bounds
  local line_count = vim.api.nvim_buf_line_count(buf)
  if start_row >= line_count or end_row >= line_count then
    return
  end
  
  -- Choose highlight group based on stream ID
  local hl_group = "TidalHighlight" .. ((stream_id % 4) + 1)
  
  -- Create extmark with highlight
  local extmark_id = vim.api.nvim_buf_set_extmark(buf, ns, start_row, start_col, {
    end_row = end_row,
    end_col = end_col,
    hl_group = hl_group,
    priority = 100  -- High priority to override other highlights
  })
  
  -- Create timer for automatic cleanup
  local timer = vim.loop.new_timer()
  timer:start(duration_ms, 0, vim.schedule_wrap(function()
    state.remove_highlight(buf, start_row, extmark_id)
  end))
  
  -- Add to state tracking
  state.add_highlight(buf, start_row, extmark_id, timer)
  
  return extmark_id
end

-- Clear all highlights in a buffer
function M.clear_buffer(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end

-- Get all active extmarks (for debugging)
function M.get_active_extmarks(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
end

return M