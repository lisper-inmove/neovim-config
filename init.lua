-- bootstrap lazy.nvim, LazyVim and your plugins

-- 在 init.lua 最开头添加
vim.g.clipboard = {
    name = "xclip",
    copy = {
        ["+"] = "xclip -selection clipboard",
        ["*"] = "xclip -selection clipboard",
    },
    paste = {
        ["+"] = "xclip -selection clipboard -o",
        ["*"] = "xclip -selection clipboard -o",
    },
}
require("config.lazy")
