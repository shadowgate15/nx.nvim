---@class nx.NxJestTarget : nx.NxTarget

---@class nx.neotest.JestExecutor : nx.neotest.Executor
---@field opts nx.NxJestTarget
local M = { name = 'jest' }

---@param opts nx.NxJestTarget
function M:new(opts)
  opts = opts or {}

  local newinstance = { opts = opts }

  setmetatable(newinstance, self)

  self.__index = self

  return newinstance --[[@as nx.neotest.Executor]]
end

-- Check if the given path is a test file
---@param file_path string
---@return boolean
function M:is_test_file(file_path) end

return M
