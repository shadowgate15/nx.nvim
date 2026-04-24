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
