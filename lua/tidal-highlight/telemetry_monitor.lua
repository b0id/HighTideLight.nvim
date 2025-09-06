-- lua/tidal-highlight/telemetry_monitor.lua
-- Comprehensive telemetry validation and monitoring system

local M = {}

-- Monitoring state
local monitor_state = {
  message_log = {},           -- Circular buffer of recent OSC messages
  validation_errors = {},     -- Track validation failures
  performance_metrics = {},   -- Timing and performance data
  active = false,
  log_size_limit = 100       -- Maximum messages to keep in log
}

-- Message validation rules
local VALIDATION_RULES = {
  ["/neovim/highlight"] = {
    arg_count = 6,
    arg_types = {"number", "number", "number", "number", "number", "string"},
    arg_names = {"lineStart", "colStart", "lineEnd", "colEnd", "delta", "sound"},
    constraints = {
      lineStart = function(val) return val >= 1 and val <= 10000 end,
      colStart = function(val) return val >= 0 and val <= 1000 end,
      lineEnd = function(val) return val >= 1 and val <= 10000 end,
      colEnd = function(val) return val >= 0 and val <= 1000 end,
      delta = function(val) return val > 0 and val <= 30 end, -- Max 30 second highlights
      sound = function(val) return type(val) == "string" and #val > 0 and #val <= 50 end
    }
  }
}

