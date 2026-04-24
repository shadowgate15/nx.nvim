---@mod nx.workspace Workspace root detection

local M = {}

-- Per-cwd memo: { [cwd_string] = root_string|false }
-- false means "checked, no workspace found"
local _memo = {}

--- Walk up from start_dir to find nx.json, return containing dir.
--- @param start_dir? string defaults to vim.uv.cwd()
--- @return string|nil absolute path to workspace root, or nil
function M.find_root(start_dir)
  start_dir = start_dir or vim.uv.cwd()
  local results = vim.fs.find('nx.json', { upward = true, path = start_dir, type = 'file' })
  if not results or #results == 0 then
    return nil
  end
  local p = vim.fs.dirname(results[1])
  return vim.fs.normalize(vim.fn.fnamemodify(p, ':p'))
end

--- Return workspace root, honoring $NX_WORKSPACE_ROOT_PATH env var first.
--- Memoized per cwd.
--- @return string|nil
function M.root()
  local env_key = 'NX_WORKSPACE_ROOT_PATH'
  -- Try to read from config if available (non-fatal if setup() not called yet)
  local ok, conf = pcall(require, 'nx.config')
  if ok and conf.cli and conf.cli.workspace_root_env then
    env_key = conf.cli.workspace_root_env
  end

  local env_val = vim.env[env_key]
  if env_val and env_val ~= '' then
    -- Validate: nx.json must exist there
    if vim.fn.filereadable(env_val .. '/nx.json') == 1 then
      return vim.fs.normalize(vim.fn.fnamemodify(env_val, ':p'))
    else
      -- Warn once per session (use a flag)
      if not M._env_warned then
        M._env_warned = true
        vim.notify(
          string.format('nx.nvim: $%s=%s does not contain nx.json, falling back to cwd walk-up.', env_key, env_val),
          vim.log.levels.WARN
        )
      end
    end
  end

  local cwd = vim.uv.cwd() or ''
  if _memo[cwd] ~= nil then
    return _memo[cwd] or nil
  end

  local found = M.find_root(cwd)
  _memo[cwd] = found or false
  return found
end

--- Clear the per-cwd memo (call after workspace changes).
function M.invalidate()
  _memo = {}
  M._env_warned = nil
end

return M
