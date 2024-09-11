---@mod nx

local dependent_plugins = {
  'overseer',
}

---@param default_opts? neotest.CoreConfig
local function setup_neotest_project(default_opts)
  if require('nx.workspace').try_workspace() then
    require('neotest').setup_project(
      vim.fn.getcwd(),
      vim.tbl_extend('force', default_opts or {}, {
        adapters = {
          ['nx.neotest'] = {},
        },
      })
    )
  end

  if default_opts then
    require('neotest').setup_project(vim.fn.getcwd(), default_opts)
  end
end

local M = {}

setmetatable(M, {
  __index = function(t, key)
    local ok, val = pcall(require, string.format('nx.%s', key))

    if ok then
      rawset(t, key, val)

      return val
    else
      error(string.format('Error requiring nx.%s: %s', key, val))
    end
  end,
})

---@param opts? nx.Config
function M.setup(opts)
  opts = opts or {}

  local config = require('nx.config')

  config.setup(opts)

  require('nx.commands').setup()

  -- Load dependent plugins if available
  for _, plugin in ipairs(dependent_plugins) do
    local ok, _ = pcall(require, plugin)

    if ok then
      require('nx.' .. plugin).setup()
    end
  end
end

-- Setup neotest to listen for dir changes and setup the project
---@param default_opts? neotest.CoreConfig
function M.setup_neotest(default_opts)
  setup_neotest_project(default_opts)

  vim.api.nvim_create_autocmd('DirChanged', {
    callback = function()
      setup_neotest_project(default_opts)
    end,
    pattern = 'global',
  })
end

return M
