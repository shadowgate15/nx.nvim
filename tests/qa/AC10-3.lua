-- AC10-3: nx_refresh() calls cache.invalidate(root) and notifies INFO
local invalidate_args = nil
local notify_calls = {}

local ws = require('nx.workspace')
local orig_root = ws.root
ws.root = function() return '/ws-refresh' end

local cache = require('nx.cache')
local orig_invalidate = cache.invalidate
cache.invalidate = function(root) invalidate_args = root end

local orig_notify = vim.notify
vim.notify = function(msg, level) table.insert(notify_calls, { msg = msg, level = level }) end

local commands = require('nx.commands')
commands.nx_refresh()

ws.root = orig_root
cache.invalidate = orig_invalidate
vim.notify = orig_notify

local notified_info = false
for _, n in ipairs(notify_calls) do
  if n.level == vim.log.levels.INFO then notified_info = true end
end

local ok = invalidate_args == '/ws-refresh' and notified_info
local line = ok and 'PASS: AC10-3'
  or ('FAIL: AC10-3 :: invalidate_args=' .. tostring(invalidate_args) .. ' notified_info=' .. tostring(notified_info))
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC10-3.txt')
vim.cmd('qa!')
