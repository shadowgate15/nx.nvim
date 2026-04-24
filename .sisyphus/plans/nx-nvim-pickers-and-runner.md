# nx.nvim — fzf-lua Pickers + Snacks Task Runner

## TL;DR

> **Quick Summary**: Build a Neovim plugin that exposes Nx workspace projects/tasks via fzf-lua pickers and runs tasks in backgroundable Snacks.terminal floats.
>
> **Deliverables**:
> - `:NxProject` — fzf-lua picker of Nx projects with project.json preview
> - `:NxProjectTasks` — fzf-lua picker of tasks for a project, with task config preview
> - `:NxRefresh` — clear cached projects/tasks for current workspace
> - `:NxTask {list|foreground|kill} [project:task]` — manage backgrounded task floats
> - Snacks.terminal float runner with `<C-b>` to background, registry of running/exited tasks
> - `:checkhealth nx` reporting CLI/version/dependency status
> - In-memory cache per workspace root, auto-invalidated on `nx.json`/`project.json` writes
>
> **Estimated Effort**: Medium
> **Parallel Execution**: YES — 3 waves
> **Critical Path**: Task 1 → Task 2/3 → Task 6 → Task 9 → Task 11 → Task 12 → F1-F4

---

## Context

### Original Request

> Create an nvim plugin for NX. Adding commands and a Snacks float.
>
> Commands:
> 1. `NxProject` — FzfLua picker for nx projects pulled from the nx cli
> 2. `NxProjectTasks` — FzfLua picker of tasks for a project pulled from the nx cli
>
> Upon accepting an nx project the `NxProjectTasks` picker should be called.
> Upon accepting an nx project task a Snacks.nvim float should be created similar to the
> lazygit integration that Snacks already has. We don't need colorscheme configuration.

User then added a backgrounding requirement: keypress in float to background the task, plus a command to foreground a backgrounded task.

### Interview Summary

**Key Discussions**:
- CLI source: `nx show projects --json` + `nx show project <name> --json` (Nx ≥ 16.3, recommend ≥ 18.1)
- Workspace detection: walk up from cwd to find `nx.json`; honor `$NX_WORKSPACE_ROOT_PATH`
- CLI invocation: prefer local `node_modules/.bin/nx`, then global `nx`. **No `npx` fallback.**
- Caching: in-memory per workspace root; auto-invalidate on `nx.json`/`project.json` `BufWritePost`; manual `:NxRefresh`
- Picker preview: fzf-lua preview pane shows project.json (project picker) and task config JSON (tasks picker)
- Loading model: keep current `setup()` pattern; commands registered inside `setup()`
- Float: `Snacks.terminal(cmd, { interactive = true, auto_close = false, win = { position = "float", style = "terminal" } })`. `q` hides (Snacks default), `<C-b>` (configurable) backgrounds
- Backgrounding: multiple concurrent tasks; one instance per `<project>:<task>` key; re-running an active task foregrounds it
- Foreground UX: 0 → notify; 1 → foreground directly; 2+ → fzf-lua picker
- Commands: unified `:NxTask` with subcommands `list` (default), `foreground [project:task]`, `kill [project:task]`
- Lifecycle on exit: `vim.notify` with exit code; **dump terminal buffer to a temp file**, free live buffer, keep registry entry with `status = 'exited'`, `exit_code`, `output_file`
- Foregrounding an exited task: open the temp file in a read-only scratch buffer inside a Snacks float (NOT a terminal)
- VimLeavePre: do nothing; Neovim's default child-job kill is sufficient
- `:checkhealth nx`: included
- Multi-workspace: officially supported; cache + registry keyed by absolute workspace root
- Async: `vim.system({...table form...})` for all CLI calls; never block UI
- In-flight dedup: concurrent `:NxProject` calls share one CLI invocation per workspace
- Registry self-healing: `BufWipeout` autocmd cleans dangling entries
- Tests: no unit/integration test framework; agent-executed QA only via `nvim --headless` + stub-and-assert pattern

**Research Findings**:
- **Snacks.terminal** (commit `ad9ede6a`): `terminal:hide()` keeps buffer + job alive (`lua/snacks/win.lua:619-622`); `terminal:close()` deletes buffer (kills job). `Snacks.terminal.list()` returns only **visible** terminals — must maintain own registry for backgrounded ones. Default `q` keymap inside terminal float already calls `hide()`.
- **fzf-lua** (commit `ffa44ee`): `fzf_exec(contents, opts)` accepts a static Lua table. `actions = { ["enter"] = fn, ["ctrl-x"] = fn }`. On fzf ≥ 0.53 use `require('fzf-lua.actions').normalize_selected(selected, opts)` to extract real entries. Custom previewer: `preview = function(args) return string end`. Wrap chained pickers in `vim.schedule(function() ... end)`.
- **Nx CLI** (commit `04ec111c`): `nx show projects --json` outputs `string[]`. `nx show project <name> --json` outputs full `ProjectConfiguration` with `targets: Record<string, TargetConfiguration>`. Workspace detection via `nx.json` walk-up. Stderr clean for `show` commands.

### Metis Review

**Identified Gaps** (addressed):
- Async strategy: locked to `vim.system({...table...})` table form; no shell concat; no UI blocking
- VimLeavePre: locked (do nothing)
- `:checkhealth nx`: locked (included)
- npx fallback: dropped
- Exited task lifecycle: locked (temp file dump pattern)
- Multi-workspace: locked (cache+registry keyed by abs root)
- BufWipeout self-healing: locked
- In-flight dedup for concurrent CLI calls: locked
- `interactive=true` confirmed for Snacks terminal
- First `:` as `<project>:<task>` separator: locked
- snake_case config naming: locked
- Module structure: locked (`workspace`, `cli`, `cache`, `registry`, `terminal`, `pickers`, `commands`, `health`; no `utils.lua`)
- Min versions pinned in README
- Stub-and-assert headless QA pattern: locked

---

## Work Objectives

### Core Objective

Provide a complete fzf-lua + Snacks.terminal-based UX for browsing Nx workspace projects, inspecting their task configs, running tasks in backgroundable floats, and managing those running tasks across the Neovim session.

### Concrete Deliverables

- `lua/nx/init.lua` — updated to register commands inside `setup()` (existing scaffolding preserved)
- `lua/nx/config.lua` — extended with `cli`, `cache`, `runner`, `pickers` sub-tables
- `lua/nx/workspace.lua` — workspace root detection (cwd walk-up + `$NX_WORKSPACE_ROOT_PATH`)
- `lua/nx/cli.lua` — async `vim.system` wrapper, binary resolution chain
- `lua/nx/cache.lua` — per-workspace in-memory cache with in-flight dedup + invalidation API + autocmds
- `lua/nx/registry.lua` — backgrounded task registry, self-healing on `BufWipeout`
- `lua/nx/terminal.lua` — Snacks.terminal wrapper for running tasks, background/foreground/kill
- `lua/nx/pickers.lua` — fzf-lua project picker and tasks picker (with preview, chaining)
- `lua/nx/commands.lua` — `:NxProject`, `:NxProjectTasks`, `:NxRefresh`, `:NxTask {list|foreground|kill}`
- `lua/nx/health.lua` — `:checkhealth nx` implementation
- `tests/fixtures/sample-workspace/` — minimal Nx workspace fixture (nx.json, 2 projects, 2 targets each) for QA scenarios
- `tests/qa/*.lua` — Lua headless QA scripts (one per command/feature)
- `tests/qa/run-all.sh` — bash wrapper that runs all QA scripts via `nvim --headless` and prints PASS/FAIL per AC
- `README.md` — updated with usage, configuration, dependency requirements, minimum versions

### Definition of Done

- [ ] `bash tests/qa/run-all.sh` reports all acceptance criteria PASS
- [ ] `nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "lua require('nx').setup({})" -c "qa"` exits 0 (smoke)
- [ ] `nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "checkhealth nx" -c "qa"` writes a health report to a captured file containing the expected sections
- [ ] All Final Verification Wave reviews APPROVE

### Must Have

- All four commands (`:NxProject`, `:NxProjectTasks`, `:NxRefresh`, `:NxTask`) registered inside `setup()`
- Async CLI invocation (`vim.system` table form, never `vim.fn.system` for show commands)
- Cache keyed by absolute workspace root; auto-invalidation on `nx.json`/`project.json` BufWritePost; in-flight dedup
- Registry of running/exited tasks keyed by `(workspace_root, project, task)` tuple
- Background keybind inside running terminal float (default `<C-b>`, configurable)
- Foreground command UX: 0 notify / 1 direct / 2+ picker
- Exited task → buffer dumped to temp file → registry retains `output_file`; foregrounding an exited task opens the temp file in a Snacks float
- Re-running active `<project>:<task>` foregrounds existing terminal (no duplicate spawn)
- `:checkhealth nx` reports Nx CLI availability + version, fzf-lua presence, Snacks presence, workspace detection result
- Soft-dep error messages naming the missing plugin
- README with min versions, install snippet for lazy.nvim, dependency table, command reference, config schema

### Must NOT Have (Guardrails)

- ❌ No colorscheme/highlight group definitions
- ❌ No `:NxProject <name>` argument tab-completion
- ❌ No Nx graph visualization
- ❌ No `nx generate` UI
- ❌ No Telescope.nvim adapter
- ❌ No mini.pick adapter
- ❌ No `nx affected` integration
- ❌ No task argument passing (`nx build app --foo=bar`) in v1
- ❌ No task configuration selection (`nx build app -c production`) in v1
- ❌ No statusline component
- ❌ No `lua/nx/utils.lua` "junk drawer" — every helper has a domain home
- ❌ No `vim.fn.system()` for `nx show *` calls (must be async `vim.system`)
- ❌ No shell string concatenation for CLI args (must use table form for path safety)
- ❌ No `plugin/nx.lua` — commands registered inside `setup()` per existing pattern
- ❌ No `plenary.async` or custom promise/async abstraction layers
- ❌ No retry/backoff logic on CLI calls
- ❌ No logging framework — only `vim.notify` for user-facing events
- ❌ No defensive `pcall` wrapping of every `vim.fn`/`vim.api` call
- ❌ No `vim.validate` paranoia on internal functions (reserve for `setup()` opts only)
- ❌ No global event bus / hook system
- ❌ No cache TTL configuration knob — invalidation only via autocmd or `:NxRefresh`
- ❌ No project preview customization knob — locked to raw JSON pretty-print in v1
- ❌ No multiple float positions/styles knobs — Snacks defaults + single `win` override pass-through
- ❌ No additional in-float keybinds beyond `<C-b>` (no `<C-r>` restart, etc.)
- ❌ No notify wrapper — call `vim.notify` directly
- ❌ No `npx` fallback in CLI resolution chain
- ❌ No `VimLeavePre` cleanup hooks (Neovim handles child-job kill)
- ❌ No unit tests / no test framework setup (agent-executed QA only)

---

## Verification Strategy (MANDATORY)

> **ZERO HUMAN INTERVENTION** — all verification is agent-executed. No "user manually tests" criteria allowed.

### Test Decision

- **Infrastructure exists**: NO
- **Automated tests**: NONE (no unit/integration framework). All verification is agent-executed QA.
- **Framework**: N/A
- **TDD/RED-GREEN-REFACTOR**: N/A — tasks include direct QA scenarios instead of test cases

### QA Policy

Every implementation task MUST include agent-executed QA scenarios. Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **Picker flows**: stub `require('fzf-lua').fzf_exec` to capture `(contents, opts)` and immediately invoke the action callback with a fixture selection. Assert on captured args and resulting state.
- **Float runner**: stub `Snacks.terminal` to capture `(cmd, opts)` and return a fake terminal object with mocked `hide`/`show`/`focus`/`buf_valid`/`win_valid`. Assert on captured args.
- **CLI calls**: stub `vim.system` to return canned JSON fixture stdout. Assert on captured argv.
- **Workspace detection**: use `tests/fixtures/sample-workspace/` as a real workspace; `cd` into it for the test.
- **Registry/cache state**: directly inspect tables via `require('nx.registry').state()` / `require('nx.cache').state()` test helpers.
- **`:checkhealth nx`**: redirect output via `vim.api.nvim_command('redir > /tmp/health.txt')` then read file.
- **Soft-dep errors**: stub `package.loaded` so that `require('fzf-lua')` / `require('snacks')` fail; assert `vim.notify` was called with expected message.

### Headless QA Runner

`tests/qa/run-all.sh` invokes each `tests/qa/*.lua` script via:

```sh
nvim --headless --noplugin -u tests/qa/minimal_init.lua \
  -c "luafile tests/qa/{ac_id}.lua" -c "qa!"
```

Each Lua QA script writes a single line to `.sisyphus/evidence/qa-{ac_id}.txt` containing `PASS: {ac_id}` or `FAIL: {ac_id} :: {reason}`. The shell wrapper greps these files and prints a summary table.

### Fixture Workspace

`tests/fixtures/sample-workspace/`:
```
nx.json                    # minimal Nx config
package.json               # name + nx dep
apps/
  alpha/
    project.json           # targets: build, serve
libs/
  beta/
    project.json           # targets: build, test
```

---

## Execution Strategy

### Parallel Execution Waves

