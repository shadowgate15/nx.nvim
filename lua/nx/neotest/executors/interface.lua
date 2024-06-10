---@meta

local Executor = {}

---@class nx.neotest.Executor
---@field name string
Executor = {}

---@generic T : nx.NxTarget
---@param opts T
---@return nx.neotest.Executor
function Executor:new(opts) end

-- Check if the given path is a test file
---@param file_path string
---@return boolean
function Executor:is_test_file(file_path) end

return Executor
