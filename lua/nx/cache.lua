local M = {
  cache = {},
}

-- Claer the cache
function M.clear()
  M.cache = {}
end

-- Get a value from the cache
---@generic T
---@param key string
---@return T
function M.get(key)
  return M.cache[key]
end

-- Get all values from the cache for a given pattern
---@generic T
---@param pattern string | number
---@return T
function M.get_match(pattern)
  return vim.tbl_values(vim.tbl_filter(function(key)
    if type(key) ~= 'string' then
      return false
    end

    return key:match(pattern)
  end, M.cache))
end

-- Set a value in the cache
---@param key string
---@param value any
function M.set(key, value)
  M.cache[key] = value
end

return M
