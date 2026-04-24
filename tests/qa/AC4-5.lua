-- AC4-5: cache.get_projects flattens by-kind results in apps -> libs -> e2e order
local cli = require('nx.cli')
cli.show_projects_by_type = function(_, kind, on_done)
  if kind == 'app' then
    on_done({ ok = true, projects = { 'web', 'admin' } })
  elseif kind == 'lib' then
    on_done({ ok = true, projects = { 'utils', 'shared-ui' } })
  elseif kind == 'e2e' then
    on_done({ ok = true, projects = { 'web-e2e' } })
  end
end

local cache = require('nx.cache')
cache.invalidate()

local got = nil
cache.get_projects('/ws-order', function(r) got = r end)

vim.defer_fn(function()
  -- Within a kind, names are sorted alphabetically; kinds themselves come
  -- in the fixed order apps -> libs -> e2e.
  local expected = { 'admin', 'web', 'shared-ui', 'utils', 'web-e2e' }
  local kinds_ok = got and got.ok
    and got.project_kinds
    and got.project_kinds['admin'] == 'app'
    and got.project_kinds['web'] == 'app'
    and got.project_kinds['shared-ui'] == 'lib'
    and got.project_kinds['utils'] == 'lib'
    and got.project_kinds['web-e2e'] == 'e2e'

  local order_ok = got and got.projects and #got.projects == #expected
  if order_ok then
    for i, name in ipairs(expected) do
      if got.projects[i] ~= name then
        order_ok = false
        break
      end
    end
  end

  local by_kind_ok = got and got.projects_by_kind
    and #got.projects_by_kind.app == 2
    and #got.projects_by_kind.lib == 2
    and #got.projects_by_kind.e2e == 1

  local ok = kinds_ok and order_ok and by_kind_ok
  local line = ok and 'PASS: AC4-5'
    or ('FAIL: AC4-5 :: kinds_ok=' .. tostring(kinds_ok)
        .. ' order_ok=' .. tostring(order_ok)
        .. ' by_kind_ok=' .. tostring(by_kind_ok)
        .. ' got=' .. vim.inspect(got))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC4-5.txt')
  vim.cmd('qa!')
end, 100)
