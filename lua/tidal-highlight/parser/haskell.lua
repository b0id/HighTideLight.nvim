-- lua/tidal-highlight/parser/haskell.lua
-- Uses Tree-sitter to find mini-notation strings in Haskell code blocks.

local M = {}

local query_cache = {}

--- Finds all string literals in a given range of a buffer.
-- @param bufnr number The buffer handle.
-- @param range table { start_line = number, end_line = number } (1-based)
-- @return table A list of { content = string, range = Range } tables.
function M.find_mini_notation_strings(bufnr, range)
  -- Check if treesitter is available
  local has_ts, ts_query = pcall(require, 'nvim-treesitter.query')
  if not has_ts then
    if vim.fn.exists(":TidalHighlightDiagnostics") == 2 then
        vim.notify("HighTideLight: nvim-treesitter not available", vim.log.levels.WARN)
    end
    return {}
  end

  -- Use the core, more stable Neovim API to get the parser
  local parser = vim.treesitter.get_parser(bufnr, 'haskell')

  -- The robust check is still important
  if not parser or not parser.parse then
    if vim.fn.exists(":TidalHighlightDiagnostics") == 2 then
        vim.notify("HighTideLight: Haskell parser not ready for buffer " .. bufnr, vim.log.levels.WARN)
    end
    return {}
  end

  if not query_cache.haskell then
    -- Use the more robust Neovim treesitter API
    local success, query = pcall(vim.treesitter.query.parse, 'haskell', '(string) @mini_notation')
    if not success then
      -- Try alternative query patterns
      success, query = pcall(vim.treesitter.query.parse, 'haskell', '(quoted_string) @mini_notation')
      if not success then
        if vim.fn.exists(":TidalHighlightDiagnostics") == 2 then
            vim.notify("HighTideLight: Failed to parse Haskell query: " .. tostring(query), vim.log.levels.ERROR)
        end
        return {}
      end
    end
    query_cache.haskell = query
  end
  local query = query_cache.haskell

  -- The parse call should now succeed
  local root = parser:parse()[1]:root()
  local results = {}
  local start_line_0based = range.start_line - 1
  local end_line_0based = range.end_line - 1

  for _, node in query:iter_captures(root, bufnr, start_line_0based, end_line_0based) do
    local s_line, s_col, e_line, e_col = node:range()
    local content = vim.treesitter.get_node_text(node, bufnr)

    content = content:sub(2, -2)

    table.insert(results, {
      content = content,
      range = {
        start = { line = s_line + 1, col = s_col },
        ["end"] = { line = e_line + 1, col = e_col },
      },
    })
  end

  return results
end

return M