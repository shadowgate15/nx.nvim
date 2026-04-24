# nx.nvim

A Neovim plugin for [Nx](https://nx.dev/) workspaces. Browse projects and tasks via fzf-lua pickers, and run them in backgroundable Snacks.nvim terminal floats.

<!-- toc -->

- [Requirements](#requirements)
- [Install](#install)
- [Commands](#commands)
- [Configuration](#configuration)
- [Backgrounded task lifecycle](#backgrounded-task-lifecycle)
- [:checkhealth nx](#checkhealth-nx)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)

<!-- tocstop -->

## Requirements

| Dependency | Minimum version | Required for |
|---|---|---|
| [Neovim](https://neovim.io/) | 0.10 | `vim.system`, `vim.health`, `vim.fs.find` |
| [Nx](https://nx.dev/) | 16.3 (recommend 18.1+) | `nx show projects --json` and `nx show project --json` |
| [ibhagwan/fzf-lua](https://github.com/ibhagwan/fzf-lua) | latest | `:NxProject` and `:NxProjectTasks` pickers |
| [folke/snacks.nvim](https://github.com/folke/snacks.nvim) | latest | Task runner float |

## Install

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'your-username/nx.nvim',
  cmd = { 'NxProject', 'NxProjectTasks', 'NxRefresh', 'NxTask' },
  dependencies = {
    'ibhagwan/fzf-lua',
    'folke/snacks.nvim',
  },
  opts = {},
}
```

Using the `cmd` key ensures the plugin is lazy-loaded on first command invocation.

If you prefer explicit setup:

```lua
require('nx').setup({
  -- optional overrides (see Configuration)
})
```

## Commands

| Command | Description |
|---|---|
| `:NxProject` | Open a fuzzy picker of Nx projects. Selecting a project opens the task picker. |
| `:NxProjectTasks [project]` | Open a fuzzy picker of tasks for a project. If no project is specified, the project picker opens first. |
| `:NxRefresh` | Clear cached project data for the current workspace. Run after changing `project.json` or `nx.json`. |
| `:NxTask [list\|foreground\|kill] [project:task]` | Manage backgrounded task floats. Defaults to `list`. |

### :NxTask subcommands

| Subcommand | Description |
|---|---|
| `:NxTask` or `:NxTask list` | Show all running/exited tasks for this workspace. Select to foreground, `<C-x>` to kill. |
| `:NxTask foreground [project:task]` | Bring a backgrounded task to the foreground. If no argument, picks from the list. |
| `:NxTask kill [project:task]` | Stop a task. If no argument, picks from the list. |

### Inside the task float

The float's border footer always shows the available keymaps (e.g. ` <C-b> background  q hide  :NxTask kill `) so you don't have to memorise them.

| Keymap | Action |
|---|---|
| `q` | Hide the float (Snacks default). Task keeps running in the background. |
| `<C-b>` (configurable) | Explicit background: hide the float, keep the task running. |
| `:NxTask kill project:task` | Stop a running task (no in-float binding by design — see [Configuration](#configuration)). |

## Configuration

Call `require('nx').setup({})` with any of these options:

```lua
require('nx').setup({
  cli = {
    -- Timeout in milliseconds for nx CLI calls
    timeout_ms = 30000,
    -- Extra environment variables passed to nx invocations
    env = {},
    -- Environment variable that overrides workspace root detection
    workspace_root_env = 'NX_WORKSPACE_ROOT_PATH',
  },
  cache = {
    -- Auto-invalidate cache on nx.json / project.json writes
    auto_invalidate = true,
    -- File patterns that trigger cache invalidation on write
    watch_files = { 'nx.json', 'project.json' },
  },
  runner = {
    keymaps = {
      -- Keymap inside the terminal float to background the task
      background = '<C-b>',
    },
    -- Pass-through table for Snacks.terminal win options
    win = {},
  },
  pickers = {
    -- Show a preview pane with project/task JSON config
    preview = true,
  },
})
```

## Backgrounded task lifecycle

1. Run a task via `:NxProject` (or `:NxProjectTasks`). A Snacks.nvim terminal float opens running `nx run project:task`.
2. Press `<C-b>` (or `q`) to hide the float. The task continues running in the background.
3. When the task exits, you receive a `vim.notify` message with the exit code.
4. The terminal output is saved to a temporary file.
5. Use `:NxTask foreground project:task` (or `:NxTask list` then select) to reopen the output read-only in a float.
6. Use `:NxTask kill project:task` to stop a running task.
7. Re-running the same `project:task` while it's active will foreground it instead of starting a duplicate.

## :checkhealth nx

Run `:checkhealth nx` to verify your setup:

- **Workspace**: Confirms an Nx workspace is detected from your current directory.
- **CLI**: Confirms the `nx` binary is found and checks its version.
- **Dependencies**: Confirms fzf-lua and snacks.nvim are installed.
- **Configuration**: Summarizes the active configuration defaults.

## Troubleshooting

**"Not in an Nx workspace"**
Ensure `nx.json` exists at or above your current working directory, or set `$NX_WORKSPACE_ROOT_PATH` to the workspace root.

**"Nx CLI not found"**
Install Nx as a project devDependency (`npm i -D nx`) or globally (`npm i -g nx`). The plugin looks for `node_modules/.bin/nx` first, then falls back to the global `nx` on your `$PATH`.

**Slow first invocation**
The Nx daemon starts on the first CLI call. Subsequent calls are fast (< 100ms). This is expected behavior.

**Task float does not open**
Ensure [snacks.nvim](https://github.com/folke/snacks.nvim) is installed. Run `:checkhealth nx` to confirm.

**Picker does not open**
Ensure [fzf-lua](https://github.com/ibhagwan/fzf-lua) is installed. Run `:checkhealth nx` to confirm.

## Limitations

The following features are intentionally out of scope for v1:

- No task argument passing (e.g., `nx build app --foo=bar`). Tasks run with default configuration.
- No task configuration selection (`-c production`). The default Nx configuration is used.
- No `nx affected` integration.
- No Nx project graph visualization.
- fzf-lua only — no Telescope.nvim or mini.pick adapter.
- No colorscheme or highlight customization.
- No statusline component (though `require('nx.registry').list()` can be called for custom integrations).
