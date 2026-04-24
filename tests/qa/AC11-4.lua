-- AC11-4: :NxTask foreground (no arg, 1 entry) directly foregrounds
local ws = require('nx.workspace')
ws.root = function() return '/ws' end

local registry = require('nx.registry')
local orig_list = registry.list
registry.list = function()
  return { { workspace_root = '/ws', project = 'alpha', task = 'build', status = 'running', exit_code = nil, started_at = 1 } }
end

local terminal = require('nx.terminal')
local orig_fg = terminal.foreground
local fg_calls = 0
terminal.foreground = function(root, project, task) fg_calls = fg_calls + 1 end

local commands = require('nx.commands')
commands.nx_task({ fargs = { 'foreground' } })

ws.root = require('nx.workspace').find_root
registry.list = orig_list
terminal.foreground = orig_fg

local ok = fg_calls == 1
local line = ok and 'PASS: AC11-4' or ('FAIL: AC11-4 :: fg_calls=' .. fg_calls)
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC11-4.txt')
vim.cmd('qa!')
