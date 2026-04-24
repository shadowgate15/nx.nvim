-- AC11-5: :NxTask kill no-colon-here -> ERROR notify
local ws = require('nx.workspace')
ws.root = function() return '/ws' end

local terminal = require('nx.terminal')
local orig_kill = terminal.kill
local kill_calls = 0
terminal.kill = function() kill_calls = kill_calls + 1 end

local notify_calls = {}
local orig_notify = vim.notify
vim.notify = function(msg, level) table.insert(notify_calls, { msg = msg, level = level }) end

local commands = require('nx.commands')
commands.nx_task({ fargs = { 'kill', 'no-colon-here' } })

ws.root = require('nx.workspace').find_root
terminal.kill = orig_kill
vim.notify = orig_notify

local errored = false
for _, n in ipairs(notify_calls) do
  if n.level == vim.log.levels.ERROR and n.msg:find('project:task') then errored = true end
end

local ok = kill_calls == 0 and errored
local line = ok and 'PASS: AC11-5'
  or ('FAIL: AC11-5 :: kill_calls=' .. kill_calls .. ' errored=' .. tostring(errored) .. ' notify=' .. vim.inspect(notify_calls))
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC11-5.txt')
vim.cmd('qa!')
