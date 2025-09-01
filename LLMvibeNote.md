-- Modify processor.lua to inject deltaContext correctly
function M.process_line(buffer, line_num, text)
  local event_id = M.next_event_id
  M.next_event_id = M.next_event_id + 1
  
  -- Key insight from Pulsar: inject at the pattern level, not individual words
  -- Look for pattern definitions (d1, d2, p 1, etc)
  local processed = text:gsub('(%$%s*)(".-")', function(dollar, quoted)
    -- Store the column offset for this pattern
    local _, col_start = text:find(dollar, 1, true)
    M.event_ids[event_id] = {
      buffer = buffer,
      row = line_num - 1,
      col_offset = col_start,  -- Store offset for mapping
    }
    -- Inject deltaContext with column offset and event ID
    return dollar .. '(deltaContext ' .. col_start .. ' ' .. event_id .. ' ' .. quoted .. ')'
  end)

  - Update osc.lua to handle the exact format from Tidal
function parse_osc_message(data)
  local offset = 1
  
  -- Check for /editor/highlights address
  local addr_end = data:find("\0", offset)
  local address = data:sub(offset, addr_end - 1)
  
  if address ~= "/editor/highlights" then
    return nil
  end
  
  -- Parse based on Pulsar's expected format:
  -- [id, duration, cycle, colStart, eventId, colEnd]
  -- ... existing parsing code ...
  
  -- Transform to match Pulsar structure
  return {
    address = address,
    args = {
      id = args[1],          -- stream ID (d1=1, d2=2, etc)
      duration = args[2],    -- event duration
      cycle = args[3],       -- current cycle
      colStart = args[4],    -- start column in pattern
      eventId = args[5] - 1, -- event ID (0-indexed)
      colEnd = args[6]       -- end column in pattern
    }
  }
end
  
  return processed, event_id
end

-- In highlights.lua
function M.add_highlight(event_data)
  local event_info = processor.get_event_info(event_data.eventId)
  if not event_info then return end
  
  local buffer = event_info.buffer
  local row = event_info.row
  
  -- Calculate actual column positions
  -- The colStart/colEnd are relative to the pattern string
  local actual_start = event_info.col_offset + event_data.colStart
  local actual_end = event_info.col_offset + event_data.colEnd
  
  -- Create highlight with proper decay animation
  M.create_animated_highlight(buffer, row, actual_start, actual_end, event_data)
end

function M.create_animated_highlight(buffer, row, start_col, end_col, event_data)
  local ns = M.namespace
  local hl_group = M.get_highlight_group(event_data.id)
  
  -- Initial bright highlight
  local mark_id = vim.api.nvim_buf_set_extmark(buffer, ns, row, start_col, {
    end_row = row,
    end_col = end_col,
    hl_group = hl_group,
    priority = 100 + (10 - event_data.id), -- Layer by stream
    strict = false,
  })
  
  -- Animate decay over duration
  local steps = 5
  local decay_time = (event_data.duration * 1000) / steps
  
  for i = 1, steps do
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buffer) then
        -- Update with fading highlight
        local fade_group = hl_group .. "_fade_" .. i
        vim.api.nvim_buf_del_extmark(buffer, ns, mark_id)
        if i < steps then
          mark_id = vim.api.nvim_buf_set_extmark(buffer, ns, row, start_col, {
            end_row = row,
            end_col = end_col,
            hl_group = fade_group,
            priority = 100 + (10 - event_data.id) - i,
            strict = false,
          })
        end
      end
    end, i * decay_time)
  end
end

-- In config.lua setup
function M.create_highlight_groups()
  local colors = {
    { base = "#ff6b6b", name = "TidalStream1" },
    { base = "#4ecdc4", name = "TidalStream2" },
    { base = "#45b7d1", name = "TidalStream3" },
    { base = "#96ceb4", name = "TidalStream4" },
  }
  
  for _, color in ipairs(colors) do
    -- Base highlight
    vim.api.nvim_set_hl(0, color.name, {
      bg = color.base,
      blend = 20,
    })
    
    -- Fade stages
    for i = 1, 5 do
      local blend = 20 + (i * 10) -- Increase transparency
      vim.api.nvim_set_hl(0, color.name .. "_fade_" .. i, {
        bg = color.base,
        blend = blend,
      })
    end
  end
end
6. Testing Configuration
Add to your BootTidal.hs:
7. Debug Commands
Add these for testing:
luavim.api.nvim_create_user_command('TidalHighlightDebug', function()
  -- Show current event mappings
  local processor = require('tidal-highlight.processor')
  print(vim.inspect(processor.event_ids))
  
  -- Show active highlights
  local highlights = require('tidal-highlight.highlights')
  print(vim.inspect(highlights.highlights))
end, {})

vim.api.nvim_create_user_command('TidalHighlightSimulate', function()
  -- Simulate an OSC message for testing
  local animation = require('tidal-highlight.animation')
  animation.queue_event({
    id = 1,
    eventId = 0,
    colStart = 0,
    colEnd = 10,
    duration = 0.5,
    cycle = 1.0
  })
end, {})