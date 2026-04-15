local mod_dir = os.getenv("APPDATA"):gsub("\\", "/") .. "/Balatro/Mods/balatro_mcp"

print("[balatro-mcp-mod] entry bootstrap v0.1.1")

local function register_module(module_name, file_name)
  package.preload[module_name] = function()
    local chunk, err = loadfile(mod_dir .. "/" .. file_name)
    if not chunk then
      error("[balatro-mcp-mod] loadfile failed for " .. module_name .. ": " .. tostring(err))
    end
    return chunk()
  end
end

register_module("bmcp.main", "main.lua")
register_module("bmcp.adapter", "adapter.lua")
register_module("bmcp.balatro_adapter", "balatro_adapter.lua")
register_module("bmcp.bridge_client", "bridge_client.lua")
register_module("bmcp.state_extractor", "state_extractor.lua")
register_module("bmcp.event_emitter", "event_emitter.lua")
register_module("bmcp.action_executor", "action_executor.lua")
register_module("bmcp.sync_controller", "sync_controller.lua")
register_module("bmcp.default_adapter", "default_adapter.lua")
register_module("bmcp.config", "config.lua")
register_module("bmcp.json_util", "json_util.lua")
register_module("bmcp.simple_json", "simple_json.lua")
register_module("bmcp.state_cache", "state_cache.lua")
register_module("bmcp.http_server", "http_server.lua")

local function safe_require(module_name)
  local ok, result = pcall(require, module_name)
  if not ok then
    print("[balatro-mcp-mod] require failed for " .. module_name .. ": " .. tostring(result))
    return nil
  end
  if type(result) ~= "table" then
    print("[balatro-mcp-mod] invalid module return for " .. module_name .. ": " .. tostring(type(result)))
    return nil
  end
  return result
end

local main = safe_require("bmcp.main")
local adapter = safe_require("bmcp.adapter")
local balatro_adapter = safe_require("bmcp.balatro_adapter")

if not (main and adapter and balatro_adapter) then
  print("[balatro-mcp-mod] disabled due to module load failure")
  return
end

if type(adapter.set) ~= "function" then
  print("[balatro-mcp-mod] disabled: adapter.set missing")
  return
end

if type(main.init) ~= "function" or type(main.tick) ~= "function" then
  print("[balatro-mcp-mod] disabled: main.init/main.tick missing")
  return
end

adapter.set(balatro_adapter)
main.init()

local update_ref = love.update
love.update = function(...)
  local ok, err = pcall(main.tick)
  if not ok then
    -- Keep game loop alive even if bridge tick fails.
    print("[balatro-mcp-mod] tick error: " .. tostring(err))
  end
  return update_ref(...)
end

print("[balatro-mcp-mod] entry loaded")
