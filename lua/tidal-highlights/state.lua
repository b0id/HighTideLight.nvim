-- State management module for tidal-highlights.nvim
-- Handles the complex state tracking identified as critical in research

local M = {}

-- Active highlights storage: buffer -> line -> {extmark_id, timer}
M.active_highlights = {}

-- Add a highlight to state tracking
function M.add_highlight(buf, line, extmark_id, timer)
  if not M.active_highlights[buf] then
    M.active_highlights[buf] = {}
  end
  
  if not M.active_highlights[buf][line] then
    M.active_highlights[buf][line] = {}
  end
  
  -- Store the extmark and its cleanup timer
  table.insert(M.active_highlights[buf][line], {
    extmark_id = extmark_id,
    timer = timer
  })
end

-- Remove a specific highlight
function M.remove_highlight(buf, line, extmark_id)
  if not M.active_highlights[buf] or not M.active_highlights[buf][line] then
    return
  end
  
  for i, highlight in ipairs(M.active_highlights[buf][line]) do
    if highlight.extmark_id == extmark_id then
      -- Cancel timer if it exists
      if highlight.timer then
        highlight.timer:stop()
        highlight.timer:close()
      end
      
      -- Remove from Neovim
      pcall(vim.api.nvim_buf_del_extmark, buf, 0, extmark_id)
      
      -- Remove from our state
      table.remove(M.active_highlights[buf][line], i)
      break
    end
  end
  
  -- Clean up empty tables
  if #M.active_highlights[buf][line] == 0 then
    M.active_highlights[buf][line] = nil
  end
  
  if next(M.active_highlights[buf]) == nil then
    M.active_highlights[buf] = nil
  end
end

-- Clear all highlights in a line range (for re-evaluation)
function M.clear_line_range(buf, start_line, end_line)
  if not M.active_highlights[buf] then
    return
  end
  
  for line = start_line, end_line do
    if M.active_highlights[buf][line] then
      -- Copy the array since we'll be modifying it
      local highlights = vim.deepcopy(M.active_highlights[buf][line])
      
      for _, highlight in ipairs(highlights) do
        M.remove_highlight(buf, line, highlight.extmark_id)
      end
    end
  end
end

-- Clear all highlights (for hush command)
function M.clear_all()
  for buf, buffer_highlights in pairs(M.active_highlights) do
    for line, line_highlights in pairs(buffer_highlights) do
      -- Copy the array since we'll be modifying it
      local highlights = vim.deepcopy(line_highlights)
      
      for _, highlight in ipairs(highlights) do
        M.remove_highlight(buf, line, highlight.extmark_id)
      end
    end
  end
  
  M.active_highlights = {}
end

-- Get active highlight count (for diagnostics)
function M.get_active_count()
  local count = 0
  for _, buffer_highlights in pairs(M.active_highlights) do
    for _, line_highlights in pairs(buffer_highlights) do
      count = count + #line_highlights
    end
  end
  return count
end

-- Automatic cleanup when buffers are deleted
vim.api.nvim_create_autocmd("BufDelete", {
  callback = function(args)
    if M.active_highlights[args.buf] then
      M.clear_line_range(args.buf, 0, math.huge)
    end
  end
})

return M