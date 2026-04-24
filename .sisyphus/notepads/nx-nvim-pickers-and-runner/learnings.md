# Learnings — nx-nvim-pickers-and-runner

## Project Structure
- Plugin entry: lua/nx/init.lua (lazy __index loader, M.setup pattern)
- Config: lua/nx/config.lua (empty default_config, vim.tbl_deep_extend 'force')
- .stylua.toml: 2-space indent, AutoPreferSingle quotes, sort_requires=true

## Key Invariants
- All new modules: lua/nx/{workspace,cli,cache,registry,terminal,pickers,commands,health}.lua
- NO lua/nx/utils.lua
- NO plugin/nx.lua
- Commands registered inside setup() only
- All nx show* CLI calls: async vim.system({table form}) — never vim.fn.system
- Cache + registry keyed by absolute workspace root string
- Snacks: terminal:hide() keeps buffer+job alive; terminal:close() kills both
- Snacks.terminal.list() returns VISIBLE only — use our own registry for hidden
- fzf-lua: normalize_selected(selected, opts) required on fzf >= 0.53
- Wrap chained pickers in vim.schedule(function() ... end)
- First ':' separates <project>:<task>
- snake_case for all config keys

## Task 5 — Registry (lua/nx/registry.lua)
- Registry key: `workspace_root .. '::' .. project .. '::' .. task`
- BufWipeout fires BEFORE buffer is deleted; nil entry.bufnr to prevent use-after-free
- `pcall(os.remove, path)` handles gracefully missing files
- `pcall(vim.api.nvim_buf_delete, ...)` graceful on already-deleted buffers
- `clear()` must collect all entries first then remove (avoid modifying _entries while iterating)
- `attach_self_healing()` uses `nvim_create_augroup('nx.registry', { clear=true })` to avoid duplicate autocmds on repeated setup() calls
- BufWipeout self-heal: DO NOT delete the entry, only mark status='exited', exit_code=-1
- `vim.uv.now()` for timestamps (milliseconds since boot, monotonic)
- All 3 QA scenarios PASS: AC5-1 (round-trip+sort), AC5-2 (BufWipeout heal), AC5-3 (tempfile cleanup)
- Commit: 9eafa00 (QA files); registry.lua was pre-existing in df2e840 fixture commit

## Task 4 — Cache (lua/nx/cache.lua)
- `lua/nx/cache.lua` and `tests/qa/AC4-1.lua` were pre-existing (committed in a prior session)
- AC4-3 and AC4-4 QA files were the new additions for this task
- In-flight dedup key format: `'projects::' .. ws_root` / `'project::' .. ws_root .. '::' .. name`
- Cache invalidate: set to nil (not empty table); _ensure_root guards nil-index on next access
- BufWritePost patterns: both `'*/nx.json'` and `'nx.json'` needed for cwd-relative saves
- `vim.api.nvim_create_augroup('nx.cache', { clear=true })` prevents duplicate registrations
- AC4-4 test: call `cache.attach_autocmds()` directly rather than `require('nx').setup({})` to avoid config dependency
- `vim.api.nvim_exec_autocmds` with `data = { file = nx_file }` to fire BufWritePost in headless tests
- All 3 AC4 scenarios PASS: AC4-1 (cache hit/CLI once), AC4-3 (invalidate re-fetches), AC4-4 (autocmd clears)
- Commit: 8b0e0bd

## Tasks 8 & 9 — fzf-lua pickers (lua/nx/pickers.lua)
- `fzf_exec(contents, opts)` — contents is a plain Lua list of strings
- Custom previewer: `{ fn = function(items) return string end, field_index = '{}' }`
- `require('fzf-lua.actions').normalize_selected(selected, opts)` — handles keybind prefix on fzf >= 0.53; use pcall so it degrades gracefully
- `cache.state()` returns a deep copy — safe for sync cache-hit checks inside previewer
- Always `vim.schedule()` after async callback before calling fzf_exec
- In QA scripts: `package.loaded['nx.pickers'] = nil` then re-require after stubbing fzf-lua to force fresh module load
- AC8-1..AC8-4 and AC9-1..AC9-3 all PASS (headless nvim, defer_fn pattern)
- Two commits: 57cab7e (projects picker + AC8 QA), ff27384 (AC9 QA)

## Task 7 — terminal.lua

