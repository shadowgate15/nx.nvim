---@mod nx.cache Per-workspace project/task cache with in-flight dedup

local M = {}

-- Cache table: { [ws_root] = { projects=string[]|nil, project_configs={[name]=table}, fetched_at=number } }
local _cache = {}

-- In-flight table: { [flight_key] = { callbacks = { fn, ... } } }
-- flight_key = 'projects::' .. ws_root  OR  'project::' .. ws_root .. '::' .. name
local _inflight = {}

local function _flight_key_projects(ws_root)
  return 'projects::' .. ws_root
end

local function _flight_key_project(ws_root, name)
  return 'project::' .. ws_root .. '::' .. name
end

local function _ensure_root(ws_root)
  if not _cache[ws_root] then
    _cache[ws_root] = { projects = nil, project_configs = {}, fetched_at = 0 }
  end
end

--- Fetch all projects for a workspace, using cache and in-flight dedup.
--- @param workspace_root string
--- @param on_done fun(result: {ok: boolean, projects?: string[], error?: string})
function M.get_projects(workspace_root, on_done)
  _ensure_root(workspace_root)

  -- Cache hit
  if _cache[workspace_root].projects ~= nil then
    vim.schedule(function()
      on_done({ ok = true, projects = _cache[workspace_root].projects })
    end)
    return
  end

  local key = _flight_key_projects(workspace_root)

  -- In-flight: queue this callback
  if _inflight[key] then
    table.insert(_inflight[key].callbacks, on_done)
    return
  end

  -- Start new request
  _inflight[key] = { callbacks = { on_done } }

  local cli = require('nx.cli')
  cli.show_projects(workspace_root, function(result)
    local cbs = _inflight[key] and _inflight[key].callbacks or {}
    _inflight[key] = nil

    if result.ok then
      _ensure_root(workspace_root)
      _cache[workspace_root].projects = result.projects
      _cache[workspace_root].fetched_at = vim.uv.now()
    end

    for _, cb in ipairs(cbs) do
      cb(result)
    end
  end)
end

--- Fetch a single project's config, using cache and in-flight dedup.
--- @param workspace_root string
--- @param name string project name
--- @param on_done fun(result: {ok: boolean, project?: table, error?: string})
function M.get_project(workspace_root, name, on_done)
  _ensure_root(workspace_root)

  -- Cache hit
  if _cache[workspace_root].project_configs[name] ~= nil then
    vim.schedule(function()
      on_done({ ok = true, project = _cache[workspace_root].project_configs[name] })
    end)
    return
  end

  local key = _flight_key_project(workspace_root, name)

  -- In-flight: queue
  if _inflight[key] then
    table.insert(_inflight[key].callbacks, on_done)
    return
  end

  _inflight[key] = { callbacks = { on_done } }

  local cli = require('nx.cli')
  cli.show_project(workspace_root, name, function(result)
    local cbs = _inflight[key] and _inflight[key].callbacks or {}
    _inflight[key] = nil

    if result.ok then
      _ensure_root(workspace_root)
      _cache[workspace_root].project_configs[name] = result.project
    end

    for _, cb in ipairs(cbs) do
      cb(result)
    end
  end)
end

--- Invalidate cache for a workspace root, or all roots if nil.
--- @param workspace_root? string
function M.invalidate(workspace_root)
  if workspace_root then
    _cache[workspace_root] = nil
  else
    _cache = {}
  end
end

--- Test helper: returns a deep copy of the internal cache table.
--- @return table
function M.state()
  return vim.deepcopy(_cache)
end

--- Attach BufWritePost autocmd for auto-invalidation.
--- Call this from setup().
function M.attach_autocmds()
  local ok, conf = pcall(require, 'nx.config')
  local watch_files = (ok and conf.cache and conf.cache.watch_files) or { 'nx.json', 'project.json' }

  -- Build the pattern for the autocmd
  local patterns = {}
  for _, f in ipairs(watch_files) do
    table.insert(patterns, '*/' .. f)
    table.insert(patterns, f)
  end

  local group = vim.api.nvim_create_augroup('nx.cache', { clear = true })

  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    pattern = patterns,
    callback = function(args)
      -- Resolve workspace root from the written file's directory
      local file_dir = vim.fn.fnamemodify(args.file, ':h')
      local ws = require('nx.workspace').find_root(file_dir)
      if ws then
        M.invalidate(ws)
      end
    end,
    desc = 'nx.nvim: invalidate project cache on nx.json/project.json write',
  })
end

return M
