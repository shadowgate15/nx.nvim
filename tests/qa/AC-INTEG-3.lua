-- AC-INTEG-3: terminal.run -> _on_exit -> registry exited -> foreground opens tempfile.

local snacks_state = { win_file = nil }

package.loaded['snacks'] = {
  terminal = function(_, _)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'build output line 1', 'build output line 2' })
    return {
      buf = buf,
      show = function(self) return self end,
      focus = function(self) return self end,
      hide = function(self) return self end,
      buf_valid = function() return true end,
      win_valid = function() return true end,
    }
  end,
  win = function(opts)
    snacks_state.win_file = opts and opts.file
    return {}
  end,
}

local cli = require('nx.cli')
cli._bin_cache = { ['/ws-integ3'] = '/fake/nx' }
cli.resolve_bin = function() return '/fake/nx' end

local ws = require('nx.workspace')
ws.root = function() return '/ws-integ3' end

local registry = require('nx.registry')
registry.clear()

local terminal = require('nx.terminal')
terminal.run('/ws-integ3', 'alpha', 'build')

vim.defer_fn(function()
  local entry = registry.get('/ws-integ3', 'alpha', 'build')
  local was_running = entry and entry.status == 'running'

  terminal._on_exit('/ws-integ3', 'alpha', 'build', 0)

  vim.defer_fn(function()
    local exited_entry = registry.get('/ws-integ3', 'alpha', 'build')
    local exited_ok = exited_entry ~= nil
      and exited_entry.status == 'exited'
      and exited_entry.exit_code == 0
      and exited_entry.output_file ~= nil
      and vim.fn.filereadable(exited_entry.output_file) == 1

    terminal.foreground('/ws-integ3', 'alpha', 'build')

    vim.defer_fn(function()
      local win_opened = exited_entry and snacks_state.win_file == exited_entry.output_file
      local ok = was_running and exited_ok and win_opened
      local line = ok and 'PASS: AC-INTEG-3'
        or ('FAIL: AC-INTEG-3 :: was_running=' .. tostring(was_running)
            .. ' exited_ok=' .. tostring(exited_ok)
            .. ' win_opened=' .. tostring(win_opened)
            .. ' win_file=' .. tostring(snacks_state.win_file)
            .. ' output_file=' .. tostring(exited_entry and exited_entry.output_file))
      vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC-INTEG-3.txt')
      vim.cmd('qa!')
    end, 100)
  end, 100)
end, 100)
