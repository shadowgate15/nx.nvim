---@class nx.CommandDef<TArgs, TReturn>
---@field name string
---@field cmd string
---@field args? table
---@field def vim.api.keyset.user_command

---@type nx.CommandDef[]
local commands = {
  {
    name = 'ClearCache',
    cmd = 'clear_cache',
    def = {
      desc = 'Clear the cache',
    },
  },
}

---@class nx.Commands
local M = {}

function M.clear_cache()
  require('nx.cache').clear()
end

function M.setup()
  for _, cmd in ipairs(commands) do
    vim.api.nvim_create_user_command('Nx' .. cmd.name, function()
      return M[cmd.cmd](cmd.args)
    end, cmd.def)
  end
end

return M
