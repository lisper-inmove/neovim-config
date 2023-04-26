require'telescope'.load_extension('project')
vim.api.nvim_set_keymap("n", "<leader>p", "<cmd>Telescope project<CR>", { noremap = true, silent = true })
