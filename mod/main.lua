local bridge_client = require("bmcp.bridge_client")
local state_extractor = require("bmcp.state_extractor")
local event_emitter = require("bmcp.event_emitter")
local action_executor = require("bmcp.action_executor")
local sync_controller = require("bmcp.sync_controller")
local state_cache = require("bmcp.state_cache")
local http_server = require("bmcp.http_server")
local adapter = require("bmcp.adapter")
local default_adapter = require("bmcp.default_adapter")
local config = require("bmcp.config")

local M = {}
local next_heartbeat_at = 0
local last_action_times = {}

local ACTION_COOLDOWNS = {
  continue = 0.9,
  choose_option = 0.9,
  skip = 0.9,
  end_turn = 0.9,
  buy_item = 0.4,
  reroll_shop = 0.4,
}

local function now_seconds()
  return os.clock()
end

local function maybe_heartbeat()
  if not config.enable_bridge_client then
    return
  end
  if not config.enable_heartbeat then
    return
  end
  local now = now_seconds()
  if now < next_heartbeat_at then
    return
  end
  next_heartbeat_at = now + config.heartbeat_interval_seconds
  bridge_client.heartbeat()
end

local function log(msg)
  print((config.log_prefix or "[balatro-mcp-mod]") .. " " .. tostring(msg))
end

local function action_cooldown_seconds(action_type)
  return ACTION_COOLDOWNS[action_type] or 0.15
end

local function is_action_throttled(action_type)
  if action_type == nil then
    return false, 0
  end
  local now = now_seconds()
  local cooldown = action_cooldown_seconds(action_type)
  local last_at = last_action_times[action_type]
  if last_at ~= nil then
    local delta = now - last_at
    if delta < cooldown then
      return true, cooldown - delta
    end
  end
  return false, 0
end

local function mark_action_executed(action_type)
  if action_type == nil then
    return
  end
  last_action_times[action_type] = now_seconds()
end

-- Called by the mod loader entry point.
function M.init()
  if adapter.get() == nil then
    adapter.set(default_adapter)
  end
  sync_controller.reset_timers()
  http_server.init()
  local snapshot = state_extractor.extract_game_state()
  if snapshot then
    state_cache.update_snapshot(snapshot)
  end
  if config.enable_bridge_client then
    bridge_client.heartbeat()
  end
  event_emitter.emit("mod_initialized", { ok = true })
end

function M.set_adapter(new_adapter)
  adapter.set(new_adapter)
end

-- Balatro 1.0.1o bug: discover_card() is called with a blind string ID ("bl_small")
-- instead of a Card table, causing a crash. Patch it once on first tick.
local _discover_card_patched = false
local function patch_discover_card()
  if _discover_card_patched then return end
  _discover_card_patched = true
  if type(discover_card) == "function" then
    local _orig = discover_card
    discover_card = function(card, ...)
      if type(card) ~= "table" then return end
      return _orig(card, ...)
    end
    log("patched discover_card to guard against non-table input")
  end
end

local _ui_callbacks_patched = false
local _screenwipe_warn_count = 0
local _event_manager_patched = false

local function is_screenwipe_error(err)
  local msg = tostring(err or "")
  if msg == "" then
    return false
  end
  return string.find(msg, "screenwipe", 1, true) ~= nil
end

local function is_blind_select_error(err)
  local msg = tostring(err or "")
  if msg == "" then
    return false
  end
  return string.find(msg, "blind_select", 1, true) ~= nil
end

local function ensure_room_screenwipe()
  local G = rawget(_G, "G")
  if type(G) ~= "table" then
    return
  end
  if type(G.ROOM) ~= "table" then
    G.ROOM = {}
  end
  if type(G.ROOM.screenwipe) ~= "table" then
    G.ROOM.screenwipe = { _mcp_placeholder = true }
  end
end

local function ensure_blind_select_stub()
  local G = rawget(_G, "G")
  if type(G) ~= "table" then
    return
  end
  if type(G.GAME) ~= "table" then
    return
  end
  if type(G.GAME.blind_select) ~= "table" then
    G.GAME.blind_select = { _mcp_placeholder = true }
  end
end

local function patch_ui_callback_safety()
  if _ui_callbacks_patched then return end
  local G = rawget(_G, "G")
  if type(G) ~= "table" or type(G.FUNCS) ~= "table" then
    return
  end

  local function wrap(name)
    local fn = G.FUNCS[name]
    if type(fn) ~= "function" then
      return
    end
    G.FUNCS[name] = function(...)
      local g = rawget(_G, "G")
      local room = g and g.ROOM
      if type(room) ~= "table" or type(room.screenwipe) ~= "table" then
        ensure_room_screenwipe()
        if _screenwipe_warn_count < 5 then
          _screenwipe_warn_count = _screenwipe_warn_count + 1
          log("patched missing ROOM.screenwipe before calling " .. tostring(name))
        end
      end
      ensure_blind_select_stub()
      local ok, result = xpcall(fn, debug.traceback, ...)
      if ok then
        return result
      end
      if is_screenwipe_error(result) then
        if _screenwipe_warn_count < 10 then
          _screenwipe_warn_count = _screenwipe_warn_count + 1
          log("suppressed screenwipe error in " .. tostring(name) .. ": " .. tostring(result))
        end
        ensure_room_screenwipe()
        return
      end
      if is_blind_select_error(result) then
        if _screenwipe_warn_count < 10 then
          _screenwipe_warn_count = _screenwipe_warn_count + 1
          log("suppressed blind_select error in " .. tostring(name) .. ": " .. tostring(result))
        end
        ensure_blind_select_stub()
        return
      end
      error(result)
    end
  end

  wrap("cash_out")
  wrap("toggle_shop")
  wrap("select_blind")
  wrap("blind_choice_handler")
  wrap("wipe_on")
  wrap("wipe_off")
  wrap("start_run")
  wrap("start_setup_run")
  wrap("notify_then_setup_run")
  wrap("setup_run")
  _ui_callbacks_patched = true
  log("patched fragile UI callbacks for screenwipe safety")
