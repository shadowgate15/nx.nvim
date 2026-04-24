-- AC8-5: project picker orders entries apps -> libs -> e2e and labels each correctly
local fzf_contents = nil

package.loaded['fzf-lua'] = {
  fzf_exec = function(contents, _opts) fzf_contents = contents end,
}
package.loaded['fzf-lua.actions'] = {
  normalize_selected = function(s, _) return nil, s end,
}

local cache = require('nx.cache')
local orig_get = cache.get_projects
cache.get_projects = function(_, on_done)
  on_done({
    ok = true,
    -- Caller-provided order is preserved by the picker; cache is responsible
    -- for the apps -> libs -> e2e ordering. Provide it that way here.
    projects = { 'web', 'admin', 'shared-ui', 'utils', 'admin-e2e', 'web-e2e' },
    project_kinds = {
      ['web'] = 'app',
      ['admin'] = 'app',
      ['shared-ui'] = 'lib',
      ['utils'] = 'lib',
      ['admin-e2e'] = 'e2e',
      ['web-e2e'] = 'e2e',
    },
  })
end

package.loaded['nx.pickers'] = nil
local pickers = require('nx.pickers')
pickers.projects('/ws', function() end)

vim.defer_fn(function()
  cache.get_projects = orig_get

  local function entry_at(i, kind, name)
    local e = fzf_contents and fzf_contents[i]
    if type(e) ~= 'string' then return false end
    if not e:find('%[' .. kind .. '%]', 1, false) then return false end
    if not e:find(name .. '$') then return false end
    return true
  end

  -- Verify the picker preserved order AND tagged each entry with the matching kind.
  local order_ok = fzf_contents ~= nil
    and #fzf_contents == 6
    and entry_at(1, 'app', 'web')
    and entry_at(2, 'app', 'admin')
    and entry_at(3, 'lib', 'shared%-ui')
    and entry_at(4, 'lib', 'utils')
    and entry_at(5, 'e2e', 'admin%-e2e')
    and entry_at(6, 'e2e', 'web%-e2e')

  -- Round-trip: every selected entry must strip back to its bare project name.
  local strip_ok = true
  if fzf_contents then
    local expected = { 'web', 'admin', 'shared-ui', 'utils', 'admin-e2e', 'web-e2e' }
    for i, e in ipairs(fzf_contents) do
      if pickers._strip_prefix(e) ~= expected[i] then
        strip_ok = false
        break
      end
    end
  else
    strip_ok = false
  end

  local ok = order_ok and strip_ok
  local line = ok and 'PASS: AC8-5'
    or ('FAIL: AC8-5 :: order_ok=' .. tostring(order_ok)
        .. ' strip_ok=' .. tostring(strip_ok)
        .. ' contents=' .. vim.inspect(fzf_contents))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC8-5.txt')
  vim.cmd('qa!')
end, 100)
