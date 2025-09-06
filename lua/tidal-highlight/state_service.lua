-- lua/tidal-highlight/state_service.lua
-- Persistent stateful background service for OSC telemetry synchronization

local M = {}

-- Service state
local service_state = {
  active = false,
  sync_timer = nil,
  heartbeat_timer = nil,
  last_sync_time = 0,
  sync_failures = 0,
  registered_patterns = {},  -- Track what we've sent to SuperCollider
  pending_registrations = {} -- Queue for retry on failure
}

-- Dependencies
local integration = require('tidal-highlight.integration')
local osc = require('tidal-highlight.osc')
local config = require('tidal-highlight.config')

-- Configuration
local SYNC_INTERVAL_MS = 10000     -- Check every 10 seconds (reduced frequency)
local HEARTBEAT_INTERVAL_MS = 30000 -- Ping SuperCollider every 30s
local MAX_SYNC_FAILURES = 10       -- More tolerant of failures
local REGISTRATION_RETRY_MS = 2000  -- Retry failed registrations

--- Send heartbeat to SuperCollider to detect connection issues
local function send_heartbeat()
  local timestamp = vim.loop.hrtime()
  osc.send("/tidal/heartbeat", {timestamp}, config.current.supercollider.ip, config.current.supercollider.port)
  
  if vim.g.tidal_highlight_debug then
    vim.notify("HighTideLight: Heartbeat sent to SuperCollider", vim.log.levels.DEBUG)
  end
end

--- Register source map data with SuperCollider
local function register_source_maps()
  local stats = integration.get_stats()
  local registrations_sent = 0
  
  for bufnr, buf_source_maps in pairs(integration.active_source_maps or {}) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      for range_key, range_data in pairs(buf_source_maps) do
        local orbit = range_data.orbit
        local source_map_data = range_data.source_map
        
        -- Create registration key for deduplication
        local reg_key = bufnr .. ":" .. range_key .. ":" .. orbit
        
        -- Only register if not already registered or if data changed
        if not service_state.registered_patterns[reg_key] or 
           service_state.registered_patterns[reg_key].timestamp < range_data.last_updated then
          
          -- Send pattern text registration
          osc.send("/tidal/pattern", {
            orbit,
            range_data.line_content or "",
            0  -- colOffset (could be enhanced later)
          }, config.current.supercollider.ip, config.current.supercollider.port)
          
          -- Send individual sound positions
          for unique_id, token_info in pairs(source_map_data) do
            osc.send("/tidal/sound_position", {
              orbit,
              token_info.value,
              token_info.range.start.col,
              token_info.range["end"].col
            }, config.current.supercollider.ip, config.current.supercollider.port)
            
            registrations_sent = registrations_sent + 1
          end
          
          -- Mark as registered
          service_state.registered_patterns[reg_key] = {
            timestamp = vim.loop.hrtime(),
            orbit = orbit,
            token_count = vim.tbl_count(source_map_data)
          }
        end
      end
    end
  end
  
  if registrations_sent > 0 and vim.g.tidal_highlight_debug then
    vim.notify(string.format("HighTideLight: Sent %d registrations to SuperCollider", registrations_sent), vim.log.levels.INFO)
  end
  
  return registrations_sent
end

--- Clean up stale registrations for invalid buffers
local function cleanup_stale_registrations()
  local cleaned = 0
  local valid_keys = {}
  
  -- Build set of valid keys from current active source maps
  for bufnr, buf_source_maps in pairs(integration.active_source_maps or {}) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      for range_key, range_data in pairs(buf_source_maps) do
        local reg_key = bufnr .. ":" .. range_key .. ":" .. range_data.orbit
        valid_keys[reg_key] = true
      end
    end
  end
  
  -- Remove registrations for keys that no longer exist
  for reg_key, _ in pairs(service_state.registered_patterns) do
    if not valid_keys[reg_key] then
      service_state.registered_patterns[reg_key] = nil
      cleaned = cleaned + 1
    end
  end
  
  if cleaned > 0 and vim.g.tidal_highlight_debug then
    vim.notify(string.format("HighTideLight: Cleaned up %d stale registrations", cleaned), vim.log.levels.DEBUG)
  end
end

--- Main synchronization function
local function sync_state()
  local start_time = vim.loop.hrtime()
  
  pcall(function()
    -- Clean up stale data
    cleanup_stale_registrations()
    
    -- Register current source maps
    local registrations = register_source_maps()
    
    -- Update service state
    service_state.last_sync_time = start_time
    service_state.sync_failures = 0  -- Reset on successful sync
    
    local duration_ms = (vim.loop.hrtime() - start_time) / 1e6
    if vim.g.tidal_highlight_debug then
      vim.notify(string.format("HighTideLight: State sync completed in %.1fms (%d registrations)", 
        duration_ms, registrations), vim.log.levels.DEBUG)
    end
  end)
end

--- Handle sync failures with backoff and recovery
local function handle_sync_failure(error_msg)
  service_state.sync_failures = service_state.sync_failures + 1
  
  if vim.g.tidal_highlight_debug then
    vim.notify(string.format("HighTideLight: State sync failure #%d: %s", 
      service_state.sync_failures, error_msg), vim.log.levels.WARN)
  end
  
  if service_state.sync_failures >= MAX_SYNC_FAILURES then
    vim.notify("HighTideLight: Too many sync failures, restarting service", vim.log.levels.ERROR)
    M.restart()
  end
end

