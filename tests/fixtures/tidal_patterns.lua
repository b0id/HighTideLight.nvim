-- Test fixtures with sample Tidal patterns for testing
local M = {}

-- Basic drum patterns
M.drum_patterns = {
  'd1 $ sound "bd sn"',
  'd1 $ sound "bd*2 sn"',
  'd1 $ sound "bd sn hh oh"',
  'd1 $ sound "[bd bd] sn"',
  'd1 $ sound "bd [sn sn]"',
  'd1 $ sound "bd*3 sn*2 hh*4"',
  'd1 $ sound "bd(3,8) sn(5,8)"',
}

-- Patterns with controls
M.control_patterns = {
  'd1 $ sound "bd sn" # gain 0.8',
  'd1 $ sound "bd sn" # gain 0.8 # pan 0.5',
  'd1 $ sound "bd sn" # lpf 1000 # res 0.3',
  'd1 $ sound "bd sn" # room 0.3 # size 0.8',
  'd1 $ sound "bd sn" # begin 0.1 # end 0.9',
  'd1 $ sound "bd sn" # speed 0.5 # crush 8',
}

-- Complex patterns
M.complex_patterns = {
  'd1 $ jux rev $ sound "bd*2 [sn oh]"',
  'd1 $ every 4 (|+| speed 2) $ sound "bd sn hh"',
  'd1 $ off 0.25 (|+| n 12) $ sound "bass"',
  'd1 $ stack [sound "bd*2", sound "~ sn", sound "hh*8"]',
  'd1 $ whenmod 8 6 (# crush 8) $ sound "bd sn"',
  'd1 $ degradeBy 0.2 $ sound "hh*16"',
}

-- Multi-line patterns
M.multiline_patterns = {
  [[d1 $ sound "bd sn"
   # gain 0.8
   # pan (slow 4 sine)]],
  
  [[d1 $ stack [
     sound "bd*2",
     sound "~ sn",
     sound "hh*8" # gain 0.6
   ]],
   
  [[d1 $ every 4 (
     rev . (# speed 2)
   ) $ sound "bd sn hh oh"]]
}

-- Patterns with variables
M.variable_patterns = {
  'let drums = "bd sn hh oh"',
  'let melody = "c d e f g"',
  'd1 $ sound drums',
  'd2 $ n melody # s "piano"',
  'p 1 $ sound "bd sn"',
  'p "drums" $ sound "bd*2 sn"',
}

-- Error patterns (for testing error handling)
M.error_patterns = {
  'd1 $ sond "bd sn"',  -- typo in 'sound'
  'd1 $ sound [bd sn"',  -- unmatched bracket
  'd1 $ sound "bd sn" #',  -- incomplete control
  '',  -- empty line
  '-- comment only',
}

-- Expected highlights for testing
M.expected_highlights = {
  ['d1 $ sound "bd sn"'] = {
    {word = "bd", type = "mini_notation", start_col = 11, end_col = 13},
    {word = "sn", type = "mini_notation", start_col = 14, end_col = 16},
  },
  
  ['d1 $ sound "bd sn" # gain 0.8'] = {
    {word = "bd", type = "mini_notation", start_col = 11, end_col = 13},
    {word = "sn", type = "mini_notation", start_col = 14, end_col = 16},
    {word = "gain", type = "control"},
  },
  
  ['d1 $ sound "bd*2 sn hh"'] = {
    {word = "bd*2", type = "mini_notation"},
    {word = "sn", type = "mini_notation"},
    {word = "hh", type = "mini_notation"},
  }
}

-- Test cases for processor
M.processor_test_cases = {
  {
    input = 'd1 $ sound "bd sn"',
    should_inject_context = true,
    expected_markers = 2,  -- bd, sn
    expected_mini_notation = {"bd", "sn"},
    expected_controls = {},
  },
  
  {
    input = 'd1 $ sound "bd sn" # gain 0.8 # pan 0.5',
    should_inject_context = true,
    expected_markers = 4,  -- bd, sn, gain, pan
    expected_mini_notation = {"bd", "sn"},
    expected_controls = {"gain", "pan"},
  },
  
  {
    input = 'let drums = "bd sn hh"',
    should_inject_context = false,  -- variable definitions don't get context
    expected_markers = 3,  -- bd, sn, hh
    expected_mini_notation = {"bd", "sn", "hh"},
    expected_controls = {},
  },
  
  {
    input = 'd1 $ sound "bd 1 sn 2"',
    should_inject_context = true,
    expected_markers = 2,  -- bd, sn (numbers excluded)
    expected_mini_notation = {"bd", "sn"},
    expected_controls = {},
  }
}

-- OSC test events
M.osc_test_events = {
  {
    address = "/editor/highlights",
    args = {1, 1, 0, 10, 15, 0.5, 1.0},
    types = "iiiiiff",
    description = "Basic highlight event"
  },
  
  {
    address = "/editor/highlights", 
    args = {2, 1, 1, 0, 20, 1.0, 2.0},
    types = "iiiiiff", 
    description = "Second line highlight"
  },
  
  {
    address = "/editor/highlights",
    args = {3, 2, 0, 5, 8, 0.25, 0.5},
    types = "iiiiiff",
    description = "Different buffer highlight"
  }
}

-- Performance test data
M.performance_patterns = {}
for i = 1, 100 do
  table.insert(M.performance_patterns, string.format('d%d $ sound "bd sn hh oh"', i))
end

-- Helper function to get random pattern
function M.get_random_pattern(category)
  category = category or "drum_patterns"
  local patterns = M[category]
  if patterns and #patterns > 0 then
    return patterns[math.random(#patterns)]
  end
  return 'd1 $ sound "bd sn"'  -- fallback
end

-- Helper function to validate pattern structure
function M.validate_pattern(pattern)
  -- Basic validation
  if type(pattern) ~= "string" or pattern == "" then
    return false, "Pattern must be non-empty string"
  end
  
  -- Check for basic Tidal structure
  if not (pattern:match("^d%d+") or pattern:match("^p%s") or pattern:match("^let%s")) then
    return false, "Pattern should start with d1-9, p, or let"
  end
  
  return true, "Valid pattern"
end

return M