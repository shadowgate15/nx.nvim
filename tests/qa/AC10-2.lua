-- AC10-2: outside workspace -> notify WARN, picker not called
local pickers_count = 0
local notify_calls = {}

local ws = require('nx.workspace')
local orig_root = ws.root
ws.root = function() return nil end

local orig_notify = vim.notify
vim.notify = function(msg, level) table.insert(notify_calls, { msg = msg, level = level }) end

local pickers = require('nx.pickers')
local orig_projects = pickers.projects
pickers.projects = function() pickers_count = pickers_count + 1 end

local commands = require('nx.commands')
commands.nx_project()

ws.root = orig_root
vim.notify = orig_notify
pickers.projects = orig_projects

local warned = false
for _, n in ipairs(notify_calls) do
  if n.level == vim.log.levels.WARN and n.msg:find('Not in an Nx workspace') then warned = true end
end

local ok = pickers_count == 0 and warned
local line = ok and 'PASS: AC10-2'
  or ('FAIL: AC10-2 :: pickers_count=' .. pickers_count .. ' warned=' .. tostring(warned) .. ' notify=' .. vim.inspect(notify_calls))
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC10-2.txt')
vim.cmd('qa!')
