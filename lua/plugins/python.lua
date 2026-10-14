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

  -- neotest-python 依赖 python treesitter parser 才能解析出测试用例
  -- （LazyVim 核心的 ensure_installed 里不含 python）
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "python" } },
  },

  -- neotest：在 nvim 内运行/调试 pytest
  -- 需先启用 lazyvim.plugins.extras.test.core（它只给 neotest 骨架，adapters 默认为空）
  -- 键位由该 extra 提供：<leader>tt 当前文件 / <leader>tr 光标最近用例
  --                    <leader>ts 摘要面板 / <leader>to 输出 / <leader>tw watch
  {
    "nvim-neotest/neotest",
    optional = true,
    dependencies = { "nvim-neotest/neotest-python" },
    opts = {
      adapters = {
        ["neotest-python"] = {
          runner = "pytest",
          -- 走 uv：与终端里 `uv run pytest` 行为一致，跑测试前自动 sync 依赖
          -- （若 nvim 的 PATH 里没有 uv，改成 ".venv/bin/python"）
          python = { "uv", "run", "python" },
        },
      },
    },
  },
}
