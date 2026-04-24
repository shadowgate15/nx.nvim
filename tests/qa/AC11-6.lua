-- AC11-6: :NxTask completion returns subcommand names
local commands = require('nx.commands')
commands.register()
commands.register_nxtask()

local completions = vim.fn.getcompletion('NxTask ', 'cmdline')

local has_list = vim.tbl_contains(completions, 'list')
local has_fg = vim.tbl_contains(completions, 'foreground')
local has_kill = vim.tbl_contains(completions, 'kill')

local ok = has_list and has_fg and has_kill
local line = ok and 'PASS: AC11-6'
  or ('FAIL: AC11-6 :: completions=' .. vim.inspect(completions))
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC11-6.txt')
vim.cmd('qa!')
