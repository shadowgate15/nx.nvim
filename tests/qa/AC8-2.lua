package.loaded['fzf-lua'] = nil
package.preload['fzf-lua'] = function() error('not installed') end

local notify_calls = {}
local orig_notify = vim.notify
vim.notify = function(msg, level) table.insert(notify_calls, { msg = msg, level = level }) end

local pickers = require('nx.pickers')
package.loaded['nx.pickers'] = nil
pickers = require('nx.pickers')
pickers.projects('/ws', function() end)

vim.notify = orig_notify

local ok = #notify_calls > 0
  and notify_calls[1].level == vim.log.levels.ERROR
  and notify_calls[1].msg:find('fzf%-lua') ~= nil

local line = ok and 'PASS: AC8-2' or ('FAIL: AC8-2 :: notify=' .. vim.inspect(notify_calls))
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC8-2.txt')
vim.cmd('qa!')
