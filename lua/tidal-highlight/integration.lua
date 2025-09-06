-- lua/tidal-highlight/integration.lua
-- Integrates source map coordinate system with OSC message handling

local source_map = require('tidal-highlight.source_map')
local highlight_handler = require('tidal-highlight.highlight_handler')
local cache = require('tidal-highlight.cache')

local M = {}

-- Global storage for active source maps (bufnr -> range -> source_map)
M.active_source_maps = {}

-- Track which buffers we're monitoring
local monitored_buffers = {}

--- Generates and caches source maps for a buffer
local function update_source_map(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  
  -- Clear old mappings for this buffer
  M.active_source_maps[bufnr] = {}
  
  -- Generate source maps for all lines in the buffer
  for line = 1, line_count do
    local range = { start_line = line, end_line = line }
    local source_map_data = source_map.generate(bufnr, range)
    
    if next(source_map_data) then  -- Only store non-empty source maps
      local range_key = line .. "_" .. line
      M.active_source_maps[bufnr] = M.active_source_maps[bufnr] or {}
      M.active_source_maps[bufnr][range_key] = source_map_data
    end
  end
  
  if vim.g.tidal_highlight_debug then
    local total_tokens = 0
    for _, buf_maps in pairs(M.active_source_maps[bufnr] or {}) do
      for _ in pairs(buf_maps) do
        total_tokens = total_tokens + 1
      end
    end
    vim.notify("HighTideLight: Updated source map for buffer " .. bufnr .. " (" .. total_tokens .. " tokens)", vim.log.levels.INFO)
  end
end

--- Find token by sample name across all active source maps
local function find_token_by_sample(sample_name)
  for bufnr, buf_source_maps in pairs(M.active_source_maps) do
    for range_key, source_map_data in pairs(buf_source_maps) do
      for unique_id, token_info in pairs(source_map_data) do
        if token_info.value == sample_name then
          return {
            bufnr = bufnr,
            unique_id = unique_id,
            token_info = token_info,
            range_key = range_key
          }
        end
      end
    end
  end
  return nil
end

--- Enhanced OSC message handler that uses source map coordinates
local function handle_integrated_highlight(args, address)
  if #args < 6 then
    vim.notify("HighTideLight: Invalid integrated highlight message - expected 6 args, got " .. #args, vim.log.levels.WARN)
    return
  end
  
  local lineStart = args[1]
  local colStart = args[2] 
  local lineEnd = args[3]
  local colEnd = args[4]
  local delta = args[5]
  local s = args[6]
  
  -- Try to find precise coordinates using our source map
  local token_match = find_token_by_sample(s)
  
  if token_match then
    -- Use precise coordinates from our parsing system
    local precise_coords = token_match.token_info.range
    
    -- Override OSC coordinates with our precise ones
    lineStart = precise_coords.start.line
    colStart = precise_coords.start.col
    lineEnd = precise_coords["end"].line  
    colEnd = precise_coords["end"].col
    
    if vim.g.tidal_highlight_debug then
      vim.notify(string.format(
        "HighTideLight: Using precise coordinates for '%s': line %d, cols %d-%d", 
        s, lineStart, colStart, colEnd
      ), vim.log.levels.INFO)
    end
  else
    if vim.g.tidal_highlight_debug then
      vim.notify("HighTideLight: No source map found for '" .. s .. "', using OSC coordinates", vim.log.levels.WARN)
    end
  end
  
  -- Create highlight with the chosen coordinates
  return highlight_handler.handle_highlight_message({lineStart, colStart, lineEnd, colEnd, delta, s}, address)
end

--- Send current source map data to SuperCollider
local function send_source_map_to_supercollider(bufnr, osc_client)
  local buf_source_maps = M.active_source_maps[bufnr]
  if not buf_source_maps then
    return
  end
  
  local config = require('tidal-highlight.config')
  
  for range_key, source_map_data in pairs(buf_source_maps) do
    for unique_id, token_info in pairs(source_map_data) do
      -- Send sound position data: /tidal/sound_position [orbit, sound, startCol, endCol]
      local orbit = 0  -- TODO: Extract from buffer context or line analysis
      
      osc_client.send("/tidal/sound_position", {
        orbit,
        token_info.value,
        token_info.range.start.col,
        token_info.range["end"].col
      }, config.current.supercollider.ip, config.current.supercollider.port)
    end
  end
end

--- Monitor a buffer for changes and update source maps
function M.monitor_buffer(bufnr)
  if monitored_buffers[bufnr] then
    return -- Already monitoring
  end
  
  monitored_buffers[bufnr] = true
  
  -- Initial source map generation
  update_source_map(bufnr)
  
  -- Set up autocmds for this buffer
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
    buffer = bufnr,
    callback = function()
      -- Debounced update (only update after 500ms of no changes)
      if M._update_timer then
        M._update_timer:stop()
      end
      
      M._update_timer = vim.defer_fn(function()
        update_source_map(bufnr)
        
        -- Send updated data to SuperCollider
        local osc = require('tidal-highlight.osc')
        send_source_map_to_supercollider(bufnr, osc)
      end, 500)
    end
  })
  
  -- Cleanup on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = bufnr,
    callback = function()
      M.active_source_maps[bufnr] = nil
      monitored_buffers[bufnr] = nil
      if M._update_timer then
        M._update_timer:stop()
        M._update_timer = nil
      end
    end
  })
end

--- Set up the integrated system
function M.setup(osc_server)
  -- Register our integrated highlight handler
  osc_server.on("/neovim/highlight", handle_integrated_highlight)
  
  -- Monitor Haskell buffers automatically
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "haskell",
    callback = function(args)
      M.monitor_buffer(args.buf)
    end
  })
  
  -- Monitor currently open Haskell buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_option(bufnr, 'filetype') == 'haskell' then
      M.monitor_buffer(bufnr)
    end
  end
  
  vim.notify("HighTideLight: Source map integration enabled", vim.log.levels.INFO)
end

--- Manual source map update for current buffer
function M.update_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  update_source_map(bufnr)
  
  -- Send to SuperCollider
  local osc = require('tidal-highlight.osc')
  send_source_map_to_supercollider(bufnr, osc)
  
  vim.notify("HighTideLight: Source map updated for current buffer", vim.log.levels.INFO)
end

--- Get integration statistics
function M.get_stats()
  local buffer_count = 0
  local total_tokens = 0
  
  for bufnr, buf_source_maps in pairs(M.active_source_maps) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      buffer_count = buffer_count + 1
      for _, source_map_data in pairs(buf_source_maps) do
        for _ in pairs(source_map_data) do
          total_tokens = total_tokens + 1
        end
      end
    end
  end
  
  return {
    monitored_buffers = buffer_count,
    total_tokens = total_tokens,
    active_source_maps = M.active_source_maps
  }
end

return M