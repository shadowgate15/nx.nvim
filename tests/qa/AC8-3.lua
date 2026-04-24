local fzf_count = 0
package.loaded['fzf-lua'] = {
  fzf_exec = function() fzf_count = fzf_count + 1 end,
}
package.loaded['fzf-lua.actions'] = { normalize_selected = function(s, o) return nil, s end }

local notify_calls = {}
local orig_notify = vim.notify
vim.notify = function(msg, level) table.insert(notify_calls, { msg = msg, level = level }) end

local cache = require('nx.cache')
local orig_get = cache.get_projects
cache.get_projects = function(ws, on_done)
  on_done({ ok = true, projects = {} })
end

package.loaded['nx.pickers'] = nil
local pickers = require('nx.pickers')
pickers.projects('/ws', function() end)

vim.defer_fn(function()
  cache.get_projects = orig_get
  vim.notify = orig_notify

  local warned = false
  for _, n in ipairs(notify_calls) do
    if n.level == vim.log.levels.WARN then warned = true end
  end

  local ok = fzf_count == 0 and warned
  local line = ok and 'PASS: AC8-3' or ('FAIL: AC8-3 :: fzf_count=' .. fzf_count .. ' warned=' .. tostring(warned))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC8-3.txt')
  vim.cmd('qa!')
end, 100)
