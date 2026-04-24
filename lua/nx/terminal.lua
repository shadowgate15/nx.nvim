---@mod nx.terminal Task runner using Snacks.terminal

local M = {}

--- Run an Nx task in a Snacks terminal float.
--- Re-foregrounds if already running. Starts fresh if exited.
--- @param workspace_root string
--- @param project string
--- @param task string
function M.run(workspace_root, project, task)
  local ok, snacks = pcall(require, 'snacks')
  if not ok then
    vim.notify('nx.nvim: Snacks.nvim is required to run tasks (folke/snacks.nvim).', vim.log.levels.ERROR)
    return
  end

  local registry = require('nx.registry')
  local entry = registry.get(workspace_root, project, task)

  if entry and entry.status == 'running' and entry.terminal and entry.terminal:buf_valid() then
    entry.terminal:show()
    entry.terminal:focus()
    return
  end

  if entry then
    registry.remove(workspace_root, project, task)
  end

  local bin = require('nx.cli').resolve_bin(workspace_root)
  if not bin then
    vim.notify(
      'nx.nvim: Nx CLI not found for workspace: ' .. workspace_root .. '. Check node_modules/.bin/nx or PATH.',
      vim.log.levels.ERROR
    )
    return
  end

  local cmd = { bin, 'run', project .. ':' .. task }

  local conf_ok, conf = pcall(require, 'nx.config')
  local runner_win = (conf_ok and conf.runner and conf.runner.win) or {}
  local bg_keymap = (conf_ok and conf.runner and conf.runner.keymaps and conf.runner.keymaps.background) or '<C-b>'

  local term = snacks.terminal(
    cmd,
    vim.tbl_deep_extend('force', {
      cwd = workspace_root,
      interactive = true,
      auto_close = false,
      win = vim.tbl_deep_extend('force', { position = 'float', style = 'terminal' }, runner_win),
    }, {})
  )

  local bufnr = term.buf
  -- vim.b[bufnr].terminal_job_id is only populated after termopen completes,
  -- so it must be read on the next event-loop tick.
  local job_id = nil
  vim.schedule(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      job_id = vim.b[bufnr].terminal_job_id
      local e = registry.get(workspace_root, project, task)
      if e then
        e.job_id = job_id
      end
    end
  end)

  registry.put(workspace_root, project, task, {
    terminal = term,
    bufnr = bufnr,
    job_id = job_id,
    status = 'running',
    exit_code = nil,
    output_file = nil,
    started_at = vim.uv.now(),
    exited_at = nil,
  })

  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local keymap_opts = { noremap = true, silent = true, buffer = bufnr }
    local bg_fn = function()
      M.background(workspace_root, project, task)
    end
    vim.keymap.set('t', bg_keymap, bg_fn, keymap_opts)
    vim.keymap.set('n', bg_keymap, bg_fn, keymap_opts)

    vim.api.nvim_create_autocmd('TermClose', {
      buffer = bufnr,
      once = true,
      callback = function(_)
        local exit_code = vim.v.event and vim.v.event.status or -1
        M._on_exit(workspace_root, project, task, exit_code)
      end,
      desc = 'nx.nvim: handle task exit for ' .. project .. ':' .. task,
    })
  end
end

--- Background a running task (hide float, keep job alive).
--- @param workspace_root string
--- @param project string
--- @param task string
function M.background(workspace_root, project, task)
  local entry = require('nx.registry').get(workspace_root, project, task)
  if not entry then
    return
  end
  if entry.terminal and entry.terminal:win_valid() then
    entry.terminal:hide()
  end
end

--- Foreground a task: re-show running float, or open exited output in a read-only Snacks float.
--- @param workspace_root string
--- @param project string
--- @param task string
function M.foreground(workspace_root, project, task)
  local registry = require('nx.registry')
  local entry = registry.get(workspace_root, project, task)

  if not entry then
    vim.notify(string.format('nx.nvim: No task %s:%s found in registry.', project, task), vim.log.levels.WARN)
    return
  end

  if entry.status == 'running' then
    if entry.terminal and entry.terminal:buf_valid() then
      entry.terminal:show()
      entry.terminal:focus()
    else
      vim.notify(string.format('nx.nvim: Task %s:%s terminal buffer is gone.', project, task), vim.log.levels.WARN)
    end
    return
  end

  if entry.output_file then
    if vim.fn.filereadable(entry.output_file) == 0 then
      vim.notify(
        string.format('nx.nvim: Output file for %s:%s is no longer readable.', project, task),
        vim.log.levels.ERROR
      )
      registry.remove(workspace_root, project, task)
      return
    end

    local ok, snacks = pcall(require, 'snacks')
    if ok and snacks.win then
      snacks.win.new({ file = entry.output_file, style = 'float' })
    else
      vim.cmd('split ' .. vim.fn.fnameescape(entry.output_file))
      vim.bo.readonly = true
      vim.bo.modifiable = false
    end
  else
    vim.notify(string.format('nx.nvim: No output captured for %s:%s.', project, task), vim.log.levels.WARN)
  end
end

--- Kill a task: stop the job, remove from registry (no output dump on kill).
--- @param workspace_root string
--- @param project string
--- @param task string
function M.kill(workspace_root, project, task)
  local registry = require('nx.registry')
  local entry = registry.get(workspace_root, project, task)

  if not entry then
    vim.notify(string.format('nx.nvim: No task %s:%s found to kill.', project, task), vim.log.levels.WARN)
    return
  end

  if entry.status == 'running' and entry.job_id then
    -- The _killing flag instructs _on_exit (fired by jobstop's TermClose)
    -- to skip the buffer-dump path so killed tasks leave no output file.
    entry._killing = true
    vim.fn.jobstop(entry.job_id)
  end

  registry.remove(workspace_root, project, task)
end

--- Handle task exit: dump buffer to tempfile, update registry, notify user.
--- Called by TermClose autocmd. Should not be called externally (but exposed for testing).
--- @param workspace_root string
--- @param project string
--- @param task string
--- @param exit_code integer
function M._on_exit(workspace_root, project, task, exit_code)
  local registry = require('nx.registry')
  local entry = registry.get(workspace_root, project, task)

  if not entry then
    return
  end

  if entry._killing then
    return
  end

  local lines = {}
  local old_bufnr = entry.bufnr
  if old_bufnr and vim.api.nvim_buf_is_valid(old_bufnr) then
    lines = vim.api.nvim_buf_get_lines(old_bufnr, 0, -1, false)
    while #lines > 0 and lines[#lines]:match('^%s*$') do
      table.remove(lines)
    end
  end

  local tmp = vim.fn.tempname() .. '.nx-task.txt'
  if #lines > 0 then
    vim.fn.writefile(lines, tmp)
  end

  entry.terminal = nil
  entry.bufnr = nil
  entry.job_id = nil
  entry.status = 'exited'
  entry.exit_code = exit_code
  entry.output_file = (#lines > 0) and tmp or nil
  entry.exited_at = vim.uv.now()

  if old_bufnr then
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(old_bufnr) then
        pcall(vim.api.nvim_buf_delete, old_bufnr, { force = true })
      end
    end)
  end

  local level = exit_code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
  local msg = string.format(
    'nx: %s:%s exited (code %d). Use :NxTask foreground %s:%s to view output.',
    project,
    task,
    exit_code,
    project,
    task
  )
  vim.notify(msg, level)
end

return M
