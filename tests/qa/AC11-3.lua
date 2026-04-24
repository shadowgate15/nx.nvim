-- AC11-3: :NxTask foreground alpha:build calls terminal.foreground(root, alpha, build)
local ws = require('nx.workspace')
local orig_root = ws.root
ws.root = function() return '/ws' end

local terminal = require('nx.terminal')
local orig_fg = terminal.foreground
local fg_args = nil
terminal.foreground = function(root, project, task) fg_args = { root = root, project = project, task = task } end

local commands = require('nx.commands')
commands.nx_task({ fargs = { 'foreground', 'alpha:build' } })

ws.root = orig_root
terminal.foreground = orig_fg

local ok = fg_args ~= nil
  and fg_args.root == '/ws'
  and fg_args.project == 'alpha'
  and fg_args.task == 'build'

local line = ok and 'PASS: AC11-3' or ('FAIL: AC11-3 :: fg_args=' .. vim.inspect(fg_args))
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC11-3.txt')
vim.cmd('qa!')
