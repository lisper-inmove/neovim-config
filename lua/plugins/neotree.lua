-- 使用 lazy.nvim 安装 neo-tree.nvim
return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x", -- 建议使用 v3.x 分支，更稳定 [citation:3]
    -- 声明依赖项，lazy.nvim 会自动处理 [citation:1][citation:3][citation:5]
    dependencies = {
      "nvim-lua/plenary.nvim",      -- 必备，提供底层工具函数
      "MunifTanjim/nui.nvim",       -- 必备，提供 UI 组件
      "nvim-tree/nvim-web-devicons", -- 强烈推荐，显示文件图标
    },
    -- lazy = false, 可以取消注释，确保插件在 Neovim 启动时加载，让快捷键随时可用 [citation:3]
    config = function()
      -- 在这里调用 setup 函数进行配置
      require("neo-tree").setup({
        -- 在此处添加你的个性化配置，例如：
        close_if_last_window = true,  -- 如果这是最后一个窗口，关闭 Neovim
        enable_git_status = true,     -- 开启 Git 状态显示 [citation:1]
        enable_diagnostics = true,    -- 开启 LSP 诊断信息显示 [citation:1]
        window = {
          width = 30,                 -- 设置侧边栏宽度
          position = "left",          -- 设置在左侧显示
        },
        -- 文件系统相关的配置
        filesystem = {
          filtered_items = {
            visible = false, -- 是否显示隐藏文件（以点开头的文件）
            hide_dotfiles = false, -- 是否隐藏 dotfiles 文件
            hide_gitignored = false, -- 是否隐藏被 .gitignore 忽略的文件
          },
          follow_current_file = {    -- 自动跟随当前文件所在的目录 [citation:3]
            enabled = true,
          },
          use_libuv_file_watcher = true, -- 启用文件监视，自动刷新 [citation:2][citation:3]
        },
      })
      -- 设置快捷键，在 Normal 模式下按 <C-n> 打开或关闭文件树 [citation:4][citation:5]
      vim.keymap.set("n", "<C-n>", ":Neotree filesystem reveal left<CR>", { noremap = true, silent = true })
    end,
  },
}
