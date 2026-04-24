-- AC-INTEG-1: Full chain NxProject -> project picker -> task picker -> terminal.run
-- Stubs: fzf-lua, snacks, workspace.root, cli.show_projects/show_project.

local fzf_calls = {}
package.loaded['fzf-lua'] = {
  fzf_exec = function(contents, opts)
    table.insert(fzf_calls, { contents = contents, opts = opts })
    if opts and opts.actions and opts.actions['default'] then
      opts.actions['default']({ contents[1] }, {})
    end
  end,
}
package.loaded['fzf-lua.actions'] = {
  normalize_selected = function(selected, _)
    return nil, selected
  end,
}

local terminal_calls = {}
package.loaded['snacks'] = {
  terminal = function(cmd, opts)
    table.insert(terminal_calls, { cmd = cmd, opts = opts })
    return {
      buf = vim.api.nvim_create_buf(false, true),
      show = function(self) return self end,
      focus = function(self) return self end,
      hide = function(self) return self end,
      buf_valid = function() return true end,
      win_valid = function() return true end,
    }
  end,
}

local ws = require('nx.workspace')
ws.root = function() return '/ws-integ' end

local cli = require('nx.cli')
cli._bin_cache = { ['/ws-integ'] = '/fake/nx' }
cli.resolve_bin = function() return '/fake/nx' end
cli.show_projects_by_type = function(_, kind, on_done)
  if kind == 'app' then
    on_done({ ok = true, projects = { 'alpha' } })
  elseif kind == 'lib' then
    on_done({ ok = true, projects = { 'beta' } })
  else
    on_done({ ok = true, projects = {} })
  end
end
cli.show_project = function(_, name, on_done)
  on_done({
    ok = true,
    project = {
      name = name,
      targets = {
        build = { executor = 'nx:run-commands', options = { command = 'echo ' .. name } },
      },
    },
  })
end

require('nx.cache').invalidate()
require('nx.registry').clear()

require('nx.commands').nx_project()

vim.defer_fn(function()
  local first_cmd = terminal_calls[1] and terminal_calls[1].cmd
  local cmd_str = first_cmd and table.concat(first_cmd, ' ') or ''
  local ok = #fzf_calls >= 2
    and #terminal_calls >= 1
    and cmd_str:find('alpha:build', 1, true) ~= nil

  local line = ok and 'PASS: AC-INTEG-1'
    or ('FAIL: AC-INTEG-1 :: fzf_calls=' .. #fzf_calls
        .. ' terminal_calls=' .. #terminal_calls
        .. ' cmd=' .. vim.inspect(first_cmd))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC-INTEG-1.txt')
  vim.cmd('qa!')
end, 300)
