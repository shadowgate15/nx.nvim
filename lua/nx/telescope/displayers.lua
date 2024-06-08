local entry_display = require('telescope.pickers.entry_display')

local M = {}

M.projects = entry_display.create({
  separator = ' ',
  items = {
    { width = 30 },
    { width = 15 },
    { remaining = true },
  },
})

return M
