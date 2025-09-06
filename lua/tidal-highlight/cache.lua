-- lua/tidal-highlight/cache.lua
-- Caches generated SourceMap objects to avoid re-parsing.

local M = {}
local cache = {} -- Main cache table: cache[bufnr] = { [range_key] = source_map }

--- Generates a unique key for a line range.
-- @param range table { start_line = number, end_line = number }
-- @return string
local function get_range_key(range)
  return tostring(range.start_line) .. ":" .. tostring(range.end_line)
end

--- Retrieves a SourceMap from the cache.
-- @param bufnr number
-- @param range table
-- @return table|nil The cached SourceMap or nil.
function M.get(bufnr, range)
  if not cache[bufnr] then
    return nil
  end
  return cache[bufnr][get_range_key(range)]
end

--- Stores a SourceMap in the cache.
-- @param bufnr number
-- @param range table
-- @param source_map table
function M.set(bufnr, range, source_map)
  if not cache[bufnr] then
    cache[bufnr] = {}
  end
  cache[bufnr][get_range_key(range)] = source_map
end

--- Clears the cache for a specific buffer.
-- Should be called on buffer modifications.
-- @param bufnr number
function M.invalidate(bufnr)
  cache[bufnr] = nil
end

return M