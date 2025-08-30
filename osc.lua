-- ~/.config/nvim/lua/tidal-highlight/osc.lua
local uv = vim.loop
local bit = require('bit')

local M = {}
M.server = nil
M.callbacks = {}

-- OSC packet parsing
local function parse_osc_packet(data)
  local messages = {}
  local offset = 1
  
  -- Check if it's a bundle
  if data:sub(1, 8) == "#bundle\0" then
    -- Parse OSC bundle
    offset = 17  -- Skip bundle header and timetag
    
    while offset < #data do
      local size = string.unpack(">I4", data, offset)
      offset = offset + 4
      local msg_data = data:sub(offset, offset + size - 1)
      local msg = parse_osc_message(msg_data)
      if msg then
        table.insert(messages, msg)
      end
      offset = offset + size
    end
  else
    -- Single message
    local msg = parse_osc_message(data)
    if msg then
      table.insert(messages, msg)
    end
  end
  
  return messages
end

-- Parse single OSC message
function parse_osc_message(data)
  local offset = 1
  
  -- Extract address pattern (null-terminated string)
  local addr_end = data:find("\0", offset)
  if not addr_end then return nil end
  
  local address = data:sub(offset, addr_end - 1)
  offset = addr_end + 1
  
  -- Align to 4-byte boundary
  while (offset - 1) % 4 ~= 0 do
    offset = offset + 1
  end
  
  -- Extract type tag string
  if data:sub(offset, offset) ~= "," then return nil end
  local type_end = data:find("\0", offset)
  if not type_end then return nil end
  
  local types = data:sub(offset + 1, type_end - 1)
  offset = type_end + 1
  
  -- Align to 4-byte boundary
  while (offset - 1) % 4 ~= 0 do
    offset = offset + 1
  end
  
  -- Parse arguments based on type tags
  local args = {}
  for i = 1, #types do
    local type_char = types:sub(i, i)
    
    if type_char == "i" then
      -- 32-bit integer
      local val = string.unpack(">i4", data, offset)
      table.insert(args, val)
      offset = offset + 4
    elseif type_char == "f" then
      -- 32-bit float
      local val = string.unpack(">f", data, offset)
      table.insert(args, val)
      offset = offset + 4
    elseif type_char == "s" then
      -- String
      local str_end = data:find("\0", offset)
      local str = data:sub(offset, str_end - 1)
      table.insert(args, str)
      offset = str_end + 1
      -- Align to 4-byte boundary
      while (offset - 1) % 4 ~= 0 do
        offset = offset + 1
      end
    elseif type_char == "d" then
      -- 64-bit double
      local val = string.unpack(">d", data, offset)
      table.insert(args, val)
      offset = offset + 8
    end
  end
  
  return {
    address = address,
    args = args
  }
end

-- Start OSC server
function M.start(config)
  if M.server then
    M.stop()
  end
  
  M.server = uv.new_udp()
  M.server:bind(config.osc.ip, config.osc.port)
  
  M.server:recv_start(function(err, data, addr, flags)
    if err then
      if config.debug then
        vim.schedule(function()
          vim.notify("OSC error: " .. err, vim.log.levels.ERROR)
        end)
      end
      return
    end
    
    if data then
      local messages = parse_osc_packet(data)
      
      for _, msg in ipairs(messages) do
        vim.schedule(function()
          -- Call registered callbacks
          for pattern, callback in pairs(M.callbacks) do
            if msg.address:match(pattern) then
              callback(msg.args, msg.address)
            end
          end
        end)
      end
    end
  end)
  
  if config.debug then
    print(string.format("OSC server listening on %s:%d", config.osc.ip, config.osc.port))
  end
end

-- Stop OSC server
function M.stop()
  if M.server then
    M.server:recv_stop()
    M.server:close()
    M.server = nil
  end
end

-- Register callback for OSC address pattern
function M.on(address_pattern, callback)
  M.callbacks[address_pattern] = callback
end

return M