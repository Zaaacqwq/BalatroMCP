local M = {}

local adapter = nil

function M.set(new_adapter)
  adapter = new_adapter
end

function M.get()
  return adapter
end

function M.call(method_name, ...)
  if adapter == nil then
    return nil, "adapter_not_set"
  end
  local fn = adapter[method_name]
  if type(fn) ~= "function" then
    return nil, "adapter_method_missing:" .. tostring(method_name)
  end
  local ok, result = pcall(fn, ...)
  if not ok then
    return nil, "adapter_exception:" .. tostring(result)
  end
  return result, nil
end

return M
