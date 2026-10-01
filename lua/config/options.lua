-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.number = true
vim.opt.relativenumber = false

-- Use neo-tree (lazyvim.plugins.extras.editor.neo-tree) as the default
-- explorer instead of the default snacks explorer. Must be set before
-- lazy.nvim starts.
vim.g.lazyvim_explorer = "neo-tree"

-- Use fzf-lua (lazyvim.plugins.extras.editor.fzf) for all pickers.
vim.g.lazyvim_picker = "fzf"
