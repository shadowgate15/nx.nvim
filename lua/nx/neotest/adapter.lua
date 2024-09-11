---@module 'neotest'

local config = require('nx.config')
local executors = require('nx.neotest.executors')
local workspace = require('nx.workspace')

---@class (exact) nx.NeotestConfig
---@field filter_dir? fun(name: string, rel_path: string, root: string): boolean Filter directories when searching for test files
---@field test_target_name? string|fun(project_name: string): string Name of the test target to run. defaults to `'test'`

---@param project_name string
---@return string
local function get_test_target_name(project_name)
  local test_target_name = config.neotest.test_target_name

  if test_target_name then
    if type(test_target_name) == 'function' then
      return test_target_name(project_name)
    end

    return test_target_name
  end

  return 'test'
end

---@type neotest.Adapter
local M = { name = 'nx' }

---Find the project root directory given a current directory to work from.
---Should no root be found, the adapter can still be used in a non-project context if a test file matches.
function M.root(dir)
  local w = workspace.try_workspace()

  if w then
    return w.path
  end
end

---Filter directories when searching for test files
---@async
---@param name string Name of directory
---@param rel_path string Path to directory, relative to root
---@param root string Root directory of project
---@return boolean
function M.filter_dir(name, rel_path, root)
  if config.filter_dir then
    return config.filter_dir(name, rel_path, root)
  end

  return name ~= 'node_modules' and name ~= '.git' and name ~= 'dist'
end

---@async
---@param file_path? string
---@return boolean
function M.is_test_file(file_path)
  if not file_path then
    return false
  end

  local w = workspace.try_workspace()

  if not w then
    return false
  end

  print('[nx/is_test_file] Checking if file is test file:', file_path)

  local project = workspace.project_from_path(file_path)

  if not project then
    -- We don't know what project this file belongs to
    return false
  end

  local target_name = get_test_target_name(project.name)
  local target = project.targets[target_name]

  if not target then
    return false
  end

  local executor = executors.get_executor(target.executor, target)

  if not executor then
    return false
  end

  return executor:is_test_file(file_path)
end

---Given a file path, parse all the tests within it.
---@async
---@param file_path string Absolute file path
---@return neotest.Tree | nil
function M.discover_positions(file_path) end

---@param args neotest.RunArgs
---@return nil | neotest.RunSpec | neotest.RunSpec[]
function M.build_spec(args) end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function M.results(spec, result, tree)
  return {}
end

setmetatable(M, {
  ---@param opts? nx.NeotestConfig
  __call = function(_, opts)
    config.set_neotest_config(opts)

    return M
  end,
})

return M
