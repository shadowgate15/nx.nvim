---@mod nx.cache Per-workspace project/task cache with in-flight dedup

local M = {}

-- Display order is fixed: apps before libs before e2e. Used for the picker
-- and for the flattened M.get_projects() return value.
local KIND_ORDER = { 'app', 'lib', 'e2e' }

-- Cache table:
-- { [ws_root] = {
--     projects               = string[]|nil,            -- flattened, ordered apps→libs→e2e
--     projects_by_kind       = { app=string[], lib=string[], e2e=string[] }|nil,
--     project_kinds          = { [name]=('app'|'lib'|'e2e') },
--     project_configs        = { [name]=table },
--     fetched_at             = number,
-- } }
local _cache = {}

-- In-flight table: { [flight_key] = { callbacks = { fn, ... } } }
local _inflight = {}

local function _flight_key_projects(ws_root)
  return 'projects::' .. ws_root
end

local function _flight_key_project(ws_root, name)
  return 'project::' .. ws_root .. '::' .. name
end

local function _ensure_root(ws_root)
  if not _cache[ws_root] then
    _cache[ws_root] = {
      projects = nil,
      projects_by_kind = nil,
      project_kinds = {},
      project_configs = {},
      fetched_at = 0,
    }
  end
end

--- Fetch all projects for a workspace, using cache and in-flight dedup.
--- Issues 3 parallel `nx show projects --type=<kind>` calls on cache miss
--- so the picker can label and order projects by Nx's authoritative
--- classification (which includes the implicit `e2e` type).
--- @param workspace_root string
--- @param on_done fun(result: {ok: boolean, projects?: string[], projects_by_kind?: {app: string[], lib: string[], e2e: string[]}, project_kinds?: table<string, string>, error?: string})
function M.get_projects(workspace_root, on_done)
  _ensure_root(workspace_root)

  local entry = _cache[workspace_root]

  if entry.projects ~= nil then
    vim.schedule(function()
      on_done({
        ok = true,
        projects = entry.projects,
        projects_by_kind = entry.projects_by_kind,
        project_kinds = entry.project_kinds,
      })
    end)
    return
  end

  local key = _flight_key_projects(workspace_root)

  if _inflight[key] then
    table.insert(_inflight[key].callbacks, on_done)
    return
  end

  _inflight[key] = { callbacks = { on_done } }

  local cli = require('nx.cli')

  local pending = #KIND_ORDER
  local by_kind = { app = {}, lib = {}, e2e = {} }
  local first_error = nil

  local function finalize()
    local cbs = _inflight[key] and _inflight[key].callbacks or {}
    _inflight[key] = nil

    if first_error then
      for _, cb in ipairs(cbs) do
        cb({ ok = false, error = first_error })
      end
      return
    end

    -- Flatten in display order, dedup names that appear under multiple types
    -- (defensive: nx normally classifies each project under exactly one type).
    local seen = {}
    local flat = {}
    local kinds = {}
    for _, kind in ipairs(KIND_ORDER) do
      for _, name in ipairs(by_kind[kind]) do
        if not seen[name] then
          seen[name] = true
          table.insert(flat, name)
          kinds[name] = kind
        end
      end
    end

    _ensure_root(workspace_root)
    _cache[workspace_root].projects = flat
    _cache[workspace_root].projects_by_kind = by_kind
    _cache[workspace_root].project_kinds = kinds
    _cache[workspace_root].fetched_at = vim.uv.now()

    for _, cb in ipairs(cbs) do
      cb({
        ok = true,
        projects = flat,
        projects_by_kind = by_kind,
        project_kinds = kinds,
      })
    end
  end

  for _, kind in ipairs(KIND_ORDER) do
    cli.show_projects_by_type(workspace_root, kind, function(result)
      if result.ok then
        table.sort(result.projects)
        by_kind[kind] = result.projects
      elseif not first_error then
        first_error = result.error
      end
      pending = pending - 1
      if pending == 0 then
        finalize()
      end
    end)
  end
end

--- Fetch a single project's config, using cache and in-flight dedup.
--- @param workspace_root string
--- @param name string project name
--- @param on_done fun(result: {ok: boolean, project?: table, error?: string})
function M.get_project(workspace_root, name, on_done)
  _ensure_root(workspace_root)

  if _cache[workspace_root].project_configs[name] ~= nil then
    vim.schedule(function()
      on_done({ ok = true, project = _cache[workspace_root].project_configs[name] })
    end)
    return
  end

  local key = _flight_key_project(workspace_root, name)

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
