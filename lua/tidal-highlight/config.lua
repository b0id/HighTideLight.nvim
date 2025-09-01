-- ~/.config/nvim/lua/tidal-highlight/config.lua
local M = {}

M.defaults = {
  enabled = true,
  osc = {
    ip = "127.0.0.1",
    port = 6011,  -- Different from SuperDirt's 6010
  },
  supercollider = {
    ip = "127.0.0.1",
    port = 57120,
  },
  animation = {
    fps = 30,
    duration_ms = 200,
    decay_style = "fade", -- "fade", "pulse", "instant"
  },
  highlights = {
    -- Define highlight groups for different component types (like Strudel)
    groups = {
      -- Active sound highlights (when playing)
      { name = "TidalSoundActive", fg = "#ff6b6b", bg = "#2a1a1a", blend = 0, bold = true },
      { name = "TidalSoundActive2", fg = "#4ecdc4", bg = "#1a2a2a", blend = 0, bold = true },
      { name = "TidalSoundActive3", fg = "#45b7d1", bg = "#1a1a2a", blend = 0, bold = true },
      { name = "TidalSoundActive4", fg = "#96ceb4", bg = "#1a2a1a", blend = 0, bold = true },
      
      -- Component type highlights
      { name = "TidalFunction", fg = "#ffa500", bg = nil, blend = 20, italic = true },
      { name = "TidalNumber", fg = "#90ee90", bg = nil, blend = 20 },
      { name = "TidalOperator", fg = "#ff69b4", bg = nil, blend = 20, bold = true },
      { name = "TidalQuotedString", fg = "#87ceeb", bg = nil, blend = 20 },
      { name = "TidalSeparator", fg = "#dda0dd", bg = nil, blend = 20 },
    },
    outline_style = "underline", -- or "box", "bold"
  },
  notifications = {
    transient = true, -- Auto-dismiss notifications
    level = vim.log.levels.WARN, -- Only show warnings and errors by default
  },
  debug = false,
}

M.current = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.current = vim.tbl_deep_extend("force", M.current, opts or {})
  
  -- Create highlight groups with fade stages (from Pulsar notes)
  for _, group in ipairs(M.current.highlights.groups) do
    local base_hl = {}
    if group.fg then base_hl.fg = group.fg end
    if group.bg then base_hl.bg = group.bg end
    if group.blend then base_hl.blend = group.blend end
    if group.bold then base_hl.bold = true end
    if group.italic then base_hl.italic = true end
    if M.current.highlights.outline_style == "underline" then
      base_hl.underline = true
    elseif M.current.highlights.outline_style == "bold" and not group.bold then
      base_hl.bold = true
    end
    
    -- Create base highlight group
    vim.api.nvim_set_hl(0, group.name, base_hl)
    
    -- Create fade stages for decay animation
    for i = 1, 5 do
      local fade_hl = vim.deepcopy(base_hl)
      
      -- Increase transparency/blend for fade effect
      local blend = (group.blend or 20) + (i * 10)
      fade_hl.blend = math.min(blend, 80)  -- Cap at 80% transparency
      
      -- Optionally reduce intensity
      if group.bg then
        fade_hl.bg = group.bg
      end
      
      vim.api.nvim_set_hl(0, group.name .. "_fade_" .. i, fade_hl)
    end
  end
  
  return M.current
end

return M