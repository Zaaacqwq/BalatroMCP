local config = require("bmcp.config")
local json_util = require("bmcp.json_util")
local state_extractor = require("bmcp.state_extractor")
local action_executor = require("bmcp.action_executor")
local sync_controller = require("bmcp.sync_controller")
local state_cache = require("bmcp.state_cache")

local M = {}

local ok_socket, socket = pcall(require, "socket")
local server = nil
local clients = {}

local tools = {
  {
    name = "get_game_state",
    description = "Return current normalized game state snapshot",
    input_schema = { type = "object", properties = {}, additionalProperties = false },
  },
  {
    name = "list_legal_actions",
    description = "List legal actions for current state",
    input_schema = { type = "object", properties = {}, additionalProperties = false },
  },
  {
    name = "execute_action",
    description = "Execute whitelisted action",
    input_schema = {
      type = "object",
      properties = {
        action_type = { type = "string" },
        params = { type = "object" },
      },
      required = { "action_type" },
      additionalProperties = false,
    },
  },
  {
    name = "get_action_history",
    description = "Get recent action and event history",
    input_schema = {
      type = "object",
      properties = { limit = { type = "integer", minimum = 1, maximum = 200 } },
      additionalProperties = false,
    },
  },
  {
    name = "get_run_summary",
    description = "Get run-level summary",
    input_schema = { type = "object", properties = {}, additionalProperties = false },
  },
  {
    name = "pause_mod_control",
    description = "Pause external control",
    input_schema = { type = "object", properties = {}, additionalProperties = false },
  },
  {
    name = "resume_mod_control",
    description = "Resume external control",
    input_schema = { type = "object", properties = {}, additionalProperties = false },
  },
  {
    name = "request_mod_snapshot",
    description = "Force an immediate snapshot refresh",
    input_schema = { type = "object", properties = {}, additionalProperties = false },
  },
}

local function log(msg)
  print((config.log_prefix or "[balatro-mcp-mod]") .. " " .. tostring(msg))
end

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

local function extract_string_field(raw, field_name)
  if type(raw) ~= "string" then
    return nil
  end
  local pattern = '"' .. field_name .. '"%s*:%s*"(.-)"'
  local value = raw:match(pattern)
  return value
end

local function extract_number_field(raw, field_name)
  if type(raw) ~= "string" then
    return nil
  end
  local pattern = '"' .. field_name .. '"%s*:%s*(-?%d+%.?%d*)'
  local value = raw:match(pattern)
  if value == nil then
    return nil
  end
  return tonumber(value)
end

