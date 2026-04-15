local config = require("bmcp.config")

local M = {}

local current_state = {
  schema_version = "0.1.0",
  phase = "menu",
  turn_index = 0,
  action_points = { hands_left = 0, discards_left = 0 },
  resources = {
    money = 0,
    chips = 0,
    mult = 0,
    ante = 1,
    round_score_target = 0,
    current_score = 0,
  },
  hand = {},
  jokers = {},
  consumables = {},
  shop = { items = {}, reroll_cost = 5, voucher = nil, pack_options = {} },
  blind = {},
  meta = {},
}

local history = {}
local seq = 0

local function copy_table(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[k] = copy_table(v)
  end
  return out
end

local function max_history()
  local n = tonumber(config.embedded_api_max_history) or 200
  if n < 1 then
    return 1
  end
  return n
end

local function push_history(entry)
  seq = seq + 1
  entry.seq = seq
  entry.timestamp = os.time()
  history[#history + 1] = entry
  local limit = max_history()
  while #history > limit do
    table.remove(history, 1)
  end
end

function M.update_snapshot(snapshot)
  if type(snapshot) ~= "table" then
    return
  end
  current_state = copy_table(snapshot)
  push_history({ kind = "snapshot", phase = current_state.phase or "menu" })
end

function M.record_action(action, result)
  push_history({
    kind = "action",
    action = copy_table(action or {}),
    result = copy_table(result or {}),
    phase = current_state.phase or "menu",
  })
end

function M.record_event(event_type, payload)
  push_history({
    kind = "event",
    event_type = tostring(event_type or "unknown"),
    payload = copy_table(payload or {}),
    phase = current_state.phase or "menu",
  })
end

function M.get_state()
  return copy_table(current_state)
end

function M.get_action_history(limit)
  local n = tonumber(limit) or 20
  if n < 1 then
    n = 1
  end
  local out = {}
  local start_idx = #history - n + 1
  if start_idx < 1 then
    start_idx = 1
  end
  for i = start_idx, #history do
    out[#out + 1] = copy_table(history[i])
  end
  return out
end

function M.get_run_summary()
  local s = current_state
  local resources = s.resources or {}
  local ap = s.action_points or {}
  return {
    phase = s.phase or "menu",
    turn_index = s.turn_index or 0,
    money = resources.money or 0,
    current_score = resources.current_score or 0,
    hands_left = ap.hands_left or 0,
    discards_left = ap.discards_left or 0,
    steps_logged = #history,
  }
end

return M
