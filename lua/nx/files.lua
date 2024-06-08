local M = {}

---@class FindOptions
---@field dir? string -- Path to search from
---@field children? boolean -- Include children directories

-- Find all the files
---@param files string | string[]
---@param opts? FindOptions
---
---@return string[]
function M.find_all(files, opts)
  opts = opts or {}

  if type(files) == 'string' then
    files = { files }
  end

  local upward = true

  if opts.children == true then
    upward = false
  end

  local matches = vim.fs.find(files, {
    upward = upward,
    type = 'file',
    path = opts.dir or vim.fn.getcwd(),
    stop = vim.fn.getcwd() .. '/..',
    limit = math.huge,
  })

  if #matches > 0 then
    return matches
  end

  return vim.fs.find(files, {
    upward = true,
    type = 'file',
    path = vim.fn.getcwd(),
  })
end

-- Find nearest file
---@param files string | string[]
---@param opts? FindOptions
---
---@return string | nil
function M.find_nearest(files, opts)
  local matches = M.find_all(files, opts)

  if #matches > 0 then
    return matches[1]
  end
end

-- Read JSON file
---@generic T
---@param path string
---@return T
function M.read_json(path)
  local data = vim.fn.join(vim.fn.readfile(path))

  return vim.fn.json_decode(data)
end

return M
