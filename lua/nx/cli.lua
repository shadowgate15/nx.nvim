---@mod nx.cli Nx CLI execution

local M = {}

M._bin_cache = {}

--- Resolve the nx binary for a given workspace root.
--- Prefers local node_modules/.bin/nx, falls back to global nx on PATH.
--- @param workspace_root string
--- @return string|nil
function M.resolve_bin(workspace_root)
  if M._bin_cache[workspace_root] ~= nil then
    return M._bin_cache[workspace_root] or nil
  end

  local local_bin = workspace_root .. '/node_modules/.bin/nx'
  if vim.fn.executable(local_bin) == 1 then
    M._bin_cache[workspace_root] = local_bin
    return local_bin
  end

  local global_bin = vim.fn.exepath('nx')
  if global_bin and global_bin ~= '' then
    M._bin_cache[workspace_root] = global_bin
    return global_bin
  end

  M._bin_cache[workspace_root] = false
  return nil
end

--- Clear the bin resolution cache (call on workspace change).
function M.clear_bin_cache()
  M._bin_cache = {}
end

--- Execute an nx CLI command asynchronously.
--- @param args string[] CLI arguments (without 'nx' prefix)
--- @param opts { cwd: string, on_done: fun(result: {code: integer, stdout: string, stderr: string}) }
function M.exec(args, opts)
  local ok, conf = pcall(require, 'nx.config')
  local timeout_ms = (ok and conf.cli and conf.cli.timeout_ms) or 30000
  local extra_env = (ok and conf.cli and conf.cli.env) or {}

  local bin = M.resolve_bin(opts.cwd)
  if not bin then
    vim.schedule(function()
      opts.on_done({
        code = -1,
        stdout = '',
        stderr = 'nx CLI not found (looked in node_modules/.bin and PATH)',
      })
    end)
    return
  end

  local argv = { bin }
  vim.list_extend(argv, args)

  local env = vim.tbl_extend('force', vim.fn.environ(), extra_env)

  vim.system(argv, {
    cwd = opts.cwd,
    text = true,
    env = env,
    timeout = timeout_ms,
  }, vim.schedule_wrap(function(obj)
    opts.on_done({
      code = obj.code,
      stdout = obj.stdout or '',
      stderr = obj.stderr or '',
    })
  end))
end

--- Fetch all project names for a workspace.
--- @param workspace_root string
--- @param on_done fun(result: {ok: boolean, projects?: string[], error?: string})
function M.show_projects(workspace_root, on_done)
  M.exec({ 'show', 'projects', '--json' }, {
    cwd = workspace_root,
    on_done = function(result)
      if result.code ~= 0 then
        on_done({ ok = false, error = result.stderr ~= '' and result.stderr or ('nx exited with code ' .. result.code) })
        return
      end
      local ok, parsed = pcall(vim.json.decode, result.stdout, { luanil = { object = true, array = true } })
      if not ok or type(parsed) ~= 'table' then
        on_done({ ok = false, error = 'failed to parse nx JSON output: ' .. tostring(parsed) })
        return
      end
      on_done({ ok = true, projects = parsed })
    end,
  })
end

--- Fetch project names of a single Nx project type ('app' | 'lib' | 'e2e').
--- Wraps `nx show projects --type=<type> --json`. Failure is non-fatal: an
--- empty list is returned when nx exits non-zero or emits non-array JSON
--- (older nx versions / workspaces with no projects of that type).
--- @param workspace_root string
--- @param kind 'app'|'lib'|'e2e'
--- @param on_done fun(result: {ok: boolean, projects?: string[], error?: string})
function M.show_projects_by_type(workspace_root, kind, on_done)
  M.exec({ 'show', 'projects', '--type=' .. kind, '--json' }, {
    cwd = workspace_root,
    on_done = function(result)
      if result.code ~= 0 then
        -- Treat as empty rather than fatal: a workspace with no apps (or an
        -- nx version that doesn't recognize --type) shouldn't break the picker.
        on_done({ ok = true, projects = {} })
        return
      end
      local ok, parsed = pcall(vim.json.decode, result.stdout, { luanil = { object = true, array = true } })
      if not ok or type(parsed) ~= 'table' then
        on_done({ ok = true, projects = {} })
        return
      end
      on_done({ ok = true, projects = parsed })
    end,
  })
end

--- Fetch a single project's configuration.
--- @param workspace_root string
--- @param name string project name
--- @param on_done fun(result: {ok: boolean, project?: table, error?: string})
function M.show_project(workspace_root, name, on_done)
  M.exec({ 'show', 'project', name, '--json' }, {
    cwd = workspace_root,
    on_done = function(result)
      if result.code ~= 0 then
        on_done({ ok = false, error = result.stderr ~= '' and result.stderr or ('nx exited with code ' .. result.code) })
        return
      end
      local ok, parsed = pcall(vim.json.decode, result.stdout, { luanil = { object = true, array = true } })
      if not ok or type(parsed) ~= 'table' then
        on_done({ ok = false, error = 'failed to parse nx JSON output: ' .. tostring(parsed) })
        return
      end
      on_done({ ok = true, project = parsed })
    end,
  })
end

return M
