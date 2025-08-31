-- Unit tests for processor.lua
local processor = require('tidal-highlight.processor')

local M = {}

-- Test helper functions
local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(message or string.format("Expected %s, got %s", expected, actual))
  end
end

local function assert_contains(table, value, message)
  for _, v in ipairs(table) do
    if v == value then return end
  end
  error(message or string.format("Table does not contain %s", value))
end

-- Test line processing
function M.test_process_line_basic()
  local buffer = 1
  local line_num = 1
  local text = 'd1 $ sound "bd sn"'
  
  local processed, event_id = processor.process_line(buffer, line_num, text)
  
  -- Should inject deltaContext
  assert_contains({processed:match("deltaContext")}, "deltaContext", "Should inject deltaContext")
  
  -- Should return event ID
  assert_eq(type(event_id), "number", "Should return numeric event ID")
  
  -- Event info should be stored
  local event_info = processor.get_event_info(event_id)
  assert_eq(event_info.buffer, buffer, "Should store buffer")
  assert_eq(event_info.row, line_num - 1, "Should store row (0-indexed)")
  assert_eq(event_info.original_text, text, "Should store original text")
  
  print("✓ test_process_line_basic passed")
end

-- Test mini-notation detection
function M.test_mini_notation_detection()
  local buffer = 1
  local line_num = 1
  local text = 'd1 $ sound "bd sn hh"'
  
  local processed, event_id = processor.process_line(buffer, line_num, text)
  local event_info = processor.get_event_info(event_id)
  
  -- Should detect mini-notation words
  local found_bd, found_sn, found_hh = false, false, false
  for _, marker in ipairs(event_info.markers) do
    if marker.word == "bd" and marker.type == "mini_notation" then
      found_bd = true
    elseif marker.word == "sn" and marker.type == "mini_notation" then
      found_sn = true
    elseif marker.word == "hh" and marker.type == "mini_notation" then
      found_hh = true
    end
  end
  
  assert_eq(found_bd, true, "Should find 'bd' in mini-notation")
  assert_eq(found_sn, true, "Should find 'sn' in mini-notation")
  assert_eq(found_hh, true, "Should find 'hh' in mini-notation")
  
  print("✓ test_mini_notation_detection passed")
end

-- Test control pattern detection
function M.test_control_pattern_detection()
  local buffer = 1
  local line_num = 1
  local text = 'd1 $ sound "bd" # gain 0.8 # pan 0.5'
  
  local processed, event_id = processor.process_line(buffer, line_num, text)
  local event_info = processor.get_event_info(event_id)
  
  -- Should detect control patterns
  local found_gain, found_pan = false, false
  for _, marker in ipairs(event_info.markers) do
    if marker.word == "gain" and marker.type == "control" then
      found_gain = true
    elseif marker.word == "pan" and marker.type == "control" then
      found_pan = true
    end
  end
  
  assert_eq(found_gain, true, "Should find 'gain' control pattern")
  assert_eq(found_pan, true, "Should find 'pan' control pattern")
  
  print("✓ test_control_pattern_detection passed")
end

-- Test exclusion patterns
function M.test_exclusion_patterns()
  local buffer = 1
  local line_num = 1
  local text = 'd1 $ sound "bd 1 sn 2" # gain 0.8'
  
  local processed, event_id = processor.process_line(buffer, line_num, text)
  local event_info = processor.get_event_info(event_id)
  
  -- Should exclude numbers
  for _, marker in ipairs(event_info.markers) do
    assert_eq(marker.word ~= "1" and marker.word ~= "2", true, 
              "Should exclude numeric patterns")
  end
  
  print("✓ test_exclusion_patterns passed")
end

-- Test event cleanup
function M.test_event_cleanup()
  -- Generate many events
  for i = 1, 150 do
    processor.process_line(1, 1, "test " .. i)
  end
  
  local before_count = 0
  for _ in pairs(processor.event_ids) do
    before_count = before_count + 1
  end
  
  -- Clean up old events
  processor.cleanup_old_events(50)
  
  local after_count = 0
  for _ in pairs(processor.event_ids) do
    after_count = after_count + 1
  end
  
  assert_eq(after_count <= 50, true, "Should clean up old events")
  assert_eq(after_count < before_count, true, "Should reduce event count")
  
  print("✓ test_event_cleanup passed")
end

-- Run all tests
function M.run_all()
  print("Running processor unit tests...")
  
  M.test_process_line_basic()
  M.test_mini_notation_detection()
  M.test_control_pattern_detection()
  M.test_exclusion_patterns()
  M.test_event_cleanup()
  
  print("✅ All processor tests passed!")
end

return M