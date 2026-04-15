local M = {}
local bridge_client = require("bmcp.bridge_client")
local state_cache = require("bmcp.state_cache")
local config = require("bmcp.config")

function M.emit(event_type, payload)
  local body = payload or {}
  state_cache.record_event(event_type, body)
  if not config.enable_bridge_client then
    return { ok = true, local_only = true }
  end
  return bridge_client.push_event(event_type, body)
end

return M
