-- AC11-1: :NxTask (no args) shows 'No tasks' when registry empty
local ws = require('nx.workspace')
local orig_root = ws.root
ws.root = function() return '/ws' end

local registry = require('nx.registry')
local orig_list = registry.list
registry.list = function() return {} end

local notify_calls = {}
local orig_notify = vim.notify
vim.notify = function(msg, level) table.insert(notify_calls, { msg = msg, level = level }) end

local commands = require('nx.commands')
commands.nx_task({ fargs = {} })

ws.root = orig_root
registry.list = orig_list
vim.notify = orig_notify

local notified_info = false
for _, n in ipairs(notify_calls) do
  if n.level == vim.log.levels.INFO and n.msg:find('No tasks') then notified_info = true end
end

local ok = notified_info
local line = ok and 'PASS: AC11-1' or ('FAIL: AC11-1 :: notify=' .. vim.inspect(notify_calls))
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC11-1.txt')
vim.cmd('qa!')
