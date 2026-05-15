-- Plugin entry point for yapt.nvim
-- This file is automatically loaded by Neovim

-- Prevent loading the plugin twice
if vim.g.loaded_yapt then
  return
end
vim.g.loaded_yapt = true

-- Setup the plugin with default configuration
-- Users can override this by calling require('yapt').setup() in their config
require("yapt").setup()
