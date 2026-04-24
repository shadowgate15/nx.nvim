local captured_previewer = nil
package.loaded['fzf-lua'] = {
  fzf_exec = function(contents, opts)
    captured_previewer = opts and opts.previewer
  end,
}
package.loaded['fzf-lua.actions'] = { normalize_selected = function(s, o) return nil, s end }

local cache = require('nx.cache')
local orig_get = cache.get_project
cache.get_project = function(ws, name, on_done)
  on_done({ ok = true, project = {
    targets = {
      build = { executor = 'nx:run-commands', options = { command = 'echo hi' } },
    },
  } })
end

package.loaded['nx.pickers'] = nil
local pickers = require('nx.pickers')
pickers.tasks('/ws', 'alpha', function() end)

vim.defer_fn(function()
  cache.get_project = orig_get
  local preview_result = nil
  if captured_previewer and captured_previewer.fn then
    preview_result = captured_previewer.fn({ 'build' })
  end
  local ok = preview_result ~= nil
    and preview_result:find('nx:run%-commands') ~= nil
    and preview_result:find('echo hi') ~= nil
  local line = ok and 'PASS: AC9-3' or ('FAIL: AC9-3 :: result=' .. tostring(preview_result))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC9-3.txt')
  vim.cmd('qa!')
end, 100)
