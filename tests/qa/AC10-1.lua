-- AC10-1: :NxProject chains through project picker -> task picker -> terminal.run
local pickers_projects_args = nil
local pickers_tasks_args = nil
local terminal_run_args = nil

-- Stub workspace.root
local ws = require('nx.workspace')
local orig_root = ws.root
ws.root = function() return '/ws' end

-- Stub pickers
local pickers = require('nx.pickers')
local orig_projects = pickers.projects
local orig_tasks = pickers.tasks
pickers.projects = function(root, on_select)
  pickers_projects_args = { root = root }
  on_select('alpha')  -- immediately select 'alpha'
end
pickers.tasks = function(root, project, on_select)
  pickers_tasks_args = { root = root, project = project }
  on_select('build')  -- immediately select 'build'
end

-- Stub terminal.run
local terminal = require('nx.terminal')
local orig_run = terminal.run
terminal.run = function(root, project, task)
  terminal_run_args = { root = root, project = project, task = task }
end

local commands = require('nx.commands')
commands.nx_project()

-- Restore stubs
ws.root = orig_root
pickers.projects = orig_projects
pickers.tasks = orig_tasks
terminal.run = orig_run

-- Small defer for any vim.schedule calls
vim.defer_fn(function()
  local ok = pickers_projects_args ~= nil
    and pickers_projects_args.root == '/ws'
    and pickers_tasks_args ~= nil
    and pickers_tasks_args.root == '/ws'
    and pickers_tasks_args.project == 'alpha'
    and terminal_run_args ~= nil
    and terminal_run_args.root == '/ws'
    and terminal_run_args.project == 'alpha'
    and terminal_run_args.task == 'build'

  local line = ok and 'PASS: AC10-1'
    or ('FAIL: AC10-1 :: projects=' .. vim.inspect(pickers_projects_args)
        .. ' tasks=' .. vim.inspect(pickers_tasks_args)
        .. ' terminal=' .. vim.inspect(terminal_run_args))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC10-1.txt')
  vim.cmd('qa!')
end, 100)
