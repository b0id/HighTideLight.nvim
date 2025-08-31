-- ~/.config/nvim/lua/tidal-highlight/processor.lua
local M = {}

-- Track event IDs to buffer positions
M.event_ids = {}
M.next_event_id = 1

-- Patterns to match Tidal constructs
local QUOTED_PATTERN = [["([^"]*)"]]
local CONTROL_PATTERN = [[#%s*(%w+)]]
local WORD_PATTERN = [[(%w+)]]
local EXCLUDE_PATTERNS = { "^%d+$", "^p$" }  -- numerals and 'p' function

-- Process a line before sending to Tidal
function M.process_line(buffer, line_num, text)
  local processed = text
  local markers = {}
  
  -- Generate event ID for this evaluation
  local event_id = M.next_event_id
  M.next_event_id = M.next_event_id + 1
  
  -- Store mapping of event_id to buffer location
  M.event_ids[event_id] = {
    buffer = buffer,
    row = line_num - 1,  -- 0-indexed for Neovim
    original_text = text,
    markers = {}
  }
  
  -- Inject deltaContext metadata (for mapping OSC events back)
  -- This is what Tidal will use to identify which code triggered events
  if text:match("^d%d+") or text:match("^p%s+%d+") then
    -- Find the pattern assignment
    local pattern_start = text:find("%$")
    if pattern_start then
      -- Inject metadata after the $
      local before = text:sub(1, pattern_start)
      local after = text:sub(pattern_start + 1)
      processed = before .. " (deltaContext " .. event_id .. ") $ " .. after
    end
  end
  
  -- Find and mark quoted mini-notation strings
  for start_col, quoted_text in text:gmatch('()' .. QUOTED_PATTERN) do
    -- Process words within quotes
    for word_start, word in quoted_text:gmatch('()(%S+)') do
      -- Check if word should be excluded
      local exclude = false
      for _, pattern in ipairs(EXCLUDE_PATTERNS) do
        if word:match(pattern) then
          exclude = true
          break
        end
      end
      
      if not exclude then
        local abs_start = start_col + word_start - 1
        local abs_end = abs_start + #word
        
        table.insert(M.event_ids[event_id].markers, {
          word = word,
          start_col = abs_start,
          end_col = abs_end,
          type = "mini_notation"
        })
      end
    end
  end
  
  -- Find control patterns
  for start_col, control in text:gmatch('()' .. CONTROL_PATTERN) do
    table.insert(M.event_ids[event_id].markers, {
      word = control,
      start_col = start_col,
      end_col = start_col + #control,
      type = "control"
    })
  end
  
  return processed, event_id
end

-- Get event info by ID
function M.get_event_info(event_id)
  return M.event_ids[event_id]
end

-- Clean up old event IDs (garbage collection)
function M.cleanup_old_events(keep_recent_n)
  keep_recent_n = keep_recent_n or 100
  
  if M.next_event_id > keep_recent_n * 2 then
    local cutoff = M.next_event_id - keep_recent_n
    for id, _ in pairs(M.event_ids) do
      if id < cutoff then
        M.event_ids[id] = nil
      end
    end
  end
end

return M