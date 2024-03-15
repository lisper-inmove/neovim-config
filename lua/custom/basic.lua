vim.opt.guicursor = ""

vim.opt.nu = true
vim.opt.relativenumber = false

vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.shiftwidth = 2
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
vim.o.cursorline = true
vim.o.cursorcolumn = true
vim.api.nvim_set_hl(0, 'CursorLine', { fg = '#808080' })

vim.g.mapleader = "t"
vim.api.nvim_set_keymap("n", "<leader>f", ":Telescope find_files<CR>", { silent = true })
vim.api.nvim_set_keymap("n", "<leader>a", ":Telescope live_grep<CR>", { silent = true })
vim.api.nvim_set_keymap("n", "<leader>p", ":Telescope neovim-project discover<CR>", { silent = true })
vim.api.nvim_set_keymap("n", "<C-j>", "<C-W>j", {})
vim.api.nvim_set_keymap("n", "<C-k>", "<C-W>k", {})
vim.api.nvim_set_keymap("n", "<C-l>", "<C-W>l", {})
vim.api.nvim_set_keymap("n", "<C-h>", "<C-W>h", {})