--- Add message to circular log
local function log_message(address, args, timestamp, validation_result)
  local message = {
    timestamp = timestamp,
    address = address,
    args = args,
    arg_count = #args,
    validation = validation_result,
    id = (#monitor_state.message_log + 1)
  }
  
  table.insert(monitor_state.message_log, message)
  
  -- Maintain circular buffer
  if #monitor_state.message_log > monitor_state.log_size_limit then
    table.remove(monitor_state.message_log, 1)
  end
end

--- Validate OSC message against rules
local function validate_message(address, args)
  local rules = VALIDATION_RULES[address]
  if not rules then
    return {
      valid = false,
      error = "No validation rules for address: " .. address,
      code = "NO_RULES"
    }
  end
  
  -- Check argument count
  if #args ~= rules.arg_count then
    return {
      valid = false,
      error = string.format("Expected %d arguments, got %d", rules.arg_count, #args),
      code = "ARG_COUNT_MISMATCH",
      expected = rules.arg_count,
      actual = #args
    }
  end
  
  -- Check argument types
  for i, expected_type in ipairs(rules.arg_types) do
    local actual_type = type(args[i])
    if actual_type ~= expected_type then
      return {
        valid = false,
        error = string.format("Arg %d (%s): expected %s, got %s", 
          i, rules.arg_names[i], expected_type, actual_type),
        code = "TYPE_MISMATCH",
        arg_index = i,
        arg_name = rules.arg_names[i]
      }
    end
  end
  
  -- Check constraints
  for i, arg in ipairs(args) do
    local arg_name = rules.arg_names[i]
    local constraint = rules.constraints[arg_name]
    if constraint and not constraint(arg) then
      return {
        valid = false,
        error = string.format("Arg %d (%s): constraint violation - value: %s", 
          i, arg_name, tostring(arg)),
        code = "CONSTRAINT_VIOLATION",
        arg_index = i,
        arg_name = arg_name,
        value = arg
      }
    end
  end
  
  return { valid = true }
end

--- Record performance metrics
local function record_performance_metric(metric_name, duration_ms, metadata)
  if not monitor_state.performance_metrics[metric_name] then
    monitor_state.performance_metrics[metric_name] = {
      count = 0,
      total_time = 0,
      min_time = math.huge,
      max_time = 0,
      recent_samples = {}
    }
  end
  
  local metrics = monitor_state.performance_metrics[metric_name]
  metrics.count = metrics.count + 1
  metrics.total_time = metrics.total_time + duration_ms
  metrics.min_time = math.min(metrics.min_time, duration_ms)
  metrics.max_time = math.max(metrics.max_time, duration_ms)
  
  -- Keep recent samples for trend analysis
  table.insert(metrics.recent_samples, {
    timestamp = vim.loop.hrtime(),
    duration = duration_ms,
    metadata = metadata
  })
  
  -- Limit recent samples to last 50
  if #metrics.recent_samples > 50 then
    table.remove(metrics.recent_samples, 1)
  end
end

--- Monitor OSC message processing
function M.monitor_osc_message(address, args, processing_start_time)
  if not monitor_state.active then
    return { valid = true } -- Pass-through when monitoring disabled
  end
  
  local timestamp = vim.loop.hrtime()
  local processing_duration = processing_start_time and 
    (timestamp - processing_start_time) / 1e6 or 0
  
  -- Validate message
  local validation_result = validate_message(address, args)
  
  -- Log message
  log_message(address, args, timestamp, validation_result)
  
  -- Record performance metrics
  record_performance_metric("osc_processing", processing_duration, {
    address = address,
    arg_count = #args,
    valid = validation_result.valid
  })
  
  -- Track validation errors
  if not validation_result.valid then
    table.insert(monitor_state.validation_errors, {
      timestamp = timestamp,
      address = address,
      args = args,
      error = validation_result
    })
    
    -- Limit error log size
    if #monitor_state.validation_errors > 50 then
      table.remove(monitor_state.validation_errors, 1)
    end
    
    if vim.g.tidal_highlight_debug then
      vim.notify(string.format("HighTideLight: OSC validation error - %s", 
        validation_result.error), vim.log.levels.ERROR)
    end
  end
  
  return validation_result
end

--- Generate telemetry health report
function M.get_health_report()
  local now = vim.loop.hrtime()
  local recent_threshold = 60 * 1e9 -- Last 60 seconds
  
  -- Analyze recent messages
  local recent_messages = {}
  local recent_errors = {}
  
  for _, msg in ipairs(monitor_state.message_log) do
    if (now - msg.timestamp) <= recent_threshold then
      table.insert(recent_messages, msg)
      if not msg.validation.valid then
        table.insert(recent_errors, msg)
      end
    end
  end
  
  -- Calculate error rates
  local total_messages = #monitor_state.message_log
  local recent_message_count = #recent_messages
  local recent_error_count = #recent_errors
  local error_rate = recent_message_count > 0 and 
    (recent_error_count / recent_message_count * 100) or 0
  
  -- Performance analysis
  local perf_summary = {}
  for metric_name, metrics in pairs(monitor_state.performance_metrics) do
    perf_summary[metric_name] = {
      count = metrics.count,
      avg_time = metrics.count > 0 and (metrics.total_time / metrics.count) or 0,
      min_time = metrics.min_time ~= math.huge and metrics.min_time or 0,
      max_time = metrics.max_time
    }
  end
  
  return {
    status = error_rate < 5 and "HEALTHY" or error_rate < 20 and "DEGRADED" or "CRITICAL",
    message_stats = {
      total_messages = total_messages,
      recent_messages = recent_message_count,
      recent_errors = recent_error_count,
      error_rate_percent = error_rate
    },
    performance = perf_summary,
    validation_errors = monitor_state.validation_errors,
    recent_messages = recent_messages
  }
end

--- Start telemetry monitoring
function M.start()
  monitor_state.active = true
  monitor_state.message_log = {}
  monitor_state.validation_errors = {}
  monitor_state.performance_metrics = {}
  
  if vim.g.tidal_highlight_debug then
    vim.notify("HighTideLight: Telemetry monitoring started", vim.log.levels.INFO)
  end
end

--- Stop telemetry monitoring
function M.stop()
  monitor_state.active = false
  
  if vim.g.tidal_highlight_debug then
    vim.notify("HighTideLight: Telemetry monitoring stopped", vim.log.levels.INFO)
  end
end

--- Get recent messages for debugging
function M.get_recent_messages(count)
  count = count or 10
  local recent = {}
  local start_idx = math.max(1, #monitor_state.message_log - count + 1)
  
  for i = start_idx, #monitor_state.message_log do
    table.insert(recent, monitor_state.message_log[i])
  end
  
  return recent
end

--- Check if monitoring is active
function M.is_active()
  return monitor_state.active
end

return M