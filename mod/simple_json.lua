local M = {}

local function decode_error(pos, msg)
  error("json decode error at " .. tostring(pos) .. ": " .. tostring(msg))
end

local function skip_ws(s, i)
  while true do
    local c = s:sub(i, i)
    if c == " " or c == "\n" or c == "\r" or c == "\t" then
      i = i + 1
    else
      return i
    end
  end
end

local parse_value

local function parse_string(s, i)
  i = i + 1
  local out = {}
  while i <= #s do
    local c = s:sub(i, i)
    if c == '"' then
      return table.concat(out), i + 1
    end
    if c == "\\" then
      local esc = s:sub(i + 1, i + 1)
      if esc == '"' or esc == "\\" or esc == "/" then
        out[#out + 1] = esc
        i = i + 2
      elseif esc == "b" then
        out[#out + 1] = "\b"
        i = i + 2
      elseif esc == "f" then
        out[#out + 1] = "\f"
        i = i + 2
      elseif esc == "n" then
        out[#out + 1] = "\n"
        i = i + 2
      elseif esc == "r" then
        out[#out + 1] = "\r"
        i = i + 2
      elseif esc == "t" then
        out[#out + 1] = "\t"
        i = i + 2
      elseif esc == "u" then
        local hex = s:sub(i + 2, i + 5)
        if #hex < 4 or not hex:match("^[0-9a-fA-F]+$") then
          decode_error(i, "invalid unicode escape")
        end
        local code = tonumber(hex, 16)
        if code < 128 then
          out[#out + 1] = string.char(code)
        elseif code < 2048 then
          out[#out + 1] = string.char(192 + math.floor(code / 64), 128 + (code % 64))
        else
          out[#out + 1] = string.char(224 + math.floor(code / 4096), 128 + (math.floor(code / 64) % 64), 128 + (code % 64))
        end
        i = i + 6
      else
        decode_error(i, "invalid escape")
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  decode_error(i, "unterminated string")
end

local function parse_number(s, i)
  local j = i
  while j <= #s and s:sub(j, j):match("[0-9+\-eE\.]") do
    j = j + 1
  end
  local n = tonumber(s:sub(i, j - 1))
  if n == nil then
    decode_error(i, "invalid number")
  end
  return n, j
end

local function parse_array(s, i)
  i = i + 1
  local arr = {}
  i = skip_ws(s, i)
  if s:sub(i, i) == "]" then
    return arr, i + 1
  end
  while true do
    local v
    v, i = parse_value(s, i)
    arr[#arr + 1] = v
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == "]" then
      return arr, i + 1
    end
    if c ~= "," then
      decode_error(i, "expected ',' or ']' in array")
    end
    i = skip_ws(s, i + 1)
  end
end

local function parse_object(s, i)
  i = i + 1
  local obj = {}
  i = skip_ws(s, i)
  if s:sub(i, i) == "}" then
    return obj, i + 1
  end
  while true do
    if s:sub(i, i) ~= '"' then
      decode_error(i, "expected string key")
    end
    local k
    k, i = parse_string(s, i)
    i = skip_ws(s, i)
    if s:sub(i, i) ~= ":" then
      decode_error(i, "expected ':' after key")
    end
    i = skip_ws(s, i + 1)
    local v
    v, i = parse_value(s, i)
    obj[k] = v
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == "}" then
      return obj, i + 1
    end
    if c ~= "," then
      decode_error(i, "expected ',' or '}' in object")
    end
    i = skip_ws(s, i + 1)
  end
end

parse_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == '"' then
    return parse_string(s, i)
  end
  if c == "{" then
    return parse_object(s, i)
  end
  if c == "[" then
    return parse_array(s, i)
  end
  if c == "-" or c:match("%d") then
    return parse_number(s, i)
  end
  if s:sub(i, i + 3) == "true" then
    return true, i + 4
  end
  if s:sub(i, i + 4) == "false" then
    return false, i + 5
  end
  if s:sub(i, i + 3) == "null" then
    return nil, i + 4
  end
  decode_error(i, "unexpected token")
end

function M.decode(raw)
  if raw == nil or raw == "" then
    return nil
  end
  local ok, value, idx = pcall(parse_value, raw, 1)
  if not ok then
    return nil
  end
  idx = skip_ws(raw, idx)
  if idx <= #raw then
    return nil
  end
  return value
end

return M
