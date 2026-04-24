local fzf_contents = nil
package.loaded['fzf-lua'] = {
  fzf_exec = function(contents, opts) fzf_contents = contents end,
}
package.loaded['fzf-lua.actions'] = { normalize_selected = function(s, o) return nil, s end }

local cache = require('nx.cache')
local orig_get = cache.get_project
cache.get_project = function(ws, name, on_done)
  on_done({ ok = true, project = { targets = { build = {}, serve = {}, test = {} } } })
end

package.loaded['nx.pickers'] = nil
local pickers = require('nx.pickers')
pickers.tasks('/ws', 'alpha', function() end)

vim.defer_fn(function()
  cache.get_project = orig_get
  local ok = fzf_contents ~= nil
    and #fzf_contents == 3
    and fzf_contents[1] == 'build'
    and fzf_contents[2] == 'serve'
    and fzf_contents[3] == 'test'
  local line = ok and 'PASS: AC9-1' or ('FAIL: AC9-1 :: contents=' .. vim.inspect(fzf_contents))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC9-1.txt')
  vim.cmd('qa!')
end, 100)