end

local function patch_event_manager_safety()
  if _event_manager_patched then return end
  local G = rawget(_G, "G")
  if type(G) ~= "table" or type(G.E_MANAGER) ~= "table" then
    return
  end
  if type(G.E_MANAGER.add_event) ~= "function" then
    return
  end

  local original_add_event = G.E_MANAGER.add_event
  G.E_MANAGER.add_event = function(self, event, ...)
    if type(event) == "table" and type(event.func) == "function" and not event._mcp_wrapped then
      local original_func = event.func
      event.func = function(...)
        ensure_room_screenwipe()
        ensure_blind_select_stub()
        local ok, result = xpcall(original_func, debug.traceback, ...)
        if ok then
          return result
        end
        if is_screenwipe_error(result) then
          if _screenwipe_warn_count < 10 then
            _screenwipe_warn_count = _screenwipe_warn_count + 1
            log("suppressed screenwipe error in event callback: " .. tostring(result))
          end
          ensure_room_screenwipe()
          return true
        end
        if is_blind_select_error(result) then
          if _screenwipe_warn_count < 10 then
            _screenwipe_warn_count = _screenwipe_warn_count + 1
            log("suppressed blind_select error in event callback: " .. tostring(result))
          end
          ensure_blind_select_stub()
          return true
        end
        error(result)
      end
      event._mcp_wrapped = true
    end
    return original_add_event(self, event, ...)
  end

  _event_manager_patched = true
  log("patched E_MANAGER.add_event for screenwipe safety")
end

-- Called from a safe game tick hook while run is active.
function M.tick()
  patch_discover_card()
  ensure_room_screenwipe()
  ensure_blind_select_stub()
  patch_ui_callback_safety()
  patch_event_manager_safety()
  maybe_heartbeat()
  http_server.update()

  if sync_controller.should_push_snapshot() then
    local snapshot = state_extractor.extract_game_state()
    if snapshot then
      state_cache.update_snapshot(snapshot)
      if config.enable_bridge_client then
        bridge_client.push_snapshot(snapshot)
      end
    end
  end

  if not config.enable_bridge_client then
    return
  end

  if not sync_controller.should_poll_command() then
    return
  end

  local command, poll_err = bridge_client.poll_next_command()
  if poll_err ~= nil then
    local err_code = poll_err.error or "poll_failed"
    local err_detail = poll_err.detail or ""
    log("poll_next_command error=" .. tostring(err_code) .. " detail=" .. tostring(err_detail))
    return
  end
  if command == nil then
    return
  end

  if command.command_id == nil then
    log("received command without command_id")
    return
  end

  local command_type = command.command_type or "execute_action"
  log("processing command_id=" .. tostring(command.command_id) .. " type=" .. tostring(command_type))
  if command_type == "pause_control" then
    sync_controller.pause()
    local r = bridge_client.push_command_result(command.command_id, { success = true, command_type = command_type })
    if not (r and r.ok) then
      log("push_command_result failed for pause_control")
    end
    return
  end

  if command_type == "resume_control" then
    sync_controller.resume()
    local r = bridge_client.push_command_result(command.command_id, { success = true, command_type = command_type })
    if not (r and r.ok) then
      log("push_command_result failed for resume_control")
    end
    return
  end

  if command_type == "request_snapshot" then
    local snapshot = state_extractor.extract_game_state()
    if snapshot then
      bridge_client.push_snapshot(snapshot)
    end
    local r = bridge_client.push_command_result(command.command_id, { success = true, command_type = command_type })
    if not (r and r.ok) then
      log("push_command_result failed for request_snapshot")
    end
    return
  end

  local payload = command.payload or {}
  local action = payload.action or command.action
  local action_type = action and action.action_type or nil

  local throttled, retry_after = is_action_throttled(action_type)
  if throttled then
    local r = bridge_client.push_command_result(command.command_id, {
      success = false,
      error = "action_cooldown",
      warnings = { string.format("retry_after=%.3f", retry_after) },
      action_type = action_type,
    })
    if not (r and r.ok) then
      log("push_command_result failed for throttled execute_action")
    end
    return
  end

  if not sync_controller.can_control() then
    local r = bridge_client.push_command_result(command.command_id, {
      success = false,
      error = "control_paused",
      warnings = { "mod_control_paused" },
      action_type = action_type,
    })
    if not (r and r.ok) then
      log("push_command_result failed for paused execute_action")
    end
    return
  end

  mark_action_executed(action_type)
  local result = action_executor.execute(action)
  state_cache.record_action(action, result)
  local r = bridge_client.push_command_result(command.command_id, result)
  if not (r and r.ok) then
    log("push_command_result failed for execute_action")
  end
end

return M