- Snacks.terminal returns object with `:show()`, `:focus()`, `:hide()`, `:buf_valid()`, `:win_valid()` methods. `auto_close=false` is required so the buffer survives long enough for `_on_exit` to dump output.
- `vim.b[bufnr].terminal_job_id` is populated asynchronously by `termopen`; must read on `vim.schedule` next tick, not synchronously after `snacks.terminal()`.
- `TermClose` autocmd `args.data` carries exit code on Neovim 0.10+; fallback to `vim.v.event.status` for older builds.
- `kill()` semantics: set `entry._killing = true` BEFORE `vim.fn.jobstop`, then `registry.remove`; the in-flight `_on_exit` (fired by jobstop's TermClose) checks the flag before dump and skips.
- Buffer-local keymaps (`buffer = bufnr`) are correct — registered in both terminal (`t`) and normal (`n`) modes.
- For `foreground()` of an exited task: prefer `snacks.win({ file = path })`; fallback to `:split <path>` + readonly when Snacks unavailable. Missing-file path notifies ERROR and removes registry entry.
- QA pattern: stub `package.loaded['snacks']` BEFORE `require('nx.terminal')` so the module's `pcall(require, 'snacks')` picks up the stub. Use `cli._bin_cache = { ['/ws'] = '/fake/nx' }` to bypass binary resolution.

## Task 10 — commands.lua

- `M._with_workspace(fn)` correctly uses `require('nx.workspace').root()` (not `find_root()`); memo+env-var honoring is encapsulated in `root()`.
- Picker chaining: `nx_project()` passes `M.nx_project_tasks(project_name)` as `on_select`; the pickers themselves use `vim.schedule` internally so commands don't need extra scheduling.
- `nx_project_tasks(nil)` redirects to `nx_project()` for the project picker fallback — no recursion loop since `nx_project()` always provides a name.
- `cache.invalidate(root)` takes a string; `nx_refresh()` passes the resolved root and notifies INFO after.
- `register()` uses `nvim_create_user_command` with `nargs='?'` only on `:NxProjectTasks`; `:NxProject` and `:NxRefresh` take no args.
- QA stub pattern: replace module function on module table directly (`ws.root = function() ... end`) — works because Lua modules are cached tables.
- All 4 AC10 scenarios pass in headless nvim with minimal_init.lua. Commit: c52cb2b.

## Task 14 (QA Runner) Learnings

- AC scripts use `vim.defer_fn(..., 100)` to wait for vim.schedule callbacks; they then call `vim.cmd('qa!')` themselves inside the deferred function.
- Adding `-c "qa!"` to the runner KILLS the script before its deferred assertion runs. Confirmed by empty `/tmp/qa-*.log` and missing evidence files.
- Solution: schedule a long safety-net quit BEFORE running the script: `-c "lua vim.defer_fn(function() vim.cmd('qa!') end, 5000)" -c "luafile $script"`. Each script's own `qa!` fires first; safety net only triggers if a script hangs.
- `rm -f $EVIDENCE` before each run prevents stale PASS evidence from a prior run masking a regression.
- INTEG-1 stubbing: the `cli.resolve_bin` stub is needed (terminal.run calls it), not just `cli._bin_cache`.
- INTEG-3: `terminal.foreground` calls `pcall(require, 'snacks')`; the stubbed `snacks.win` captures `opts.file` for assertion. Verified `entry.output_file == snacks_state.win_file`.
- All 35 QA scripts now pass (24 pre-existing + 3 INTEG + 0 inline). Runner exits 0 on full pass, non-zero with `FAIL: <AC>` lines on any failure (AC14-2 verified with synthetic AC-DEMO-FAIL.lua).

## F2 Code Quality Review (review pass)

- All 10 modules in `lua/nx/` `return M` properly.
- All 24 `vim.notify` calls include `vim.log.levels.*`.
- No `vim.fn.system` calls; CLI uses `vim.system(table, opts, cb)` correctly.
- No global mutations (`vim.g`, `_G`).
- No `plugin/nx.lua`, no `lua/nx/utils.lua`, no telescope/mini.pick/highlight refs.
- `init.lua` setup() body matches plan: 4 calls only (config.setup, commands.register, cache.attach_autocmds, registry.attach_self_healing); lazy `__index` metatable preserved; no `dependent_plugins`.
- `cache.lua`: in-flight dedup via `_inflight` table, `invalidate(root)` sets `_cache[root] = nil`, `attach_autocmds()` uses `nvim_create_augroup('nx.cache', { clear = true })`.
- `registry.lua`: `M.list()` sorts by `started_at` desc; `BufWipeout` autocmd self-heals; `M.remove()` uses `pcall(os.remove, entry.output_file)`.
- `terminal.lua`: `run()` uses `snacks.terminal(cmd, opts)` with cmd as table; `_on_exit()` dumps lines via `vim.fn.writefile(lines, tmp)` then deletes buffer via `nvim_buf_delete`; `kill()` uses `vim.fn.jobstop(job_id)`; keymaps are buffer-local with `buffer = bufnr`.
- `commands.lua`: `M.register()` calls `M.register_nxtask()` internally; `_parse_key()` uses `arg:find(':', 1, true)` (literal find on first colon).
- `health.lua`: has `M.check()`; uses `vim.health.start/ok/warn/error/info`.
- Stylua: 2 cosmetic-only diffs (line-length wrapping in `cli.lua` and `pickers.lua`). Non-blocking — purely formatting choices.

