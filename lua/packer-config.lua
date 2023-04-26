-- This file can be loaded by calling `lua require('plugins')` from your init.vim

-- Only required if you have packer configured as `opt`
vim.cmd [[packadd packer.nvim]]

return require('packer').startup(function(use)

  -- Packer can manage itself
  use 'wbthomason/packer.nvim'
  use 'neovim/nvim-lspconfig'
  use 'simrat39/rust-tools.nvim'

  -- Completion framework:
  use 'hrsh7th/nvim-cmp'

  -- LSP completion source:
  use 'hrsh7th/cmp-nvim-lsp'

  -- Useful completion sources:
  use 'hrsh7th/cmp-nvim-lua'
  use 'hrsh7th/cmp-nvim-lsp-signature-help'
  use 'hrsh7th/cmp-vsnip'
  use 'hrsh7th/cmp-path'
  use 'hrsh7th/cmp-buffer'
  use 'hrsh7th/vim-vsnip'

  use 'puremourning/vimspector'
  use 'tanvirtin/monokai.nvim'
  use 'voldikss/vim-floaterm'

  use 'numkil/ag.nvim'

  use 'natecraddock/nvim-find'
  use 'junegunn/fzf'
  use 'junegunn/fzf.vim'

  use {
    'nvim-telescope/telescope.nvim', tag = '0.1.1',
    requires = { {
	    'nvim-lua/plenary.nvim', 'nvim-telescope/telescope-file-browser.nvim',
    } }
  }

  use 'nvim-telescope/telescope-project.nvim'

  use "folke/which-key.nvim"

  use 'airblade/vim-gitgutter'

  use 'ojroques/nvim-hardline'

  use ({
    'nvim-treesitter/nvim-treesitter', { run = ':TSUpdate' }
  })

  use {
    'VonHeikemen/lsp-zero.nvim',
    branch = 'v2.x',
    requires = {
      -- LSP Support
      {'neovim/nvim-lspconfig'},             -- Required
      {                                      -- Optional
        'williamboman/mason.nvim',
        run = function()
          pcall(vim.cmd, 'MasonUpdate')
        end,
      },
      {'williamboman/mason-lspconfig.nvim'}, -- Optional
  
      -- Autocompletion
      {'hrsh7th/nvim-cmp'},     -- Required
      {'hrsh7th/cmp-nvim-lsp'}, -- Required
      {'L3MON4D3/LuaSnip'},     -- Required
    }
  }

  use {
    'akinsho/flutter-tools.nvim',
    lazy = false,
    dependencies = {
        'nvim-lua/plenary.nvim',
        'stevearc/dressing.nvim', -- optional for vim.ui.select
    },
  }

end)
