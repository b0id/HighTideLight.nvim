-- tidal-highlights.nvim: Companion plugin for TidalCycles highlighting
-- Based on comprehensive Pulsar research and clean architecture

local M = {}

-- Configuration with sensible defaults
M.config = {
  enabled = true,
  bridge_path = nil,  -- Auto-detect
  debug = false,
  animation = {
    duration_ms = 500,
    fade_steps = 5,
  },
  highlights = {
    groups = {
      { name = "TidalActive", fg = "#ff6b6b", bg = "#2a1a1a", bold = true },
      { name = "TidalActive2", fg = "#4ecdc4", bg = "#1a2a2a", bold = true },
      { name = "TidalActive3", fg = "#45b7d1", bg = "#1a1a2a", bold = true },
      { name = "TidalActive4", fg = "#96ceb4", bg = "#1a2a1a", bold = true },
    },
  },
}

-- State
M.bridge_job = nil
M.highlights = {}
M.namespace = vim.api.nvim_create_namespace('tidal_highlights')

-- Create highlight groups with fade variants
local function create_highlight_groups()
  for _, group in ipairs(M.config.highlights.groups) do
    local base_hl = {
      fg = group.fg,
      bg = group.bg,
      bold = group.bold
    }
    
    vim.api.nvim_set_hl(0, group.name, base_hl)
    
    -- Create fade variants
    for i = 1, M.config.animation.fade_steps do
      local fade_hl = vim.tbl_deep_copy(base_hl)
      fade_hl.blend = math.min(20 + (i * 15), 80)
      vim.api.nvim_set_hl(0, group.name .. "_fade_" .. i, fade_hl)
    end
  end
end

-- Handle OSC message from bridge (6-argument format from research)
function M.handle_osc_message(args)
  if #args ~= 6 then
    if M.config.debug then
      vim.notify("Invalid OSC args count: " .. #args, vim.log.levels.WARN)
    end
    return
  end

  local stream_id = args[1]
  local start_row = args[2] - 1  -- Convert to 0-indexed
  local start_col = args[3] - 1  -- Convert to 0-indexed  
  local end_row = args[4] - 1
  local end_col = args[5] - 1
  local duration = args[6] or M.config.animation.duration_ms

  if M.config.debug then
    vim.notify(string.format("OSC: stream=%s, pos=(%d,%d)-(%d,%d), dur=%d", 
      stream_id, start_row, start_col, end_row, end_col, duration))
  end

  -- Find current buffer (TODO: make this smarter)
  local buffer = vim.api.nvim_get_current_buf()
  
  -- Select highlight group cyclically
  local group_idx = ((tonumber(stream_id) or 1) % #M.config.highlights.groups) + 1
  local hl_group = M.config.highlights.groups[group_idx].name

  M.add_highlight(buffer, start_row, start_col, end_col, hl_group, duration)
end

-- Add animated highlight
function M.add_highlight(buffer, row, start_col, end_col, hl_group, duration)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end

  -- Create initial highlight
  local mark_id = vim.api.nvim_buf_set_extmark(buffer, M.namespace, row, start_col, {
    end_col = end_col,
    hl_group = hl_group,
    priority = 100,
    strict = false,
  })

  -- Animate fade over duration
  local fade_interval = duration / M.config.animation.fade_steps
  
  for i = 1, M.config.animation.fade_steps do
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buffer) then
        pcall(vim.api.nvim_buf_del_extmark, buffer, M.namespace, mark_id)
        
        if i < M.config.animation.fade_steps then
          -- Create faded version
          local fade_group = hl_group .. "_fade_" .. i
          mark_id = vim.api.nvim_buf_set_extmark(buffer, M.namespace, row, start_col, {
            end_col = end_col,
            hl_group = fade_group,
            priority = 100 - i,
            strict = false,
          })
        end
      end
    end, i * fade_interval)
  end
end

-- Auto-detect bridge path
local function find_bridge_path()
  local potential_paths = {
    vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h") .. "/tidal-osc-bridge/target/release/tidal-osc-bridge",
    vim.fn.stdpath("data") .. "/lazy/HighTideLight.nvim/tidal-osc-bridge/target/release/tidal-osc-bridge",
    "tidal-osc-bridge"  -- Assume in PATH
  }

  for _, path in ipairs(potential_paths) do
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
  
  return nil
end

-- Start OSC bridge
function M.start_bridge()
  if M.bridge_job then
    return
  end

  local bridge_path = M.config.bridge_path or find_bridge_path()
  if not bridge_path then
    vim.notify("tidal-osc-bridge not found. Please build it first.", vim.log.levels.ERROR)
    return false
  end

  local args = { bridge_path }
  if M.config.debug then
    table.insert(args, "--debug")
  end

  M.bridge_job = vim.fn.jobstart(args, {
    on_stdout = function(_, data, _)
      for _, line in ipairs(data) do
        if line and line ~= "" then
          local ok, parsed = pcall(vim.json.decode, line)
          if ok and parsed.args then
            vim.schedule(function()
              M.handle_osc_message(parsed.args)
            end)
          elseif M.config.debug then
            vim.schedule(function()
              vim.notify("Bridge: " .. line, vim.log.levels.INFO)
            end)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      for _, line in ipairs(data) do
        if line and line ~= "" and M.config.debug then
          vim.schedule(function()
            vim.notify("Bridge error: " .. line, vim.log.levels.WARN)
          end)
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      M.bridge_job = nil
      if exit_code ~= 0 and M.config.debug then
        vim.schedule(function()
          vim.notify("Bridge exited with code: " .. exit_code, vim.log.levels.WARN)
        end)
      end
    end,
  })

  if M.bridge_job > 0 then
    if M.config.debug then
      vim.notify("Started OSC bridge (job " .. M.bridge_job .. ")")
    end
    return true
  else
    vim.notify("Failed to start OSC bridge", vim.log.levels.ERROR)
    return false
  end
end

-- Stop OSC bridge
function M.stop_bridge()
  if M.bridge_job then
    vim.fn.jobstop(M.bridge_job)
    M.bridge_job = nil
    if M.config.debug then
      vim.notify("Stopped OSC bridge")
    end
  end
end

-- Clear all highlights
function M.clear_highlights()
  vim.api.nvim_buf_clear_namespace(0, M.namespace, 0, -1)
end

-- Setup function
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  
  if not M.config.enabled then
    return
  end

  -- Create highlight groups
  create_highlight_groups()

  -- Auto-start bridge
  vim.defer_fn(function()
    M.start_bridge()
  end, 100)

  -- Commands
  vim.api.nvim_create_user_command("TidalHighlightsStart", function()
    M.start_bridge()
  end, { desc = "Start Tidal highlights bridge" })

  vim.api.nvim_create_user_command("TidalHighlightsStop", function()
    M.stop_bridge()
  end, { desc = "Stop Tidal highlights bridge" })

  vim.api.nvim_create_user_command("TidalHighlightsClear", function()
    M.clear_highlights()
  end, { desc = "Clear all highlights" })

  -- Auto-stop on exit
  vim.api.nvim_create_autocmd("VimLeave", {
    callback = function()
      M.stop_bridge()
    end,
  })

  if M.config.debug then
    vim.notify("tidal-highlights.nvim loaded")
  end
end

return M