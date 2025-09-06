-- lua/tidal-highlight/parser/mini_notation.lua
-- Character-precise parser for Tidal mini-notation with exact coordinate tracking

local M = {}

-- Token patterns with precise character boundaries
local PATTERNS = {
  sound = "([%w_]+)",              -- bd, cp, hh, kick_1
  rest = "(~)",                    -- silence
  group_start = "(%[)",            -- group start
  group_end = "(%])",              -- group end  
  multiplier = "(%*%d+)",          -- *2, *4, *8
  polyrhythm_start = "({)",        -- polyrhythm start
  polyrhythm_end = "(})",          -- polyrhythm end
  comma = "(,)",                   -- separator
  space = "(%s+)"                  -- whitespace
}

--- Character-level tokenizer that preserves exact positions
-- This is the cornerstone: every character position must be trackable
local function tokenize_with_positions(str)
  local tokens = {}
  local pos = 1
  local id_counter = 0
  
  while pos <= #str do
    local matched = false
    
    -- Try each pattern at current position
    for token_type, pattern in pairs(PATTERNS) do
      local start_pos, end_pos, match = string.find(str, "^" .. pattern, pos)
      
      if start_pos then
        -- Skip whitespace tokens (but track position)
        if token_type ~= "space" then
          id_counter = id_counter + 1
          table.insert(tokens, {
            type = token_type,
            value = match,
            unique_id = match .. "_" .. (id_counter - 1),
            relative_range = {
              start = pos - 1,  -- 0-based for consistency with TreeSitter
              ["end"] = end_pos - 1
            }
          })
        end
        pos = end_pos + 1
        matched = true
        break
      end
    end
    
    if not matched then
      -- Skip unknown character but maintain position tracking
      pos = pos + 1
    end
  end
  
  return tokens
end

--- Expands groups with multipliers into virtual tokens
-- Example: [bd hh]*2 → bd_0, hh_1, bd_2, hh_3 (with calculated positions)
local function expand_groups(tokens)
  local expanded = {}
  local i = 1
  local virtual_id_counter = 0
  
  while i <= #tokens do
    local token = tokens[i]
    
    if token.type == "group_start" then
      -- Find matching group_end and multiplier
      local group_tokens = {}
      local j = i + 1
      local nest_level = 1
      
      while j <= #tokens and nest_level > 0 do
        if tokens[j].type == "group_start" then
          nest_level = nest_level + 1
        elseif tokens[j].type == "group_end" then
          nest_level = nest_level - 1
        end
        
        if nest_level > 0 then
          table.insert(group_tokens, tokens[j])
        end
        j = j + 1
      end
      
      -- Check for multiplier
      local multiplier = 1
      if j <= #tokens and tokens[j].type == "multiplier" then
        multiplier = tonumber(string.match(tokens[j].value, "%d+")) or 1
        j = j + 1  -- Skip multiplier token
      end
      
      -- Expand group contents
      local group_start_pos = token.relative_range.start
      local group_end_pos = tokens[j-2] and tokens[j-2].relative_range["end"] or token.relative_range["end"]
      local group_width = group_end_pos - group_start_pos + 1
      
      for rep = 0, multiplier - 1 do
        for _, group_token in ipairs(group_tokens) do
          if group_token.type == "sound" or group_token.type == "rest" then
            virtual_id_counter = virtual_id_counter + 1
            -- Calculate virtual position within the expanded sequence
            local virtual_offset = (rep * group_width) / multiplier
            table.insert(expanded, {
              type = group_token.type,
              value = group_token.value,
              unique_id = group_token.value .. "_" .. (virtual_id_counter - 1),
              relative_range = {
                start = group_start_pos + virtual_offset,
                ["end"] = group_start_pos + virtual_offset + #group_token.value - 1
              },
              is_virtual = true,
              original_group = {group_start_pos, group_end_pos}
            })
          end
        end
      end
      
      i = j  -- Skip past the entire group
    else
      -- Regular token - pass through
      table.insert(expanded, token)
      i = i + 1
    end
  end
  
  return expanded
end

--- Main parsing function: the data contract cornerstone
-- @param str string The mini-notation content (without quotes)
-- @return table List of tokens with precise relative_range coordinates
function M.parse(str)
  if not str or str == "" then
    return {}
  end
  
  -- Step 1: Tokenize with exact positions
  local tokens = tokenize_with_positions(str)
  
  -- Step 2: Expand groups (preserving coordinate precision)
  local expanded = expand_groups(tokens)
  
  return expanded
end

return M