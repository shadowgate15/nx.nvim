---@mod nx.health :checkhealth nx implementation

local M = {}

--- Parse Nx version from `nx --version` output.
--- Returns version string like '18.3.0' or nil on failure.
--- @param output string raw output from nx --version
--- @return string|nil
local function _parse_version(output)
  -- Nx outputs versions like:
  --   "Nx                       18.3.0"
  -- or just "18.3.0" on some versions
  local version = output:match('%d+%.%d+%.%d+')
  return version
end

--- Compare version strings. Returns -1, 0, or 1.
--- @param a string version like '18.3.0'
--- @param b string version like '16.3.0'
--- @return integer
local function _version_cmp(a, b)
  local function parts(v)
    local t = {}
    for n in v:gmatch('%d+') do
      table.insert(t, tonumber(n))
    end
    return t
  end
  local pa, pb = parts(a), parts(b)
  for i = 1, math.max(#pa, #pb) do
    local ai = pa[i] or 0
    local bi = pb[i] or 0
    if ai < bi then
      return -1
    end
    if ai > bi then
      return 1
    end
  end
  return 0
end

--- Health check entry point.
--- Called by Neovim when user runs `:checkhealth nx`.
function M.check()
  local health = vim.health

  -- === Workspace ===
  health.start('nx.nvim: Workspace')

  local root = require('nx.workspace').root()
  if root then
    health.ok('Workspace root: ' .. root)
  else
    health.warn(
      'No Nx workspace detected from cwd: '
        .. (vim.uv.cwd() or '?')
        .. '\n  Set $NX_WORKSPACE_ROOT_PATH or open a buffer inside an Nx workspace.'
    )
  end

  -- === CLI ===
  health.start('nx.nvim: CLI')

  if root then
    local bin = require('nx.cli').resolve_bin(root)
    if not bin then
      health.error(
        'Nx CLI not found in node_modules/.bin or $PATH.' .. '\n  Install Nx: npm i -D nx   OR   npm i -g nx'
      )
    else
      health.ok('Nx binary: ' .. bin)

      -- Version check
      local result = vim.system({ bin, '--version' }, { text = true }):wait(5000)
      local version = result and _parse_version((result.stdout or '') .. (result.stderr or ''))
      if version then
        if _version_cmp(version, '18.1.0') >= 0 then
          health.ok('Nx ' .. version)
        elseif _version_cmp(version, '16.3.0') >= 0 then
          health.info('Nx ' .. version .. ' supported; recommend ≥ 18.1 for stable JSON output.')
        else
          health.warn('Nx ' .. version .. ' is below minimum 16.3 (nx show JSON support).')
        end
      else
        health.warn('Could not determine Nx version from output: ' .. tostring(result and result.stdout))
      end
    end
  else
    health.info('Skipping CLI check (no workspace detected).')
  end

  -- === Dependencies ===
  health.start('nx.nvim: Dependencies')

  local fzf_ok = pcall(require, 'fzf-lua')
  if fzf_ok then
    health.ok('fzf-lua is installed.')
  else
    health.error('fzf-lua not installed (ibhagwan/fzf-lua). Required for :NxProject and :NxProjectTasks pickers.')
  end

  local snacks_ok = pcall(require, 'snacks')
  if snacks_ok then
    health.ok('snacks.nvim is installed.')
  else
    health.error('snacks.nvim not installed (folke/snacks.nvim). Required for the task runner float.')
  end

  -- === Configuration ===
  health.start('nx.nvim: Configuration')

  local defaults = require('nx.config').defaults()
  -- Show a compact summary (avoid giant inspect dumps)
  health.info('cli.timeout_ms = ' .. tostring(defaults.cli.timeout_ms))
  health.info('cli.workspace_root_env = ' .. tostring(defaults.cli.workspace_root_env))
  health.info('cache.auto_invalidate = ' .. tostring(defaults.cache.auto_invalidate))
  health.info('cache.watch_files = ' .. vim.inspect(defaults.cache.watch_files))
  health.info('runner.keymaps.background = ' .. tostring(defaults.runner.keymaps.background))
  health.info('pickers.preview = ' .. tostring(defaults.pickers.preview))
end

return M
