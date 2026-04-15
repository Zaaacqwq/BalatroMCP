local M = {}

local config = require("bmcp.config")
local json_util = require("bmcp.json_util")

local ok_http, http = pcall(require, "socket.http")
local ok_ltn12, ltn12 = pcall(require, "ltn12")

local function log(msg)
  print("[balatro-mcp-mod] " .. tostring(msg))
end

local function fail(error_code, detail)
  return {
    ok = false,
    error = error_code,
    detail = detail,
  }
end

local function http_post(path, body)
  if not ok_http or not ok_ltn12 then
    return fail("http_client_missing", "LuaSocket not available")
  end

  local payload = json_util.encode(body or {})
  local response_chunks = {}
  http.TIMEOUT = config.http_timeout_seconds

  local _, code, _, status = http.request({
    url = path,
    method = "POST",
    source = ltn12.source.string(payload),
    sink = ltn12.sink.table(response_chunks),
    headers = {
      ["Content-Type"] = "application/json",
      ["Content-Length"] = tostring(#payload),
    },
  })

  if tonumber(code) == nil or tonumber(code) >= 400 then
    return fail("http_post_failed", status or tostring(code))
  end

  local raw = table.concat(response_chunks)
  local decoded = json_util.decode(raw)
  if decoded == nil then
    log("json decode failed (POST), raw=" .. tostring(raw))
  end
  return {
    ok = true,
    status_code = tonumber(code),
    raw = raw,
    data = decoded,
  }
end

local function http_get(path)
  if not ok_http or not ok_ltn12 then
    return fail("http_client_missing", "LuaSocket not available")
  end

  local response_chunks = {}
  http.TIMEOUT = config.http_timeout_seconds
  local _, code, _, status = http.request({
    url = path,
    method = "GET",
    sink = ltn12.sink.table(response_chunks),
  })
  if tonumber(code) == nil or tonumber(code) >= 400 then
    return fail("http_get_failed", status or tostring(code))
  end

  local raw = table.concat(response_chunks)
  local decoded = json_util.decode(raw)
  if decoded == nil then
    log("json decode failed (GET), raw=" .. tostring(raw))
  end
  return {
    ok = true,
    status_code = tonumber(code),
    raw = raw,
    data = decoded,
  }
end

function M.heartbeat()
  return http_post(config.bridge_base_url .. "/bridge/mod/heartbeat", {})
end

function M.push_snapshot(snapshot)
  return http_post(config.bridge_base_url .. "/bridge/mod/snapshot", { snapshot = snapshot })
end

function M.push_event(event_type, payload)
  return http_post(config.bridge_base_url .. "/bridge/mod/event", {
    event_type = event_type,
    payload = payload or {},
  })
end

function M.poll_next_command()
  local response = http_get(config.bridge_base_url .. "/bridge/mod/next_command_lua")
  if not response.ok then
    return nil, response
  end
  local chunk, load_err = load(response.raw)
  if chunk == nil then
    return nil, fail("lua_decode_failed", load_err)
  end
  local ok, decoded = pcall(chunk)
  if not ok or type(decoded) ~= "table" then
    return nil, fail("lua_decode_failed", decoded)
  end
  return decoded.command, nil
end

function M.push_command_result(command_id, result)
  return http_post(config.bridge_base_url .. "/bridge/mod/command_result", {
    command_id = command_id,
    result = result,
  })
end

return M
