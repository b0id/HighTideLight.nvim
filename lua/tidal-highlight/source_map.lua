-- lua/tidal-highlight/source_map.lua
-- Orchestrates parsers to generate a SourceMap for a block of code.

local cache = require('tidal-highlight.cache')
local haskell_parser = require('tidal-highlight.parser.haskell')
local mini_notation_parser = require('tidal-highlight.parser.mini_notation')

local M = {}

--- Generates a SourceMap for a given code block.
-- @param bufnr number The buffer handle.
-- @param range table { start_line = number, end_line = number }
-- @return table The generated or cached SourceMap.
function M.generate(bufnr, range)
  local cached = cache.get(bufnr, range)
  if cached then
    return cached
  end

  local source_map = {}
  local string_literals = haskell_parser.find_mini_notation_strings(bufnr, range)

  for _, literal in ipairs(string_literals) do
    local mini_tokens = mini_notation_parser.parse(literal.content)

    for _, token in ipairs(mini_tokens) do
      if token.unique_id then
        -- Calculate the absolute position of the token in the buffer
        local absolute_range = {
          start = {
            line = literal.range.start.line,
            -- Add 1 to account for the opening quote
            col = literal.range.start.col + 1 + token.relative_range.start,
          },
          ["end"] = {
            line = literal.range.start.line,
            col = literal.range.start.col + 1 + token.relative_range["end"] + 1,
          },
        }

        source_map[token.unique_id] = {
          range = absolute_range,
          value = token.value,
        }
      end
    end
  end

  cache.set(bufnr, range, source_map)
  return source_map
end

return M