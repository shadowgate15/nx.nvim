---@class (exact) nx.Config

local default_config = {}

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

return M
