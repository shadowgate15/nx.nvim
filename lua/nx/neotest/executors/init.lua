local executors = {
  ['@nx/jest:jest'] = 'jest',
}

local M = {}

-- Get the executor for a target
---@param target_name string
---@param target nx.NxTarget
---@return nx.neotest.Executor?
function M.get_executor(target_name, target)
  local pkg = executors[target_name]

  if pkg then
    ---@type nx.neotest.Executor
    local Executor = require('nx.neotest.executors.' .. pkg)

    return Executor:new(target)
  end

  vim.notify(
    'No executor found for "' .. target_name .. '" target.',
    vim.log.levels.ERROR,
    { title = 'Nx Neotest', icon = require('neotest.config').icons.notify }
  )
end

return M
