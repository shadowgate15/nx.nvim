---@mod nx.commands User commands for nx.nvim

local M = {}

--- Resolve workspace root and call fn(root), or notify WARN and return.
--- @param fn fun(root: string)
function M._with_workspace(fn)
  local root = require('nx.workspace').root()
  if not root then
    vim.notify('nx.nvim: Not in an Nx workspace. Ensure nx.json exists or set $NX_WORKSPACE_ROOT_PATH.', vim.log.levels.WARN)
    return
  end
  fn(root)
end

--- Open the Nx project picker.
--- On selection, opens the task picker for that project.
function M.nx_project()
  M._with_workspace(function(root)
    require('nx.pickers').projects(root, function(project_name)
      M.nx_project_tasks(project_name)
    end)
  end)
end

--- Open the Nx task picker for a specific project, or open the project picker first.
--- @param project_name? string if nil, opens project picker first
function M.nx_project_tasks(project_name)
  if not project_name then
    M.nx_project()
    return
  end
  M._with_workspace(function(root)
    require('nx.pickers').tasks(root, project_name, function(task_name)
      require('nx.terminal').run(root, project_name, task_name)
    end)
  end)
end

--- Clear cached projects/tasks for the current workspace.
function M.nx_refresh()
  M._with_workspace(function(root)
    require('nx.cache').invalidate(root)
    vim.notify('nx.nvim: Cache cleared for ' .. root, vim.log.levels.INFO)
  end)
end

--- Register user commands. Called from setup().
--- NOTE: :NxTask is registered by M.register_nxtask() called from Task 11.
function M.register()
  vim.api.nvim_create_user_command('NxProject', function()
    M.nx_project()
  end, { desc = 'Pick an Nx project' })

  vim.api.nvim_create_user_command('NxProjectTasks', function(opts)
    local project = opts.fargs and opts.fargs[1]
    M.nx_project_tasks(project)
  end, { nargs = '?', desc = 'Pick a task for an Nx project' })

  vim.api.nvim_create_user_command('NxRefresh', function()
    M.nx_refresh()
  end, { desc = 'Clear Nx project cache' })
end

return M
