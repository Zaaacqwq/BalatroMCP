local M = {}
local adapter = require("bmcp.adapter")

local handlers = {}

handlers.select_card = function(params)
  return adapter.call("select_card", params)
end

handlers.deselect_card = function(params)
  return adapter.call("deselect_card", params)
end

handlers.play_hand = function(params)
  return adapter.call("play_hand", params)
end

handlers.discard_selected = function(params)
  return adapter.call("discard_selected", params)
end

handlers.buy_item = function(params)
  return adapter.call("buy_item", params)
end

handlers.reroll_shop = function(params)
  return adapter.call("reroll_shop", params)
end

handlers.continue = function(params)
  return adapter.call("continue_flow", params)
end

handlers.skip = function(params)
  return adapter.call("skip", params)
end

handlers.choose_option = function(params)
  return adapter.call("choose_option", params)
end

handlers.end_turn = function(params)
  return adapter.call("end_turn", params)
end

handlers.start = function(params)
  return adapter.call("start", params)
end

handlers.menu = function(params)
  return adapter.call("menu", params)
end

handlers.cash_out = function(params)
  return adapter.call("cash_out", params)
end

handlers.next_round = function(params)
  return adapter.call("next_round", params)
end

handlers.rearrange = function(params)
  return adapter.call("rearrange", params)
end

handlers.save = function(params)
  return adapter.call("save", params)
end

handlers.load = function(params)
  return adapter.call("load", params)
end

handlers.add = function(params)
  return adapter.call("add", params)
end

handlers.set = function(params)
  return adapter.call("set", params)
end

handlers.screenshot = function(params)
  return adapter.call("screenshot", params)
end

