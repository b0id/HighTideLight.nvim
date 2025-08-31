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
  local ok, tidal = pcall(require, 'tidal')
  if not ok then
    return false, "Could not load tidal module"
  end
  
  -- grddavies/tidal.nvim has functions in tidal.api
  if not tidal.api then
    return false, "No tidal.api found"
  end
  
  -- Create wrapper for evaluation
  local function wrap_evaluation(original_func, func_name)
    return function(...)
      local args = {...}
      
      -- Get the code being sent
      local code = args[1] or ""
      if type(code) == "table" then
        code = table.concat(code, "\n")
      end
      
      -- Process the code before sending
      if processor_callback then
        local buffer = vim.api.nvim_get_current_buf()
        local cursor = vim.api.nvim_win_get_cursor(0)
        processor_callback(buffer, cursor[1], code)
      end
      
      -- Call original function
      return original_func(...)
    end
  end
  
  -- Hook into the API functions
  local functions_to_wrap = {
    'send_line',
    'send_block', 
    'send_visual',
    'send_multiline',
    'send_node',
  }
  
  local wrapped_count = 0
  for _, func_name in ipairs(functions_to_wrap) do
    if tidal.api[func_name] then
      tidal.api[func_name] = wrap_evaluation(tidal.api[func_name], func_name)
      wrapped_count = wrapped_count + 1
    end
  end
  
  if wrapped_count == 0 then
    return false, "No evaluation functions found to wrap in tidal.api"
  end
  
  return true, string.format("Wrapped %d API functions", wrapped_count)
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
    -- Process lines before sending
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