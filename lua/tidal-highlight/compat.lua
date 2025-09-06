-- lua/tidal-highlight/compat.lua
-- Compatibility layer for different Tidal Neovim plugins
local M = {}

-- Plugin detection and API mapping
M.tidal_plugins = {
  ["tidal"] = {
    name = "tidalcycles/tidal.nvim",
    send_function = "send",
    detect = function()
      local ok, tidal = pcall(require, 'tidal')
      return ok and tidal.send ~= nil
    end
  },
  ["tidal.nvim"] = {
    name = "grddavies/tidal.nvim",
    send_function = nil, -- Uses different approach
    detect = function()
      local ok, tidal = pcall(require, 'tidal')
      return ok and tidal.setup ~= nil and tidal.send == nil
    end
  }
}

-- Detect which Tidal plugin is active
function M.detect_tidal_plugin()
  for plugin_key, plugin_info in pairs(M.tidal_plugins) do
    if plugin_info.detect() then
      return plugin_key, plugin_info
    end
  end
  return nil, nil
end

-- Get the current Tidal module and its capabilities
function M.get_tidal_info()
  local plugin_key, plugin_info = M.detect_tidal_plugin()
  if not plugin_key then
    return nil, "No supported Tidal plugin detected"
  end

  local ok, tidal = pcall(require, 'tidal')
  if not ok then
    return nil, "Could not load Tidal module"
  end

  return {
    plugin = plugin_key,
    info = plugin_info,
    module = tidal,
    has_send_function = plugin_info.send_function and tidal[plugin_info.send_function] ~= nil
  }, nil
end

-- Hook into grddavies/tidal.nvim evaluation
function M.hook_grddavies_tidal(processor_callback)
  local ok, message = pcall(require, 'tidal.core.message')
  if not ok then
    return false, "Could not load tidal.core.message module"
  end

  local original_send_line = message.tidal.send_line
  if not original_send_line then
    return false, "No tidal.send_line found"
  end

  message.tidal.send_line = function(text)
    -- The hook's only job now is to capture the text and pass it to the main callback.
    if processor_callback and text and #text > 0 then
      local buffer = vim.api.nvim_get_current_buf()
      local cursor = vim.api.nvim_win_get_cursor(0)
      -- The callback will trigger M.ingest_tidal_text in init.lua
      processor_callback(buffer, cursor[1], text)
    end

    -- Call original function
    return original_send_line(text)
  end

  return true, "Hooked into tidal.core.message.tidal.send_line"
end

-- Hook into tidalcycles/tidal.nvim
function M.hook_tidalcycles_tidal(processor_callback)
  local ok, tidal = pcall(require, 'tidal')
  if not ok then
    return false, "Could not load tidal module"
  end

  local original_send = tidal.send
  if not original_send then
    return false, "No send function found"
  end

  tidal.send = function(lines, ...)
    if processor_callback then
      local buffer = vim.api.nvim_get_current_buf()
      local cursor = vim.api.nvim_win_get_cursor(0)
      for i, line in ipairs(lines) do
        processor_callback(buffer, cursor[1] + i - 1, line)
      end
    end

    return original_send(lines, ...)
  end

  return true, "Hooked into tidal.send function"
end

-- Main hook function that works with detected plugin
function M.hook_tidal_evaluation(processor_callback)
  local tidal_info, err = M.get_tidal_info()
  if not tidal_info then
    return false, err
  end

  if tidal_info.plugin == "tidal.nvim" then
    return M.hook_grddavies_tidal(processor_callback)
  elseif tidal_info.plugin == "tidal" then
    return M.hook_tidalcycles_tidal(processor_callback)
  else
    return false, "Unknown Tidal plugin: " .. tidal_info.plugin
  end
end

return M