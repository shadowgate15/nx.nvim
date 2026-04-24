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
  on_done({
    ok = true,
    projects = { 'alpha-app', 'beta-lib', 'gamma-e2e' },
    project_kinds = { ['alpha-app'] = 'app', ['beta-lib'] = 'lib', ['gamma-e2e'] = 'e2e' },
  })
end

local pickers = require('nx.pickers')
pickers.projects('/ws', function() end)

vim.defer_fn(function()
  cache.get_projects = orig_get

  -- Each entry must end with the bare project name, and start with a `[kind]`
  -- prefix matching the project's kind. ANSI color codes may surround the
  -- bracket label, so we anchor on the bracket+name suffix rather than exact equality.
  local function entry_ok(entry, kind, name)
    if type(entry) ~= 'string' then return false end
    if not entry:find('%[' .. kind .. '%]', 1, false) then return false end
    if not entry:find(name .. '$') then return false end
    return true
  end

  local ok = fzf_contents ~= nil
    and #fzf_contents == 3
    and entry_ok(fzf_contents[1], 'app', 'alpha%-app')
    and entry_ok(fzf_contents[2], 'lib', 'beta%-lib')
    and entry_ok(fzf_contents[3], 'e2e', 'gamma%-e2e')
    and fzf_opts ~= nil
    and fzf_opts.prompt ~= nil
    and fzf_opts.prompt:find('Projects') ~= nil

  local line = ok and 'PASS: AC8-1'
    or ('FAIL: AC8-1 :: contents=' .. vim.inspect(fzf_contents) .. ' prompt=' .. tostring(fzf_opts and fzf_opts.prompt))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC8-1.txt')
  vim.cmd('qa!')
end, 100)
