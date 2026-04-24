---@class (exact) nx.Config
---@field cli nx.Config.Cli
---@field cache nx.Config.Cache
---@field runner nx.Config.Runner
---@field pickers nx.Config.Pickers

---@class (exact) nx.Config.Cli
---@field timeout_ms integer
---@field env table<string, string>
---@field workspace_root_env string

---@class (exact) nx.Config.Cache
---@field auto_invalidate boolean
---@field watch_files string[]

---@class (exact) nx.Config.Runner
---@field keymaps table<string, string>
---@field win table

---@class (exact) nx.Config.Pickers
---@field preview boolean

local default_config = {
  cli = {
    timeout_ms = 30000,
    env = {},
    workspace_root_env = 'NX_WORKSPACE_ROOT_PATH',
  },
  cache = {
    auto_invalidate = true,
    watch_files = { 'nx.json', 'project.json' },
  },
  runner = {
    keymaps = {
      background = '<C-b>',
    },
    win = {},
  },
  pickers = {
    preview = true,
  },
}

local M = vim.deepcopy(default_config)

---@return nx.Config
function M.defaults()
  return vim.deepcopy(default_config)
end

---@param opts? nx.Config
function M.setup(opts)
  opts = opts or {}

  -- Extend the default config with the user-provided options
  local newconf = vim.tbl_deep_extend('force', default_config, opts)

  for k, v in pairs(newconf) do
    M[k] = v
  end
end

return M
