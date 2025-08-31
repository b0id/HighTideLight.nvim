-- ~/.config/nvim/lua/tidal-highlight/highlights.lua
local M = {}

-- Structure to hold active highlights
M.active_highlights = {}
-- Namespace for extmarks
M.namespace = vim.api.nvim_create_namespace('tidal_highlights')

-- Add highlight for an event
function M.add_highlight(event_data)
  local buffer = event_data.buffer
  local row = event_data.row
  local start_col = event_data.start_col
  local end_col = event_data.end_col
  local event_id = event_data.event_id
  local hl_group = event_data.hl_group or "TidalEvent1"
  local duration = event_data.duration or 0.2 -- Default duration

  -- Ensure buffer is valid
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end

  -- Create extmark
  local mark_id = vim.api.nvim_buf_set_extmark(buffer, M.namespace, row, start_col, {
    end_row = row,
    end_col = end_col,
    hl_group = hl_group,
    priority = 100,
    strict = false,
  })

  -- Store in active highlights
  M.active_highlights[event_id] = {
    mark_id = mark_id,
    buffer = buffer,
    death_time = vim.loop.now() + (duration * 1000)
  }
end

-- Remove highlight
function M.remove_highlight(event_id)
  local highlight = M.active_highlights[event_id]
  if not highlight then return end

  if vim.api.nvim_buf_is_valid(highlight.buffer) then
    vim.api.nvim_buf_del_extmark(highlight.buffer, M.namespace, highlight.mark_id)
  end

  M.active_highlights[event_id] = nil
end

-- Update highlights (called each frame)
function M.update_frame()
  local now = vim.loop.now()
  for event_id, highlight in pairs(M.active_highlights) do
    if now > highlight.death_time then
      M.remove_highlight(event_id)
    end
  end
end

-- Clear highlights for a specific line
function M.clear_line(buffer, row)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  
  -- Clear extmarks for this line
  vim.api.nvim_buf_clear_namespace(buffer, M.namespace, row, row + 1)
end

-- Clear all highlights
function M.clear_all()
  for event_id, _ in pairs(M.active_highlights) do
    M.remove_highlight(event_id)
  end
end

return M