> Wave 1 = pure foundation modules (no cross-deps). Wave 2 = composition + commands. Wave 3 = QA infrastructure + docs.

```
Wave 1 (Start Immediately — foundation):
├── Task 1: Config schema extension [quick]
├── Task 2: Workspace root detection [quick]
├── Task 3: CLI binary resolution + async exec [quick]
├── Task 4: Cache module with in-flight dedup [unspecified-low]
├── Task 5: Registry module with self-healing [unspecified-low]
└── Task 6: Test fixture workspace [quick]

Wave 2 (After Wave 1 — composition):
├── Task 7: Terminal runner (Snacks integration + temp-file dump) [unspecified-high]
├── Task 8: fzf-lua project picker [unspecified-low]
├── Task 9: fzf-lua tasks picker [unspecified-low]
├── Task 10: Picker chaining + commands integration [unspecified-low]
├── Task 11: :NxTask subcommands (list/foreground/kill) [unspecified-low]
└── Task 12: Health check (:checkhealth nx) [quick]

Wave 3 (After Wave 2 — wiring + docs + QA):
├── Task 13: Wire setup() to register all commands + autocmds [quick]
├── Task 14: Headless QA scripts + runner [unspecified-high]
└── Task 15: README documentation [writing]

Wave FINAL (After ALL tasks — 4 parallel reviews, then user okay):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Real manual QA execution (unspecified-high)
└── Task F4: Scope fidelity check (deep)
-> Present results -> Wait for user's explicit "okay"

Critical Path: T1 → T3 → T7 → T10 → T11 → T13 → T14 → F1-F4 → user okay
Parallel Speedup: ~60% faster than sequential
Max Concurrent: 6 (Wave 1)
```

### Dependency Matrix

| Task | Depends On | Blocks |
|------|------------|--------|
| 1 (Config) | — | 7, 8, 9, 11, 13 |
| 2 (Workspace) | — | 3, 4, 13 |
| 3 (CLI exec) | 2 | 4, 12 |
| 4 (Cache) | 2 | 8, 9, 13 |
| 5 (Registry) | — | 7, 11 |
| 6 (Fixture) | — | 14 |
| 7 (Terminal runner) | 1, 5 | 10 |
| 8 (Project picker) | 1, 4 | 10 |
| 9 (Tasks picker) | 1, 4 | 10 |
| 10 (Chaining + cmds) | 1, 7, 8, 9 | 13 |
| 11 (NxTask cmds) | 1, 5, 7 | 13 |
| 12 (Health) | 3 | 13 |
| 13 (setup() wiring) | 1, 2, 4, 10, 11, 12 | 14 |
| 14 (QA scripts) | 6, 13 | F1-F4 |
| 15 (README) | 13 | F1 |
| F1-F4 | 14, 15 | user okay |

### Agent Dispatch Summary

| Wave | Tasks | Agent assignments |
|------|-------|-------------------|
| 1 | 6 | T1 → `quick`, T2 → `quick`, T3 → `quick`, T4 → `unspecified-low`, T5 → `unspecified-low`, T6 → `quick` |
| 2 | 6 | T7 → `unspecified-high`, T8 → `unspecified-low`, T9 → `unspecified-low`, T10 → `unspecified-low`, T11 → `unspecified-low`, T12 → `quick` |
| 3 | 3 | T13 → `quick`, T14 → `unspecified-high`, T15 → `writing` |
| FINAL | 4 | F1 → `oracle`, F2 → `unspecified-high`, F3 → `unspecified-high`, F4 → `deep` |

---

## TODOs

> Implementation + QA = ONE Task. Never separate.
> Every task MUST have: Recommended Agent Profile + Parallelization info + QA Scenarios.
> A task WITHOUT QA Scenarios is INCOMPLETE.

- [ ] 1. **Config schema extension**

  **What to do**:
  - Edit `lua/nx/config.lua`. Replace empty `default_config` with the v1 schema. Use snake_case throughout.
  - Add type alias `---@class (exact) nx.Config` fields:
    ```
    cli = {
      timeout_ms = 30000,           -- vim.system timeout for nx show calls
      env = {},                      -- table merged into spawn env
      workspace_root_env = 'NX_WORKSPACE_ROOT_PATH',  -- env var honored for explicit root
    }
    cache = {
      auto_invalidate = true,        -- BufWritePost autocmds enabled
      watch_files = { 'nx.json', 'project.json' },  -- glob patterns for invalidation
    }
    runner = {
      keymaps = {
        background = '<C-b>',        -- keybind inside terminal float
      },
      win = {},                      -- pass-through to Snacks.terminal `win` option
    }
    pickers = {
      preview = true,                -- enable JSON preview pane
    }
    ```
  - Keep existing `M.setup(opts)` deep-extend pattern. Remove `M.set_neotest_config` (it references nonexistent `M.neotest`; per draft, no Neotest support in scope).
  - Export `M.defaults()` returning a deep copy of `default_config` for use by `:checkhealth nx`.

  **Must NOT do**:
  - No additional config keys beyond the four sub-tables above.
  - No `cache.ttl_seconds`, no `runner.float_position`, no `pickers.formatter`.
  - No `vim.validate` calls inside `setup()` (just deep-merge).

  **Recommended Agent Profile**:
  - **Category**: `quick` — single small file, schema-only change.
  - **Skills**: `[]` — no domain skills required.
  - **Skills Evaluated but Omitted**: none considered.

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3, 4, 5, 6)
  - **Blocks**: 7, 8, 9, 11, 13
  - **Blocked By**: None — can start immediately

  **References**:

  *Pattern References*:
  - `lua/nx/config.lua:1-29` — existing `default_config` + `setup` + `vim.tbl_deep_extend('force', ...)` pattern. Match this exactly; just expand `default_config`.
  - `lua/nx/init.lua:21-31` — shows how `config.setup(opts)` is called from the plugin entry. Maintain that contract.

  *External References*:
  - lazy.nvim convention for `config = function(_, opts) require('nx').setup(opts) end`. Schema must accept partial overrides cleanly via `tbl_deep_extend`.

  **WHY each reference matters**:
  - `lua/nx/config.lua:1-29` — locks the file format and merge semantics; deviating breaks user setup contracts.

  **Acceptance Criteria** (agent-executable only):

  **QA Scenarios**:

  ```
  Scenario AC1-1: defaults() returns expected schema with no opts
    Tool: Bash (nvim --headless)
    Preconditions: clean repo
    Steps:
      1. Run: nvim --headless --noplugin -u tests/qa/minimal_init.lua \
           -c "lua local d=require('nx.config').defaults(); print(vim.inspect(d))" -c "qa!" \
           > .sisyphus/evidence/task-1-defaults.txt 2>&1
      2. grep -q 'cli = {' .sisyphus/evidence/task-1-defaults.txt
      3. grep -q 'cache = {' .sisyphus/evidence/task-1-defaults.txt
      4. grep -q 'runner = {' .sisyphus/evidence/task-1-defaults.txt
      5. grep -q 'pickers = {' .sisyphus/evidence/task-1-defaults.txt
      6. grep -q "background = '<C-b>'" .sisyphus/evidence/task-1-defaults.txt
    Expected Result: all greps exit 0
    Failure Indicators: any grep returns non-zero, or `print(vim.inspect(d))` errors
    Evidence: .sisyphus/evidence/task-1-defaults.txt

  Scenario AC1-2: setup() merges user opts deeply
    Tool: Bash (nvim --headless)
    Preconditions: clean repo
    Steps:
      1. Run: nvim --headless --noplugin -u tests/qa/minimal_init.lua \
           -c "lua require('nx').setup({ runner = { keymaps = { background = '<C-q>' } } }); print(require('nx.config').runner.keymaps.background); print(require('nx.config').cli.timeout_ms)" \
           -c "qa!" > .sisyphus/evidence/task-1-merge.txt 2>&1
      2. head -1 .sisyphus/evidence/task-1-merge.txt | grep -Fxq '<C-q>'
      3. sed -n '2p' .sisyphus/evidence/task-1-merge.txt | grep -Fxq '30000'
    Expected Result: user override takes effect (`<C-q>`), unspecified key keeps default (`30000`)
    Evidence: .sisyphus/evidence/task-1-merge.txt
  ```

  **Evidence to Capture**: `.sisyphus/evidence/task-1-defaults.txt`, `.sisyphus/evidence/task-1-merge.txt`

  **Commit**: YES (groups with self)
  - Message: `feat(config): extend default config schema for cli/cache/runner/pickers`
  - Files: `lua/nx/config.lua`
  - Pre-commit: run AC1-1 and AC1-2

