-- https://jestjs.io/docs/29.6/configuration#testmatch-arraystring
local _default_test_file_globs = { '**/__tests__/**/*.[jt]s?(x)', '**/?(*.)+(spec|test).[jt]s?(x)' }
local default_test_file_globs = {}

for _, glob in ipairs(_default_test_file_globs) do
  default_test_file_globs[#default_test_file_globs + 1] = vim.fn.glob2regpat(glob)
end

print(vim.inspect(default_test_file_globs))

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
function M:is_test_file(file_path)
  for _, glob in ipairs(default_test_file_globs) do
    if file_path:match(glob) then
      print(file_path, 'matches', glob)
    end
  end

  return false
end

return M
