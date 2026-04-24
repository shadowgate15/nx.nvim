# Decisions — nx-nvim-pickers-and-runner

## Config schema (Task 1)
- Four sub-tables: cli{timeout_ms=30000, env={}, workspace_root_env='NX_WORKSPACE_ROOT_PATH'},
  cache{auto_invalidate=true, watch_files={'nx.json','project.json'}},
  runner{keymaps{background='<C-b>'}, win={}},
  pickers{preview=true}
- Export M.defaults() returning vim.deepcopy(default_config)

## Workspace detection (Task 2)
- vim.fs.find('nx.json', {upward=true, path=start_dir, type='file'})
- Honor vim.env[config.cli.workspace_root_env] first
- Return absolute path via vim.fs.normalize(vim.fn.fnamemodify(p, ':p'))

## CLI resolution (Task 3)
- <root>/node_modules/.bin/nx → vim.fn.exepath('nx') → nil
- vim.system({bin, ...args}, {cwd, text=true, env, timeout}, vim.schedule_wrap(cb))
- json parse: vim.json.decode(stdout, {luanil={object=true, array=true}})

## Cache (Task 4)
- in-flight key: 'projects::' .. ws_root OR 'project::' .. ws_root .. '::' .. name
- autocmd group: 'nx.cache', event: BufWritePost

## Registry (Task 5)
- key: ws_root .. '::' .. project .. '::' .. task
- autocmd group: 'nx.registry', event: BufWipeout
- On exit: status='exited', exit_code=-1 (self-heal), NOT deleted

## Terminal runner (Task 7)
- interactive=true, auto_close=false
- background keymap: buffer-local in 't' and 'n' modes
- _on_exit: read buf lines → writefile to tempname()..'.nx-task.txt' → delete buf
- foreground exited: Snacks.win or nvim_open_win with the temp file (read-only)
- kill: vim.fn.jobstop(job_id), then registry.remove (no dump)

## Pickers (Tasks 8+9)
- Pretty-print: vim.inspect(vim.json.decode(json_str), {newline='\n', indent='  '})
- previewer field: { fn=function(items)...end, field_index='{}' }

## Commands (Tasks 10+11)
- NxTask subcommand completion: only subcommand names (not project:task)
- fg alias: 'fg' == 'foreground'

## Health (Task 12)
- lua/nx/health.lua with M.check() — auto-discovered by Neovim 0.10+
- Sync via :wait(5000) is acceptable in health

## init.lua (Task 13)
- Remove dependent_plugins block entirely
- setup() calls: config.setup, commands.register, cache.attach_autocmds, registry.attach_self_healing

## QA (Task 14)
- minimal_init.lua: vim.opt.runtimepath:prepend(vim.fn.getcwd())
- Stubs in tests/qa/_stubs/init.lua
- Evidence files: .sisyphus/evidence/qa-<AC-ID>.txt

## Exited task foregrounding
- Buffer contents dumped to tempname()..'.nx-task.txt'
- registry retains output_file path
- Snacks.win({ file=..., win={style='float'} }) to show read-only
