-- ~/.config/nvim/lua/tidal-highlight/highlights.lua
local M = {}

-- Nested structure: buffer -> row -> col -> marker
M.markers = {}
-- Map: event_id -> buffer -> col -> marker
M.highlights = {}
-- Namespace for extmarks
M.namespace = vim.api.nvim_create_namespace('tidal_highlights')

-- Current frame's events
M.current_frame_events = {}
M.previous_frame_events = {}

-- Add highlight for an event
function M.add_highlight(event_data)
  local buffer = event_data.buffer
  local row = event_data.row
  local start_col = event_data.start_col
  local end_col = event_data.end_col
  local event_id = event_data.event_id
  local hl_group = event_data.hl_group or "TidalEvent1"
  
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
  
  -- Store in structures
  if not M.markers[buffer] then M.markers[buffer] = {} end
  if not M.markers[buffer][row] then M.markers[buffer][row] = {} end
  if not M.markers[buffer][row][start_col] then 
    M.markers[buffer][row][start_col] = {}
  end
  
  M.markers[buffer][row][start_col] = {
    mark_id = mark_id,
    event_id = event_id,
    end_col = end_col
  }
  
  if not M.highlights[event_id] then M.highlights[event_id] = {} end
  if not M.highlights[event_id][buffer] then M.highlights[event_id][buffer] = {} end
  M.highlights[event_id][buffer][start_col] = mark_id
  
  -- Track in current frame
  M.current_frame_events[event_id] = true
end

-- Remove highlight
function M.remove_highlight(event_id)
  if not M.highlights[event_id] then return end
  
  for buffer, cols in pairs(M.highlights[event_id]) do
    if vim.api.nvim_buf_is_valid(buffer) then
      for _, mark_id in pairs(cols) do
        vim.api.nvim_buf_del_extmark(buffer, M.namespace, mark_id)
      end
    end
  end
  
  M.highlights[event_id] = nil
end

-- Diff and update highlights (called each frame)
function M.update_frame()
  -- Remove highlights that are no longer present
  for event_id, _ in pairs(M.previous_frame_events) do
    if not M.current_frame_events[event_id] then
      M.remove_highlight(event_id)
    end
  end
  
  -- Swap frames
  M.previous_frame_events = M.current_frame_events
  M.current_frame_events = {}
end

-- Clear highlights for a specific line
function M.clear_line(buffer, row)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  
  -- Clear extmarks for this line
  vim.api.nvim_buf_clear_namespace(buffer, M.namespace, row, row + 1)
  
  -- Clean up our data structures
  if M.markers[buffer] and M.markers[buffer][row] then
    M.markers[buffer][row] = nil
  end
end

-- Clear all highlights
function M.clear_all()
  for buffer, _ in pairs(M.markers) do
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_clear_namespace(buffer, M.namespace, 0, -1)
    end
  end
  
  M.markers = {}
  M.highlights = {}
  M.current_frame_events = {}
  M.previous_frame_events = {}
end

return M