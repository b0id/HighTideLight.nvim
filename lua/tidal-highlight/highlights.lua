-- ~/.config/nvim/lua/tidal-highlight/highlights.lua
local M = {}

-- Structure to hold active highlights with timing
M.active_highlights = {}
-- Namespace for extmarks
M.namespace = vim.api.nvim_create_namespace('tidal_highlights')

-- Add highlight for an event with proper decay timing (Pulsar-style animation)
function M.add_highlight(event_data)
  local buffer = event_data.buffer
  local row = event_data.row
  local start_col = event_data.start_col
  local end_col = event_data.end_col
  local event_id = event_data.event_id
  local base_hl_group = event_data.hl_group or "TidalSoundActive"
  local duration = event_data.duration or 500 -- Duration in milliseconds

  -- Ensure buffer is valid
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end

  -- Remove any existing highlight for this event_id first
  M.remove_highlight(event_id)

  -- Create initial bright highlight
  local mark_id = vim.api.nvim_buf_set_extmark(buffer, M.namespace, row, start_col, {
    end_row = row,
    end_col = end_col,
    hl_group = base_hl_group,
    priority = 100,
    strict = false,
  })

  -- Store in active highlights with fade animation data
  M.active_highlights[event_id] = {
    mark_id = mark_id,
    buffer = buffer,
    row = row,
    start_col = start_col,
    end_col = end_col,
    base_hl_group = base_hl_group,
    birth_time = vim.loop.now(),
    death_time = vim.loop.now() + duration,
    fade_stage = 0  -- Track fade progression
  }

  -- Animate decay over duration with fade stages
  local fade_steps = 5
  local decay_time = duration / fade_steps
  
  for i = 1, fade_steps do
    vim.defer_fn(function()
      local highlight = M.active_highlights[event_id]
      if highlight and vim.api.nvim_buf_is_valid(highlight.buffer) then
        -- Delete old extmark
        pcall(vim.api.nvim_buf_del_extmark, highlight.buffer, M.namespace, highlight.mark_id)
        
        if i < fade_steps then
          -- Create faded highlight
          local fade_group = base_hl_group .. "_fade_" .. i
          local new_mark_id = vim.api.nvim_buf_set_extmark(highlight.buffer, M.namespace, highlight.row, highlight.start_col, {
            end_row = highlight.row,
            end_col = highlight.end_col,
            hl_group = fade_group,
            priority = 100 - i,  -- Lower priority as it fades
            strict = false,
          })
          highlight.mark_id = new_mark_id
          highlight.fade_stage = i
        else
          -- Final stage - remove completely
          M.active_highlights[event_id] = nil
        end
      end
    end, i * decay_time)
  end
end

-- Remove highlight immediately
function M.remove_highlight(event_id)
  local highlight = M.active_highlights[event_id]
  if not highlight then return end

  if vim.api.nvim_buf_is_valid(highlight.buffer) then
    pcall(vim.api.nvim_buf_del_extmark, highlight.buffer, M.namespace, highlight.mark_id)
  end

  M.active_highlights[event_id] = nil
end

-- Update highlights each frame (called by animation loop)
function M.update_frame()
  local now = vim.loop.now()
  local expired_events = {}
  
  for event_id, highlight in pairs(M.active_highlights) do
    if now >= highlight.death_time then
      table.insert(expired_events, event_id)
    end
  end
  
  -- Remove expired highlights
  for _, event_id in ipairs(expired_events) do
    M.remove_highlight(event_id)
  end
end

-- Clear highlights for a specific line (immediate)
function M.clear_line(buffer, row)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  
  -- Find and remove highlights on this line
  for event_id, highlight in pairs(M.active_highlights) do
    if highlight.buffer == buffer and highlight.row == row then
      M.remove_highlight(event_id)
    end
  end
end

-- Clear all highlights immediately
function M.clear_all()
  for event_id, _ in pairs(M.active_highlights) do
    M.remove_highlight(event_id)
  end
end

-- Get count of active highlights (for debugging)
function M.get_active_count()
  local count = 0
  for _ in pairs(M.active_highlights) do
    count = count + 1
  end
  return count
end

return M