local function extract_cards_field(raw)
  if type(raw) ~= "string" then
    return nil
  end
  local array_blob = raw:match('"cards"%s*:%s*%[(.-)%]')
  if array_blob == nil then
    return nil
  end
  local cards = {}
  for num in array_blob:gmatch("-?%d+") do
    cards[#cards + 1] = tonumber(num)
  end
  return cards
end

local function extract_string_array_field(raw, field_name)
  if type(raw) ~= "string" or type(field_name) ~= "string" or field_name == "" then
    return nil
  end
  local pattern = '"' .. field_name .. '"%s*:%s*%[(.-)%]'
  local array_blob = raw:match(pattern)
  if array_blob == nil then
    return nil
  end
  local values = {}
  for quoted in array_blob:gmatch('"(.-)"') do
    values[#values + 1] = quoted
  end
  if #values == 0 then
    for num in array_blob:gmatch('-?%d+%.?%d*') do
      values[#values + 1] = tostring(num)
    end
  end
  if #values == 0 then
    return nil
  end
  return values
end

local function extract_params_blob(raw)
  if type(raw) ~= "string" then
    return nil
  end
  local blob = raw:match('"params"%s*:%s*{(.*)}%s*,%s*"id"')
  if blob ~= nil then
    return blob
  end
  blob = raw:match('"params"%s*:%s*{(.*)}%s*}')
  return blob
end

local function extract_params_table(raw)
  local params = {}
  local blob = extract_params_blob(raw)
  if blob == nil then
    blob = raw
  end

  local string_fields = { "path", "seed", "deck", "stake", "option_id", "card_id", "item_id", "joker_id", "consumable_id", "key", "edition", "seal", "enhancement", "name", "effect_text", "rarity" }
  for _, field_name in ipairs(string_fields) do
    local value = extract_string_field(blob, field_name)
    if value ~= nil then
      params[field_name] = value
    end
  end

  local numeric_fields = { "money", "chips", "ante", "round", "hands", "discards", "reroll_cost", "sell_value" }
  for _, field_name in ipairs(numeric_fields) do
    local value = extract_number_field(blob, field_name)
    if value ~= nil then
      params[field_name] = value
    end
  end

  local cards = extract_cards_field(blob)
  if cards ~= nil then
    params.cards = cards
  end

  local card_ids = extract_string_array_field(blob, "card_ids")
  if card_ids ~= nil then
    params.card_ids = card_ids
  end

  if blob:match('"skip"%s*:%s*true') then
    params.skip = true
  end

  if blob:match('"shop"%s*:%s*true') then
    params.shop = true
  end

  return params
end

local function fallback_parse_request_body(raw)
  if type(raw) ~= "string" then
    return {}
  end
  local body = {
    name = extract_string_field(raw, "name"),
    action_type = extract_string_field(raw, "action_type"),
    idempotency_key = extract_string_field(raw, "idempotency_key"),
  }
  body.params = extract_params_table(raw)
  body.arguments = {
    action_type = body.action_type,
    params = body.params,
    idempotency_key = body.idempotency_key,
  }
  return body
end

local function decode_uri_component(value)
  local s = tostring(value or "")
  s = s:gsub("+", " ")
  s = s:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  return s
end

local function parse_query(path)
  local query = {}
  local q = path:match("%?(.*)$")
  if not q then
    return query
  end
  for pair in q:gmatch("[^&]+") do
    local key, val = pair:match("([^=]+)=?(.*)")
    if key then
      query[decode_uri_component(key)] = decode_uri_component(val or "")
    end
  end
  return query
end

local function strip_query(path)
  local p = tostring(path or "/")
  local idx = p:find("?", 1, true)
  if idx then
    return p:sub(1, idx - 1)
  end
  return p
end

local function http_status_text(code)
  local map = {
    [200] = "OK",
    [400] = "Bad Request",
    [404] = "Not Found",
    [405] = "Method Not Allowed",
    [500] = "Internal Server Error",
  }
  return map[code] or "OK"
end

local function format_response(code, body, content_type)
  local payload = body or ""
  local headers = {
    "HTTP/1.1 " .. tostring(code) .. " " .. http_status_text(code),
    "Content-Type: " .. (content_type or "application/json"),
    "Content-Length: " .. tostring(#payload),
    "Connection: close",
    "Cache-Control: no-store",
  }
  return table.concat(headers, "\r\n") .. "\r\n\r\n" .. payload
end

local function json_response(code, data)
  return format_response(code, json_util.encode(data or {}), "application/json")
end

local function text_response(code, text)
  return format_response(code, tostring(text or ""), "text/plain; charset=utf-8")
end

local function file_response(path, content_type)
  local f = io.open(path, "rb")
  if f == nil then
    return text_response(404, "not found")
  end
  local body = f:read("*a")
  f:close()
  return format_response(200, body or "", content_type)
end

local function get_mod_dir()
  local appdata = os.getenv("APPDATA")
  if type(appdata) == "string" and appdata ~= "" then
    return appdata:gsub("\\", "/") .. "/Balatro/Mods/balatro_mcp"
  end
  return "."
end

local function list_legal_actions(state)
  local phase = state.phase or "menu"
  local actions = {}

  local function add(name, params_schema, valid_params)
    local action = { action_type = name, params_schema = params_schema or {} }
    if type(valid_params) == "table" and next(valid_params) ~= nil then
      action.valid_params = valid_params
    end
    actions[#actions + 1] = action
  end

  if phase == "menu" or phase == "game_over" or phase == "round_eval" then
    add("continue")
    return actions
  end

  if phase == "blind_select" then
    local blind = state.blind or {}
    local options = blind.options or {}
    local option_ids = {}
    for _, option in ipairs(options) do
      if type(option) == "table" and option.option_id ~= nil then
        option_ids[#option_ids + 1] = tostring(option.option_id)
      end
    end
    if #option_ids == 0 then
      option_ids = { "small", "big", "boss" }
    end
    add("choose_option", { option_id = "string" }, { option_id = option_ids, options = options })
    add("skip")
    return actions
  end

  if phase == "in_round" then
    local ap = state.action_points or {}
    local cards = state.hand or {}
    local card_ids = {}
    for _, card in ipairs(cards) do
      local card_id = card.card_id or card.id
      if card_id ~= nil then
        card_ids[#card_ids + 1] = tostring(card_id)
      end
    end
    add("select_card", { card_id = "string" }, { card_id = card_ids })
    add("deselect_card", { card_id = "string" }, { card_id = card_ids })
    if (ap.hands_left or 0) > 0 then
      add("play_hand", { card_ids = { "string" } }, { card_ids = card_ids })
    end
    if (ap.discards_left or 0) > 0 then
      add("discard_selected")
    end
    if (ap.hands_left or 0) <= 0 then
      add("end_turn")
    end
    return actions
  end

  if phase == "shop" then
    local resources = state.resources or {}
    local shop = state.shop or {}
    local item_ids = {}
    local item_names = {}
    for _, item in ipairs(shop.items or {}) do
      if type(item) == "table" then
        if item.item_id ~= nil then
          item_ids[#item_ids + 1] = tostring(item.item_id)
        end
        item_names[#item_names + 1] = {
          item_id = item.item_id,
          name = item.name,
          item_type = item.item_type,
          price = item.price,
        }
      end
    end
    add("buy_item", { item_id = "string" }, { item_id = item_ids, items = item_names })
    if (resources.money or 0) >= (shop.reroll_cost or 0) then
      add("reroll_shop")
    end
    local joker_ids = {}
    for _, joker in ipairs(state.jokers or {}) do
      if type(joker) == "table" and joker.joker_id ~= nil then
        joker_ids[#joker_ids + 1] = tostring(joker.joker_id)
      end
    end
    local consumable_ids = {}
    for _, consumable in ipairs(state.consumables or {}) do
      if type(consumable) == "table" and consumable.consumable_id ~= nil then
        consumable_ids[#consumable_ids + 1] = tostring(consumable.consumable_id)
      end
    end
    add("sell_joker", { joker_id = "string" }, { joker_id = joker_ids })
    add("use_consumable", { consumable_id = "string" }, { consumable_id = consumable_ids })
    add("end_turn")
    add("continue")
    return actions
  end

  if phase == "pack" then
    add("choose_option", { option_id = "string" }, { option_id = state.shop and state.shop.pack_options or {} })
    add("skip")
    return actions
  end

  return actions
end

local function refresh_snapshot(reason)
  local snapshot = state_extractor.extract_game_state()
  if type(snapshot) == "table" then
    state_cache.update_snapshot(snapshot)
    return {
      ok = true,
      reason = reason or "refresh",
      phase = snapshot.phase,
      turn_index = snapshot.turn_index,
    }
  end
  return { ok = false, error = "snapshot_unavailable" }
end

local function execute_action(action)
  if type(action) ~= "table" or type(action.action_type) ~= "string" then
    return { success = false, error = "invalid_action_payload" }
  end

  local G = rawget(_G, "G")
  if type(G) == "table" then
    if type(G.ROOM) ~= "table" then
      G.ROOM = {}
    end
    if type(G.ROOM.screenwipe) ~= "table" then
      G.ROOM.screenwipe = { _mcp_placeholder = true }
    end
  end

  if not sync_controller.can_control() then
    return {
      success = false,
      error = "control_paused",
      warnings = { "mod_control_paused_or_busy" },
      action_type = action.action_type,
    }
  end

  local result = action_executor.execute(action)
  state_cache.record_action(action, result)
  refresh_snapshot("execute_action")
  return result
end

local function run_mcp_tool(name, args)
  local arguments = args or {}
  if name == "get_game_state" then
    -- Always extract a fresh snapshot so transient cache states are never seen.
    local snap = state_extractor.extract_game_state()
    if snap then state_cache.update_snapshot(snap) end
    return { content = state_cache.get_state() }
  end
  if name == "list_legal_actions" then
    return { content = list_legal_actions(state_cache.get_state()) }
  end
  if name == "execute_action" then
    local action = {
      action_type = arguments.action_type,
      params = arguments.params or {},
      idempotency_key = arguments.idempotency_key,
    }
    return { content = execute_action(action) }
  end
  if name == "get_action_history" then
    return { content = state_cache.get_action_history(arguments.limit or 20) }
  end
  if name == "get_run_summary" then
    return { content = state_cache.get_run_summary() }
  end
  if name == "pause_mod_control" then
    sync_controller.pause()
    return { content = { ok = true, paused = true } }
  end
  if name == "resume_mod_control" then
    sync_controller.resume()
    return { content = { ok = true, paused = false } }
  end
  if name == "request_mod_snapshot" then
    return { content = refresh_snapshot("manual_request") }
  end
  if name == "debug_ui" then
    return { content = action_executor.execute({ action_type = "debug_ui", params = {} }) }
  end
  return nil, "unknown_tool"
end

local function handle_rest(method, path, body_raw)
  local clean_path = strip_query(path)
  local query = parse_query(path)

  if method == "GET" and (clean_path == "/" or clean_path == "/ui") then
    local html_path = get_mod_dir() .. "/web/index.html"
    return file_response(html_path, "text/html; charset=utf-8")
  end

  if method == "GET" and clean_path == "/web/app.js" then
    return file_response(get_mod_dir() .. "/web/app.js", "application/javascript; charset=utf-8")
  end

  if method == "GET" and clean_path == "/web/style.css" then
    return file_response(get_mod_dir() .. "/web/style.css", "text/css; charset=utf-8")
  end

  if method == "GET" and clean_path == "/health" then
    return json_response(200, {
      status = "ok",
      server = "balatro_mcp_mod_embedded",
      paused = sync_controller.is_paused(),
    })
  end

  if method == "GET" and clean_path == "/state" then
    local snap = state_extractor.extract_game_state()
    if snap then state_cache.update_snapshot(snap) end
    return json_response(200, state_cache.get_state())
  end

  if method == "GET" and clean_path == "/adapter_raw" then
    -- Raw adapter output for debugging
    local adapter = require("bmcp.adapter")
    local runtime_state, _ = adapter.call("get_runtime_state")
    return json_response(200, runtime_state or { error = "adapter_call_failed" })
  end

  if method == "GET" and clean_path == "/legal_actions" then
    return json_response(200, { actions = list_legal_actions(state_cache.get_state()) })
  end

  if method == "GET" and clean_path == "/action_history" then
    local limit = tonumber(query.limit) or 20
    return json_response(200, { history = state_cache.get_action_history(limit) })
  end

  if method == "GET" and clean_path == "/run_summary" then
    return json_response(200, state_cache.get_run_summary())
  end

  if method == "GET" and clean_path == "/mcp/tools" then
    return json_response(200, { tools = tools })
  end

  local body = json_util.decode(body_raw or "")
  if type(body) ~= "table" then
    body = fallback_parse_request_body(body_raw)
  else
    if body.name == nil then body.name = extract_string_field(body_raw, "name") end
    if body.action_type == nil then body.action_type = extract_string_field(body_raw, "action_type") end
    if body.params == nil then body.params = extract_params_table(body_raw) end
    if body.arguments == nil and body.name == "execute_action" then
      body.arguments = {
        action_type = body.action_type,
        params = body.params,
        idempotency_key = body.idempotency_key,
      }
    end
  end

  if method == "POST" and clean_path == "/execute_action" then
    local action = {
      action_type = body.action_type,
      params = body.params or {},
      idempotency_key = body.idempotency_key,
    }
    return json_response(200, execute_action(action))
  end

  if method == "POST" and clean_path == "/pause_control" then
    sync_controller.pause()
    return json_response(200, { ok = true, paused = true })
  end

  if method == "POST" and clean_path == "/resume_control" then
    sync_controller.resume()
    return json_response(200, { ok = true, paused = false })
  end

  if method == "POST" and clean_path == "/request_snapshot" then
    return json_response(200, refresh_snapshot("manual_request"))
  end

  if method == "POST" and clean_path == "/mcp/call" then
    local name = body.name
    local arguments = body.arguments or {}
    local result, err = run_mcp_tool(name, arguments)
    if result == nil then
      return json_response(404, { error = err or "unknown_tool" })
    end
    return json_response(200, result)
  end

  if method == "POST" and clean_path == "/debug/echo" then
    return json_response(200, {
      raw = body_raw,
      parsed = body,
    })
  end

  if method ~= "GET" and method ~= "POST" then
    return text_response(405, "method not allowed")
  end

  return text_response(404, "not found")
end

local function parse_request(buffer, allow_truncated_body)
  local header_end = buffer:find("\r\n\r\n", 1, true)
  if not header_end then
    return nil
  end

  local header_blob = buffer:sub(1, header_end - 1)
  local lines = {}
  for line in header_blob:gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
  end
  if #lines == 0 then
    return { error = "empty request", consumed = #buffer }
  end

  local method, path = lines[1]:match("^(%u+)%s+(%S+)%s+HTTP/%d%.%d$")
  if method == nil then
    return { error = "invalid request line", consumed = #buffer }
  end

  local content_length = 0
  local has_content_length = false
  for i = 2, #lines do
    local key, val = lines[i]:match("^([^:]+):%s*(.*)$")
    if key and key:lower() == "content-length" then
      content_length = tonumber(val) or 0
      has_content_length = true
      break
    end
  end

  local body_start = header_end + 4
  local total_needed = body_start - 1
  local body = ""

  if has_content_length then
    total_needed = body_start + content_length - 1
    if #buffer < total_needed then
      if not allow_truncated_body then
        return nil
      end
      if #buffer < body_start then
        return nil
      end
      body = buffer:sub(body_start)
      total_needed = #buffer
      return {
        method = method,
        path = path,
        body = body,
        consumed = total_needed,
      }
    end
    if content_length > 0 then
      body = buffer:sub(body_start, total_needed)
    end
  else
    -- Fallback for clients that omit Content-Length (or use transfer styles we don't parse).
    if method == "POST" then
      body = buffer:sub(body_start)
      total_needed = #buffer
    end
  end

  return {
    method = method,
    path = path,
    body = body,
    consumed = total_needed,
  }
end

function M.init()
  if not config.enable_embedded_api then
    return
  end
  if not ok_socket then
    log("embedded api disabled: LuaSocket not available")
    return
  end
  if server ~= nil then
    return
  end

  local host = config.embedded_api_host or "127.0.0.1"
  local port = tonumber(config.embedded_api_port) or 12346

  local sock, err = socket.tcp()
  if not sock then
    log("embedded api socket create failed: " .. tostring(err))
    return
  end

  sock:setoption("reuseaddr", true)
  local bind_ok, bind_err = sock:bind(host, port)
  if not bind_ok then
    log("embedded api bind failed: " .. tostring(bind_err))
    return
  end

  local listen_ok, listen_err = sock:listen(8)
  if not listen_ok then
    log("embedded api listen failed: " .. tostring(listen_err))
    sock:close()
    return
  end

  sock:settimeout(0)
  server = sock
  clients = {}
  refresh_snapshot("startup")
  log("embedded api listening at http://" .. host .. ":" .. tostring(port))
end

local function close_client(i)
  local c = clients[i]
  if c and c.sock then
    pcall(c.sock.close, c.sock)
  end
  table.remove(clients, i)
end

-- Extract an execute_action payload from an HTTP request.
-- Returns (action_table, response_format) or (nil, nil) if not an execute_action request.
-- response_format is "raw" for /execute_action, "mcp" for /mcp/call.
local function extract_execute_action(method, clean_path, body_raw)
  if method ~= "POST" then return nil, nil end

  local body = json_util.decode(body_raw or "")
  if type(body) ~= "table" then
    body = fallback_parse_request_body(body_raw)
  else
    if body.action_type == nil then body.action_type = extract_string_field(body_raw, "action_type") end
    if body.params == nil then body.params = extract_params_table(body_raw) end
    if body.arguments == nil and body.name == "execute_action" then
      body.arguments = { action_type = body.action_type, params = body.params }
    end
  end

  if clean_path == "/execute_action" then
    local at = body.action_type
    if type(at) ~= "string" or at == "" then return nil, nil end
    return {
      action_type = at,
      params = body.params or {},
      idempotency_key = body.idempotency_key,
    }, "raw"
  end

  if clean_path == "/mcp/call" then
    if body.name ~= "execute_action" then return nil, nil end
    local args = body.arguments or {}
    local at = args.action_type
    if type(at) ~= "string" or at == "" then return nil, nil end
    return {
      action_type = at,
      params = args.params or {},
      idempotency_key = args.idempotency_key,
    }, "mcp"
  end

  return nil, nil
end

-- Determine whether a just-executed action has fully settled (animations done,
-- state stable) so the next action can safely be accepted.
local function is_action_settled(c)
  local elapsed = os.clock() - (c.settle_start or 0)
  -- Hard safety timeout: never block forever.
  if elapsed > 18.0 then return true end

  -- If the action failed, don't wait for expensive state transitions —
  -- just give the game one short tick to breathe.
  if not c.action_succeeded then
    return elapsed > 0.1
  end

  local at = c.settled_action_type

  -- play_hand / discard: game enters HAND_PLAYED then DRAW_TO_HAND.
  -- play_cards_from_highlighted queues E_MANAGER events; HAND_PLAYED state
  -- only starts on the next game tick. Require a minimum delay so we don't
  -- check can_control() before the busy state has even started.
  --
  -- After the last hand of a LOSING round the sequence is:
  --   HAND_PLAYED → DRAW_TO_HAND → GAME_OVER (auto-advances) → menu
  -- GAME_OVER has can_control()=true but is transient; if we return there
  -- the agent's next get_game_state might race and see "menu" instead of
  -- "game_over". Wait through GAME_OVER so we always land at stable "menu".
  --
  -- After the last hand of a WINNING round:
  --   HAND_PLAYED → DRAW_TO_HAND → ROUND_EVAL (stable; player must click cash_out)
  -- ROUND_EVAL is stable (not auto-advancing), so we correctly return there.
  if at == "play_hand" or at == "discard_selected" then
    if elapsed < 0.15 then return false end
    if not sync_controller.can_control() then return false end
    local s = state_cache.get_state()
    local ph = s.phase or ""
    -- After losing: GAME_OVER auto-advances to menu; wait through it.
    if ph == "game_over" then return false end
    -- After winning: there is a ~0.3s delay between DRAW_TO_HAND ending and
    -- G.STATE becoming ROUND_EVAL.  During that window G.STATE is unrecognised
    -- so get_phase() returns "menu" as a fallback — but G.STAGE is still RUN.
    -- Don't treat that transient "menu" as a stable landing state.
    if ph == "menu" then
      local G = rawget(_G, "G")
      if G and G.STAGES and G.STAGE == G.STAGES.RUN then
        return false   -- still in a run; wait for a recognised stable state
      end
    end
    return true
  end

  -- choose_option: selecting a blind starts card deal (DRAW_TO_HAND).
  -- Wait until phase changes away from blind_select AND can_control() is true.
  if at == "choose_option" then
    local s = state_cache.get_state()
    local phase_changed = (s.phase or "") ~= (c.pre_phase or "blind_select")
    if not phase_changed then return false end
    return sync_controller.can_control()
  end

  -- skip: skipping a blind stays in BLIND_SELECT (game shows the next blind).
  -- No phase change occurs; just wait for the brief skip animation to finish.
  if at == "skip" then
    if elapsed < 0.5 then return false end
    return sync_controller.can_control()
  end

  -- continue / end_turn: async cash_out / shop / round transitions.
  -- Wait until phase changes, then let can_control() confirm stability.
  if at == "continue" or at == "end_turn" then
    local s = state_cache.get_state()
    local phase_changed = (s.phase or "") ~= (c.pre_phase or "")
    if not phase_changed then return false end
    -- If we transitioned into blind_select, also wait for G.blind_select
    -- UI panel to be created (it's built asynchronously after state change).
    if s.phase == "blind_select" then
      local G = rawget(_G, "G")
      if G and type(G.blind_select) ~= "table" then return false end
    end
    return sync_controller.can_control()
  end

  -- select_card, deselect_card, buy_item, reroll_shop, etc: fast ops.
  -- One short tick is enough for state_cache to refresh.
  return elapsed > 0.1
end

function M.update()
  if server == nil then
    return
  end

  for _ = 1, 4 do
    local client, err = server:accept()
    if client == nil then break end
    client:settimeout(0)
    clients[#clients + 1] = { sock = client, buffer = "", cstatus = "reading" }
  end

  local i = 1
  while i <= #clients do
    local c = clients[i]

    -- ── State: pending ────────────────────────────────────────────────────────
    -- Waiting for can_control() before we can execute the deferred action.
    if c.cstatus == "pending" then
      local timed_out = (os.clock() - (c.pending_start or 0)) > 5.0
      if sync_controller.can_control() or timed_out then
        local raw = execute_action(c.pending_action)
        local resp_body = c.resp_format == "mcp" and { content = raw } or raw
        c.pending_response = json_response(200, resp_body)
        c.settled_action_type = c.pending_action.action_type
        c.action_succeeded = raw.success == true
        c.settle_start = os.clock()
        c.cstatus = "settling"
      end
      i = i + 1

    -- ── State: settling ───────────────────────────────────────────────────────
    -- Action was executed; waiting for game animations / state transitions to finish.
    elseif c.cstatus == "settling" then
      if is_action_settled(c) then
        refresh_snapshot("post_settle")
        c.sock:send(c.pending_response)
        close_client(i)
        -- i intentionally NOT incremented: element was removed
      else
        i = i + 1
      end

    -- ── State: reading ────────────────────────────────────────────────────────
    -- Accumulating request bytes from the client.
    else
      local chunk, recv_err, partial = c.sock:receive(8192)
      local data = chunk or partial

      if data and #data > 0 then
        c.buffer = c.buffer .. data
        local req = parse_request(c.buffer)

        if req and req.error then
          c.sock:send(text_response(400, req.error))
          close_client(i)

        elseif req then
          local clean_path = strip_query(req.path)
          local action, resp_fmt = extract_execute_action(req.method, clean_path, req.body)

          if action ~= nil then
            -- Execute-action request: run through pending → settling pipeline.
            local snap = state_cache.get_state()
            c.pre_phase = snap.phase
            c.pending_action = action
            c.resp_format = resp_fmt

            if sync_controller.can_control() then
              local raw = execute_action(action)
              local resp_body = resp_fmt == "mcp" and { content = raw } or raw
              c.pending_response = json_response(200, resp_body)
              c.settled_action_type = action.action_type
              c.action_succeeded = raw.success == true
              c.settle_start = os.clock()
              c.cstatus = "settling"
            else
              c.pending_start = os.clock()
              c.cstatus = "pending"
            end
            i = i + 1

          else
            -- All other requests (get_game_state, list_legal_actions, etc.)
            -- are answered immediately.
            local response = handle_rest(req.method, req.path, req.body)
            c.sock:send(response)
            close_client(i)
          end

        else
          -- Request not complete yet; keep buffering.
          i = i + 1
        end

      elseif recv_err == "closed" then
        -- Connection dropped while reading; try to handle whatever we have.
        local req2 = parse_request(c.buffer, true)
        if req2 and not req2.error then
          local clean_path = strip_query(req2.path)
          local action, resp_fmt = extract_execute_action(req2.method, clean_path, req2.body)
          if action then
            local raw = execute_action(action)
            local resp_body = resp_fmt == "mcp" and { content = raw } or raw
            c.sock:send(json_response(200, resp_body))
          else
            c.sock:send(handle_rest(req2.method, req2.path, req2.body))
          end
        end
        close_client(i)

      else
        i = i + 1
      end
    end
  end
end

function M.shutdown()
  if server ~= nil then
    pcall(server.close, server)
    server = nil
  end
  for i = #clients, 1, -1 do
    close_client(i)
  end
  clients = {}
end

return M
