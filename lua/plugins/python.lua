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
          -- 直接用 venv 里的解释器，不用 `uv run`。
          -- 原因：neotest 调试（<leader>td）会把解释器原样塞进 debugpy 的 `python` 字段，
          -- 而 debugpy 只接受单个解释器路径；`{ "uv", "run", "python" }` 是 3 个元素，
          -- 会导致 debug 会话卡死（实测：会话建立但永不结束、无结果）。
          -- 代价：不再自动 sync 依赖，改动依赖后需自己跑一次 `uv sync`。
          python = ".venv/bin/python",
        },
      },
    },
  },

  -- debugpy 本体：nvim-dap-python 需要它提供的 debugpy-adapter 可执行文件
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "debugpy" } },
  },

  -- Python 调试：注册 dap.adapters.python
  -- <leader>td（neotest 的 dap strategy）和断点调试都依赖它；
  -- 没有它时按 <leader>td 会报 "No adapter for type 'python'"
  {
    "mfussenegger/nvim-dap",
    optional = true,
    dependencies = {
      {
        "mfussenegger/nvim-dap-python",
        config = function()
          require("dap-python").setup("debugpy-adapter")
        end,
      },
    },
  },

  -- 别让 mason-nvim-dap 自动注册 python 适配器，否则会覆盖上面 dap-python 注册的
  {
    "jay-babu/mason-nvim-dap.nvim",
    optional = true,
    opts = { handlers = { python = function() end } },
  },
}
