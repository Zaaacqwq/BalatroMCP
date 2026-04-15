local M = {}
local adapter = require("bmcp.adapter")

local function extract_phase()
  local phase, err = adapter.call("get_phase")
  if err ~= nil then
    return "menu"
  end
  return phase or "menu"
end

function M.extract_game_state()
  local runtime_state, _ = adapter.call("get_runtime_state")
  runtime_state = runtime_state or {}

  local action_points = runtime_state.action_points or {}
  local resources = runtime_state.resources or {}
  local blind_raw = runtime_state.blind or {}

  -- Validate round_score_target is meaningful: if phase is in_round/blind_select, target must be > 0
  local target_score = resources.round_score_target or 0
  local phase = extract_phase()
  if (phase == "in_round" or phase == "blind_select") and target_score == 0 then
    -- Force re-query from adapter to ensure we get fresh state
    local fresh_runtime, _ = adapter.call("get_runtime_state")
    if type(fresh_runtime) == "table" then
      target_score = fresh_runtime.resources and fresh_runtime.resources.round_score_target or target_score
    end
  end

  return {
    schema_version = "0.1.0",
    phase = phase,
    turn_index = runtime_state.turn_index or 0,
    action_points = {
      hands_left = action_points.hands_left or 0,
      discards_left = action_points.discards_left or 0,
    },
    resources = {
      money = resources.money or 0,
      chips = resources.chips or 0,
      mult = resources.mult or 0,
      ante = resources.ante or 1,
      round_score_target = target_score,
      current_score = resources.current_score or 0,
    },
    hand = runtime_state.hand or {},
    jokers = runtime_state.jokers or {},
    consumables = runtime_state.consumables or {},
    shop = runtime_state.shop or {
      items = {},
      reroll_cost = 5,
      voucher = nil,
      pack_options = {},
    },
    blind = blind_raw and type(blind_raw) == "table" and (blind_raw.name or blind_raw.level) and blind_raw or {},
    meta = {
      source = "smods_adapter",
      adapter_attached = adapter.get() ~= nil,
      timestamp = os.time(),
    },
  }
end

return M
