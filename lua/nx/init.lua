---@mod nx

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

  require('nx.config').setup(opts)
  require('nx.commands').register()
  require('nx.cache').attach_autocmds()
  require('nx.registry').attach_self_healing()
end

return M
