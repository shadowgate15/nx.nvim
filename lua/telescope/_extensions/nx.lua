local nx = require('nx.telescope')

return require('telescope').register_extension({
  exports = {
    nx = nx.projects,
    projects = nx.projects,
  },
})
