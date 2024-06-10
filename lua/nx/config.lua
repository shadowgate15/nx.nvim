---@class (exact) nx.Config
---@field neotest? nx.NeotestConfig

local default_config = {
  neotest = {},
}

local M = vim.deepcopy(default_config)

---@param opts? nx.Config
function M.setup(opts)
  opts = opts or {}

  -- Extend the default config with the user-provided options
  local newconf = vim.tbl_deep_extend('force', default_config, opts)

  for k, v in pairs(newconf) do
    M[k] = v
  end
end

---@param opts? nx.NeotestConfig
function M.set_neotest_config(opts)
  opts = opts or {}

  M.neotest = vim.tbl_deep_extend('force', M.neotest, opts)
end

return M
