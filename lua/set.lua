vim.opt.guicursor = ""

vim.opt.nu = true
vim.opt.relativenumber = false

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smartindent = true

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.termguicolors = true

vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50
vim.opt.colorcolumn = "120"

vim.g.mapleader = "t"
vim.api.nvim_set_keymap("n", "<leader>tt", ":FloatermToggle<CR>", { silent = true })
vim.api.nvim_set_keymap("n", "<C-j>", "<C-W>j", {})
vim.api.nvim_set_keymap("n", "<C-k>", "<C-W>k", {})
vim.api.nvim_set_keymap("n", "<C-l>", "<C-W>l", {})
vim.api.nvim_set_keymap("n", "<C-h>", "<C-W>h", {})
