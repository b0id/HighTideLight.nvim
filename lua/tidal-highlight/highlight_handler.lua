-- lua/tidal-highlight/highlight_handler.lua
-- Handles OSC highlight messages with precise coordinate mapping and extmark-based rendering

local M = {}

-- Track active highlights for lifecycle management
local active_highlights = {}
local next_highlight_id = 1

-- Configuration
local HIGHLIGHT_GROUP = "TidalHighlightActive"
local NAMESPACE_ID = vim.api.nvim_create_namespace("tidal-highlight")

--- Creates or updates the highlight group
local function ensure_highlight_group()
  vim.api.nvim_set_hl(0, HIGHLIGHT_GROUP, {
    bg = "#4a90e2",
    fg = "#ffffff",
    bold = true
  })
end

--- Converts buffer coordinates to 0-based for extmarks
local function to_extmark_coords(line, col_start, col_end)
  return {
    line = line - 1,  -- Convert to 0-based
    col_start = col_start,
    col_end = col_end
  }
end

--- Finds buffer and line for a given sound/sample name using source map
local function find_sound_position(sound_name, source_maps)
  for bufnr, buf_source_maps in pairs(source_maps or {}) do
    for range_key, source_map in pairs(buf_source_maps or {}) do
      for unique_id, token_info in pairs(source_map) do
        if token_info.value == sound_name then
          return bufnr, token_info.range.start.line, token_info.range.start.col, token_info.range["end"].col
        end
      end
    end
  end
  return nil
end

--- Creates an extmark-based highlight with automatic cleanup
local function create_timed_highlight(bufnr, line, col_start, col_end, duration_seconds, unique_id)
  local coords = to_extmark_coords(line, col_start, col_end)
  
  -- Create the extmark
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE_ID, coords.line, coords.col_start, {
    end_col = coords.col_end,
    hl_group = HIGHLIGHT_GROUP,
    priority = 1000,
    strict = false  -- Don't error if position is invalid
  })
  
  local highlight_id = next_highlight_id
  next_highlight_id = next_highlight_id + 1
  
  -- Store highlight info for tracking
  active_highlights[highlight_id] = {
    bufnr = bufnr,
    mark_id = mark_id,
    unique_id = unique_id,
    start_time = vim.loop.hrtime(),
    duration_ns = duration_seconds * 1e9
  }
  
  -- Schedule automatic cleanup
  vim.defer_fn(function()
    M.cleanup_highlight(highlight_id)
  end, math.max(100, duration_seconds * 1000))  -- Minimum 100ms
  
  return highlight_id
end

--- Cleanup a specific highlight
function M.cleanup_highlight(highlight_id)
  local highlight = active_highlights[highlight_id]
  if highlight then
    pcall(vim.api.nvim_buf_del_extmark, highlight.bufnr, NAMESPACE_ID, highlight.mark_id)
    active_highlights[highlight_id] = nil
  end
end

--- Cleanup all active highlights
function M.cleanup_all_highlights()
  for highlight_id, _ in pairs(active_highlights) do
    M.cleanup_highlight(highlight_id)
  end
end

--- OSC Message Handler: /neovim/highlight
-- Implements your 6-argument specification:
-- lineStart (Integer), colStart (Integer), lineEnd (Integer), colEnd (Integer), delta (Float), s (String)
function M.handle_highlight_message(args, address)
  ensure_highlight_group()
  
  if #args < 6 then
    vim.notify("HighTideLight: Invalid highlight message - expected 6 args, got " .. #args, vim.log.levels.WARN)
    return
  end
  
  local lineStart = args[1]    -- 1-indexed line number
  local colStart = args[2]     -- 0-indexed column number  
  local lineEnd = args[3]      -- 1-indexed line number (usually same as lineStart)
  local colEnd = args[4]       -- 0-indexed column number
  local delta = args[5]        -- Duration in seconds (float)
  local s = args[6]           -- Sample/sound name (string)
  
  -- Get current buffer (assuming highlight is for current buffer)
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- Validate coordinates
  if lineStart < 1 or lineEnd < 1 then
    vim.notify("HighTideLight: Invalid line numbers: " .. lineStart .. "," .. lineEnd, vim.log.levels.WARN)
    return
  end
  
  if colStart < 0 or colEnd <= colStart then
    vim.notify("HighTideLight: Invalid column range: " .. colStart .. "-" .. colEnd, vim.log.levels.WARN)
    return
  end
  
  -- Create the timed highlight
  local highlight_id = create_timed_highlight(
    bufnr, 
    lineStart,     -- Use lineStart as the primary line
    colStart, 
    colEnd, 
    delta,
    s
  )
  
  -- Debug output
  if vim.g.tidal_highlight_debug then
    vim.notify(string.format(
      "HighTideLight: %s highlighted at line %d, cols %d-%d for %.2fs", 
      s, lineStart, colStart, colEnd, delta
    ), vim.log.levels.INFO)
  end
  
  return highlight_id
end

--- Alternative handler for source-map based highlighting
-- Uses our precise coordinate system to find exact token positions
function M.handle_token_highlight(token_unique_id, duration_seconds, source_map)
  ensure_highlight_group()
  
  if not source_map or not source_map[token_unique_id] then
    vim.notify("HighTideLight: Token not found in source map: " .. tostring(token_unique_id), vim.log.levels.WARN)
    return
  end
  
  local token_info = source_map[token_unique_id]
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- Create highlight using precise coordinates from our parser
  local highlight_id = create_timed_highlight(
    bufnr,
    token_info.range.start.line,
    token_info.range.start.col,
    token_info.range["end"].col,
    duration_seconds,
    token_unique_id
  )
  
  return highlight_id
end

--- Initialize the highlight handler
function M.setup(osc_server)
  ensure_highlight_group()
  
  -- Register OSC callback for your specified message format
  osc_server.on("/neovim/highlight", M.handle_highlight_message)
  
  -- Optional: Register alternative callback for source-map based highlights
  osc_server.on("/neovim/token_highlight", function(args, address)
    if #args >= 2 then
      local token_id = args[1]  -- unique_id from our parser
      local duration = args[2]  -- duration in seconds
      -- Would need source_map passed in or retrieved from global state
      -- M.handle_token_highlight(token_id, duration, global_source_map)
    end
  end)
  
  vim.notify("HighTideLight: OSC highlight handlers registered", vim.log.levels.INFO)
end

--- Get highlight statistics
function M.get_stats()
  local count = 0
  for _ in pairs(active_highlights) do
    count = count + 1
  end
  
  return {
    active_highlights = count,
    namespace_id = NAMESPACE_ID
  }
end

return M