-- Temporary diagnostic: returns raw card IDs as Balatro sees them.
handlers.debug_hand = function(params)
  local G = rawget(_G, "G")
  if G == nil or G.hand == nil or type(G.hand.cards) ~= "table" then
    return { success = false, error = "no_hand", warnings = {} }
  end
  local cards = {}
  for i, card in ipairs(G.hand.cards) do
    local sort_id = card and card.sort_id
    local unique_val = card and card.unique_val
    local rid = nil
    if sort_id ~= nil then
      rid = "sort:" .. tostring(sort_id)
    elseif unique_val ~= nil then
      rid = "uval:" .. string.format("%.17g", tonumber(unique_val) or 0)
    else
      rid = "idx:" .. tostring(i)
    end
    cards[#cards + 1] = rid .. "|" .. tostring(card and card.base and card.base.value or "?") .. tostring(card and card.base and card.base.suit or "?")
  end
  return { success = true, error = nil, warnings = {}, cards = cards,
           hand_size = #G.hand.cards, highlighted_size = type(G.hand.highlighted) == "table" and #G.hand.highlighted or -1 }
end

handlers.debug_round_eval = function(params)
  local G = rawget(_G, "G")
  if G == nil then return { success = false, error = "no_G", warnings = {} } end
  local re = G.round_eval
  if type(re) ~= "table" then
    return { success = false, error = "no_round_eval", warnings = {} }
  end
  -- List keys of G.round_eval to understand its structure
  local keys = {}
  for k, v in pairs(re) do
    keys[#keys+1] = tostring(k) .. "=" .. type(v)
  end
  -- Also check if there's a cash_out method or button
  local has_cash_out = type(re.cash_out) == "function"
  local has_UIRoot = type(re.UIRoot) == "table"
  local has_get_UIE = type(re.get_UIE_by_ID) == "function"
  return { success = true, error = nil, warnings = {}, keys = keys,
           has_cash_out = has_cash_out, has_UIRoot = has_UIRoot, has_get_UIE = has_get_UIE }
end

handlers.debug_state = function(params)
  local G = rawget(_G, "G")
  if G == nil then return { success = false, error = "no_G", warnings = {} } end
  local state_val = tostring(G.STATE)
  local states = {}
  if type(G.STATES) == "table" then
    for k, v in pairs(G.STATES) do
      if tostring(v) == state_val then
        states[#states + 1] = k .. "=" .. state_val
      end
    end
  end
  local round_eval = tostring(type(G.round_eval))
  local shop_str = tostring(type(G.shop))
  return { success = true, error = nil, warnings = {},
           state = state_val, matching_states = states,
           round_eval_type = round_eval, shop_type = shop_str }
end

handlers.debug_snapshot_shop = function(params)
  -- Encode get_runtime_state().shop as JSON and return the raw string
  local adapter_mod = require("bmcp.adapter")
  local json_mod = require("bmcp.json_util")
  local runtime, err = adapter_mod.call("get_runtime_state")
  if runtime == nil then return { success = false, error = tostring(err), warnings = {} } end
  local shop = runtime.shop or {}
  local items = shop.items or {}
  local raw_json = json_mod.encode(items)
  return { success = true, error = nil, warnings = {},
           items_count = #items, raw_json = raw_json }
end

handlers.debug_runtime_shop = function(params)
  local G = rawget(_G, "G")
  if G == nil then return { success = false, error = "no_G", warnings = {} } end
  -- Check each area: type, cards type, cards count
  local checks = {}
  local areas = { shop_jokers = G.shop_jokers, shop_vouchers = G.shop_vouchers, shop_booster = G.shop_booster }
  for name, area in pairs(areas) do
    local area_type = type(area)
    local cards_type = "N/A"
    local cards_count = -1
    if area_type == "table" then
      cards_type = type(area.cards)
      if type(area.cards) == "table" then
        cards_count = #area.cards
        -- Also check raw access
        local raw_cards = rawget(area, "cards")
        checks[#checks+1] = name .. " area=table cards_type=" .. cards_type ..
          " #cards=" .. tostring(cards_count) ..
          " rawget_cards_type=" .. type(raw_cards) ..
          " rawget_#=" .. (type(raw_cards)=="table" and tostring(#raw_cards) or "N/A")
      else
        checks[#checks+1] = name .. " area=table cards_type=" .. cards_type
      end
    else
      checks[#checks+1] = name .. " area=" .. area_type
    end
  end
  -- Also call adapter get_runtime_state
  local adapter = require("bmcp.adapter")
  local runtime, err = adapter.call("get_runtime_state")
  local shop_items_count = -99
  if runtime and runtime.shop then
    local items = runtime.shop.items
    shop_items_count = type(items) == "table" and #items or -1
  end
  return { success = true, error = nil, warnings = {}, checks = checks, adapter_shop_items = shop_items_count }
end

  handlers.debug_ui = function(params)
    local G = rawget(_G, "G")
    if G == nil then return { success = false, error = "no_G", warnings = {} } end
    local func_keys = {}
    if type(G.FUNCS) == "table" then
      for k, v in pairs(G.FUNCS) do
        if type(k) == "string" then
          func_keys[#func_keys + 1] = k
        end
      end
    end
    table.sort(func_keys)

    local button_keys = {}
    if type(G.buttons) == "table" then
      for k, v in pairs(G.buttons) do
        if type(k) == "string" then
          button_keys[#button_keys + 1] = k
        end
      end
    end
    table.sort(button_keys)

    return {
      success = true,
      error = nil,
      warnings = {},
      func_keys = func_keys,
      button_keys = button_keys,
      state = tostring(G.STATE),
      room_has_screenwipe = type(G.ROOM) == "table" and type(G.ROOM.screenwipe) == "table",
    }
  end

handlers.debug_shop = function(params)
  local G = rawget(_G, "G")
  if G == nil then return { success = false, error = "no_G", warnings = {} } end
  local areas = {
    shop_jokers   = type(G.shop_jokers)   == "table" and #(G.shop_jokers.cards   or {}) or -1,
    shop_vouchers = type(G.shop_vouchers) == "table" and #(G.shop_vouchers.cards or {}) or -1,
    shop_booster  = type(G.shop_booster)  == "table" and #(G.shop_booster.cards  or {}) or -1,
    pack_cards    = type(G.pack_cards)    == "table" and #(G.pack_cards.cards    or {}) or -1,
    shop          = type(G.shop) == "table" and "exists" or "nil",
  }
  -- Collect item IDs from each area
  local items = {}
  local area_names = { shop_jokers = G.shop_jokers, shop_vouchers = G.shop_vouchers, shop_booster = G.shop_booster }
  for aname, area in pairs(area_names) do
    if type(area) == "table" and type(area.cards) == "table" then
      for i, card in ipairs(area.cards) do
        local name = card and card.config and card.config.center and card.config.center.name or "?"
        local cost = card and card.cost or "?"
        local sid = card and card.sort_id or "?"
        items[#items + 1] = aname .. "[" .. i .. "] name=" .. tostring(name) .. " cost=" .. tostring(cost) .. " sort_id=" .. tostring(sid)
      end
    end
  end
  return { success = true, error = nil, warnings = {}, areas = areas, items = items }
end

function M.execute(action)
  if action == nil or action.action_type == nil then
    return {
      success = false,
      error = "invalid_action_payload",
      warnings = { "missing_action_type" },
    }
  end

  local handler = handlers[action.action_type]
  if handler == nil then
    return {
      success = false,
      error = "unsupported_action_type",
      warnings = { action.action_type },
    }
  end

  local ok, result = pcall(handler, action.params or {})
  if not ok then
    return {
      success = false,
      error = "handler_exception",
      warnings = { tostring(result) },
    }
  end

  if type(result) ~= "table" then
    return {
      success = false,
      error = "invalid_handler_result",
      warnings = { action.action_type },
    }
  end

  if result.success == nil then
    result.success = true
  end
  if result.warnings == nil then
    result.warnings = {}
  end
  result.action_type = action.action_type

  return result
end

return M
