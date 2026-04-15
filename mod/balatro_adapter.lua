-- Balatro runtime adapter template.
-- Replace placeholders with actual Balatro/SMODS runtime object access.

local M = {}
local json_util = require("bmcp.json_util")
local state_cache = require("bmcp.state_cache")

local function get_G()
  return rawget(_G, "G")
end

local function safe_table(v)
  if type(v) == "table" then
    return v
  end
  return {}
end

local function make_action_ok(extra)
  local result = {
    success = true,
    error = nil,
    warnings = {},
  }
  if type(extra) == "table" then
    for k, v in pairs(extra) do
      result[k] = v
    end
  end
  return result
end

local function make_action_error(code, warning)
  local warnings = {}
  if warning ~= nil then
    warnings[#warnings + 1] = tostring(warning)
  end
  return {
    success = false,
    error = code,
    warnings = warnings,
  }
end

local function current_state_equals(state_key)
  local G = get_G()
  if G == nil then
    return false
  end
  local states = safe_table(G.STATES)
  if states[state_key] ~= nil then
    return G.STATE == states[state_key]
  end
  return G.STATE == state_key
end

local function card_runtime_id(card, fallback_index)
  if type(card) ~= "table" then
    return tostring(fallback_index or "")
  end
  if card.sort_id ~= nil then
    return tostring(card.sort_id)
  end
  if card.unique_val ~= nil then
    local n = tonumber(card.unique_val)
    if n ~= nil then
      return string.format("%.17g", n)
    end
    return tostring(card.unique_val)
  end
  return tostring(fallback_index or "")
end

local function card_id_matches(a, b)
  local sa = tostring(a or "")
  local sb = tostring(b or "")
  if sa == sb then
    return true
  end
  local na = tonumber(sa)
  local nb = tonumber(sb)
  if na ~= nil and nb ~= nil then
    return math.abs(na - nb) < 1e-9
  end
  return false
end

local function shop_item_id(prefix, card, fallback_index)
  return tostring(prefix) .. ":" .. card_runtime_id(card, fallback_index)
end

local function find_hand_card(card_id)
  local G = get_G()
  if G == nil or G.hand == nil or type(G.hand.cards) ~= "table" then
    return nil
  end
  local wanted = tostring(card_id or "")
  for i, card in ipairs(G.hand.cards) do
    if card_id_matches(card_runtime_id(card, i), wanted) then
      return card
    end
  end
  return nil
end

local function first_hand_card(prefer_highlighted)
  local G = get_G()
  if G == nil or G.hand == nil or type(G.hand.cards) ~= "table" then
    return nil
  end
  for _, card in ipairs(G.hand.cards) do
    if card ~= nil and (prefer_highlighted == nil or card.highlighted == prefer_highlighted) then
      return card
    end
  end
  return nil
end

local function collect_highlighted_hand_cards()
  local G = get_G()
  local selected = {}
  if G == nil or G.hand == nil or type(G.hand.cards) ~= "table" then
    return selected
  end
  for _, card in ipairs(G.hand.cards) do
    if card ~= nil and card.highlighted then
      selected[#selected + 1] = card
    end
  end
  return selected
end

local function is_playable_hand_card(card, hand_area)
  if type(card) ~= "table" then
    return false
  end
  if card.removed then
    return false
  end
  if hand_area ~= nil and card.area ~= nil and card.area ~= hand_area then
    return false
  end
  if type(card.base) ~= "table" then
    return false
  end
  if card.base.value == nil or card.base.suit == nil then
    return false
  end
  return true
end

local function collect_sanitized_play_cards()
  local G = get_G()
  local selected = {}
  local seen = {}
  if G == nil or G.hand == nil or type(G.hand.cards) ~= "table" then
    return selected
  end

  for i, card in ipairs(G.hand.cards) do
    if card ~= nil and card.highlighted and is_playable_hand_card(card, G.hand) then
      local id = card_runtime_id(card, i)
      if not seen[id] then
        seen[id] = true
        selected[#selected + 1] = card
      end
    end
  end
  return selected
end

local function hand_is_stable_for_play()
  local G = get_G()
  if G == nil or G.hand == nil or type(G.hand.cards) ~= "table" then
    return false
  end

  local valid = 0
  for _, card in ipairs(G.hand.cards) do
    if is_playable_hand_card(card, G.hand) then
      valid = valid + 1
    end
  end

  return valid >= 1
end

local function iter_shop_areas(G)
  return {
    { prefix = "joker", area = G.shop_jokers },
    { prefix = "voucher", area = G.shop_vouchers },
    { prefix = "booster", area = G.shop_booster },
    { prefix = "pack", area = G.pack_cards },
  }
end

local function find_shop_card(item_id)
  local G = get_G()
  if G == nil then
    return nil
  end

  local wanted = tostring(item_id or "")
  local plain_id = wanted:gsub("^[^:]+:", "")

  for _, entry in ipairs(iter_shop_areas(G)) do
    local area = entry.area
    if type(area) == "table" and type(area.cards) == "table" then
      for i, card in ipairs(area.cards) do
        local sid = shop_item_id(entry.prefix, card, i)
        local cid = card_runtime_id(card, i)
        if wanted == sid or wanted == cid or plain_id == cid then
          return card
        end
      end
    end
  end

  return nil
end

local function current_money()
  local G = get_G()
  if G == nil or type(G.GAME) ~= "table" then
    return 0
  end
  if G.GAME.dollars ~= nil then
    return tonumber(G.GAME.dollars) or 0
  end
  if type(G.GAME.current_round) == "table" and G.GAME.current_round.dollars ~= nil then
    return tonumber(G.GAME.current_round.dollars) or 0
  end
  return 0
end

local function call_func(func_name, ...)
  local G = get_G()
  if G == nil then
    return false, "missing_G"
  end
  if type(G.FUNCS) ~= "table" or type(G.FUNCS[func_name]) ~= "function" then
    return false, "missing_func:" .. tostring(func_name)
  end
  local ok, err = pcall(G.FUNCS[func_name], ...)
  if not ok then
    return false, "func_exception:" .. tostring(err)
  end
  return true, nil
end

local function get_state_snapshot()
  return state_cache.get_state()
end

local function write_text_file(path, text)
  if type(path) ~= "string" or path == "" then
    return false, "missing_path"
  end
  local handle, err = io.open(path, "wb")
  if handle == nil then
    return false, tostring(err)
  end
  handle:write(text or "")
  handle:close()
  return true, nil
end

local function read_text_file(path)
  if type(path) ~= "string" or path == "" then
    return nil, "missing_path"
  end
  local handle, err = io.open(path, "rb")
  if handle == nil then
    return nil, tostring(err)
  end
  local data = handle:read("*a")
  handle:close()
  return data, nil
end

local function mutate_cached_state(mutator)
  local snapshot = state_cache.get_state()
  local ok, result = pcall(mutator, snapshot)
  if not ok then
    return make_action_error("mutate_state_failed", tostring(result))
  end
  state_cache.update_snapshot(snapshot)
  return make_action_ok(result or {})
end

local function schedule_delayed_play(delay_seconds)
  local G = get_G()
  if G == nil then
    return false, "missing_G"
  end
  if type(G.E_MANAGER) ~= "table" or type(G.E_MANAGER.add_event) ~= "function" then
    return false, "missing_event_manager"
  end

  local event_payload = {
      trigger = "after",
      delay = delay_seconds or 0.05,
      blockable = false,
      blocking = false,
      func = function()
        call_func("play_cards_from_highlighted", {})
        return true
      end,
  }

  local ok, err = pcall(function()
    if type(Event) == "function" then
      G.E_MANAGER:add_event(Event(event_payload))
    else
      G.E_MANAGER:add_event(event_payload)
    end
  end)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

function M.get_phase()
  local G = get_G()
  if G == nil then
    return "menu"
  end

  if current_state_equals("SHOP") then
    return "shop"
  end
  if current_state_equals("GAME_OVER") then
    return "game_over"
  end
  if current_state_equals("PACK") then
    return "pack"
  end
  if current_state_equals("BLIND_SELECT") then
    return "blind_select"
  end
  if current_state_equals("SELECTING_HAND") or current_state_equals("DRAW_TO_HAND") or current_state_equals("HAND_PLAYED") then
    return "in_round"
  end
  if current_state_equals("ROUND_EVAL") then
    return "round_eval"
  end
  return "menu"
end

function M.get_debug_game_fields()
  -- Helper to introspect G.GAME structure for debugging
  local G = get_G()
  if G == nil then
    return { error = "missing_G" }
  end
  local run = safe_table(G.GAME)
  
  -- Collect round_resets info
  local r_resets = safe_table(G.GAME and G.GAME.round_resets)
  local blind_choices = safe_table(r_resets.blind_choices)
  local blind_states = safe_table(r_resets.blind_states)
  local blind_tags = safe_table(r_resets.blind_tags)
  
  -- Check G.blind and G.P_BLINDS
  local blind_obj = G.blind and { key = G.blind.key, name = G.blind.name, mult = type(G.blind.mult) } or nil
  
  -- Check if get_blind_amount is available
  local has_get_blind_amount = type(get_blind_amount) == "function"
  
  -- Try to get some G.P_BLINDS info
  local p_blinds_sample = {}
  if G.P_BLINDS then
    if G.P_BLINDS.bl_small then p_blinds_sample.bl_small_mult = G.P_BLINDS.bl_small.mult end
    if G.P_BLINDS.bl_big then p_blinds_sample.bl_big_mult = G.P_BLINDS.bl_big.mult end
    local boss_key = blind_choices.Boss or "bl_boss" 
    if G.P_BLINDS[boss_key] then p_blinds_sample.boss_mult = G.P_BLINDS[boss_key].mult end
  end
  
  return {
    -- Basic game state
    round = run.round,
    ante = r_resets.ante,
    chips = run.chips,
    mult = run.mult,
    dollars = run.dollars,
    
    -- Blind calculation components
    starting_params_ante_scaling = (G.GAME.starting_params and G.GAME.starting_params.ante_scaling) or "missing",
    get_blind_amount_available = has_get_blind_amount,
    
    -- Round resets info
    round_resets_ante = r_resets.ante,
    blind_choices_small = blind_choices.Small,
    blind_choices_big = blind_choices.Big,
    blind_choices_boss = blind_choices.Boss,
    blind_states_small = blind_states.Small,
    blind_states_big = blind_states.Big,
    blind_states_boss = blind_states.Boss,
    
    -- Current blind object
    blind_obj_key = (blind_obj and blind_obj.key) or nil,
    blind_obj_name = (blind_obj and blind_obj.name) or nil,
    game_blind_on_deck = G.GAME.blind_on_deck,
    
    -- Blind config multipliers
    p_blinds_sample = p_blinds_sample,
    p_blinds_exists = G.P_BLINDS ~= nil,
    
    -- Old fields for compatibility
    chips_to_win = run.chips_to_win,
    blind_chips = run.blind_chips,
  }
end

function M.get_runtime_state()
  local G = get_G()
  if G == nil then
    return nil
  end

  local run = safe_table(G.GAME)
  local hand = {}
  local current_hand = safe_table(G.hand and G.hand.cards)
  local phase = tostring(M.get_phase() or "menu")

  for i, card in ipairs(current_hand) do
    hand[#hand + 1] = {
      card_id = card_runtime_id(card, i),
      rank = tostring(card and card.base and card.base.value or ""),
      suit = tostring(card and card.base and card.base.suit or ""),
      selected = card and card.highlighted or false,
      debuffed = card and card.debuff or false,
    }
  end

  local shop_items = {}
  for _, entry in ipairs(iter_shop_areas(G)) do
    local area = entry.area
    if type(area) == "table" and type(area.cards) == "table" then
      for i, card in ipairs(area.cards) do
        shop_items[#shop_items + 1] = {
          item_id = shop_item_id(entry.prefix, card, i),
          item_type = tostring(card and card.ability and card.ability.set or entry.prefix),
          price = tonumber(card and card.cost or 0) or 0,
          name = tostring(card and card.config and card.config.center and card.config.center.name or card and card.config and card.config.center_key or ""),
        }
      end
    end
  end

  local blind_options = {}
  local blind_choices = safe_table(run.round_resets and run.round_resets.blind_choices)
  local blind_states = safe_table(run.round_resets and run.round_resets.blind_states)
  local blind_meta = {
    { option_id = "small", choice_key = "Small", label = "Small Blind" },
    { option_id = "big", choice_key = "Big", label = "Big Blind" },
    { option_id = "boss", choice_key = "Boss", label = "Boss Blind" },
  }
  for _, meta in ipairs(blind_meta) do
    local blind_key = blind_choices[meta.choice_key]
    local blind_cfg = type(G.P_BLINDS) == "table" and blind_key and G.P_BLINDS[blind_key] or nil
    blind_options[#blind_options + 1] = {
      option_id = meta.option_id,
      blind_key = blind_key,
      label = meta.label,
      name = tostring(blind_cfg and blind_cfg.name or blind_key or meta.label),
      state = tostring(blind_states[meta.choice_key] or ""),
      mult = tonumber(blind_cfg and blind_cfg.mult or 0) or 0,
    }
  end

  -- Extract blind info and target score using exhaustive fallback
  -- Extract blind info and target score using correct BalatroBot calculation
  local blind_info = {}
  local target_score = 0

  -- CORRECT METHOD: Calculate from G.GAME.round_resets (not runtime blind)
  -- Formula: base_amount * multiplier * ante_scaling
  if G and G.GAME and G.GAME.round_resets then
    local ante = tonumber(G.GAME.round_resets.ante or 1) or 1
    local ante_scaling = tonumber((G.GAME.starting_params and G.GAME.starting_params.ante_scaling) or 1) or 1
    local base_amount = 0
    
    -- Try to get base_amount from Balatro's get_blind_amount function
    if type(get_blind_amount) == "function" then
      base_amount = tonumber(get_blind_amount(ante)) or 0
    else
      -- Fallback: standard progression is 8 * ante for White stake
      base_amount = 8 * ante
    end
    
    -- Get the current blind key (which blind is in play)
    local current_blind_key = ""
    if G.blind and G.blind.key then
      current_blind_key = string.lower(G.blind.key)
    elseif G.GAME.blind_on_deck then
      current_blind_key = string.lower(G.GAME.blind_on_deck)
    end
    
    -- Get blind choices and states from round_resets
    local blind_choices = G.GAME.round_resets.blind_choices or {}
    local blind_states = G.GAME.round_resets.blind_states or {}
    
    -- Determine which blind type is currently selected
    local current_blind_type = ""
    if blind_states.Small == "Current" or blind_states.Small == "Select" or string.find(current_blind_key, "small") then
      current_blind_type = "Small"
    elseif blind_states.Big == "Current" or blind_states.Big == "Select" or string.find(current_blind_key, "big") then
      current_blind_type = "Big"
    elseif blind_states.Boss == "Current" or blind_states.Boss == "Select" or string.find(current_blind_key, "boss") then
      current_blind_type = "Boss"
    end
    
    -- Get the blind key from choices
    local chosen_blind_key = blind_choices[current_blind_type] or current_blind_key or "bl_small"
    
    -- Look up blind config in G.P_BLINDS
    if G.P_BLINDS and G.P_BLINDS[chosen_blind_key] then
      local blind_config = G.P_BLINDS[chosen_blind_key]
      
      blind_info = {
        name = tostring(blind_config.name or chosen_blind_key or ""),
        level = tonumber(blind_config.level or 1) or 1,
      }
      
      -- Calculate correct score
      local mult = tonumber(blind_config.mult or 1) or 1
      target_score = math.floor(base_amount * mult * ante_scaling)
    end
  end
  
  -- Secondary attempt: check current_round.chips_to_win (for in_round phase)
  if target_score == 0 and G.GAME and G.GAME.current_round then
    local c_round_target = tonumber(G.GAME.current_round.chips_to_win) or 0
    if c_round_target > 0 then
      target_score = c_round_target
    end
  end
  
  -- Fallback: if all else fails, try runtime blind object
  if target_score == 0 then
    local blind_obj = G.blind or (run and run.blind)
    if type(blind_obj) == "table" then
      if not blind_info.name then
        blind_info = {
          name = tostring(blind_obj.name or blind_obj.key or ""),
          level = tonumber(blind_obj.level or 1) or 1,
        }
      end
      -- Try runtime fields as last resort
      target_score = tonumber(blind_obj.chips or blind_obj.chip_req or blind_obj.chips_to_win or 0) or 0
    end
  end

  return {
    turn_index = tonumber(run.round or 0) or 0,
    action_points = {
      hands_left = tonumber(run.current_round and run.current_round.hands_left or run.hands_left or 0) or 0,
      discards_left = tonumber(run.current_round and run.current_round.discards_left or run.discards_left or 0) or 0,
    },
    resources = {
      money = tonumber(run.dollars or 0) or 0,
      chips = tonumber(run.chips or 0) or 0,
      mult = tonumber(run.mult or 0) or 0,
      ante = tonumber(run.ante or 1) or 1,
      round_score_target = target_score,
      current_score = tonumber(run.chips or 0) or 0,
    },
    hand = hand,
    jokers = {},
    consumables = {},
    shop = {
      items = shop_items,
      reroll_cost = tonumber(run.current_round and run.current_round.reroll_cost or run.reroll_cost or 5) or 5,
      voucher = nil,
      pack_options = {},
    },
    blind = {
      name = blind_info.name,
      level = blind_info.level,
      options = blind_options,
      selected_option_id = phase == "blind_select" and nil or (
        tostring(blind_states.Small or "") == "Current" and "small" or
        tostring(blind_states.Big or "") == "Current" and "big" or
        tostring(blind_states.Boss or "") == "Current" and "boss" or nil
      ),
    },
  }
end

-- Click a card to toggle its highlight state (the correct Balatro API).
-- card:click() updates both card.highlighted and G.hand.highlighted together.
local function card_click(card)
  if type(card) ~= "table" then return false end
  local ok = pcall(card.click, card)
  return ok
end

-- Get the real play/discard button element from Balatro's button bar.
local function get_button_elem(button_id)
  local G = get_G()
  if G == nil then return {} end
  -- Try G.buttons UIRoot first (how BalatraBot accesses it)
  local ok, btn = pcall(function()
    if type(G.buttons) == "table" then
      local root = G.buttons.UIRoot or G.buttons
      if type(root) == "table" and type(root.get_UIE_by_ID) == "function" then
        return root:get_UIE_by_ID(button_id) or {}
      end
    end
    return {}
  end)
  return (ok and btn) or {}
end

local function has_ready_screenwipe(G)
  if type(G) ~= "table" then
    return false
  end
  if type(G.ROOM) ~= "table" then
    return false
  end
  return type(G.ROOM.screenwipe) == "table"
end

local function ensure_screenwipe(G)
  if type(G) ~= "table" then
    return false
  end
  if type(G.ROOM) ~= "table" then
    G.ROOM = {}
  end
  if type(G.ROOM.screenwipe) ~= "table" then
    G.ROOM.screenwipe = { _mcp_placeholder = true }
  end
  return true
end

function M.select_card(params)
  params = safe_table(params)
  local card = find_hand_card(params.card_id)
  if card == nil then
    return make_action_error("card_not_found", params.card_id)
  end
  -- Use card:click() - the proper Balatro API for toggling card selection.
  -- It updates both card.highlighted and G.hand.highlighted atomically.
  if not card.highlighted then
    card_click(card)
  end
  local selected_id = card_runtime_id(card, tostring(params.card_id))
  return make_action_ok({ selected_card_id = selected_id })
end

function M.deselect_card(params)
  params = safe_table(params)
  local card = find_hand_card(params.card_id)
  if card == nil then
    return make_action_error("card_not_found", params.card_id)
  end
  if card.highlighted then
    card_click(card)
  end
  local deselected_id = card_runtime_id(card, tostring(params.card_id))
  return make_action_ok({ deselected_card_id = deselected_id })
end

function M.play_hand(params)
  params = safe_table(params)
  local G = get_G()
  if G == nil or G.hand == nil then
    return make_action_error("missing_runtime", "hand")
  end

  if not current_state_equals("SELECTING_HAND") then
    return make_action_error("play_not_available_in_state", tostring(G.STATE))
  end

  if not hand_is_stable_for_play() then
    return make_action_error("hand_not_stable_for_safe_play")
  end

  local hands_left = tonumber(G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or G.GAME and G.GAME.hands_left or 0) or 0
  if hands_left <= 0 then
    return make_action_error("no_hands_left")
  end

  local pre_hands_left = hands_left
  local pre_phase = M.get_phase()

  -- STEP 1: Collect card references BEFORE touching any highlight state.
  -- unhighlight_all may have side-effects on G.hand.cards in some Balatro
  -- versions, so we gather all needed references first while the hand is stable.
  local cards_to_play = {}
  local seen_cards = {}   -- dedup by object reference (most reliable)

  local card_ids = (type(params.card_ids) == "table" and #params.card_ids > 0)
                   and params.card_ids or {}
  local explicit_card_ids = #card_ids > 0

  for _, card_id in ipairs(card_ids) do
    if #cards_to_play >= 5 then break end
    local card = find_hand_card(card_id)
    if card ~= nil and not seen_cards[card] then
      seen_cards[card] = true
      cards_to_play[#cards_to_play + 1] = card
    end
  end

  if explicit_card_ids and #cards_to_play == 0 then
    return make_action_error("play_cards_not_found", "card_ids")
  end

  -- If no explicit IDs are provided, prefer currently highlighted cards.
  if (not explicit_card_ids) and #cards_to_play == 0 then
    cards_to_play = collect_sanitized_play_cards()
  end

  -- Last fallback: use first card in hand.
  if #cards_to_play == 0 then
    for _, card in ipairs(G.hand.cards) do
      if type(card) == "table" and not card.removed then
        cards_to_play[1] = card
        break
      end
    end
  end

  if #cards_to_play == 0 then
    return make_action_error("no_playable_cards_found", "hand_empty")
  end

  -- STEP 2: Synchronously clear, highlight, then play.
  -- select_card/deselect_card also operate synchronously in the mod tick - same approach.
  local ok, err = pcall(function()
    -- 2a. Clear all existing highlights.
    if type(G.hand) == "table" and type(G.hand.unhighlight_all) == "function" then
      G.hand:unhighlight_all()
    end

    -- 2b. Click each target card to highlight it.
    -- card:click() atomically updates card.highlighted AND G.hand.highlighted.
    for _, c in ipairs(cards_to_play) do
      if type(c) == "table" and not c.removed then
        if not c.highlighted then
          pcall(c.click, c)
        end
      end
    end

    -- 2c. Play the highlighted cards.
    if type(G.FUNCS) ~= "table" or type(G.FUNCS.play_cards_from_highlighted) ~= "function" then
      error("play_cards_from_highlighted_missing")
    end
    local btn = get_button_elem("play_button")
    G.FUNCS.play_cards_from_highlighted(btn)
  end)

  if not ok then
    return make_action_error("play_hand_failed", tostring(err))
  end

  local post_hands_left = tonumber(G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or G.GAME and G.GAME.hands_left or 0) or 0
  local post_phase = M.get_phase()
  local committed = (post_hands_left < pre_hands_left) or (post_phase ~= pre_phase)
  local warnings = {}
  if not committed then
    warnings[#warnings + 1] = "play_commit_pending"
  end

  return make_action_ok({
    played_count = #cards_to_play,
    committed = committed,
    hands_left_before = pre_hands_left,
    hands_left_after = post_hands_left,
    warnings = warnings,
  })
end

function M.discard_selected(params)
  local G = get_G()
  if G == nil then
    return make_action_error("missing_G")
  end

  if not current_state_equals("SELECTING_HAND") then
    return make_action_error("discard_not_available_in_state", tostring(G.STATE))
  end

  local selected_cards = collect_highlighted_hand_cards()
  if #selected_cards < 1 then
    local fallback = first_hand_card(false) or first_hand_card(nil)
    if fallback ~= nil then
      card_click(fallback)
      selected_cards = collect_highlighted_hand_cards()
    end
    if #selected_cards < 1 then
      return make_action_error("no_selected_cards")
    end
  end

  local discards_left = tonumber(G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or G.GAME and G.GAME.discards_left or 0) or 0
  if discards_left <= 0 then
    return make_action_error("no_discards_left")
  end

  local btn = get_button_elem("discard_button")
  local ok, err = pcall(function()
    if type(G.FUNCS) ~= "table" or type(G.FUNCS.discard_cards_from_highlighted) ~= "function" then
      error("discard_cards_from_highlighted_missing")
    end
    G.FUNCS.discard_cards_from_highlighted(btn)
  end)
  if not ok then
    return make_action_error("discard_failed", tostring(err))
  end
  return make_action_ok({ discarded_count = #selected_cards })
end

function M.buy_item(params)
  params = safe_table(params)
  local card = find_shop_card(params.item_id)
  if card == nil then
    return make_action_error("shop_item_not_found", params.item_id)
  end

  local price = tonumber(card.cost or 0) or 0
  local money = current_money()
  if money < price then
    return make_action_error("insufficient_funds", "money=" .. tostring(money) .. ", price=" .. tostring(price))
  end

  local ok, err = call_func("buy_from_shop", { config = { ref_table = card, id = "buy" } })
  if not ok then
    return make_action_error("buy_item_failed", err)
  end
  return make_action_ok({ bought_item_id = tostring(params.item_id), price = price, money_before = money, money_after = current_money() })
end

function M.reroll_shop(params)
  local ok, err = call_func("reroll_shop", {})
  if not ok then
    return make_action_error("reroll_failed", err)
  end
  return make_action_ok()
end

function M.continue_flow(params)
  local G = get_G()
  if G == nil then
    return make_action_error("missing_G")
  end

  if current_state_equals("MENU") or current_state_equals("SPLASH") or current_state_equals("SANDBOX") then
    local ok, err = false, nil
    local launch_payload = { config = { id = "mcp_auto_start" } }

    ok, err = call_func("start_setup_run", launch_payload)
    if not ok then
      ok, err = call_func("notify_then_setup_run", launch_payload)
    end
    if not ok then
      ok, err = call_func("setup_run", {})
    end
    if not ok then
      ok, err = call_func("start_run", { config = { id = "mcp_auto_start" } })
    end
    if not ok then
      ok, err = call_func("start_run", launch_payload, {})
    end
    if not ok then
      return make_action_error("continue_failed", err)
    end
    return make_action_ok({ path = "setup_or_start_run" })
  end

  -- Round evaluation screen: click through to shop.
  -- Guard against half-initialized UI state: cash_out schedules deferred callbacks
  -- that require a live room screenwipe object.
  if current_state_equals("ROUND_EVAL") or current_state_equals("NEW_ROUND") then
    ensure_screenwipe(G)
    if type(G.round_eval) ~= "table" then
      return make_action_error("continue_failed", "round_eval_missing")
    end
    local ok, err = pcall(function()
      if type(G.FUNCS) ~= "table" or type(G.FUNCS.cash_out) ~= "function" then
        error("cash_out_missing")
      end
      -- G.round_eval is the actual UIBox with a proper .config table.
      local btn = G.round_eval
      -- Also try finding the cash_out button inside the UIRoot
      if type(G.round_eval) == "table" and type(G.round_eval.get_UIE_by_ID) == "function" then
        local ok_find, found = pcall(G.round_eval.get_UIE_by_ID, G.round_eval, "cash_out")
        if ok_find and found ~= nil then btn = found end
      end
      G.FUNCS.cash_out(btn)
    end)
    if not ok then
      return make_action_error("continue_failed", tostring(err))
    end
    return make_action_ok({ path = "cash_out" })
  end

  -- Game over: return to main menu so a new run can start.
  -- G.FUNCS.go_to_menu clears the E_MANAGER queue, starts a wipe animation,
  -- then calls G:delete_run() and G:main_menu('game') via async events.
  -- It does not read e.config so any table (or nil) can be passed.
  if current_state_equals("GAME_OVER") then
    local ok, err = call_func("go_to_menu", {})
    if not ok then
      return make_action_error("continue_failed_game_over", err)
    end
    return make_action_ok({ path = "go_to_menu" })
  end

  if G.shop ~= nil then
    if type(G.FUNCS) ~= "table" or type(G.FUNCS.toggle_shop) ~= "function" then
      return make_action_error("continue_failed", "toggle_shop_missing")
    end
    ensure_screenwipe(G)

    -- Use real shop UI object/button; synthetic {} can crash in button callbacks
    -- when callback expects a populated config.ref_table.shop.
    if type(G.GAME) ~= "table" or G.GAME.shop == nil then
      return make_action_error("continue_failed", "shop_ref_missing")
    end

    local btn = nil
    if type(G.shop) == "table" then
      btn = G.shop
      if type(G.shop.get_UIE_by_ID) == "function" then
        local ids = { "next_round_button", "next_round", "toggle_shop" }
        for _, id in ipairs(ids) do
          local ok_find, found = pcall(G.shop.get_UIE_by_ID, G.shop, id)
          if ok_find and found ~= nil then
            btn = found
            break
          end
        end
      end
    end

    if btn == nil then
      return make_action_error("continue_failed", "shop_button_missing")
    end

    local ok, err = pcall(G.FUNCS.toggle_shop, btn)
    if not ok then
      return make_action_error("continue_failed", tostring(err))
    end
    return make_action_ok({ path = "toggle_shop" })
  end

  if G.booster_pack ~= nil then
    local ok, err = call_func("end_consumeable", {})
    if not ok then
      return make_action_error("continue_failed", err)
    end
    return make_action_ok({ path = "end_consumeable" })
  end

  return make_action_error("continue_not_available", tostring(G.STATE))
end

function M.skip(params)
  local G = get_G()
  if G ~= nil and current_state_equals("BLIND_SELECT") then
    ensure_screenwipe(G)
    if type(G.FUNCS) ~= "table" or type(G.FUNCS.skip_blind) ~= "function" then
      return make_action_error("skip_blind_unavailable")
    end

    local real_uibox = nil
    local blind_on_deck = tostring(G.GAME and G.GAME.blind_on_deck or "")
    local blind_key = string.lower(blind_on_deck)

    local blind_opts = safe_table(G.blind_select_opts)
    local opt = blind_opts[blind_key]
    if type(opt) == "table" and type(opt.get_UIE_by_ID) == "function" then
      local ok_opt, box = pcall(opt.get_UIE_by_ID, opt, "tag_container")
      if ok_opt and box ~= nil then
        real_uibox = {
          get_UIE_by_ID = function(_, id)
            if id == "tag_container" then
              return box
            end
            return nil
          end,
        }
      end
    end

    if type(G.blind_select) == "table" and type(G.blind_select.get_UIE_by_ID) == "function" then
      local ok_real, box = pcall(G.blind_select.get_UIE_by_ID, G.blind_select, "tag_container")
      if ok_real and box ~= nil then
        real_uibox = {
          get_UIE_by_ID = function(_, id)
            if id == "tag_container" then
              return box
            end
            return nil
          end,
        }
      end
    end

    local uibox = real_uibox
    if uibox == nil then
      local blind_tags = safe_table(G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_tags)
      local tag_ref = blind_tags[blind_on_deck]
      local blind_tag = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_tag

      if type(blind_tag) == "table" then
        tag_ref = blind_tag
      end

      if tag_ref == nil then
        local fallback = M.choose_option({ option_id = "small" })
        if type(fallback) == "table" and fallback.success then
          local warnings = fallback.warnings or {}
          warnings[#warnings + 1] = "skip_blind_tag_missing_fallback_choose_option"
          fallback.warnings = warnings
          fallback.path = "skip_fallback_choose_option"
          return fallback
        end
        return make_action_error("skip_blind_missing_tag", blind_on_deck)
      end

      local normalized_tag_ref = tag_ref
      if type(normalized_tag_ref) == "string" then
        normalized_tag_ref = { key = normalized_tag_ref }
      end

      uibox = {
        get_UIE_by_ID = function(_, id)
          if id == "tag_container" then
            return { config = { ref_table = normalized_tag_ref } }
          end
          return nil
        end,
      }
    end

    local ok, err = pcall(G.FUNCS.skip_blind, { UIBox = uibox })
    if not ok then
      return make_action_error("skip_failed", err)
    end
    return make_action_ok({ path = "skip_blind" })
  end

  if G ~= nil and G.booster_pack ~= nil then
    local ok, err = call_func("skip_booster", {})
    if not ok then
      return make_action_error("skip_failed", err)
    end
    return make_action_ok({ path = "skip_booster" })
  end
  return make_action_error("skip_not_available")
end

function M.choose_option(params)
  params = safe_table(params)
  local option = tostring(params.option_id or ""):lower()
  if option == "" then
    return make_action_error("missing_option_id")
  end

  local G = get_G()
  if G == nil then
    return make_action_error("missing_G")
  end
  if not current_state_equals("BLIND_SELECT") then
    return make_action_error("choose_option_not_available", tostring(G.STATE))
  end
  ensure_screenwipe(G)
  if type(G.FUNCS) ~= "table" or type(G.FUNCS.select_blind) ~= "function" then
    return make_action_error("select_blind_unavailable")
  end

  local key = option
  if key == "small_blind" then
    key = "small"
  elseif key == "big_blind" then
    key = "big"
  elseif key == "boss_blind" then
    key = "boss"
  end

  local blind_choices = safe_table(G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices)
  local id_map = {
    small = "Small",
    big = "Big",
    boss = "Boss",
  }
  local blind_id = id_map[key]
  if blind_id == nil then
    return make_action_error("invalid_option_id", option)
  end

  local ref_table = blind_choices[blind_id]
  if ref_table == nil then
    return make_action_error("blind_choice_unavailable", blind_id)
  end

  local before_state = tostring(G.STATE)

  -- Prefer the real blind pane/button when present, but fall back to a minimal
  -- Build the button element that G.FUNCS.select_blind(e) expects.
  -- It accesses e.UIBox:get_UIE_by_ID("tag_container"), so UIBox must be set.
  local select_button = nil
  local blind_opts = safe_table(G.blind_select_opts)
  local pane = blind_opts[key]
  if type(pane) == "table" and type(pane.get_UIE_by_ID) == "function" then
    local ok_btn, found = pcall(pane.get_UIE_by_ID, pane, "select_blind_button")
    if ok_btn and type(found) == "table" then
      -- Patch UIBox onto the real button if missing; select_blind navigates via it.
      if found.UIBox == nil then
        found.UIBox = pane
      end
      select_button = found
    end
  end

  if select_button == nil then
    -- Fallback: construct a synthetic button with UIBox pointing to a container
    -- that returns the blind ref_table when queried for "tag_container".
    local uibox_container = {
      get_UIE_by_ID = function(_, id)
        if id == "tag_container" then
          return { config = { ref_table = ref_table } }
        end
        return nil
      end,
    }
    select_button = {
      UIBox = uibox_container,
      config = { ref_table = ref_table },
    }
  end

  -- G.FUNCS.select_blind is async: it queues G.E_MANAGER events rather than
  -- changing STATE synchronously.  The one thing it DOES set synchronously
  -- (when G.blind_select is not nil) is G.GAME.facing_blind = true.
  -- Use that as the canonical success signal instead of checking STATE.
  local facing_blind_before = not not (G.GAME and G.GAME.facing_blind)
  local ok, err = pcall(G.FUNCS.select_blind, select_button)
  local facing_blind_after = not not (G.GAME and G.GAME.facing_blind)

  if facing_blind_after and not facing_blind_before then
    -- Events queued; STATE will change to in_round on the next game tick(s).
    return make_action_ok({ option_id = blind_id, async = true })
  end

  -- Fallback: maybe G.blind_select was nil (UI not ready yet).
  local after_state = tostring(G.STATE)
  if not ok and after_state == before_state then
    return make_action_error("choose_option_failed", err)
  end

  if after_state ~= before_state then
    return make_action_ok({ option_id = blind_id })
  end

  return make_action_error("choose_option_blind_select_not_ready", "G.blind_select is nil; retry after UI renders")
end

function M.end_turn(params)
  local result = M.continue_flow(params)
  if type(result) == "table" and result.success then
    return result
  end
  if type(result) == "table" and result.error == "continue_not_available" then
    return make_action_ok({
      path = "end_turn_noop",
      warnings = { "continue_not_available" },
    })
  end
  return result
end

function M.start(params)
  params = safe_table(params)
  local G = get_G()
  if G == nil then
    return make_action_error("missing_G")
  end
  local cfg = {
    id = tostring(params.seed or "mcp_manual_start"),
  }
  if params.deck ~= nil then cfg.deck = params.deck end
  if params.stake ~= nil then cfg.stake = params.stake end
  local ok, err = call_func("start_run", { config = cfg }, {})
  if not ok then
    return make_action_error("start_failed", err)
  end
  return make_action_ok({ path = "start_run", seed = cfg.id })
end

function M.menu(params)
  local ok, err = call_func("main_menu", {})
  if not ok then
    local ok2, err2 = call_func("setup_run", {})
    if not ok2 then
      return make_action_ok({
        path = "menu_noop",
        warnings = { "menu_unavailable_local_only", tostring(err2 or err) },
      })
    end
  end
  return make_action_ok({ path = "main_menu" })
end

function M.cash_out(params)
  return M.continue_flow(params)
end

function M.next_round(params)
  return M.continue_flow(params)
end

function M.rearrange(params)
  params = safe_table(params)
  local G = get_G()
  if G == nil then
    return make_action_error("missing_G")
  end

  local function reorder_area(area, order)
    if type(area) ~= "table" or type(area.cards) ~= "table" or type(order) ~= "table" then
      return false, "invalid_area"
    end
    local lookup = {}
    for i, card in ipairs(area.cards) do
      lookup[card_runtime_id(card, i)] = card
    end
    local new_cards = {}
    local used = {}
    for _, entry in ipairs(order) do
      local card = lookup[tostring(entry)]
      if card ~= nil and not used[card] then
        new_cards[#new_cards + 1] = card
        used[card] = true
      end
    end
    for _, card in ipairs(area.cards) do
      if not used[card] then
        new_cards[#new_cards + 1] = card
      end
    end
    area.cards = new_cards
    return true, #new_cards
  end

  local warnings = {}
  if params.hand ~= nil then
    local ok, count = reorder_area(G.hand, params.hand)
    if not ok then
      return make_action_error("rearrange_failed", count)
    end
    warnings[#warnings + 1] = "hand_reordered"
  end
  if params.jokers ~= nil and G.jokers ~= nil then
    local ok, count = reorder_area(G.jokers, params.jokers)
    if not ok then
      return make_action_error("rearrange_failed", count)
    end
    warnings[#warnings + 1] = "jokers_reordered"
  end
  if params.consumables ~= nil and G.consumeables ~= nil then
    local ok, count = reorder_area(G.consumeables, params.consumables)
    if not ok then
      return make_action_error("rearrange_failed", count)
    end
    warnings[#warnings + 1] = "consumables_reordered"
  end

  state_cache.update_snapshot(M.get_runtime_state() or get_state_snapshot())
  return make_action_ok({ warnings = warnings })
end

function M.save(params)
  params = safe_table(params)
  local path = tostring(params.path or "")
  if path == "" then
    return make_action_error("missing_path")
  end
  local payload = json_util.encode(get_state_snapshot())
  local ok, err = write_text_file(path, payload)
  if not ok then
    return make_action_error("save_failed", err)
  end
  return make_action_ok({ success = true, path = path })
end

function M.load(params)
  params = safe_table(params)
  local path = tostring(params.path or "")
  if path == "" then
    return make_action_error("missing_path")
  end
  local raw, err = read_text_file(path)
  if raw == nil then
    return make_action_error("load_failed", err)
  end
  local decoded = json_util.decode(raw)
  if type(decoded) ~= "table" then
    return make_action_error("load_failed", "invalid_json")
  end
  state_cache.update_snapshot(decoded)
  return make_action_ok({ success = true, path = path })
end

function M.add(params)
  params = safe_table(params)
  local key = tostring(params.key or "")
  if key == "" then
    return make_action_error("missing_key")
  end
  local created = false
  local note = "local_debug_state_only"
  local snapshot = get_state_snapshot()
  snapshot.hand = snapshot.hand or {}
  snapshot.jokers = snapshot.jokers or {}
  snapshot.consumables = snapshot.consumables or {}
  snapshot.shop = snapshot.shop or { items = {}, reroll_cost = 5, voucher = nil, pack_options = {} }

  if key:match("^j_") then
    snapshot.jokers[#snapshot.jokers + 1] = {
      joker_id = key .. ":" .. tostring(os.time()),
      name = key,
      rarity = tostring(params.rarity or "common"),
      edition = params.edition,
      sell_value = tonumber(params.sell_value or 0) or 0,
      effect_text = tostring(params.effect_text or ""),
      triggered_state = {},
      positional_index = #snapshot.jokers,
    }
    created = true
  elseif key:match("^c_") then
    snapshot.consumables[#snapshot.consumables + 1] = {
      consumable_id = key .. ":" .. tostring(os.time()),
      key = key,
      name = tostring(params.name or key),
      set = tostring(params.set or "TAROT"),
    }
    created = true
  elseif key:match("^[HDSC]_") then
    snapshot.hand[#snapshot.hand + 1] = {
      card_id = key .. ":" .. tostring(os.time()),
      rank = key:sub(3),
      suit = key:sub(1, 1),
      selected = false,
      debuffed = false,
      enhancement = params.enhancement,
      edition = params.edition,
      seal = params.seal,
    }
    created = true
  elseif key:match("^p_") then
    snapshot.shop.pack_options[#snapshot.shop.pack_options + 1] = key
    created = true
  else
    return make_action_error("unsupported_key", key)
  end

  state_cache.update_snapshot(snapshot)
  return make_action_ok({ created = created, key = key, note = note })
end

function M.set(params)
  params = safe_table(params)
  local updated = {}
  local snapshot = get_state_snapshot()
  snapshot.resources = snapshot.resources or {}
  snapshot.action_points = snapshot.action_points or {}
  snapshot.shop = snapshot.shop or { items = {}, reroll_cost = 5, voucher = nil, pack_options = {} }

  if params.money ~= nil then snapshot.resources.money = tonumber(params.money) or snapshot.resources.money; updated[#updated + 1] = "money" end
  if params.chips ~= nil then snapshot.resources.chips = tonumber(params.chips) or snapshot.resources.chips; updated[#updated + 1] = "chips" end
  if params.ante ~= nil then snapshot.resources.ante = tonumber(params.ante) or snapshot.resources.ante; updated[#updated + 1] = "ante" end
  if params.round ~= nil then snapshot.turn_index = tonumber(params.round) or snapshot.turn_index; updated[#updated + 1] = "round" end
  if params.hands ~= nil then snapshot.action_points.hands_left = tonumber(params.hands) or snapshot.action_points.hands_left; updated[#updated + 1] = "hands" end
  if params.discards ~= nil then snapshot.action_points.discards_left = tonumber(params.discards) or snapshot.action_points.discards_left; updated[#updated + 1] = "discards" end
  if params.shop ~= nil then updated[#updated + 1] = "shop" end

  state_cache.update_snapshot(snapshot)
  return make_action_ok({ updated = updated })
end

function M.screenshot(params)
  params = safe_table(params)
  local path = tostring(params.path or "")
  if path == "" then
    path = tostring(os.time()) .. ".png"
  end
  if type(love) == "table" and type(love.graphics) == "table" and type(love.graphics.captureScreenshot) == "function" then
    local ok, err = pcall(love.graphics.captureScreenshot, path)
    if not ok then
      return make_action_error("screenshot_failed", tostring(err))
    end
    return make_action_ok({ success = true, path = path })
  end
  return make_action_error("screenshot_unavailable", path)
end

return M