- [ ] 2. **Workspace root detection**

  **What to do**:
  - Create `lua/nx/workspace.lua` exporting:
    - `M.find_root(start_dir?: string): string|nil` — walks up from `start_dir` (default: `vim.uv.cwd()`) looking for `nx.json`. Returns absolute path or `nil`.
    - `M.root(): string|nil` — convenience wrapper that honors `vim.env[require('nx.config').cli.workspace_root_env]` (default `NX_WORKSPACE_ROOT_PATH`) first, else calls `find_root()`. Caches per-cwd in a module-local table; `M.invalidate()` clears the cache.
    - `M.invalidate()` — clear the per-cwd memo.
  - Use `vim.fs.find('nx.json', { upward = true, path = start_dir, type = 'file' })` and take the first result; the workspace root is `vim.fs.dirname(result)`.
  - Always return absolute paths via `vim.fs.normalize(vim.fn.fnamemodify(p, ':p'))`.
  - Handle empty result, env-var-set-but-invalid (notify WARN once, fall through to walk-up).

  **Must NOT do**:
  - No fallback to `package.json` or `node_modules/nx`. `nx.json` is the marker.
  - No global state besides the per-cwd memo.
  - No `pcall` around `vim.fs.find` (it doesn't error).

  **Recommended Agent Profile**:
  - **Category**: `quick` — small focused module.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: 3, 4, 13
  - **Blocked By**: None

  **References**:

  *Pattern References*:
  - `lua/nx/init.lua:6-19` — lazy `__index` loader; the new module will be accessed as `require('nx').workspace`. Naming must match.

  *External References*:
  - `:help vim.fs.find` — exact API for upward search.
  - Nx workspace detection logic: `packages/nx/src/utils/workspace-root.ts:14-40` in nrwl/nx repo (commit `04ec111c88c0132d98dfc539db315bd84da50e94`). Replicate the "walk up to first `nx.json`" semantic, ignoring the older `node_modules/nx/package.json` fallback (Nx 16.3+ requirement makes `nx.json` reliable).

  **WHY each reference matters**:
  - The Nx source confirms `nx.json` is the canonical marker; eliminates ambiguity.
  - `vim.fs.find` is the modern Neovim idiom (replaces older `vim.fn.findfile` patterns).

  **QA Scenarios**:

  ```
  Scenario AC2-1: detect root from inside fixture workspace
    Tool: Bash (nvim --headless)
    Preconditions: tests/fixtures/sample-workspace/nx.json exists (Task 6 dependency — but for QA we create a temp fixture inline)
    Steps:
      1. mkdir -p /tmp/nxnvim-ws-test/apps/foo && echo '{}' > /tmp/nxnvim-ws-test/nx.json
      2. cd /tmp/nxnvim-ws-test/apps/foo && nvim --headless --noplugin -u $OLDPWD/tests/qa/minimal_init.lua \
           -c "lua print(require('nx.workspace').find_root())" -c "qa!" > $OLDPWD/.sisyphus/evidence/task-2-detect.txt 2>&1
      3. grep -Fxq '/tmp/nxnvim-ws-test' .sisyphus/evidence/task-2-detect.txt  (or `/private/tmp/...` on macOS — accept either)
    Expected Result: prints the temp workspace root absolute path
    Evidence: .sisyphus/evidence/task-2-detect.txt

  Scenario AC2-2: returns nil outside any workspace
    Tool: Bash (nvim --headless)
    Preconditions: a directory with no nx.json ancestor (use a fresh tmpdir)
    Steps:
      1. T=$(mktemp -d) && cd $T && nvim --headless --noplugin -u $OLDPWD/tests/qa/minimal_init.lua \
           -c "lua local r=require('nx.workspace').find_root(); print(r==nil and 'NIL' or r)" \
           -c "qa!" > $OLDPWD/.sisyphus/evidence/task-2-nil.txt 2>&1
      2. grep -Fxq 'NIL' .sisyphus/evidence/task-2-nil.txt
    Expected Result: prints NIL
    Evidence: .sisyphus/evidence/task-2-nil.txt

  Scenario AC2-3: env var overrides walk-up
    Tool: Bash (nvim --headless)
    Preconditions: any directory; NX_WORKSPACE_ROOT_PATH set to a real path containing nx.json
    Steps:
      1. mkdir -p /tmp/nxnvim-env && echo '{}' > /tmp/nxnvim-env/nx.json
      2. T=$(mktemp -d) && cd $T && NX_WORKSPACE_ROOT_PATH=/tmp/nxnvim-env nvim --headless --noplugin -u $OLDPWD/tests/qa/minimal_init.lua \
           -c "lua require('nx').setup({}); print(require('nx.workspace').root())" -c "qa!" \
           > $OLDPWD/.sisyphus/evidence/task-2-env.txt 2>&1
      3. grep -Fq '/tmp/nxnvim-env' .sisyphus/evidence/task-2-env.txt  (or `/private/...` variant)
    Expected Result: env var path returned
    Evidence: .sisyphus/evidence/task-2-env.txt
  ```

  **Commit**: YES — `feat(workspace): add workspace root detection` — files: `lua/nx/workspace.lua` — pre-commit: AC2-1, AC2-2, AC2-3

- [ ] 3. **CLI binary resolution + async exec**

  **What to do**:
  - Create `lua/nx/cli.lua` exporting:
    - `M.resolve_bin(workspace_root: string): string|nil` — returns `<root>/node_modules/.bin/nx` if exists, else `vim.fn.exepath('nx')` if non-empty, else `nil`. Memoized per workspace_root in module-local table.
    - `M.exec(args: string[], opts: { cwd: string, on_done: fun(result: { code: integer, stdout: string, stderr: string }) }): nil` — async wrapper around `vim.system`.
      - Uses table-form argv: `vim.system({bin, unpack(args)}, { cwd = opts.cwd, text = true, env = vim.tbl_extend('force', vim.fn.environ(), require('nx.config').cli.env), timeout = require('nx.config').cli.timeout_ms }, vim.schedule_wrap(function(obj) opts.on_done({ code = obj.code, stdout = obj.stdout or '', stderr = obj.stderr or '' }) end))`.
      - If `resolve_bin` returns nil: schedule `on_done({ code = -1, stdout = '', stderr = 'nx CLI not found (looked in node_modules/.bin and PATH)' })`.
      - On timeout: `vim.system` populates `obj.signal == 15` (or similar); pass through stderr.
    - `M.show_projects(workspace_root, on_done)` — convenience: calls `exec({'show', 'projects', '--json'}, { cwd = workspace_root, on_done })` and on success parses JSON; passes `{ ok = true, projects = string[] }` or `{ ok = false, error = string }`.
    - `M.show_project(workspace_root, name, on_done)` — convenience for `nx show project <name> --json`. On success: `{ ok = true, project = ProjectConfiguration }`.
  - JSON parsing via `vim.json.decode(stdout, { luanil = { object = true, array = true } })`. On parse error, return `{ ok = false, error = 'failed to parse nx JSON output: ' .. err }`.

  **Must NOT do**:
  - No `vim.fn.system`. No string command form. No shell quoting.
  - No `npx` fallback.
  - No retry on failure. No backoff.
  - No spinner / progress UI. (Picker callers handle "loading" state themselves if needed.)

  **Recommended Agent Profile**:
  - **Category**: `quick` — small focused module with clear API.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 1, but logically depends on Task 2 for workspace path — no code import yet, just used by callers in Wave 2)
  - **Parallel Group**: Wave 1
  - **Blocks**: 4 (cache wraps these calls), 12 (health uses `resolve_bin` + version check)
  - **Blocked By**: 2 (workspace) — but only at runtime; can be authored in parallel using interface-only

  **References**:

  *Pattern References*:
  - `:help vim.system` — modern async exec primitive (Neovim ≥ 0.10).
  - `:help vim.json.decode` — JSON parsing.

  *External References*:
  - `nx show projects --json` output: `string[]`. Source: `packages/nx/src/command-line/show/projects.ts:81` in nrwl/nx repo (`04ec111c`).
  - `nx show project <name> --json` output: `ProjectConfiguration` JSON. Source: `packages/nx/src/command-line/show/project.ts:70-71` in nrwl/nx repo. Type: `packages/nx/src/config/workspace-json-project-json.ts:48-131`.

  **WHY each reference matters**:
  - Locking the JSON shapes against the Nx source ensures parser code matches reality.
  - `vim.system` table-argv form prevents shell-injection issues from project paths with spaces.

  **QA Scenarios**:

  ```
  Scenario AC3-1: resolve_bin returns local node_modules/.bin/nx when present
    Tool: Bash (nvim --headless)
    Preconditions: tmp dir with node_modules/.bin/nx (create as no-op script)
    Steps:
      1. T=$(mktemp -d) && mkdir -p $T/node_modules/.bin && printf '#!/usr/bin/env bash\necho fake\n' > $T/node_modules/.bin/nx && chmod +x $T/node_modules/.bin/nx
      2. cd $T && nvim --headless --noplugin -u $OLDPWD/tests/qa/minimal_init.lua \
           -c "lua print(require('nx.cli').resolve_bin(vim.uv.cwd()))" -c "qa!" \
           > $OLDPWD/.sisyphus/evidence/task-3-resolve.txt 2>&1
      3. grep -Eq 'node_modules/\.bin/nx$' .sisyphus/evidence/task-3-resolve.txt
    Expected Result: prints the local nx path
    Evidence: .sisyphus/evidence/task-3-resolve.txt

  Scenario AC3-2: exec invokes vim.system with table argv
    Tool: Bash (nvim --headless) — uses a stub
    Preconditions: cli module loaded; vim.system stubbed to capture args
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua \
           -c "luafile tests/qa/AC3-2.lua" -c "qa!" > .sisyphus/evidence/task-3-exec.txt 2>&1
      2. The QA script (tests/qa/AC3-2.lua) replaces vim.system with a capture function, calls require('nx.cli').exec({'show','projects','--json'}, { cwd='/tmp', on_done=function(r) end }), then asserts the captured argv[1] ends with 'nx' and argv[2..] equals {'show','projects','--json'}, and the cwd opt is '/tmp'. On pass, writes 'PASS: AC3-2' to evidence file.
    Expected Result: evidence file ends with 'PASS: AC3-2'
    Evidence: .sisyphus/evidence/task-3-exec.txt

  Scenario AC3-3: show_projects parses fixture JSON output
    Tool: Bash (nvim --headless) — stub vim.system to return canned JSON
    Preconditions: stub replaces vim.system to invoke on_exit immediately with { code=0, stdout='["alpha","beta"]', stderr='' }
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua \
           -c "luafile tests/qa/AC3-3.lua" -c "qa!" > .sisyphus/evidence/task-3-parse.txt 2>&1
      2. The QA script asserts the on_done callback received { ok = true, projects = { 'alpha', 'beta' } }
      3. Writes 'PASS: AC3-3' to evidence file
    Expected Result: PASS line present
    Evidence: .sisyphus/evidence/task-3-parse.txt

  Scenario AC3-4: show_projects surfaces parse errors gracefully (failure scenario)
    Tool: Bash (nvim --headless) — stub returns invalid JSON
    Preconditions: stub returns { code=0, stdout='not json', stderr='' }
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC3-4.lua" -c "qa!" \
           > .sisyphus/evidence/task-3-parse-err.txt 2>&1
      2. QA script asserts on_done received { ok = false, error = string-containing-'parse' }, writes PASS line
    Expected Result: PASS line present
    Evidence: .sisyphus/evidence/task-3-parse-err.txt
  ```

  **Commit**: YES — `feat(cli): add async nx CLI exec with binary resolution` — files: `lua/nx/cli.lua` — pre-commit: AC3-1..AC3-4

- [ ] 4. **Cache module with in-flight dedup**

  **What to do**:
  - Create `lua/nx/cache.lua` exporting:
    - `M.get_projects(workspace_root, on_done)` — if cached, calls `on_done({ ok=true, projects=...})` synchronously via `vim.schedule`. Else if a request for this root is in-flight, queues `on_done` to fire when the in-flight request completes. Else dispatches `cli.show_projects(...)`, stores result in cache and resolves all queued callbacks.
    - `M.get_project(workspace_root, name, on_done)` — same pattern keyed by `(workspace_root, name)`.
    - `M.invalidate(workspace_root?: string)` — if `workspace_root` given: clear that root's entry. If nil: clear all.
    - `M.state()` — test helper, returns the internal cache table (deep copy).
    - `M.attach_autocmds()` — creates a `BufWritePost` autocmd group `nx.cache` that fires for patterns from `config.cache.watch_files`. Inside the callback, resolves the workspace root from the saved file's directory and calls `M.invalidate(root)`.
  - Cache shape:
    ```
    cache = {
      [workspace_root] = {
        projects = string[]?,        -- from `nx show projects`
        project_configs = { [name] = ProjectConfiguration },  -- from `nx show project <name>`
        fetched_at = number,         -- vim.uv.now() at last full refresh
      }
    }
    inflight = {
      ['projects::' .. ws_root] = { callbacks = { fn, ... } },
      ['project::' .. ws_root .. '::' .. name] = { callbacks = { fn, ... } },
    }
    ```

  **Must NOT do**:
  - No TTL. No background refresh. No prefetch.
  - No file-system watcher beyond `BufWritePost` autocmd.
  - No persistent disk cache.
  - No global cache mutex; rely on Neovim's single-thread Lua model + in-flight dedup.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low` — straightforward but careful state machine.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: 8, 9, 13
  - **Blocked By**: 2, 3 (interface only — can author in parallel against the documented contract)

  **References**:

  *Pattern References*:
  - `lua/nx/init.lua:6-19` — module accessed as `require('nx').cache`. Naming match required.
  - `:help nvim_create_autocmd`, `:help BufWritePost`.

  **QA Scenarios**:

  ```
  Scenario AC4-1: cache hit returns synchronously from second call
    Tool: Bash (nvim --headless) — stub cli.show_projects with a counter
    Preconditions: stub increments a counter each invocation
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC4-1.lua" -c "qa!" \
           > .sisyphus/evidence/task-4-hit.txt 2>&1
      2. QA script: call get_projects twice in series, assert counter == 1 (only first call hit CLI), assert both callbacks received same projects table; writes PASS
    Expected Result: PASS line; counter == 1
    Evidence: .sisyphus/evidence/task-4-hit.txt

  Scenario AC4-2: in-flight dedup — two rapid calls share one CLI invocation
    Tool: Bash (nvim --headless) — stub defers cli.show_projects via vim.defer_fn
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC4-2.lua" -c "qa!" \
           > .sisyphus/evidence/task-4-dedup.txt 2>&1
      2. QA script: stub captures call count; calls get_projects twice synchronously without awaiting; assert counter == 1; assert both callbacks fire after the deferred resolution; writes PASS
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-4-dedup.txt

  Scenario AC4-3: invalidate(root) clears entry, next call re-fetches
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC4-3.lua" -c "qa!" \
           > .sisyphus/evidence/task-4-invalidate.txt 2>&1
      2. QA script: get_projects, then invalidate(root), then get_projects again; assert counter increments to 2; PASS
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-4-invalidate.txt

  Scenario AC4-4: BufWritePost on nx.json triggers invalidation (failure path: missing file)
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC4-4.lua" -c "qa!" \
           > .sisyphus/evidence/task-4-autocmd.txt 2>&1
      2. QA script: in fixture workspace, get_projects, manually fire `BufWritePost` for `nx.json` via `nvim_exec_autocmds`, then assert cache.state()[root] == nil; PASS
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-4-autocmd.txt
  ```

  **Commit**: YES — `feat(cache): per-workspace in-memory cache with autocmd invalidation` — files: `lua/nx/cache.lua` — pre-commit: AC4-1..AC4-4

