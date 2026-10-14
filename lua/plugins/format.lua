-- Python 自动格式化:使用全局安装的 autoflake / isort / black
-- 与项目 .pre-commit-config.yaml 保持一致的完整链(经 stdin 管道读写)。
-- 工具已通过 `uv tool install` 装入全局 ~/.bin,无需 uv run 或项目 venv。

return {
  {
    "conform.nvim",
    opts = {
      -- LazyVim 默认 python = { "isort", "black" };这里改为完整链:先删未使用 import,
      -- 再排导入顺序,最后 black 格式化
      formatters_by_ft = {
        python = { "autoflake", "isort", "black" },
      },
      formatters = {
        autoflake = {
          command = "autoflake",
          args = { "--remove-all-unused-imports", "-" },
          stdin = true,
        },
        isort = {
          command = "isort",
          args = { "--profile", "black", "-" },
          stdin = true,
        },
        black = {
          command = "black",
          args = { "--quiet", "-" },
          stdin = true,
        },
      },
      -- 注意:不要设置 opts.format_on_save —— LazyVim 自己管理"保存时格式化",
      -- 用 <leader>uf 切换(vim.g.autoformat),默认开启。
    },
  },
}
