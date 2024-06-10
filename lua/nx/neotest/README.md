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
