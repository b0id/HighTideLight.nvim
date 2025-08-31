-- OSC Mock Server for testing HighTideLight.nvim without Tidal
local uv = vim.loop

local M = {}
M.server = nil

-- Create OSC message
local function create_osc_message(address, args, types)
  local data = ""
  
  -- Add address pattern with null termination and padding
  data = data .. address .. "\0"
  while #data % 4 ~= 0 do
    data = data .. "\0"
  end
  
  -- Add type tag string
  data = data .. "," .. (types or "") .. "\0"
  while #data % 4 ~= 0 do
    data = data .. "\0"
  end
  
  -- Add arguments
  for i, arg in ipairs(args or {}) do
    if type(arg) == "number" then
      if math.floor(arg) == arg then
        -- Integer
        data = data .. string.pack(">i4", arg)
      else
        -- Float
        data = data .. string.pack(">f", arg)
      end
    elseif type(arg) == "string" then
      data = data .. arg .. "\0"
      while #data % 4 ~= 0 do
        data = data .. "\0"
      end
    end
  end
  
  return data
end

-- Send highlight event
function M.send_highlight_event(opts)
  opts = opts or {}
  local event_id = opts.event_id or 1
  local buffer_id = opts.buffer_id or vim.api.nvim_get_current_buf()
  local row = opts.row or 0
  local start_col = opts.start_col or 0
  local end_col = opts.end_col or 10
  local duration = opts.duration or 0.2
  local cycle = opts.cycle or 1.0
  
  local args = {event_id, buffer_id, row, start_col, end_col, duration, cycle}
  local types = "iiiiiff"
  local message = create_osc_message("/editor/highlights", args, types)
  
  -- Send to plugin's OSC port
  local client = uv.new_udp()
  client:send(message, "127.0.0.1", 6011, function(err)
    if err then
      print("Error sending OSC message:", err)
    end
    client:close()
  end)
end

-- Send multiple highlight events for testing patterns
function M.send_pattern_highlights(pattern_text, buffer_id, row)
  buffer_id = buffer_id or vim.api.nvim_get_current_buf()
  row = row or 0
  
  -- Simulate highlighting different parts of a Tidal pattern
  local words = {}
  for word in pattern_text:gmatch("%S+") do
    table.insert(words, word)
  end
  
  local col = 0
  for i, word in ipairs(words) do
    -- Skip numbers and common words
    if not word:match("^%d+$") and word ~= "p" then
      vim.defer_fn(function()
        M.send_highlight_event({
          event_id = i,
          buffer_id = buffer_id,
          row = row,
          start_col = col,
          end_col = col + #word,
          duration = 0.5,
          cycle = i * 0.25
        })
      end, i * 100) -- Stagger events
    end
    col = col + #word + 1 -- Account for spaces
  end
end

-- Test commands
function M.setup_test_commands()
  vim.api.nvim_create_user_command('TidalTestSingleHighlight', function()
    M.send_highlight_event()
  end, {})
  
  vim.api.nvim_create_user_command('TidalTestPatternHighlight', function()
    local line = vim.api.nvim_get_current_line()
    local cursor = vim.api.nvim_win_get_cursor(0)
    M.send_pattern_highlights(line, vim.api.nvim_get_current_buf(), cursor[1] - 1)
  end, {})
  
  vim.api.nvim_create_user_command('TidalTestStressHighlight', function()
    -- Send many events quickly
    for i = 1, 20 do
      vim.defer_fn(function()
        M.send_highlight_event({
          event_id = i,
          row = math.random(0, 10),
          start_col = math.random(0, 50),
          end_col = math.random(10, 80)
        })
      end, i * 50)
    end
  end, {})
end

return M