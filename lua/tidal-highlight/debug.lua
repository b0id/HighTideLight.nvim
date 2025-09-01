-- ~/.config/nvim/lua/tidal-highlight/debug.lua
local M = {}

-- Debug function to show which files are loaded
function M.show_loaded_files()
  local plugin_files = {
    'tidal-highlight.init',
    'tidal-highlight.config', 
    'tidal-highlight.osc',
    'tidal-highlight.processor',
    'tidal-highlight.highlights',
    'tidal-highlight.animation'
  }
  
  print("=== HighTideLight.nvim Debug Info ===")
  print("Git branch: " .. vim.fn.system("cd " .. vim.fn.stdpath('data') .. "/lazy/HighTideLight.nvim && git branch --show-current"):gsub("\n", ""))
  print("Git commit: " .. vim.fn.system("cd " .. vim.fn.stdpath('data') .. "/lazy/HighTideLight.nvim && git rev-parse --short HEAD"):gsub("\n", ""))
  
  for _, module in ipairs(plugin_files) do
    local loaded = package.loaded[module]
    if loaded then
      local info = debug.getinfo(loaded.setup or loaded.start or function() end, "S")
      print(string.format("✓ %s: %s", module, info.source or "loaded"))
    else
      print(string.format("✗ %s: not loaded", module))
    end
  end
  
  -- Show current working directory of plugin
  local plugin_path = vim.fn.stdpath('data') .. '/lazy/HighTideLight.nvim'
  if vim.fn.isdirectory(plugin_path) == 1 then
    print("Plugin path: " .. plugin_path)
  else
    print("Plugin path: LOCAL DEV MODE")
  end
end

-- Debug function to reload all modules
function M.reload_plugin()
  local modules_to_reload = {
    'tidal-highlight.init',
    'tidal-highlight.config', 
    'tidal-highlight.osc',
    'tidal-highlight.processor',
    'tidal-highlight.highlights',
    'tidal-highlight.animation'
  }
  
  for _, module in ipairs(modules_to_reload) do
    package.loaded[module] = nil
  end
  
  -- Reload the main module
  require('tidal-highlight')
  print("HighTideLight.nvim reloaded!")
end

return M