- [ ] 5. **Registry module with self-healing**

  **What to do**:
  - Create `lua/nx/registry.lua` exporting:
    - Internal table `entries = {}` keyed by string key `<workspace_root>::<project>::<task>`.
    - `M.key(workspace_root, project, task): string` — canonical key formatter.
    - `M.put(workspace_root, project, task, entry): nil` — insert/replace. `entry` shape:
      ```
      {
        workspace_root: string,
        project: string,
        task: string,
        terminal: snacks.win|nil,    -- nil after task exits and buffer is dumped
        bufnr: integer|nil,           -- live terminal bufnr while running
        job_id: integer|nil,
        status: 'running'|'exited',
        exit_code: integer|nil,
        output_file: string|nil,      -- temp file path after exit
        started_at: integer,          -- vim.uv.now()
        exited_at: integer|nil,
      }
      ```
    - `M.get(workspace_root, project, task): entry|nil`
    - `M.remove(workspace_root, project, task): nil` — also deletes `output_file` from disk (`os.remove`) if present, and tries `pcall(vim.api.nvim_buf_delete, bufnr, {force=true})` if buffer still valid.
    - `M.list(workspace_root?): entry[]` — when `workspace_root` given, filter to that root; else all. Sorted by `started_at` desc.
    - `M.find_running(workspace_root?): entry[]` — only entries with `status == 'running'`.
    - `M.attach_self_healing(): nil` — creates `BufWipeout` autocmd; on wipeout of any bufnr present in the registry, marks the entry's `terminal = nil`, `bufnr = nil`, and if `status == 'running'`, set `status = 'exited'`, `exit_code = -1`, `exited_at = now`. Does NOT delete the entry.
    - `M.state()` — test helper returning a deep copy of `entries`.
    - `M.clear()` — test helper, removes all entries (calls `M.remove` for each to clean up tempfiles).

  **Must NOT do**:
  - No `VimLeavePre` cleanup. Neovim's child-job kill is sufficient.
  - No persistent registry across sessions.
  - No global event emission. Callers query state directly.
  - No automatic exit-detection — the terminal module (Task 7) is responsible for transitioning entries to `exited` and dumping output. Self-healing autocmd is only for externally-induced bufwipes.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low` — careful state machine + autocmd.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: 7, 11
  - **Blocked By**: None

  **References**:

  *Pattern References*:
  - `:help BufWipeout`
  - `lua/nx/init.lua:6-19` — module access pattern.

  **QA Scenarios**:

  ```
  Scenario AC5-1: put/get/list round-trip
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC5-1.lua" -c "qa!" \
           > .sisyphus/evidence/task-5-crud.txt 2>&1
      2. QA script: put two entries (different keys), assert get returns each, assert list returns both sorted by started_at desc; PASS
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-5-crud.txt

  Scenario AC5-2: BufWipeout self-heals running entry
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC5-2.lua" -c "qa!" \
           > .sisyphus/evidence/task-5-heal.txt 2>&1
      2. QA script: attach_self_healing(); create scratch buffer; put entry with that bufnr and status='running'; nvim_buf_delete(bufnr,{force=true}); assert get returns entry with status='exited', exit_code=-1, terminal=nil, bufnr=nil; PASS
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-5-heal.txt

  Scenario AC5-3: remove cleans up output_file (failure path: tempfile gone)
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC5-3.lua" -c "qa!" \
           > .sisyphus/evidence/task-5-remove.txt 2>&1
      2. QA script: write a real tempfile via vim.fn.tempname()+writefile; put entry with output_file pointing at it; remove(); assert vim.fn.filereadable(path)==0; entry not in get; PASS. Also: pre-delete the tempfile, then remove() — assert no error.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-5-remove.txt
  ```

  **Commit**: YES — `feat(registry): backgrounded task registry with BufWipeout self-healing` — files: `lua/nx/registry.lua` — pre-commit: AC5-1..AC5-3

- [ ] 6. **Test fixture workspace**

  **What to do**:
  - Create `tests/fixtures/sample-workspace/` with the following files:

    `tests/fixtures/sample-workspace/nx.json`:
    ```json
    {
      "$schema": "./node_modules/nx/schemas/nx-schema.json",
      "namedInputs": { "default": ["{projectRoot}/**/*"] }
    }
    ```

    `tests/fixtures/sample-workspace/package.json`:
    ```json
    { "name": "nx-nvim-fixture", "version": "0.0.0", "private": true, "devDependencies": { "nx": "^18.0.0" } }
    ```

    `tests/fixtures/sample-workspace/apps/alpha/project.json`:
    ```json
    {
      "name": "alpha",
      "root": "apps/alpha",
      "sourceRoot": "apps/alpha/src",
      "projectType": "application",
      "tags": ["scope:app"],
      "targets": {
        "build": { "executor": "nx:run-commands", "options": { "command": "echo alpha-build" } },
        "serve": { "executor": "nx:run-commands", "options": { "command": "echo alpha-serve" } }
      }
    }
    ```

    `tests/fixtures/sample-workspace/libs/beta/project.json`:
    ```json
    {
      "name": "beta",
      "root": "libs/beta",
      "sourceRoot": "libs/beta/src",
      "projectType": "library",
      "tags": ["scope:lib"],
      "targets": {
        "build": { "executor": "nx:run-commands", "options": { "command": "echo beta-build" } },
        "test":  { "executor": "nx:run-commands", "options": { "command": "echo beta-test" } }
      }
    }
    ```

  - Create `tests/fixtures/canned/`:
    - `show-projects.json` containing `["alpha","beta"]`
    - `show-project-alpha.json` containing the contents of `apps/alpha/project.json`
    - `show-project-beta.json` containing the contents of `libs/beta/project.json`
  - These canned files are used by stub-based QA scripts that don't actually invoke `nx`.

  **Must NOT do**:
  - No `node_modules/`. No actual npm install. The fixture is intentionally inert; canned outputs are provided separately.
  - No tests/ files outside of `fixtures/` and `qa/` (added in Task 14).

  **Recommended Agent Profile**:
  - **Category**: `quick` — file creation only.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: 14
  - **Blocked By**: None

  **References**:

  *External References*:
  - Nx project.json schema: `packages/nx/src/config/workspace-json-project-json.ts:48-131` in nrwl/nx repo (`04ec111c`).
  - `nx show projects --json` returns string array; `nx show project <name> --json` returns ProjectConfiguration JSON.

  **QA Scenarios**:

  ```
  Scenario AC6-1: fixture files exist and parse as valid JSON
    Tool: Bash
    Steps:
      1. for f in tests/fixtures/sample-workspace/nx.json \
                 tests/fixtures/sample-workspace/package.json \
                 tests/fixtures/sample-workspace/apps/alpha/project.json \
                 tests/fixtures/sample-workspace/libs/beta/project.json \
                 tests/fixtures/canned/show-projects.json \
                 tests/fixtures/canned/show-project-alpha.json \
                 tests/fixtures/canned/show-project-beta.json; do
           test -f "$f" || { echo "MISSING $f"; exit 1; }
           python3 -c "import json,sys; json.load(open('$f'))" || exit 1
         done
         echo OK > .sisyphus/evidence/task-6-fixture.txt
      2. test -s .sisyphus/evidence/task-6-fixture.txt
    Expected Result: All files exist; all parse as JSON
    Evidence: .sisyphus/evidence/task-6-fixture.txt

  Scenario AC6-2: canned show-projects matches workspace projects (sanity)
    Tool: Bash + python
    Steps:
      1. python3 -c "
