-- Title:        DarkRoom plugin
-- Description:  A plugin to create a focus centered window for typing.
-- Last Change:  1 April 2025
-- Maintainer:   Paulo Diovani <https://github.com/paulodiovani>

-- Prevents the plugin from being loaded multiple times.
if vim.g.loaded_darkroom then
  return
end
vim.g.loaded_darkroom = true

-- Load the plugin and set up with default configuration
require('darkroom').setup()