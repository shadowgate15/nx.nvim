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

  M.register_nxtask()
end

--- Parse a 'project:task' arg string into (project, task).
--- Returns nil, nil if format is invalid.
--- @param arg string
--- @return string|nil, string|nil
function M._parse_key(arg)
  if not arg then return nil, nil end
  local colon = arg:find(':', 1, true)
  if not colon then return nil, nil end
  local project = arg:sub(1, colon - 1)
  local task = arg:sub(colon + 1)
  if project == '' or task == '' then return nil, nil end
  return project, task
end

--- Open a fzf-lua picker of all backgrounded/exited tasks for this workspace.
--- Default action foregrounds, ctrl-x kills.
function M.nx_task_list()
  M._with_workspace(function(root)
    local registry = require('nx.registry')
    local entries = registry.list(root)

    if #entries == 0 then
      vim.notify('nx.nvim: No tasks for this workspace.', vim.log.levels.INFO)
      return
    end

    local ok, fzf = pcall(require, 'fzf-lua')
    if not ok then
      vim.notify('nx.nvim: fzf-lua is required (ibhagwan/fzf-lua).', vim.log.levels.ERROR)
      return
    end

    local display_list = {}
    local display_to_entry = {}
    for _, e in ipairs(entries) do
      local status_str = e.status
      if e.exit_code ~= nil then
        status_str = status_str .. ' code=' .. e.exit_code
      end
      local disp = string.format('%s:%s [%s]', e.project, e.task, status_str)
      table.insert(display_list, disp)
      display_to_entry[disp] = e
    end

    fzf.fzf_exec(display_list, {
      prompt = 'Nx Tasks> ',
      actions = {
        ['default'] = function(selected, opts)
          local actions_ok, fzf_actions = pcall(require, 'fzf-lua.actions')
          local disp
          if actions_ok then
            local _, entries_sel = fzf_actions.normalize_selected(selected, opts)
            disp = entries_sel and entries_sel[1]
          else
            disp = selected and selected[1]
          end
          local e = disp and display_to_entry[disp]
          if e then
            vim.schedule(function()
              require('nx.terminal').foreground(e.workspace_root, e.project, e.task)
            end)
          end
        end,
        ['ctrl-x'] = function(selected, opts)
          local actions_ok, fzf_actions = pcall(require, 'fzf-lua.actions')
          local disp
          if actions_ok then
            local _, entries_sel = fzf_actions.normalize_selected(selected, opts)
            disp = entries_sel and entries_sel[1]
          else
            disp = selected and selected[1]
          end
          local e = disp and display_to_entry[disp]
          if e then
            vim.schedule(function()
              require('nx.terminal').kill(e.workspace_root, e.project, e.task)
              M.nx_task_list()
            end)
          end
        end,
      },
    })
  end)
end

--- Foreground a specific task by 'project:task' arg, or pick from registry.
--- @param arg? string 'project:task' format
function M.nx_task_foreground(arg)
  M._with_workspace(function(root)
    if arg then
      local project, task = M._parse_key(arg)
      if not project then
        vim.notify(
          'nx.nvim: Invalid argument "' .. arg .. '". Expected format: project:task',
          vim.log.levels.ERROR
        )
        return
      end
      require('nx.terminal').foreground(root, project, task)
      return
    end

    local entries = require('nx.registry').list(root)
    if #entries == 0 then
      vim.notify('nx.nvim: No tasks to foreground.', vim.log.levels.INFO)
    elseif #entries == 1 then
      local e = entries[1]
      require('nx.terminal').foreground(root, e.project, e.task)
    else
      M.nx_task_list()
    end
  end)
end

--- Kill a specific task by 'project:task' arg, or pick from registry.
--- @param arg? string 'project:task' format
function M.nx_task_kill(arg)
  M._with_workspace(function(root)
    if arg then
      local project, task = M._parse_key(arg)
      if not project then
        vim.notify(
          'nx.nvim: Invalid argument "' .. arg .. '". Expected format: project:task',
          vim.log.levels.ERROR
        )
        return
      end
      require('nx.terminal').kill(root, project, task)
      return
    end

    local entries = require('nx.registry').list(root)
    if #entries == 0 then
      vim.notify('nx.nvim: No tasks to kill.', vim.log.levels.INFO)
    elseif #entries == 1 then
      local e = entries[1]
      require('nx.terminal').kill(root, e.project, e.task)
    else
      M.nx_task_list()
    end
  end)
end

--- Dispatch :NxTask subcommands.
--- @param args_table table from nvim_create_user_command callback opts
function M.nx_task(args_table)
  local fargs = args_table.fargs or {}
  local sub = fargs[1]

  if not sub or sub == 'list' then
    M.nx_task_list()
  elseif sub == 'foreground' or sub == 'fg' then
    M.nx_task_foreground(fargs[2])
  elseif sub == 'kill' then
    M.nx_task_kill(fargs[2])
  else
    vim.notify('nx.nvim: Unknown :NxTask subcommand: ' .. sub .. '. Use: list, foreground, kill', vim.log.levels.ERROR)
  end
end

--- Register the :NxTask user command. Called from register().
--- NOTE: This extends the existing register() function — call it after register() in setup().
function M.register_nxtask()
  vim.api.nvim_create_user_command('NxTask', function(opts)
    M.nx_task(opts)
  end, {
    nargs = '*',
    complete = function(arg_lead, cmdline, _)
      local parts = vim.split(cmdline, '%s+')
      if #parts <= 2 then
        return vim.tbl_filter(function(s)
          return s:find(arg_lead, 1, true) == 1
        end, { 'list', 'foreground', 'kill' })
      end
      return {}
    end,
    desc = 'Manage backgrounded Nx tasks',
  })
end

return M
