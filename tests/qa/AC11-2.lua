-- AC11-2: :NxTask list opens fzf-lua with formatted display strings
local ws = require('nx.workspace')
ws.root = function() return '/ws' end

local registry = require('nx.registry')
registry.list = function()
  return {
    { workspace_root = '/ws', project = 'alpha', task = 'build', status = 'running', exit_code = nil, started_at = 2 },
    { workspace_root = '/ws', project = 'beta', task = 'test', status = 'exited', exit_code = 0, started_at = 1 },
  }
end

local fzf_contents = nil
package.loaded['fzf-lua'] = {
  fzf_exec = function(contents, opts) fzf_contents = contents end,
}
package.loaded['fzf-lua.actions'] = { normalize_selected = function(s, o) return nil, s end }

package.loaded['nx.commands'] = nil
local commands = require('nx.commands')
commands.nx_task({ fargs = { 'list' } })

vim.defer_fn(function()
  ws.root = require('nx.workspace').find_root
  registry.list = nil

  local ok = fzf_contents ~= nil
    and #fzf_contents == 2
  local has_alpha_build = false
  local has_beta_test = false
  if ok then
    for _, s in ipairs(fzf_contents) do
      if s:find('alpha:build') and s:find('running') then has_alpha_build = true end
      if s:find('beta:test') and s:find('exited') and s:find('code=0') then has_beta_test = true end
    end
  end
  ok = ok and has_alpha_build and has_beta_test

  local line = ok and 'PASS: AC11-2' or ('FAIL: AC11-2 :: contents=' .. vim.inspect(fzf_contents))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC11-2.txt')
  vim.cmd('qa!')
end, 100)
