local M = {}

local function ok_stub(name, params)
  return {
    success = true,
    warnings = { "stubbed_adapter_call:" .. name },
    params = params,
  }
end

function M.get_phase()
  return "menu"
end

function M.get_runtime_state()
  return {
    turn_index = 0,
    action_points = {
      hands_left = 0,
      discards_left = 0,
    },
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
    shop = {
      items = {},
      reroll_cost = 5,
      voucher = nil,
      pack_options = {},
    },
    blind = {},
  }
end

function M.select_card(params)
  return ok_stub("select_card", params)
end

function M.deselect_card(params)
  return ok_stub("deselect_card", params)
end

function M.play_hand(params)
  return ok_stub("play_hand", params)
end

function M.discard_selected(params)
  return ok_stub("discard_selected", params)
end

function M.buy_item(params)
  return ok_stub("buy_item", params)
end

function M.reroll_shop(params)
  return ok_stub("reroll_shop", params)
end

function M.continue_flow(params)
  return ok_stub("continue_flow", params)
end

function M.skip(params)
  return ok_stub("skip", params)
end

function M.choose_option(params)
  return ok_stub("choose_option", params)
end

function M.end_turn(params)
  return ok_stub("end_turn", params)
end

return M
