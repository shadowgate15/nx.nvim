# nx.neotest

Adds support for the [neotest](https://github.com/nvim-neotest/neotest) plugin.

<!-- toc -->

- [Usage](#usage)
- [Supported Executors](#supported-executors)

<!-- tocstop -->

## Usage

```lua
require('neotest').setup({
  ...,
  adapters = {
    ['nx.netoest'] = {
      ..., -- nx.NeotestConfig options
    }
  }
})
```

## Supported Executors

- `@nx/jest:jest`
  - Determines test file based on these globs: `[ "**/__tests__/**/*.[jt]s?(x)", "**/?(*.)+(spec|test).[jt]s?(x)" ]`

## Adding a new executor

If you place a new executor in the `nx.neotest.executors` namespace, it will be automatically picked up by the `nx.neotest` plugin.
It should follow the interface of the [`nx.netotest.Exectuor` class](lua/nx/neotest/executors/interface.lua).
