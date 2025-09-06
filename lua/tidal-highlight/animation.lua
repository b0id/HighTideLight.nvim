-- lua/tidal-highlight/animation.lua
local highlights = require('tidal-highlight.highlights')

local M = {}
M.timer = nil
M.pending_events = {}

-- Queue event for next frame
function M.queue_event(event_data)
  table.insert(M.pending_events, event_data)
end

-- Process one animation frame
function M.process_frame()
  -- Add all pending events
  for _, event in ipairs(M.pending_events) do
    highlights.add_highlight(event)
  end
  M.pending_events = {}

  -- Update highlight diff
  highlights.update_frame()
end

-- Start animation loop
function M.start(config)
  if M.timer then
    M.stop()
  end

  local interval = math.floor(1000 / config.animation.fps)

  M.timer = vim.loop.new_timer()
  M.timer:start(0, interval, vim.schedule_wrap(function()
    M.process_frame()
  end))
end

-- Stop animation loop
function M.stop()
  if M.timer then
    M.timer:stop()
    M.timer:close()
    M.timer = nil
  end
end

return M