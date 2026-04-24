local captured_cmd, captured_opts

package.loaded['snacks'] = {
  terminal = function(cmd, opts)
    captured_cmd = cmd
    captured_opts = opts
    return {
      buf = vim.api.nvim_create_buf(false, true),
      show = function(self)
        return self
      end,
      focus = function(self)
        return self
      end,
      hide = function(self)
        return self
      end,
      buf_valid = function(self)
        return true
      end,
      win_valid = function(self)
        return true
      end,
    }
  end,
}

local cli = require('nx.cli')
cli._bin_cache = { ['/ws'] = '/fake/nx' }

local registry = require('nx.registry')
local terminal = require('nx.terminal')
registry.clear()

terminal.run('/ws', 'alpha', 'build')

local ok = captured_cmd ~= nil
  and captured_cmd[1] == '/fake/nx'
  and captured_cmd[2] == 'run'
  and captured_cmd[3] == 'alpha:build'
  and captured_opts ~= nil
  and captured_opts.cwd == '/ws'
  and captured_opts.interactive == true
  and captured_opts.auto_close == false

local line = ok and 'PASS: AC7-1'
  or ('FAIL: AC7-1 :: cmd=' .. vim.inspect(captured_cmd) .. ' opts=' .. vim.inspect(captured_opts))
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC7-1.txt')
vim.cmd('qa!')
