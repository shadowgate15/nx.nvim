local M = {}

function M.projects(opts)
  opts = opts or {}

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values

  pickers
    .new(opts, {
      prompt_title = 'Nx Projects',
      finder = finders.new_dynamic({
        fn = function()
          local workspace = require('nx.workspace')

          return workspace.projects()
        end,
        ---@param entry nx.NxProject
        entry_maker = function(entry)
          return {
            value = entry,
            display = function(e)
              local displayers = require('nx.telescope.displayers')

              local projectType

              if e.value.projectType then
                projectType = { e.value.projectType }
              else
                projectType = { '-', 'TelescopeResultsComment' }
              end

              return displayers.projects({
                { e.value.name, 'TelescopeResultsIdentifier' },
                projectType,
                { e.value.sourceRoot },
              })
            end,
            ordinal = entry.name,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        local actions = require('telescope.actions')

        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

return M