import json
proj = json.load(open('tests/fixtures/canned/show-projects.json'))
assert proj == ['alpha','beta'], proj
print('OK')
" > .sisyphus/evidence/task-6-canned.txt
      2. grep -Fxq 'OK' .sisyphus/evidence/task-6-canned.txt
    Expected Result: OK
    Evidence: .sisyphus/evidence/task-6-canned.txt
  ```

  **Commit**: YES — `test(fixture): add sample Nx workspace fixture` — files: `tests/fixtures/**` — pre-commit: AC6-1, AC6-2

- [ ] 7. **Terminal runner (Snacks integration + temp-file dump)**

  **What to do**:
  - Create `lua/nx/terminal.lua` exporting:
    - `M.run(workspace_root, project, task): nil` — main entry point.
      1. Soft-dep check: `local ok, snacks = pcall(require, 'snacks')`. If not ok: `vim.notify('nx.nvim: Snacks.nvim is required to run tasks (folke/snacks.nvim).', vim.log.levels.ERROR)` and return.
      2. Look up registry entry for `(workspace_root, project, task)`.
         - If exists with `status == 'running'` and `terminal:buf_valid()`: call `terminal:show():focus()` and return (foreground existing).
         - If exists with `status == 'exited'`: remove the existing entry first (this deletes the temp file), then proceed to spawn fresh.
         - If exists but terminal/buf invalid: remove and proceed.
      3. Resolve `bin = require('nx.cli').resolve_bin(workspace_root)`. If nil: notify ERROR and return.
      4. Build cmd: `{ bin, 'run', project .. ':' .. task }`.
      5. Open Snacks terminal:
         ```lua
         local term = Snacks.terminal(cmd, vim.tbl_deep_extend('force', {
           cwd = workspace_root,
           interactive = true,
           auto_close = false,
           win = vim.tbl_deep_extend('force', { position = 'float', style = 'terminal' }, require('nx.config').runner.win or {}),
         }, {}))
         ```
      6. Capture `bufnr = term.buf`. Capture `job_id = vim.b[bufnr].terminal_job_id` (set by Neovim's terminal mode after `termopen`).
      7. Insert registry entry: `registry.put(workspace_root, project, task, { ..., terminal=term, bufnr=bufnr, job_id=job_id, status='running', started_at=vim.uv.now() })`.
      8. Set buffer-local keymap inside the terminal float for `config.runner.keymaps.background` (default `<C-b>`) in both `t` (terminal) and `n` (normal) modes; the keymap calls `M.background(workspace_root, project, task)`.
      9. Attach `vim.api.nvim_create_autocmd('TermClose', { buffer = bufnr, callback = function(args) M._on_exit(workspace_root, project, task, args.data) end })`. (`args.data` contains the exit code in newer Neovim; fallback to `vim.v.event.status` if needed.)
    - `M.background(workspace_root, project, task): nil` — look up entry; if found and `terminal:win_valid()`, call `terminal:hide()`. Otherwise notify (no-op).
    - `M.foreground(workspace_root, project, task): nil` —
      - If entry not found: notify WARN.
      - If `status == 'running'` and `terminal:buf_valid()`: `terminal:show():focus()`.
      - If `status == 'exited'` and `output_file` readable: open the temp file in a Snacks-styled scratch buffer using `Snacks.win({ file = entry.output_file, win = { style = 'float' } })` (or fallback `vim.api.nvim_open_win` if `Snacks.win` not preferred — implementer choice; document the chosen call in source comment).
      - If `status == 'exited'` and `output_file` missing: notify ERROR and remove entry.
    - `M.kill(workspace_root, project, task): nil` —
      - If entry not found: notify WARN.
      - If `status == 'running'` and job_id valid: `vim.fn.jobstop(job_id)`. The `TermClose` autocmd will fire and transition to `exited`. Then call `registry.remove(...)` to clean up output (don't dump on kill — kill is destructive).
      - If `status == 'exited'`: just `registry.remove(...)`.
    - `M._on_exit(workspace_root, project, task, exit_code): nil` —
      - Read entry; if missing, return (already cleaned up).
      - Read all lines from the live terminal buffer via `vim.api.nvim_buf_get_lines(entry.bufnr, 0, -1, false)`.
      - Filter trailing blank lines.
      - Write to `tmp = vim.fn.tempname() .. '.nx-task.txt'` via `vim.fn.writefile(lines, tmp)`.
      - Update entry: `terminal=nil`, `bufnr=nil`, `job_id=nil`, `status='exited'`, `exit_code=exit_code`, `output_file=tmp`, `exited_at=vim.uv.now()`.
      - Schedule `pcall(vim.api.nvim_buf_delete, old_bufnr, { force = true })` (this also closes the Snacks float if still visible).
      - `vim.notify(string.format('nx: %s:%s exited (code %d). Use :NxTask foreground %s:%s to view output.', project, task, exit_code, project, task), exit_code == 0 and vim.log.levels.INFO or vim.log.levels.WARN)`.

  **Must NOT do**:
  - No string-form cmd. Pass `{ bin, 'run', 'project:task' }` as table.
  - No global keymaps — only buffer-local inside the float.
  - No tmpfile cleanup at exit time (must persist for foregrounding).
  - No `auto_close = true` — buffer must persist long enough for `_on_exit` to dump.
  - No automatic re-run on exit; no watch mode wrapper.
  - No restart keybind.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — orchestrates Snacks API + registry state + autocmds + tempfile lifecycle. Most complex single module.
  - **Skills**: `[]` — no domain skill applies; standard Neovim plumbing.

  **Parallelization**:
  - **Can Run In Parallel**: YES (within Wave 2)
  - **Parallel Group**: Wave 2
  - **Blocks**: 10, 11
  - **Blocked By**: 1 (config), 5 (registry)

  **References**:

  *Pattern References*:
  - Snacks lazygit invocation pattern: `lua/snacks/lazygit.lua:192-207` in folke/snacks.nvim repo (`ad9ede6a`) — shows the canonical `Snacks.terminal(cmd, opts)` call with no special lifecycle.
  - `lua/snacks/win.lua:619-622` — `hide()` keeps buffer + job alive (the backgrounding primitive).
  - `lua/snacks/win.lua:819-938` — `show()` recreates the window pointing at the kept buffer.
  - `lua/snacks/terminal.lua:138-147` — `auto_close` semantics.
  - `:help TermClose` — exit-code event (`vim.v.event.status` historically; newer Neovim uses callback `args.data`).

  *Type/API References*:
  - `Snacks.terminal(cmd: string|string[], opts?): snacks.win` — see Research Findings in plan Context.
  - Registry contract from Task 5.

  **WHY each reference matters**:
  - The Snacks `hide()` vs `close()` distinction is THE central correctness invariant for backgrounding.
  - `TermClose` is the only reliable exit hook that fires before Neovim discards the buffer.

  **QA Scenarios**:

  ```
  Scenario AC7-1: run() opens Snacks terminal with correct cmd table form
    Tool: Bash (nvim --headless) — stub Snacks.terminal
    Preconditions: stub captures (cmd, opts) and returns a fake win object with hide/show/focus/buf_valid/win_valid methods returning true
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC7-1.lua" -c "qa!" \
           > .sisyphus/evidence/task-7-run.txt 2>&1
      2. QA script: stub package.preload.snacks (or override loaded module). stub `cli.resolve_bin` to return '/fake/nx'. Call terminal.run('/ws','alpha','build'). Assert captured cmd == { '/fake/nx', 'run', 'alpha:build' }, cwd == '/ws', interactive == true, auto_close == false; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-7-run.txt

  Scenario AC7-2: re-running active task foregrounds existing terminal
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC7-2.lua" -c "qa!" \
           > .sisyphus/evidence/task-7-rerun.txt 2>&1
      2. QA script: stub Snacks.terminal as a counter. Call run() twice; assert counter == 1 and that the fake terminal's show()+focus() were called on the second invocation; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-7-rerun.txt

  Scenario AC7-3: background() calls hide(), foreground() calls show():focus()
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC7-3.lua" -c "qa!" \
           > .sisyphus/evidence/task-7-bg.txt 2>&1
      2. QA script: stub terminal with hide/show/focus call counters; run(); background(); assert hide called once; foreground(); assert show called once and focus called once; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-7-bg.txt

  Scenario AC7-4: TermClose dumps buffer to tempfile and updates registry
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC7-4.lua" -c "qa!" \
           > .sisyphus/evidence/task-7-exit.txt 2>&1
      2. QA script: replace Snacks.terminal with a stub that creates a real scratch buffer with three lines ('line A','line B','line C'); call run(); manually invoke terminal._on_exit (or fire TermClose autocmd) with exit_code=0; assert registry entry status='exited', exit_code=0, output_file is a readable file containing those three lines; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-7-exit.txt

  Scenario AC7-5: foreground() of exited task opens output file in float (failure path: tempfile missing)
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC7-5.lua" -c "qa!" \
           > .sisyphus/evidence/task-7-fg-exited.txt 2>&1
      2. QA script (happy): put exited entry with a real readable tempfile; foreground(); assert a buffer exists whose contents match the tempfile lines; PASS-1. (failure): put exited entry with output_file='/nonexistent/path'; foreground(); assert vim.notify called with ERROR level and message containing 'output' and that registry entry was removed; PASS-2.
    Expected Result: both PASS lines present
    Evidence: .sisyphus/evidence/task-7-fg-exited.txt

  Scenario AC7-6: kill() running task calls jobstop and removes entry
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC7-6.lua" -c "qa!" \
           > .sisyphus/evidence/task-7-kill.txt 2>&1
      2. QA script: stub vim.fn.jobstop to record calls; put running entry with fake job_id=42; kill(); assert jobstop called with 42; eventually entry removed (after _on_exit fires; for the stub, simulate by calling _on_exit directly post-jobstop); PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-7-kill.txt
  ```

  **Commit**: YES — `feat(terminal): Snacks runner with background/foreground + temp-file dump` — files: `lua/nx/terminal.lua` — pre-commit: AC7-1..AC7-6

- [ ] 8. **fzf-lua project picker**

  **What to do**:
  - Create `lua/nx/pickers.lua` (initial scaffold; Task 9 extends).
  - Export `M.projects(workspace_root, on_select): nil`:
    1. Soft-dep check: `local ok, fzf = pcall(require, 'fzf-lua')`. If not ok: notify ERROR and return.
    2. Resolve `workspace_root` (caller passes; if nil, derive via `require('nx.workspace').root()`; if still nil notify WARN "Not in an Nx workspace" and return).
    3. Call `cache.get_projects(workspace_root, function(result) ... end)`:
       - If `result.ok == false`: notify ERROR with `result.error` and return.
       - If `result.projects` is empty: notify WARN "No projects in workspace" and return.
       - Else `vim.schedule(function() open_picker(result.projects) end)`.
    4. `open_picker(projects)`:
       ```lua
       fzf.fzf_exec(projects, {
         prompt = 'Nx Projects> ',
         previewer = require('nx.config').pickers.preview and {
           fn = function(items) -- items[1] is the highlighted project name
             local name = items[1]
             local lines = { 'Loading...' }
             cache.get_project(workspace_root, name, function(r)
               if r.ok then
                 lines = vim.split(vim.json.encode(r.project), '\n', { plain = true })
                 -- format: pretty-print
                 lines = vim.split(vim.fn.system({'jq','.'}, table.concat(lines, '\n')) or table.concat(lines,'\n'), '\n', { plain = true })
               else
                 lines = { 'error: ' .. (r.error or 'unknown') }
               end
             end)
             return table.concat(lines, '\n')
           end,
           field_index = '{}',
         } or nil,
         actions = {
           ['default'] = function(selected, opts)
             local _, entries = require('fzf-lua.actions').normalize_selected(selected, opts)
             local project_name = entries[1]
             if project_name and on_select then
               vim.schedule(function() on_select(project_name) end)
             end
           end,
         },
       })
       ```
    - Note: the previewer's async cache.get_project is approximate — fzf-lua previewer expects a synchronous return. **Implementation guidance**: cache MUST be hot when previewing; rely on cache.get_project being a synchronous cache hit after the projects list loads. If miss, return placeholder lines ("Loading...") and the user can re-trigger by moving cursor. (Real implementation may pre-warm by fetching all project configs in parallel after `get_projects` resolves — a Wave-2 optimization the implementer can choose.)
    - **Pretty-printing**: prefer `vim.json.encode` then pretty-format via Lua (no shell `jq` dependency). Use a tiny pretty-printer or `vim.inspect` as a fallback. **Decision locked**: use `vim.json.encode` + a small pure-Lua pretty-printer in `M._pretty(json_string)`. No `jq` shellout. Rewrite the snippet above accordingly during implementation.

  **Must NOT do**:
  - No `jq` shellout despite the snippet above showing it (snippet was illustrative; actual code uses pure-Lua pretty-print).
  - No tab-completion of project names for the picker.
  - No project filtering UI (rely on fzf's built-in fuzzy filter).
  - No cross-picker state — chaining is Task 10.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low` — direct fzf-lua API integration.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 7, 9, 11, 12 in Wave 2)
  - **Parallel Group**: Wave 2
  - **Blocks**: 10
  - **Blocked By**: 1, 4

  **References**:

  *Pattern References*:
  - fzf-lua `fzf_exec(contents, opts)`: `lua/fzf-lua/core.lua:156-167` in ibhagwan/fzf-lua (`ffa44ee`).
  - fzf-lua `actions.normalize_selected`: `lua/fzf-lua/actions.lua:67-108` (handles keybind-prefixed selections on fzf ≥ 0.53).
  - fzf-lua custom previewer pattern: `lua/fzf-lua/previewer/init.lua:94-112`.

  **WHY each reference matters**:
  - `normalize_selected` is required for correctness on modern fzf — without it, `selected[1]` is the keybind name, not the entry.
  - The previewer signature `function(items) return string end` is the simplest path; documented and stable.

  **QA Scenarios**:

  ```
  Scenario AC8-1: projects() invokes fzf_exec with projects from cache
    Tool: Bash (nvim --headless) — stub fzf-lua and cache
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC8-1.lua" -c "qa!" \
           > .sisyphus/evidence/task-8-fzf.txt 2>&1
      2. QA script: stub fzf-lua's fzf_exec to capture (contents, opts); stub cache.get_projects to invoke callback synchronously with { ok=true, projects={'alpha','beta'} }; call pickers.projects('/ws', function() end); assert captured contents == {'alpha','beta'} and opts.prompt matches 'Nx Projects'; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-8-fzf.txt

  Scenario AC8-2: missing fzf-lua produces helpful error (failure path)
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC8-2.lua" -c "qa!" \
           > .sisyphus/evidence/task-8-no-fzf.txt 2>&1
      2. QA script: ensure require('fzf-lua') fails (set package.preload['fzf-lua']=function() error('not installed') end); stub vim.notify to capture; call pickers.projects('/ws', noop); assert notify called with ERROR level and message containing 'fzf-lua'; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-8-no-fzf.txt

  Scenario AC8-3: empty workspace shows warning, no picker opened
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC8-3.lua" -c "qa!" \
           > .sisyphus/evidence/task-8-empty.txt 2>&1
      2. QA script: stub fzf-lua's fzf_exec to count invocations; stub cache.get_projects to return { ok=true, projects={} }; stub vim.notify; call projects('/ws', noop); assert fzf_exec count == 0 AND notify called with WARN containing 'No projects'; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-8-empty.txt

  Scenario AC8-4: enter action invokes on_select with project name (handles normalize_selected)
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC8-4.lua" -c "qa!" \
           > .sisyphus/evidence/task-8-select.txt 2>&1
      2. QA script: stub fzf_exec to capture opts.actions then immediately invoke opts.actions.default({ 'alpha' }, {}); pass on_select that records its arg; stub cache.get_projects with non-empty result; call projects(); assert on_select received 'alpha'; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-8-select.txt
  ```

  **Commit**: YES — `feat(pickers): fzf-lua project picker with project.json preview` — files: `lua/nx/pickers.lua` (initial) — pre-commit: AC8-1..AC8-4

- [ ] 9. **fzf-lua tasks picker**

  **What to do**:
  - Extend `lua/nx/pickers.lua` with `M.tasks(workspace_root, project, on_select): nil`:
    1. Soft-dep check (same pattern as `M.projects`).
    2. `cache.get_project(workspace_root, project, function(result) ... end)`:
       - On `result.ok == false`: notify ERROR with `result.error` and return.
       - Read `targets = result.project.targets or {}`. Build sorted list of task names: `task_names = vim.tbl_keys(targets); table.sort(task_names)`.
       - If empty: notify WARN `"No tasks for project " .. project` and return.
       - `vim.schedule(function() open_picker(task_names, targets) end)`.
    3. `open_picker(task_names, targets)`:
       ```lua
       fzf.fzf_exec(task_names, {
         prompt = string.format('Nx Tasks (%s)> ', project),
         previewer = require('nx.config').pickers.preview and {
           fn = function(items)
             local task_name = items[1]
             local target = targets[task_name]
             if not target then return 'no task config' end
             return M._pretty(vim.json.encode(target))
           end,
           field_index = '{}',
         } or nil,
         actions = {
           ['default'] = function(selected, opts)
             local _, entries = require('fzf-lua.actions').normalize_selected(selected, opts)
             local task_name = entries[1]
             if task_name and on_select then
               vim.schedule(function() on_select(task_name) end)
             end
           end,
         },
       })
       ```
  - Implement `M._pretty(json_string): string` — pure-Lua JSON pretty-printer producing newline-separated output with 2-space indent. Acceptable simple approach: `vim.json.decode(json_string)` → traverse → emit. Or even simpler: use `vim.inspect(vim.json.decode(json_string), { newline = '\n', indent = '  ' })` and accept Lua-table-syntax preview (acceptable per "raw JSON pretty-print" guardrail loosened to "structured pretty-print"; document in source comment that `vim.inspect` produces Lua-table syntax for readability since pure-Lua JSON pretty-print is non-trivial). **Decision**: `vim.inspect`-based pretty-print is acceptable; a future PR can swap to JSON-strict if requested.

  **Must NOT do**:
  - No tab-completion of task names.
  - No task filtering by configuration (configurations are OUT of scope).
  - No multi-select (single task only).

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2
  - **Blocks**: 10
  - **Blocked By**: 1, 4 (and edits the file Task 8 created — implementer must coordinate by treating Task 8+9 as a single PR if needed; for git history we keep them separate commits but executed serially within this wave step. **Update**: re-classify as serial-after-8 in execution if file conflicts arise; no functional dependency, just a textual one.)

  **References**:

  *Pattern References*:
  - Same fzf-lua references as Task 8 (file:line).
  - `:help vim.json.decode`, `:help vim.inspect`.

  **QA Scenarios**:

  ```
  Scenario AC9-1: tasks() lists targets sorted from cache
    Tool: Bash (nvim --headless) — stub fzf_exec + cache.get_project
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC9-1.lua" -c "qa!" \
           > .sisyphus/evidence/task-9-list.txt 2>&1
      2. QA script: stub get_project to return { ok=true, project={ targets={ build={}, serve={}, test={} } } }; stub fzf_exec to capture contents; call tasks('/ws','alpha', noop); assert captured contents == {'build','serve','test'}; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-9-list.txt

  Scenario AC9-2: project with no targets warns and skips picker (failure)
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC9-2.lua" -c "qa!" \
           > .sisyphus/evidence/task-9-empty.txt 2>&1
      2. QA script: stub get_project to return { ok=true, project={ targets={} } }; stub vim.notify to capture; call tasks('/ws','alpha', noop); assert notify WARN with 'No tasks for project alpha' and fzf_exec NOT called; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-9-empty.txt

  Scenario AC9-3: previewer returns formatted target config
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC9-3.lua" -c "qa!" \
           > .sisyphus/evidence/task-9-preview.txt 2>&1
      2. QA script: stub get_project with one target { build={ executor='nx:run-commands', options={ command='echo hi' } } }; stub fzf_exec to capture opts and invoke opts.previewer.fn({'build'}); assert returned string contains 'nx:run-commands' and 'echo hi'; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-9-preview.txt
  ```

  **Commit**: YES — `feat(pickers): fzf-lua tasks picker with task config preview` — files: `lua/nx/pickers.lua` (extended) — pre-commit: AC9-1..AC9-3

- [ ] 10. **Picker chaining + main commands integration**

  **What to do**:
  - Create `lua/nx/commands.lua` (initial — Task 11 extends).
  - Implement private helpers:
    - `M._with_workspace(fn)` — resolves workspace root via `require('nx.workspace').root()`; if nil, notify WARN "Not in an Nx workspace" and return; else call `fn(root)`.
  - Implement public commands:
    - `M.nx_project()` — calls `M._with_workspace(function(root) require('nx.pickers').projects(root, function(project_name) M.nx_project_tasks(project_name) end) end)`.
    - `M.nx_project_tasks(project_name?)` —
      - If `project_name` given: call `M._with_workspace(function(root) require('nx.pickers').tasks(root, project_name, function(task_name) require('nx.terminal').run(root, project_name, task_name) end) end)`.
      - If nil: invoke `M.nx_project()` (which chains to tasks picker after project selection).
    - `M.nx_refresh()` — calls `M._with_workspace(function(root) require('nx.cache').invalidate(root); vim.notify('nx: cache cleared for ' .. root, vim.log.levels.INFO) end)`.
  - Export a registration function `M.register()` to be called from `setup()` in Task 13:
    ```lua
    function M.register()
      vim.api.nvim_create_user_command('NxProject', function() M.nx_project() end, { desc = 'Pick an Nx project' })
      vim.api.nvim_create_user_command('NxProjectTasks', function(opts)
        local project = opts.fargs[1]
        M.nx_project_tasks(project)
      end, { nargs = '?', desc = 'Pick a task for an Nx project' })
      vim.api.nvim_create_user_command('NxRefresh', function() M.nx_refresh() end, { desc = 'Clear Nx project cache' })
      -- Task 11 extends with :NxTask
    end
    ```

  **Must NOT do**:
  - No `:NxProject <name>` argument handling (no positional arg on `:NxProject`).
  - No completion functions on these commands (Scope OUT).
  - No silent failures — every error path notifies.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO with Task 11 (both edit `commands.lua`); Task 11 must come after.
  - **Parallel Group**: Wave 2 (parallel with 7, 8, 9, 12 but serial vs 11)
  - **Blocks**: 13
  - **Blocked By**: 1, 7, 8, 9

  **References**:

  *Pattern References*:
  - `:help nvim_create_user_command`
  - Picker chaining via `vim.schedule` — already locked in Task 8/9 actions.

  **QA Scenarios**:

  ```
  Scenario AC10-1: :NxProject calls projects picker, selecting chains to tasks picker, selecting chains to terminal.run
    Tool: Bash (nvim --headless) — stub pickers + terminal
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC10-1.lua" -c "qa!" \
           > .sisyphus/evidence/task-10-chain.txt 2>&1
      2. QA script: stub pickers.projects to capture (root, on_select) and immediately call on_select('alpha'); stub pickers.tasks to capture (root, project, on_select) and call on_select('build'); stub terminal.run to capture (root, project, task); stub workspace.root to return '/ws'. Call commands.nx_project(). Assert: pickers.projects called with '/ws'; pickers.tasks called with ('/ws','alpha'); terminal.run called with ('/ws','alpha','build'); PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-10-chain.txt

  Scenario AC10-2: outside workspace -> notify WARN, no picker (failure)
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC10-2.lua" -c "qa!" \
           > .sisyphus/evidence/task-10-noworkspace.txt 2>&1
      2. QA script: stub workspace.root to return nil; stub vim.notify; stub pickers.projects with a counter; call commands.nx_project(); assert notify WARN with 'Not in an Nx workspace' AND pickers.projects counter == 0; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-10-noworkspace.txt

  Scenario AC10-3: :NxRefresh clears cache for current workspace and notifies
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC10-3.lua" -c "qa!" \
           > .sisyphus/evidence/task-10-refresh.txt 2>&1
      2. QA script: stub workspace.root to return '/ws'; stub cache.invalidate to capture arg; stub vim.notify; call commands.nx_refresh(); assert cache.invalidate called with '/ws' AND notify INFO; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-10-refresh.txt

  Scenario AC10-4: register() creates the three commands
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua \
           -c "lua require('nx.commands').register(); print(vim.fn.exists(':NxProject')); print(vim.fn.exists(':NxProjectTasks')); print(vim.fn.exists(':NxRefresh'))" \
           -c "qa!" > .sisyphus/evidence/task-10-register.txt 2>&1
      2. All three lines should print '2' (command exists)
      3. awk 'NR<=3 {if($0!="2") exit 1} END{print "OK"}' .sisyphus/evidence/task-10-register.txt | grep -Fxq OK
    Expected Result: OK
    Evidence: .sisyphus/evidence/task-10-register.txt
  ```

  **Commit**: YES — `feat(commands): :NxProject, :NxProjectTasks, :NxRefresh` — files: `lua/nx/commands.lua` (initial) — pre-commit: AC10-1..AC10-4

- [ ] 11. **`:NxTask` subcommands (list/foreground/kill)**

  **What to do**:
  - Extend `lua/nx/commands.lua` with `:NxTask {list|foreground|kill} [project:task]`.
  - Add helper `M._parse_key(arg)` — splits on first `:`, returns `(project, task)` or `(nil, nil)` if invalid.
  - Add public functions:
    - `M.nx_task_list()` — calls `M._with_workspace(function(root) ... end)`. Reads `entries = require('nx.registry').list(root)`. If empty: notify INFO "No tasks for this workspace" and return. Else open fzf-lua picker with display strings `string.format('%s:%s [%s%s]', e.project, e.task, e.status, e.exit_code and (' code='..e.exit_code) or '')`. Build a lookup `display -> entry`. Actions:
      - `default` — foreground the selected entry.
      - `ctrl-x` — kill the selected entry, then re-open the list (`vim.schedule(function() M.nx_task_list() end)`).
    - `M.nx_task_foreground(arg?)` — `M._with_workspace(function(root) ... end)`. If arg given: parse `(project,task)`; if invalid: notify ERROR "Invalid argument; expected `project:task`". Else call `terminal.foreground(root, project, task)`. If arg nil:
      - `running = registry.find_running(root)` (treat ALL entries — running or exited — for foregrounding semantics? **Decision locked**: foreground operates on ALL entries in the registry; users wanting running-only use `:NxTask kill`. So use `registry.list(root)`.)
      - **Re-decision**: Keep behavior consistent with Metis-confirmed UX: 0 → notify; 1 → foreground; 2+ → picker. Operate on `registry.list(root)` (running + exited). Picker reuses `nx_task_list` rendering.
      - 0 entries: notify INFO "No tasks to foreground".
      - 1 entry: call `terminal.foreground(root, e.project, e.task)`.
      - 2+ entries: open picker (delegate to `M.nx_task_list()` which already foregrounds on default action).
    - `M.nx_task_kill(arg?)` — same pattern: parse if arg given (call `terminal.kill`), else dispatch on count (0/1/2+).
    - `M.nx_task(args_table)` — dispatcher invoked by the user command; reads `args_table.fargs`:
      - No args OR first arg == `'list'`: call `M.nx_task_list()`.
      - First arg == `'foreground'` (or `'fg'`): call `M.nx_task_foreground(args_table.fargs[2])`.
      - First arg == `'kill'`: call `M.nx_task_kill(args_table.fargs[2])`.
      - Other: notify ERROR "Unknown :NxTask subcommand: " .. arg.
  - Extend `M.register()`:
    ```lua
    vim.api.nvim_create_user_command('NxTask', function(opts) M.nx_task(opts) end, {
      nargs = '*',
      complete = function(arg_lead, cmdline, _)
        -- Minimal completion: subcommands only (allowed since we said no completion ON :NxProject; :NxTask subcommands is a usability tax-vs-benefit tradeoff)
        local parts = vim.split(cmdline, '%s+')
        if #parts <= 2 then
          return vim.tbl_filter(function(s) return s:find(arg_lead, 1, true) == 1 end, { 'list', 'foreground', 'kill' })
        end
        return {}
      end,
      desc = 'Manage backgrounded Nx tasks',
    })
    ```
    **NOTE**: subcommand-name completion is allowed (no project/task name completion which was Scope OUT). The Scope OUT was specifically project-name argument completion on `:NxProject`. Subcommand completion on `:NxTask` is permitted as small UX win.

  **Must NOT do**:
  - No completion of `<project:task>` argument (only subcommand names).
  - No `:NxTask <project:task>` shorthand (must specify `foreground` or `kill`).
  - No interactive prompts (use picker for 2+ case).

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO with Task 10 (same file).
  - **Parallel Group**: Wave 2 (executes after Task 10)
  - **Blocks**: 13
  - **Blocked By**: 1, 5, 7, 10

  **References**:

  *Pattern References*:
  - Task 10 commands.lua scaffolding.
  - fzf-lua actions pattern from Task 8 references.

  **QA Scenarios**:

  ```
  Scenario AC11-1: :NxTask (no args) shows 'No tasks' when registry empty
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC11-1.lua" -c "qa!" \
           > .sisyphus/evidence/task-11-empty.txt 2>&1
      2. QA script: stub workspace.root='/ws'; registry.list returns {}; stub vim.notify; call commands.nx_task({fargs={}}); assert notify INFO with 'No tasks'; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-11-empty.txt

  Scenario AC11-2: :NxTask list opens fzf-lua picker with formatted entries
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC11-2.lua" -c "qa!" \
           > .sisyphus/evidence/task-11-list.txt 2>&1
      2. QA script: stub workspace.root='/ws'; registry.list returns two entries (alpha:build running; beta:test exited code 0); stub fzf_exec to capture contents; call commands.nx_task({fargs={'list'}}); assert captured contents has two strings, one matching 'alpha:build [running]' and one 'beta:test [exited code=0]'; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-11-list.txt

  Scenario AC11-3: :NxTask foreground alpha:build calls terminal.foreground
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC11-3.lua" -c "qa!" \
           > .sisyphus/evidence/task-11-fg-arg.txt 2>&1
      2. QA script: stub workspace.root='/ws'; stub terminal.foreground to capture args; call commands.nx_task({fargs={'foreground','alpha:build'}}); assert terminal.foreground called with ('/ws','alpha','build'); PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-11-fg-arg.txt

  Scenario AC11-4: :NxTask foreground (no arg, 1 entry) directly foregrounds
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC11-4.lua" -c "qa!" \
           > .sisyphus/evidence/task-11-fg-1.txt 2>&1
      2. QA script: stub registry.list returns single running entry; stub terminal.foreground; call nx_task({fargs={'foreground'}}); assert terminal.foreground called once with the entry's args; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-11-fg-1.txt

  Scenario AC11-5: :NxTask kill notalsk:format -> ERROR notify (failure)
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua -c "luafile tests/qa/AC11-5.lua" -c "qa!" \
           > .sisyphus/evidence/task-11-bad.txt 2>&1
      2. QA script: stub vim.notify; call commands.nx_task({fargs={'kill','no-colon-here'}}); assert notify ERROR with 'project:task'; assert terminal.kill not called; PASS.
    Expected Result: PASS line
    Evidence: .sisyphus/evidence/task-11-bad.txt

  Scenario AC11-6: subcommand completion returns list/foreground/kill
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua \
           -c "lua require('nx.commands').register(); local cmd=vim.api.nvim_get_commands({})['NxTask']; print(vim.inspect(cmd.complete))" \
           -c "qa!" > .sisyphus/evidence/task-11-complete.txt 2>&1
      2. The output should indicate a Lua function-based completion is registered (check via getcompletion):
         nvim --headless --noplugin -u tests/qa/minimal_init.lua \
           -c "lua require('nx.commands').register(); print(table.concat(vim.fn.getcompletion('NxTask ', 'cmdline'), ','))" \
           -c "qa!" >> .sisyphus/evidence/task-11-complete.txt 2>&1
         tail -1 .sisyphus/evidence/task-11-complete.txt | grep -E 'list.*foreground.*kill|kill.*list|foreground.*list'
    Expected Result: completion output contains all three subcommands
    Evidence: .sisyphus/evidence/task-11-complete.txt
  ```

  **Commit**: YES — `feat(commands): :NxTask {list,foreground,kill} subcommands` — files: `lua/nx/commands.lua` (extended) — pre-commit: AC11-1..AC11-6

- [ ] 12. **Health check (`:checkhealth nx`)**

  **What to do**:
  - Create `lua/nx/health.lua` exporting `M.check()` (Neovim's `:checkhealth nx` entry point — Neovim 0.10+ auto-discovers `lua/<plugin>/health.lua`).
  - Use the new `vim.health` API (`vim.health.start`, `vim.health.ok`, `vim.health.warn`, `vim.health.error`, `vim.health.info`).
  - Sections + checks:
    - **Section "Workspace"**:
      - Detect via `require('nx.workspace').root()`. If found: `ok("Workspace root: " .. root)`. If nil: `warn("No Nx workspace detected from cwd " .. (vim.uv.cwd() or '?') .. ". Set $NX_WORKSPACE_ROOT_PATH or open a buffer inside an Nx workspace.")`.
    - **Section "CLI"**:
      - If workspace root detected: resolve `bin = require('nx.cli').resolve_bin(root)`. If nil: `error("Nx CLI not found in node_modules/.bin or $PATH. Install Nx as a project devDependency or globally.")`. Else `ok("Nx binary: " .. bin)`.
      - Run `vim.system({bin, '--version'}, { text = true }):wait(5000)`. Parse the version line (e.g., `"Nx                       18.3.0"` or just `"18.3.0"`). If parse-able: compare against `16.3.0`. If `< 16.3`: `warn(string.format("Nx %s is below recommended minimum 16.3 (`nx show` JSON support).", parsed))`. If `>= 16.3` and `< 18.1`: `info("Nx " .. parsed .. " supported; recommend ≥ 18.1 for stable JSON output.")`. If `>= 18.1`: `ok("Nx " .. parsed)`.
      - On error / unparseable: `warn("Could not determine Nx version: " .. (stderr or 'unknown'))`.
    - **Section "Dependencies"**:
      - `pcall(require, 'fzf-lua')` → `ok` or `error("fzf-lua not installed (ibhagwan/fzf-lua). Required for :NxProject and :NxProjectTasks pickers.")`.
      - `pcall(require, 'snacks')` → `ok` or `error("snacks.nvim not installed (folke/snacks.nvim). Required for the task runner float.")`.
    - **Section "Configuration"**:
      - Print summarized config: `info(vim.inspect(require('nx.config').defaults()))` shrunk to single-line for each key, OR a 5-line summary of keys + values for each sub-table.
  - Synchronous `:wait()` in health is acceptable (health is invoked by user, not on hot path).

  **Must NOT do**:
  - No async checks (`:checkhealth` is sync by design).
  - No internet / external lookups.
  - No checks for things outside the plugin (e.g., don't check the user's git status, terminal type, etc.).

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (parallel with 7, 8, 9, 10, 11)
  - **Blocks**: 13
  - **Blocked By**: 3

  **References**:

  *Pattern References*:
  - `:help vim.health` (Neovim 0.10+).
  - Existing community plugins use the convention `lua/<plugin>/health.lua` with `M.check()` entry.

  **QA Scenarios**:

  ```
  Scenario AC12-1: checkhealth nx writes report with all expected sections
    Tool: Bash (nvim --headless) — inside fixture workspace
    Preconditions: tests/fixtures/sample-workspace exists
    Steps:
      1. cd tests/fixtures/sample-workspace && nvim --headless --noplugin -u $OLDPWD/tests/qa/minimal_init.lua \
           -c "lua require('nx').setup({})" \
           -c "redir > $OLDPWD/.sisyphus/evidence/task-12-health.txt" \
           -c "checkhealth nx" \
           -c "redir END" -c "qa!"
      2. grep -q 'Workspace' .sisyphus/evidence/task-12-health.txt
      3. grep -q 'CLI' .sisyphus/evidence/task-12-health.txt
      4. grep -q 'Dependencies' .sisyphus/evidence/task-12-health.txt
      5. grep -q 'Configuration' .sisyphus/evidence/task-12-health.txt
    Expected Result: all greps pass
    Evidence: .sisyphus/evidence/task-12-health.txt

  Scenario AC12-2: missing nx CLI -> ERROR section (failure)
    Tool: Bash (nvim --headless) — temp PATH without nx
    Steps:
      1. T=$(mktemp -d) && cd $T && echo '{}' > nx.json && PATH=/usr/bin:/bin nvim --headless --noplugin -u $OLDPWD/tests/qa/minimal_init.lua \
           -c "lua require('nx').setup({})" \
           -c "redir > $OLDPWD/.sisyphus/evidence/task-12-health-no-nx.txt" \
           -c "checkhealth nx" \
           -c "redir END" -c "qa!"
      2. grep -q 'Nx CLI not found' .sisyphus/evidence/task-12-health-no-nx.txt
    Expected Result: error line present
    Evidence: .sisyphus/evidence/task-12-health-no-nx.txt

  Scenario AC12-3: missing fzf-lua -> ERROR (failure)
    Tool: Bash (nvim --headless) — minimal init without fzf-lua/Snacks on rtp
    Steps:
      1. cd tests/fixtures/sample-workspace && nvim --headless --noplugin -u $OLDPWD/tests/qa/minimal_init.lua \
           -c "lua package.preload['fzf-lua'] = function() error('not installed') end; package.loaded['fzf-lua'] = nil" \
           -c "lua require('nx').setup({})" \
           -c "redir > $OLDPWD/.sisyphus/evidence/task-12-health-no-fzf.txt" \
           -c "checkhealth nx" \
           -c "redir END" -c "qa!"
      2. grep -q 'fzf-lua not installed' .sisyphus/evidence/task-12-health-no-fzf.txt
    Expected Result: present
    Evidence: .sisyphus/evidence/task-12-health-no-fzf.txt
  ```

  **Commit**: YES — `feat(health): :checkhealth nx implementation` — files: `lua/nx/health.lua` — pre-commit: AC12-1..AC12-3

- [ ] 13. **Wire `setup()` to register all commands + autocmds**

  **What to do**:
  - Edit `lua/nx/init.lua`:
    - Replace the `dependent_plugins` mechanism (carry-over from old scaffolding) with explicit calls inside `setup()`:
      ```lua
      function M.setup(opts)
        opts = opts or {}
        require('nx.config').setup(opts)
        require('nx.commands').register()
        require('nx.cache').attach_autocmds()
        require('nx.registry').attach_self_healing()
      end
      ```
    - Keep the lazy `__index` metatable as-is.
    - Remove the `dependent_plugins = {}` block and the `for _, plugin in ipairs(dependent_plugins)` loop (dead code from old scaffolding; not used).
  - **No `plugin/nx.lua`** is created — commands only exist after `setup()`. Document in README that lazy.nvim users should use `cmd = { 'NxProject', 'NxProjectTasks', 'NxRefresh', 'NxTask' }` to lazy-load the plugin on first command invocation.

  **Must NOT do**:
  - No `plugin/nx.lua`.
  - No auto-setup at require time.
  - No `vim.defer_fn` deferred initialization.

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO — depends on all prior modules existing.
  - **Parallel Group**: Wave 3
  - **Blocks**: 14
  - **Blocked By**: 1, 2, 4, 10, 11, 12

  **References**:

  *Pattern References*:
  - `lua/nx/init.lua:1-43` (current full file) — preserve `__index` lazy loader; modify only the `setup` body and remove `dependent_plugins`.

  **QA Scenarios**:

  ```
  Scenario AC13-1: setup() registers all four user commands
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua \
           -c "lua require('nx').setup({})" \
           -c "lua for _,n in ipairs({'NxProject','NxProjectTasks','NxRefresh','NxTask'}) do print(n .. ':' .. vim.fn.exists(':' .. n)) end" \
           -c "qa!" > .sisyphus/evidence/task-13-cmds.txt 2>&1
      2. for n in NxProject NxProjectTasks NxRefresh NxTask; do grep -Fxq "$n:2" .sisyphus/evidence/task-13-cmds.txt || exit 1; done
    Expected Result: all four show ':2'
    Evidence: .sisyphus/evidence/task-13-cmds.txt

  Scenario AC13-2: setup() attaches BufWritePost and BufWipeout autocmds
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua \
           -c "lua require('nx').setup({})" \
           -c "lua print(#vim.api.nvim_get_autocmds({ group='nx.cache', event='BufWritePost' }))" \
           -c "lua print(#vim.api.nvim_get_autocmds({ group='nx.registry', event='BufWipeout' }))" \
           -c "qa!" > .sisyphus/evidence/task-13-autocmds.txt 2>&1
      2. awk 'NR<=2 {if($0+0 < 1) exit 1} END{print "OK"}' .sisyphus/evidence/task-13-autocmds.txt | grep -Fxq OK
    Expected Result: OK
    Evidence: .sisyphus/evidence/task-13-autocmds.txt

  Scenario AC13-3: setup() with partial opts overrides only specified keys
    Tool: Bash (nvim --headless)
    Steps:
      1. nvim --headless --noplugin -u tests/qa/minimal_init.lua \
           -c "lua require('nx').setup({ runner = { keymaps = { background = '<C-q>' } } })" \
           -c "lua print(require('nx.config').runner.keymaps.background); print(require('nx.config').cli.timeout_ms)" \
           -c "qa!" > .sisyphus/evidence/task-13-merge.txt 2>&1
      2. head -1 .sisyphus/evidence/task-13-merge.txt | grep -Fxq '<C-q>'
      3. sed -n '2p' .sisyphus/evidence/task-13-merge.txt | grep -Fxq '30000'
    Expected Result: override applied, defaults retained
    Evidence: .sisyphus/evidence/task-13-merge.txt
  ```

  **Commit**: YES — `feat(init): wire setup() to register commands + autocmds` — files: `lua/nx/init.lua` — pre-commit: AC13-1..AC13-3

- [ ] 14. **Headless QA scripts + runner**

  **What to do**:
  - Create `tests/qa/minimal_init.lua`:
    ```lua
    -- Pure-headless init: only adds the plugin's lua/ to runtimepath; no rtp pollution.
    vim.opt.runtimepath:prepend(vim.fn.getcwd())
    -- Stub helpers reside in tests/qa/_stubs/; QA scripts may require them.
    ```
  - Create `tests/qa/_stubs/init.lua` exporting reusable stub helpers:
    - `M.stub_module(name, replacement)` — sets `package.loaded[name] = replacement`; returns a restore function.
    - `M.stub_method(tbl, key, replacement)` — replaces `tbl[key]`, returns restore function.
    - `M.notify_capture()` — replaces `vim.notify` with a capture; returns `{ calls = {...}, restore = function() end }`.
    - `M.system_capture(canned_results)` — replaces `vim.system` with one that captures argv/opts and either invokes callback synchronously with the next entry from `canned_results` or with `{code=0, stdout='', stderr=''}` by default.
  - Create one Lua QA script per AC referenced in Tasks 1-13 plus integration scripts. File names match `.sisyphus/evidence/qa-<AC-ID>.txt` writes:
    - `tests/qa/AC1-1.lua`, `AC1-2.lua`, `AC2-1.lua`, ..., `AC13-3.lua`. Each script:
      1. `local stubs = require('tests.qa._stubs')`
      2. Sets up stubs as described in the AC scenario.
      3. Performs the assertion.
      4. On success: `vim.fn.writefile({'PASS: <AC-ID>'}, '.sisyphus/evidence/qa-<AC-ID>.txt')`. On failure: `vim.fn.writefile({'FAIL: <AC-ID> :: ' .. reason}, '.sisyphus/evidence/qa-<AC-ID>.txt')` and `os.exit(1)` (so the headless invocation exits non-zero, optional).
      5. Each script ends with `vim.cmd('qa!')` (or relies on the `-c "qa!"` from the runner).
  - Create additional integration scripts (`AC-INTEG-1.lua` ...) for cross-task flows:
    - `AC-INTEG-1.lua`: full chain `:NxProject` → select alpha → tasks picker shows alpha targets → select build → terminal.run captured with correct args. Stubs: fzf_exec, Snacks.terminal, cli.show_projects, cli.show_project. Assert all captures match.
    - `AC-INTEG-2.lua`: cache + autocmd integration — `cache.get_projects` once, fire `BufWritePost` for `nx.json`, `cache.get_projects` again, assert second call hit CLI again.
    - `AC-INTEG-3.lua`: registry + terminal exit lifecycle — run task in stubbed Snacks terminal, fire `_on_exit`, assert registry transitions to `exited`, tempfile written, then `:NxTask foreground` opens the tempfile.
  - Create `tests/qa/run-all.sh`:
    ```sh
    #!/usr/bin/env bash
    set -uo pipefail
    cd "$(dirname "$0")/../.."
    mkdir -p .sisyphus/evidence
    SCRIPTS=$(ls tests/qa/AC*.lua tests/qa/AC-INTEG-*.lua 2>/dev/null)
    PASS=0
    FAIL=0
    for script in $SCRIPTS; do
      AC=$(basename "$script" .lua)
      nvim --headless --noplugin -u tests/qa/minimal_init.lua \
        -c "luafile $script" -c "qa!" > /tmp/qa-$AC.log 2>&1
      EVIDENCE=".sisyphus/evidence/qa-$AC.txt"
      if [ -f "$EVIDENCE" ] && head -1 "$EVIDENCE" | grep -q '^PASS:'; then
        echo "PASS: $AC"; PASS=$((PASS+1))
      else
        echo "FAIL: $AC -- see /tmp/qa-$AC.log and $EVIDENCE"
        cat "$EVIDENCE" 2>/dev/null || echo "(no evidence file)"
        FAIL=$((FAIL+1))
      fi
    done
    echo "----"
    echo "$PASS passed, $FAIL failed"
    [ "$FAIL" -eq 0 ]
    ```
  - Make the runner executable (`chmod +x tests/qa/run-all.sh`).

  **Must NOT do**:
  - No plenary.nvim, no busted, no test framework.
  - No CI configuration (out of scope; if user later wants it, separate plan).
  - No fixtures beyond what Task 6 produced.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — many small files + bash runner; needs care to keep stubs consistent.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 15 in Wave 3)
  - **Parallel Group**: Wave 3
  - **Blocks**: F1-F4
  - **Blocked By**: 6, 13

  **References**:

  *Pattern References*:
  - All AC scenarios from Tasks 1-13.

  **QA Scenarios**:

  ```
  Scenario AC14-1: run-all.sh exits 0 when all individual ACs pass
    Tool: Bash
    Steps:
      1. bash tests/qa/run-all.sh > .sisyphus/evidence/task-14-runall.txt 2>&1
      2. echo "exit=$?" >> .sisyphus/evidence/task-14-runall.txt
      3. tail -1 .sisyphus/evidence/task-14-runall.txt | grep -Fxq 'exit=0'
      4. grep -E '^[0-9]+ passed, 0 failed' .sisyphus/evidence/task-14-runall.txt
    Expected Result: exit=0 and "N passed, 0 failed"
    Evidence: .sisyphus/evidence/task-14-runall.txt

  Scenario AC14-2: missing-evidence detection works (failure-path test of the runner itself)
    Tool: Bash
    Steps:
      1. cp tests/qa/AC1-1.lua /tmp/AC-FAKE.lua && sed -i.bak 's/PASS:/SHOULD_NOT_APPEAR:/' /tmp/AC-FAKE.lua
      2. # this is illustrative; instead create a fresh failing AC inline:
         cat > tests/qa/AC-DEMO-FAIL.lua <<'EOF'
         vim.fn.writefile({'FAIL: AC-DEMO-FAIL :: intentional'}, '.sisyphus/evidence/qa-AC-DEMO-FAIL.txt')
         vim.cmd('qa!')
         EOF
      3. bash tests/qa/run-all.sh > .sisyphus/evidence/task-14-fail.txt 2>&1
      4. grep -q '^FAIL: AC-DEMO-FAIL' .sisyphus/evidence/task-14-fail.txt
      5. tail -1 .sisyphus/evidence/task-14-fail.txt | grep -E 'failed' >/dev/null
      6. rm tests/qa/AC-DEMO-FAIL.lua .sisyphus/evidence/qa-AC-DEMO-FAIL.txt
    Expected Result: runner detected the failure and reported it
    Evidence: .sisyphus/evidence/task-14-fail.txt
  ```

  **Commit**: YES — `test(qa): headless QA scripts and runner` — files: `tests/qa/**` — pre-commit: AC14-1, AC14-2

- [ ] 15. **README documentation**

  **What to do**:
  - Replace existing `README.md` (currently a near-empty toc skeleton). Sections:
    - Title + one-liner.
    - **Requirements** table:
      | Dependency | Min version | Why |
      |------------|-------------|-----|
      | Neovim | 0.10 | `vim.system`, `vim.health`, `vim.fs.find` |
      | Nx | 16.3 (recommend 18.1+) | `nx show projects --json` and `nx show project --json` |
      | ibhagwan/fzf-lua | latest | `:NxProject` and `:NxProjectTasks` pickers |
      | folke/snacks.nvim | latest | Task runner float (`Snacks.terminal`) |
    - **Install** snippet for lazy.nvim:
      ```lua
      {
        'iagoleal/nx.nvim', -- adjust to actual repo
        cmd = { 'NxProject', 'NxProjectTasks', 'NxRefresh', 'NxTask' },
        dependencies = { 'ibhagwan/fzf-lua', 'folke/snacks.nvim' },
        opts = {},
      }
      ```
    - **Commands** reference:
      - `:NxProject` — pick a project; chains to tasks picker.
      - `:NxProjectTasks [project]` — pick a task for a project; if no arg, opens project picker first.
      - `:NxRefresh` — clear cached project data for the current workspace.
      - `:NxTask [list|foreground|kill] [project:task]` — manage backgrounded task floats.
    - **Inside the task float** keymaps:
      - `q` — hide (Snacks default; keeps task running). Same as backgrounding.
      - `<C-b>` (configurable) — explicit background.
    - **Configuration** — full default schema with comments (output of `lua/nx/config.lua` defaults pretty-printed).
    - **Backgrounded task lifecycle** — short paragraph explaining: `<C-b>` → hidden, job continues; on exit → notify + buffer dumped to a tempfile; foreground exited tasks via `:NxTask foreground project:task` to view the captured output read-only.
    - **`:checkhealth nx`** — one-line description.
    - **Troubleshooting** — short list:
      - "Not in an Nx workspace" → ensure `nx.json` exists at or above your cwd, or set `$NX_WORKSPACE_ROOT_PATH`.
      - "Nx CLI not found" → `npm i -D nx` in your workspace, or install `nx` globally.
      - Slow first invocation → cold Nx daemon; subsequent calls are fast.
    - **Limitations / Out of scope (v1)**:
      - No task argument passing (e.g., `nx build app --foo=bar`).
      - No task configuration selection (`-c production`).
      - No `nx affected` integration.
      - No project graph viz.
      - fzf-lua only; no Telescope/mini.pick adapter.
      - No colorscheme/highlight customization.
    - **Inspiration / Credits**: Snacks lazygit terminal pattern, fzf-lua custom pickers.
  - Keep markdown linting clean (`.mdlrc` uses `.mdl_style.rb`). Run `mdl README.md` if available; otherwise visually verify lists, code fences, tables.

  **Must NOT do**:
  - No promise of features marked Out of scope.
  - No badge spam (zero badges in v1).
  - No animated GIFs / screenshots required for v1 (acceptable to omit; can add later).
  - No license section (LICENSE file already present).

  **Recommended Agent Profile**:
  - **Category**: `writing` — markdown documentation.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 14)
  - **Parallel Group**: Wave 3
  - **Blocks**: F1
  - **Blocked By**: 13

  **References**:

  *Pattern References*:
  - Existing `README.md` (current skeleton with toc).
  - `.mdlrc` (line 1) and `.mdl_style.rb` for the project's markdown lint config.

  **QA Scenarios**:

  ```
  Scenario AC15-1: README contains all required sections
    Tool: Bash
    Steps:
      1. for header in 'Requirements' 'Install' 'Commands' 'Configuration' 'Backgrounded task lifecycle' ':checkhealth nx' 'Troubleshooting' 'Limitations'; do
           grep -q "^## .*$header" README.md || { echo "MISSING SECTION: $header"; exit 1; }
         done
         echo OK > .sisyphus/evidence/task-15-sections.txt
      2. test -s .sisyphus/evidence/task-15-sections.txt
    Expected Result: OK
    Evidence: .sisyphus/evidence/task-15-sections.txt

  Scenario AC15-2: README mentions all four user commands
    Tool: Bash
    Steps:
      1. for cmd in NxProject NxProjectTasks NxRefresh NxTask; do
           grep -q "$cmd" README.md || { echo "MISSING: $cmd"; exit 1; }
         done
         echo OK > .sisyphus/evidence/task-15-cmds.txt
    Expected Result: OK
    Evidence: .sisyphus/evidence/task-15-cmds.txt

  Scenario AC15-3: README does NOT promise out-of-scope features
    Tool: Bash
    Steps:
      1. # forbidden phrases (out-of-scope features)
         for forbidden in 'nx affected' 'Telescope' 'mini.pick' 'project graph' 'task arguments' 'configuration selection'; do
           if grep -qiE "(supports|implements|provides) .* $forbidden" README.md; then
             echo "FORBIDDEN PROMISE: $forbidden"; exit 1
           fi
         done
         echo OK > .sisyphus/evidence/task-15-forbidden.txt
    Expected Result: OK (no forbidden promise patterns)
    Evidence: .sisyphus/evidence/task-15-forbidden.txt
  ```

  **Commit**: YES — `docs(readme): usage, config, dependency requirements` — files: `README.md` — pre-commit: AC15-1..AC15-3

---

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.
>
> **Do NOT auto-proceed after verification. Wait for user's explicit approval before marking work complete.**
> **Never mark F1-F4 as checked before getting user's okay.** Rejection or user feedback → fix → re-run → present again → wait for okay.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read `.sisyphus/plans/nx-nvim-pickers-and-runner.md` end-to-end. For each "Must Have": verify implementation exists (read file, run command). For each "Must NOT Have": search codebase for forbidden patterns — reject with file:line if found. Specifically grep for: `vim.fn.system` (forbidden for show commands), `npx`, `plenary.async`, `lua/nx/utils.lua`, `plugin/nx.lua`, custom highlight definitions, telescope/mini.pick refs, retry loops, log file writes. Confirm every Scope OUT item is absent. Check evidence files exist in `.sisyphus/evidence/`. Compare deliverables against plan.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `stylua --check lua/` and `luacheck lua/` (skip if not installed; note in output). Review all files in `lua/nx/` for: AI slop (excessive comments, generic names like `data`/`result`/`temp`/`tmp`), commented-out code, unused locals, `vim.notify` without `vim.log.levels.*`, unused requires, defensive `pcall` overuse, modules that don't follow the lazy `__index` access pattern. Check that every module returns a table `M`. Check that no module mutates global state outside its own table. Verify `vim.system` is used in table form (no string commands).
  Output: `Stylua [PASS/FAIL/SKIP] | Luacheck [PASS/FAIL/SKIP] | Files [N clean/N issues] | AI Slop Findings [N] | VERDICT`

- [ ] F3. **Real Manual QA Execution** — `unspecified-high`
  Start from clean state. Run `bash tests/qa/run-all.sh` and capture full output. Inspect every `.sisyphus/evidence/qa-AC*.txt` file. Independently re-run every QA scenario from each task by `cd`-ing into `tests/fixtures/sample-workspace/` and invoking via `nvim --headless ...`. Test cross-task integration: chain `:NxProject` → select alpha → `:NxProjectTasks` shows alpha's targets → select build → terminal float opens with correct cmd. Test edge cases: empty workspace (move fixture aside), missing fzf-lua (stub), missing Snacks (stub), invalid project name. Save all outputs to `.sisyphus/evidence/final-qa/`.
  Output: `Scenarios [N/N pass] | Integration [N/N] | Edge Cases [N/N] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task in the plan: read "What to do" + "Must NOT do", run `git log --all --pretty=format: --name-only` and `git diff main..HEAD` for the relevant files. Verify 1:1 — everything in spec was built (no missing), nothing beyond spec (no creep). Check "Must NOT do" compliance per task and global guardrails. Detect cross-task contamination (e.g., Task 8 touching `lua/nx/registry.lua` which belongs to Task 5). Flag any unaccounted file changes. Verify `lua/nx/utils.lua` does NOT exist. Verify `plugin/nx.lua` does NOT exist. Verify only the 9 module files specified in deliverables exist under `lua/nx/`.
  Output: `Tasks [N/N compliant] | Contamination [CLEAN/N issues] | Unaccounted [CLEAN/N files] | Forbidden Files [CLEAN/N found] | VERDICT`

---

## Commit Strategy

One commit per task, conventional commits format. Files listed are the expected new/modified set per task.

| Task | Type | Message | Files |
|------|------|---------|-------|
| 1 | feat | `feat(config): extend default config schema for cli/cache/runner/pickers` | `lua/nx/config.lua` |
| 2 | feat | `feat(workspace): add workspace root detection` | `lua/nx/workspace.lua` |
| 3 | feat | `feat(cli): add async nx CLI exec with binary resolution` | `lua/nx/cli.lua` |
| 4 | feat | `feat(cache): per-workspace in-memory cache with autocmd invalidation` | `lua/nx/cache.lua` |
| 5 | feat | `feat(registry): backgrounded task registry with BufWipeout self-healing` | `lua/nx/registry.lua` |
| 6 | test | `test(fixture): add sample Nx workspace fixture` | `tests/fixtures/sample-workspace/**` |
| 7 | feat | `feat(terminal): Snacks runner with background/foreground + temp-file dump` | `lua/nx/terminal.lua` |
| 8 | feat | `feat(pickers): fzf-lua project picker with project.json preview` | `lua/nx/pickers.lua` (initial) |
| 9 | feat | `feat(pickers): fzf-lua tasks picker with task config preview` | `lua/nx/pickers.lua` (extended) |
| 10 | feat | `feat(commands): :NxProject, :NxProjectTasks, :NxRefresh` | `lua/nx/commands.lua` (initial) |
| 11 | feat | `feat(commands): :NxTask {list,foreground,kill} subcommands` | `lua/nx/commands.lua` (extended) |
| 12 | feat | `feat(health): :checkhealth nx implementation` | `lua/nx/health.lua` |
| 13 | feat | `feat(init): wire setup() to register commands + autocmds` | `lua/nx/init.lua` |
| 14 | test | `test(qa): headless QA scripts and runner` | `tests/qa/**` |
| 15 | docs | `docs(readme): usage, config, dependency requirements` | `README.md` |

Pre-commit per task: `bash tests/qa/run-all.sh` (when applicable; tasks before T13 may use targeted single-AC runs).

---

## Success Criteria

### Verification Commands

```bash
# Smoke
nvim --headless --noplugin -u tests/qa/minimal_init.lua \
  -c "lua require('nx').setup({})" -c "qa!"
# Expected: exit 0, no errors

# Full QA suite
bash tests/qa/run-all.sh
# Expected: all ACs PASS

# Health check
nvim --headless --noplugin -u tests/qa/minimal_init.lua \
  -c "redir > /tmp/health.txt" -c "checkhealth nx" -c "redir END" -c "qa!"
grep -q "Nx CLI:" /tmp/health.txt && echo "OK"
# Expected: OK

# Style (if installed)
stylua --check lua/

# Forbidden patterns
! grep -RIn "vim.fn.system" lua/nx/cli.lua lua/nx/cache.lua lua/nx/pickers.lua
! test -f lua/nx/utils.lua
! test -f plugin/nx.lua
! grep -RIn "plenary.async" lua/
! grep -RIn "npx" lua/nx/cli.lua
```

### Final Checklist

- [ ] All "Must Have" items present (verified by F1)
- [ ] All "Must NOT Have" items absent (verified by F1 + F4)
- [ ] All QA scenarios PASS (verified by F3)
- [ ] No AI slop (verified by F2)
- [ ] Module structure exactly as specified (verified by F4)
- [ ] User explicitly approved final results
