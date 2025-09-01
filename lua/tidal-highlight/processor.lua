-- ~/.config/nvim/lua/tidal-highlight/processor.lua
local M = {}

-- Track event IDs to buffer positions
M.event_ids = {}
M.next_event_id = 1

-- Enhanced patterns to match ALL Tidal constructs (like Strudel)
local PATTERNS = {
  -- Quoted mini-notation strings
  quoted_strings = [["([^"]*)"]],
  
  -- Function names and operators
  functions = [[([%w_]+)%s*(%$|%#|%*|%+|%-|/|\||<|>|=)]],
  
  -- Numbers (including floats)
  numbers = [[(%d+%.?%d*)]],
  
  -- Control parameters  
  controls = [[#%s*([%w_]+)]],
  
  -- Operators and symbols
  operators = [[([\$#\*\+\-/\|<>=\(\)\[\]{}])]],
  
  -- Variables and identifiers
  identifiers = [[([%a_][%w_]*)]],
  
  -- Pattern separators and brackets
  separators = [[([\[\]{}(),])]],
  
  -- Special Tidal functions
  special_functions = [[(d%d+|p%s+%d+|jux|rev|slow|fast|sometimes|often|rarely|degradeBy|stut|echo)]],
}

local EXCLUDE_PATTERNS = { "^d%d+$", "^p$", "^$" }  -- Skip pattern assignments

-- Enhanced function to parse ALL Tidal components (like Strudel)
local function parse_all_components(text)
  local components = {}
  
  -- 1. Parse quoted strings and their contents
  for start_pos, quoted_content in text:gmatch('()"([^"]*)"') do
    local quote_start = start_pos
    local quote_end = start_pos + #quoted_content + 1
    
    -- Mark the whole quoted string
    table.insert(components, {
      word = '"' .. quoted_content .. '"',
      start_col = quote_start,
      end_col = quote_end,
      type = "quoted_string"
    })
    
    -- Parse individual sounds within quotes
    local pos_in_quote = quote_start + 1 -- Start after opening quote
    for word in quoted_content:gmatch("%S+") do
      local word_start = text:find(word, pos_in_quote, true)
      if word_start then
        table.insert(components, {
          word = word,
          start_col = word_start,
          end_col = word_start + #word - 1,
          type = "sound"
        })
        pos_in_quote = word_start + #word
      end
    end
  end
  
  -- 2. Parse numbers (including floats)
  for start_pos, number in text:gmatch('()([%d%.]+)') do
    if not text:sub(start_pos - 1, start_pos - 1):match('["\']') then -- Not inside quotes
      table.insert(components, {
        word = number,
        start_col = start_pos,
        end_col = start_pos + #number - 1,
        type = "number"
      })
    end
  end
  
  -- 3. Parse function names (common Tidal functions)
  local tidal_functions = {
    "sound", "n", "gain", "pan", "speed", "slow", "fast", "jux", "rev", 
    "sometimes", "often", "rarely", "degradeBy", "stut", "echo", "delay",
    "room", "size", "lpf", "hpf", "resonance", "cutoff", "attack", "release",
    "sustain", "decay", "vowel", "shape", "crush", "coarse"
  }
  
  for _, func_name in ipairs(tidal_functions) do
    for start_pos in text:gmatch('()' .. func_name .. '(%s|%$|%#)') do
      table.insert(components, {
        word = func_name,
        start_col = start_pos,
        end_col = start_pos + #func_name - 1,
        type = "function"
      })
    end
  end
  
  -- 4. Parse operators
  local operators = { "%$", "#", "%*", "%+", "%-", "/", "|", "<", ">", "=" }
  for _, op in ipairs(operators) do
    for start_pos in text:gmatch('()' .. op) do
      table.insert(components, {
        word = op:gsub("%%", ""), -- Remove escape chars
        start_col = start_pos,
        end_col = start_pos,
        type = "operator"
      })
    end
  end
  
  -- 5. Parse brackets and separators
  local separators = { "%[", "%]", "{", "}", "%(", "%)", "," }
  for _, sep in ipairs(separators) do
    for start_pos in text:gmatch('()' .. sep) do
      table.insert(components, {
        word = sep:gsub("%%", ""),
        start_col = start_pos,
        end_col = start_pos,
        type = "separator"
      })
    end
  end
  
  -- Sort by position
  table.sort(components, function(a, b) return a.start_col < b.start_col end)
  
  return components
end

-- Process a line before sending to Tidal  
function M.process_line(buffer, line_num, text)
  local processed = text
  local delta_context_injection_offset = 0
  local col_offset = 0  -- Initialize column offset
  
  -- Generate event ID for this evaluation
  local event_id = M.next_event_id
  M.next_event_id = M.next_event_id + 1
  
  -- Parse ALL components in the line BEFORE injection
  local components = parse_all_components(text)
  
  -- Inject deltaContext metadata (CRITICAL for OSC mapping)
  -- Match the exact Pulsar format: inject at pattern level, not individual words
  if text:match("^d%d+") or text:match("^p%s+%d+") then
    -- Find the quoted pattern string
    local quote_start, quote_end = text:find('".-"')
    if quote_start then
      local before = text:sub(1, quote_start - 1)
      local quoted_pattern = text:sub(quote_start, quote_end)
      local after = text:sub(quote_end + 1)
      
      -- Store the column offset for this pattern (relative to quote start)
      col_offset = quote_start
      
      -- Inject deltaContext with column offset and event ID
      local injection = string.format('(deltaContext %d %d %s)', col_offset, event_id, quoted_pattern)
      processed = before .. injection .. after
      
      -- Calculate offset for position mapping
      delta_context_injection_offset = #injection - #quoted_pattern
      
      -- Adjust all component positions that come after injection point
      for _, component in ipairs(components) do
        if component.start_col > quote_start then
          component.start_col = component.start_col + delta_context_injection_offset
          component.end_col = component.end_col + delta_context_injection_offset
        end
      end
    end
  end
  
  -- Store mapping with adjusted positions
  M.event_ids[event_id] = {
    buffer = buffer,
    row = line_num - 1,  -- 0-indexed for Neovim
    original_text = text,
    processed_text = processed,
    injection_offset = delta_context_injection_offset,
    col_offset = col_offset,  -- Store column offset for OSC mapping
    markers = components
  }
  
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