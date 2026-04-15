local M = {}
local config = require("bmcp.config")

local paused = false
local next_snapshot_at = 0
local next_poll_at = 0

local function now_seconds()
  return os.clock()
end

local function get_G()
  return rawget(_G, "G")
end

local function is_busy_state()
  local G = get_G()
  if G == nil then
    return false
  end
  if type(G.STATES) ~= "table" then
    return false
  end

  local state = G.STATE
  local states = G.STATES

  -- Drawing cards to hand: hand layout is not stable yet
  if states.DRAW_TO_HAND ~= nil and state == states.DRAW_TO_HAND then
    return true
  end

  -- Hand animation playing: wait for scoring/effect to finish
  if states.HAND_PLAYED ~= nil and state == states.HAND_PLAYED then
    return true
  end

  return false
end

function M.pause()
  paused = true
end

function M.resume()
  paused = false
end

function M.is_paused()
  return paused
end

function M.can_control()
  if paused then
    return false
  end
  if is_busy_state() then
    return false
  end
  return true
end

function M.should_push_snapshot()
  local now = now_seconds()
  if now < next_snapshot_at then
    return false
  end
  next_snapshot_at = now + config.snapshot_interval_seconds
  return true
end

function M.should_poll_command()
  local now = now_seconds()
  if now < next_poll_at then
    return false
  end
  next_poll_at = now + config.command_poll_interval_seconds
  return true
end

function M.reset_timers()
  next_snapshot_at = 0
  next_poll_at = 0
end

return M