--- Start the background state synchronization service
function M.start()
  if service_state.active then
    return false
  end
  
  service_state.active = true
  service_state.sync_failures = 0
  service_state.registered_patterns = {}
  
  -- Initial synchronization
  sync_state()
  
  -- Set up periodic synchronization with drift detection
  service_state.sync_timer = vim.fn.timer_start(SYNC_INTERVAL_MS, function()
    if service_state.active then
      sync_state()  -- Use basic sync for timer
    end
  end, { ['repeat'] = -1 })
  
  -- Set up heartbeat
  service_state.heartbeat_timer = vim.fn.timer_start(HEARTBEAT_INTERVAL_MS, function()
    if service_state.active then
      pcall(send_heartbeat)
    end
  end, { ['repeat'] = -1 })
  
  if vim.g.tidal_highlight_debug then
    vim.notify("HighTideLight: State synchronization service started", vim.log.levels.INFO)
  end
  
  return true
end

--- Stop the background service
function M.stop()
  if not service_state.active then
    return false
  end
  
  service_state.active = false
  
  if service_state.sync_timer then
    vim.fn.timer_stop(service_state.sync_timer)
    service_state.sync_timer = nil
  end
  
  if service_state.heartbeat_timer then
    vim.fn.timer_stop(service_state.heartbeat_timer)
    service_state.heartbeat_timer = nil
  end
  
  if vim.g.tidal_highlight_debug then
    vim.notify("HighTideLight: State synchronization service stopped", vim.log.levels.INFO)
  end
  
  return true
end

--- Restart the service
function M.restart()
  M.stop()
  vim.defer_fn(function()
    M.start()
  end, 1000) -- Wait 1 second before restart
end

--- Force immediate state synchronization
function M.force_sync()
  if service_state.active then
    sync_state()
    return true
  end
  return false
end

--- Get service statistics
function M.get_stats()
  return {
    active = service_state.active,
    last_sync_time = service_state.last_sync_time,
    sync_failures = service_state.sync_failures,
    registered_patterns_count = vim.tbl_count(service_state.registered_patterns),
    uptime_seconds = service_state.last_sync_time > 0 and 
      (vim.loop.hrtime() - service_state.last_sync_time) / 1e9 or 0
  }
end

--- Detect state drift by checking registration consistency
local function detect_state_drift()
  local drift_detected = false
  local current_stats = integration.get_stats()
  local expected_registrations = current_stats.total_tokens
  local actual_registrations = vim.tbl_count(service_state.registered_patterns)
  
  -- Check for significant discrepancy
  if math.abs(expected_registrations - actual_registrations) > 5 then
    drift_detected = true
    if vim.g.tidal_highlight_debug then
      vim.notify(string.format("HighTideLight: State drift detected - expected %d registrations, have %d", 
        expected_registrations, actual_registrations), vim.log.levels.WARN)
    end
  end
  
  -- Check for stale registrations (older than 5 minutes)
  local now = vim.loop.hrtime()
  local stale_threshold = 5 * 60 * 1e9 -- 5 minutes in nanoseconds
  local stale_count = 0
  
  for reg_key, reg_data in pairs(service_state.registered_patterns) do
    if (now - reg_data.timestamp) > stale_threshold then
      stale_count = stale_count + 1
    end
  end
  
  if stale_count > 3 then
    drift_detected = true
    if vim.g.tidal_highlight_debug then
      vim.notify(string.format("HighTideLight: %d stale registrations detected", stale_count), vim.log.levels.WARN)
    end
  end
  
  return drift_detected
end

--- Recover from state drift
local function recover_from_drift()
  if vim.g.tidal_highlight_debug then
    vim.notify("HighTideLight: Initiating state drift recovery", vim.log.levels.INFO)
  end
  
  -- Clear all registrations to force fresh sync
  service_state.registered_patterns = {}
  
  -- Force immediate full synchronization
  sync_state()
  
  -- Send recovery notification to SuperCollider
  osc.send("/tidal/recovery", {vim.loop.hrtime()}, config.current.supercollider.ip, config.current.supercollider.port)
end

--- Enhanced sync with drift detection and better error handling
local function sync_state_with_drift_detection()
  local start_time = vim.loop.hrtime()
  
  local success, error_msg = pcall(function()
    -- Check for state drift before sync
    local drift_detected = detect_state_drift()
    
    if drift_detected then
      recover_from_drift()
    else
      -- Normal sync operations
      cleanup_stale_registrations()
      register_source_maps()
    end
    
    -- Update service state
    service_state.last_sync_time = start_time
    service_state.sync_failures = 0  -- Reset only on complete success
    
    local duration_ms = (vim.loop.hrtime() - start_time) / 1e6
    if vim.g.tidal_highlight_debug then
      vim.notify(string.format("HighTideLight: State sync completed in %.1fms %s", 
        duration_ms, drift_detected and "(with recovery)" or ""), vim.log.levels.DEBUG)
    end
  end)
  
  if not success then
    service_state.sync_failures = service_state.sync_failures + 1
    if vim.g.tidal_highlight_debug then
      vim.notify(string.format("HighTideLight: Sync failure #%d: %s", 
        service_state.sync_failures, error_msg or "unknown error"), vim.log.levels.WARN)
    end
    
    if service_state.sync_failures >= MAX_SYNC_FAILURES then
      vim.notify("HighTideLight: Too many sync failures, restarting service", vim.log.levels.ERROR)
      M.restart()
    end
  end
end

--- Register evaluation event (called when Tidal pattern is evaluated)
function M.on_pattern_evaluation(bufnr, line_range)
  if service_state.active then
    -- Force immediate sync for new evaluations
    vim.defer_fn(function()
      sync_state_with_drift_detection()
    end, 100) -- Small delay to allow source map updates
  end
end

--- Hook into Tidal evaluation to trigger immediate sync
function M.hook_tidal_evaluation()
  -- This will be called by the Tidal API wrapper
  M.on_pattern_evaluation(vim.api.nvim_get_current_buf(), nil)
end

return M