-- ~/.config/nvim/lua/tidal-highlight/config.lua
local M = {}

M.defaults = {
  enabled = true,
  osc = {
    ip = "127.0.0.1",
    port = 6011,  -- Different from SuperDirt's 6010
  },
  animation = {
    fps = 30,
    duration_ms = 200,
  },
  highlights = {
    -- Define highlight groups for different event types
    groups = {
      { name = "TidalEvent1", fg = "#ff6b6b", bg = nil, blend = 30 },
      { name = "TidalEvent2", fg = "#4ecdc4", bg = nil, blend = 30 },
      { name = "TidalEvent3", fg = "#45b7d1", bg = nil, blend = 30 },
      { name = "TidalEvent4", fg = "#96ceb4", bg = nil, blend = 30 },
    },
    outline_style = "underline", -- or "box", "bold"
  },
  debug = false,
}

M.current = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.current = vim.tbl_deep_extend("force", M.current, opts or {})
  
  -- Create highlight groups
  for _, group in ipairs(M.current.highlights.groups) do
    local hl = {}
    if group.fg then hl.fg = group.fg end
    if group.bg then hl.bg = group.bg end
    if group.blend then hl.blend = group.blend end
    if M.current.highlights.outline_style == "underline" then
      hl.underline = true
    elseif M.current.highlights.outline_style == "bold" then
      hl.bold = true
    end
    vim.api.nvim_set_hl(0, group.name, hl)
  end
  
  return M.current
end

return M