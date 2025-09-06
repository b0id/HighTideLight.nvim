-- lua/tidal-highlight/debug.lua
local M = {}

-- Debug function to show which files are loaded
function M.show_loaded_files()
  local plugin_files = {
    'tidal-highlight.init',
    'tidal-highlight.config',
    'tidal-highlight.osc',
    'tidal-highlight.highlights',
    'tidal-highlight.animation',
    -- Add the new parser modules to the list
    'tidal-highlight.source_map',
    'tidal-highlight.parser.haskell',
    'tidal-highlight.parser.mini_notation',
    'tidal-highlight.cache'
  }

  print("=== HighTideLight.nvim Debug Info ===")
  -- ... (rest of the function from your original file)
end

-- Debug function to reload all modules
function M.reload_plugin()
  local modules_to_reload = {
    'tidal-highlight.init',
    'tidal-highlight.config',
    'tidal-highlight.osc',
    'tidal-highlight.highlights',
    'tidal-highlight.animation',
    'tidal-highlight.compat',
    'tidal-highlight.debug',
    'tidal-highlight.diagnostics',
    -- Add the new parser modules to the reload list
    'tidal-highlight.source_map',
    'tidal-highlight.parser.haskell',
    'tidal-highlight.parser.mini_notation',
    'tidal-highlight.cache'
  }

  for _, module in ipairs(modules_to_reload) do
    package.loaded[module] = nil
  end

  -- Reload the main module
  require('tidal-highlight')
  print("HighTideLight.nvim reloaded!")
end

-- NEW: Test the new AST parser on the current line of code.
function M.test_parser_on_current_line()
  print("=== AST Parser Debug on Current Line ===")
  local source_map_generator = require('tidal-highlight.source_map')

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]

  -- Invalidate cache for this buffer to ensure a fresh parse
  require('tidal-highlight.cache').invalidate(bufnr)

  print(string.format("Parsing line %d in buffer %d...", line_num, bufnr))

  -- Generate the source map for only the current line
  local range = { start_line = line_num, end_line = line_num }
  local source_map = source_map_generator.generate(bufnr, range)

  if source_map then
    local count = 0
    for _ in pairs(source_map) do count = count + 1 end
    print("Success! Found " .. count .. " sound tokens. Source Map:")
    print(vim.inspect(source_map))
  else
    print("Error: Source map generation failed.")
  end
  print("=== End Parser Debug ===")
end

return M