local captured_action = nil
package.loaded['fzf-lua'] = {
  fzf_exec = function(contents, opts)
    captured_action = opts and opts.actions and opts.actions['default']
  end,
}
package.loaded['fzf-lua.actions'] = {
  normalize_selected = function(selected, opts) return nil, selected end,
}

local cache = require('nx.cache')
local orig_get = cache.get_projects
cache.get_projects = function(ws, on_done)
  on_done({ ok = true, projects = { 'alpha', 'beta' } })
end

local selected_project = nil
package.loaded['nx.pickers'] = nil
local pickers = require('nx.pickers')
pickers.projects('/ws', function(name) selected_project = name end)

vim.defer_fn(function()
  cache.get_projects = orig_get

  if captured_action then
    captured_action({ 'alpha' }, {})
  end

  vim.defer_fn(function()
    local ok = selected_project == 'alpha'
    local line = ok and 'PASS: AC8-4'
      or ('FAIL: AC8-4 :: selected=' .. tostring(selected_project) .. ' action=' .. tostring(captured_action ~= nil))
    vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC8-4.txt')
    vim.cmd('qa!')
  end, 50)
end, 100)
