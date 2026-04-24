local fzf_contents = nil
local fzf_opts = nil

package.loaded['fzf-lua'] = {
  fzf_exec = function(contents, opts)
    fzf_contents = contents
    fzf_opts = opts
  end,
}
package.loaded['fzf-lua.actions'] = {
  normalize_selected = function(sel, opts) return nil, sel end,
}

local cache = require('nx.cache')
local orig_get = cache.get_projects
cache.get_projects = function(ws, on_done)
  on_done({ ok = true, projects = { 'alpha', 'beta' } })
end

local pickers = require('nx.pickers')
pickers.projects('/ws', function() end)

vim.defer_fn(function()
  cache.get_projects = orig_get

  local ok = fzf_contents ~= nil
    and #fzf_contents == 2
    and fzf_contents[1] == 'alpha'
    and fzf_contents[2] == 'beta'
    and fzf_opts ~= nil
    and fzf_opts.prompt ~= nil
    and fzf_opts.prompt:find('Projects') ~= nil

  local line = ok and 'PASS: AC8-1'
    or ('FAIL: AC8-1 :: contents=' .. vim.inspect(fzf_contents) .. ' prompt=' .. tostring(fzf_opts and fzf_opts.prompt))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC8-1.txt')
  vim.cmd('qa!')
end, 100)
