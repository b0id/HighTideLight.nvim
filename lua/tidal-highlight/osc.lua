-- ~/.config/nvim/lua/tidal-highlight/osc.lua
local uv = vim.loop
local bit = require('bit')

local M = {}
M.server = nil
M.client = nil
M.callbacks = {}

-- Helper function to write a 32-bit integer big-endian
local function write_int32_be(val)
  return string.char(
    bit.band(bit.rshift(val, 24), 0xFF),
    bit.band(bit.rshift(val, 16), 0xFF),
    bit.band(bit.rshift(val, 8), 0xFF),
    bit.band(val, 0xFF)
  )
end

-- Helper function to pad a string to a 4-byte boundary
local function pad_string(str)
  local padded = str .. "\0"
  while #padded % 4 ~= 0 do
    padded = padded .. "\0"
  end
  return padded
end

-- Function to build an OSC message
local function build_osc_message(address, args)
  local message = pad_string(address)
  local type_tags = ","
  local arg_data = ""

  for _, arg in ipairs(args) do
    if type(arg) == "number" and math.floor(arg) == arg then
      type_tags = type_tags .. "i"
      arg_data = arg_data .. write_int32_be(arg)
    elseif type(arg) == "number" then
      -- Simplified float to bytes (not fully accurate)
      type_tags = type_tags .. "f"
      local f_val = math.floor(arg * 2^20)
      arg_data = arg_data .. write_int32_be(f_val) -- Placeholder
    elseif type(arg) == "string" then
      type_tags = type_tags .. "s"
      arg_data = arg_data .. pad_string(arg)
    end
  end

  message = message .. pad_string(type_tags) .. arg_data
  return message
end

-- Send an OSC message
function M.send(address, args, dest_ip, dest_port)
  if not M.client then
    M.client = uv.new_udp()
  end

  local message = build_osc_message(address, args)
  
  M.client:send(message, dest_ip, dest_port, function(err)
    if err then
      vim.schedule(function()
        vim.notify("OSC send error: " .. err, vim.log.levels.ERROR)
      end)
    end
  end)
end

-- Helper functions for binary data parsing (Lua 5.1 compatible)
local function read_uint32_be(data, offset)
  local b1, b2, b3, b4 = data:byte(offset, offset + 3)
  -- Use math operations instead of bit operations to avoid overflow
  return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
end

local function read_int32_be(data, offset)
  local val = read_uint32_be(data, offset)
  if val > 2147483647 then  -- 0x7FFFFFFF
    val = val - 4294967296  -- 0x100000000
  end
  return val
end

local function read_float32_be(data, offset)
  -- Simple float parsing (not perfectly accurate but good enough for testing)
  local b1, b2, b3, b4 = data:byte(offset, offset + 3)
  local bits = bit.lshift(b1, 24) + bit.lshift(b2, 16) + bit.lshift(b3, 8) + b4
  
  if bits == 0 then return 0.0 end
  
  local sign = bit.rshift(bits, 31) == 1 and -1 or 1
  local exp = bit.band(bit.rshift(bits, 23), 0xFF) - 127
  local frac = bit.band(bits, 0x7FFFFF) / 0x800000 + 1
  
  return sign * frac * (2 ^ exp)
end

-- OSC packet parsing
local function parse_osc_packet(data)
  vim.notify("[HighTideLight] Parsing OSC packet...", vim.log.levels.INFO)
  local messages = {}
  local offset = 1
  
  -- Check if it's a bundle
  if data:sub(1, 8) == "#bundle\0" then
    -- Parse OSC bundle
    offset = 17  -- Skip bundle header and timetag
    
    while offset < #data do
      local size = read_uint32_be(data, offset)
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
      vim.notify("[HighTideLight] Parsed message: " .. msg.address, vim.log.levels.INFO)
      table.insert(messages, msg)
    else
      vim.notify("[HighTideLight] Failed to parse message.", vim.log.levels.WARN)
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
      local val = read_int32_be(data, offset)
      table.insert(args, val)
      offset = offset + 4
    elseif type_char == "f" then
      -- 32-bit float
      local val = read_float32_be(data, offset)
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
      -- 64-bit double (simplified - just read as two 32-bit values)
      local high = read_uint32_be(data, offset)
      local low = read_uint32_be(data, offset + 4)
      -- For testing, just approximate as float
      local val = high / 1000000.0  -- Simplified conversion
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
  
  vim.notify("[HighTideLight] Starting OSC server on " .. config.osc.ip .. ":" .. config.osc.port, vim.log.levels.INFO)
  M.server = uv.new_udp()
  M.server:bind(config.osc.ip, config.osc.port, function(err)
      if err then
          vim.schedule(function()
              vim.notify("OSC BIND error: " .. err, vim.log.levels.ERROR)
          end)
      end
  end)
  
  M.server:recv_start(function(err, data, addr, flags)
    vim.schedule(function()
      vim.notify("[HighTideLight] OSC recv_start callback fired!", vim.log.levels.INFO)
    end)
    if err then
      vim.schedule(function()
        vim.notify("OSC RECV error: " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    
    if data then
      vim.schedule(function()
        vim.notify("[HighTideLight] Received OSC data!", vim.log.levels.INFO)
      end)
      local messages = parse_osc_packet(data)
      
      for _, msg in ipairs(messages) do
        vim.schedule(function()
          vim.notify("[HighTideLight] Dispatching message: " .. msg.address, vim.log.levels.INFO)
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
    vim.notify("[HighTideLight] OSC server stopped.", vim.log.levels.INFO)
  end
end

-- Register callback for OSC address pattern
function M.on(address_pattern, callback)
  M.callbacks[address_pattern] = callback
end

-- Expose for testing
M.parse_osc_message = parse_osc_message

return M
