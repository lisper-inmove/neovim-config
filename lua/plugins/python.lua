-- Python LSP (pyright) 指向项目的 .venv,让第三方依赖(如 itcd_sdk)可解析
-- pyright 的 venvPath/venv 相对 workspace root 解析
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        pyright = {
          settings = {
            python = {
              venvPath = ".",
              venv = ".venv",
            },
          },
        },
      },
    },
  },
}
