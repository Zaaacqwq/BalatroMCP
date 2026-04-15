local M = {}

local ok_cjson, cjson = pcall(require, "cjson")
local ok_dkjson, dkjson = pcall(require, "dkjson")
local ok_simple_json, simple_json = pcall(require, "bmcp.simple_json")

local function load_simple_json_if_needed()
  if ok_simple_json and type(simple_json) == "table" and type(simple_json.decode) == "function" then
    return true
  end
  local ok, mod = pcall(require, "bmcp.simple_json")
  if ok and type(mod) == "table" and type(mod.decode) == "function" then
    ok_simple_json = true
    simple_json = mod
    return true
  end
  return false
end

local function fallback_encode(v)
  local t = type(v)
  if t == "nil" then
    return "null"
  end
  if t == "number" or t == "boolean" then
    return tostring(v)
  end
  if t == "string" then
    return string.format("%q", v)
  end
  if t == "table" then
    local is_array = (#v > 0)
    local out = {}
    if is_array then
      for i = 1, #v do
        out[#out + 1] = fallback_encode(v[i])
      end
      return "[" .. table.concat(out, ",") .. "]"
    end
    for k, val in pairs(v) do
      out[#out + 1] = string.format("%q:%s", tostring(k), fallback_encode(val))
    end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return "null"
end

function M.encode(obj)
  if ok_cjson then
    return cjson.encode(obj)
  end
  if ok_dkjson then
    return dkjson.encode(obj)
  end
  return fallback_encode(obj)
end

function M.decode(raw)
  if raw == nil or raw == "" then
    return nil
  end
  if ok_cjson then
    local ok, data = pcall(cjson.decode, raw)
    if ok then
      return data
    end
    return nil
  end
  if ok_dkjson then
    local data, _, err = dkjson.decode(raw, 1, nil)
    if err == nil then
      return data
    end
    return nil
  end
  if load_simple_json_if_needed() then
    return simple_json.decode(raw)
  end
  return nil
end

return M
