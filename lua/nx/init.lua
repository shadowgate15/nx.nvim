---@mod nx

local dependent_plugins = {
  'overseer',
}

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

return M
