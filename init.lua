-- bootstrap lazy.nvim, LazyVim and your plugins

-- System clipboard on X11. Requires xclip:
--   sudo apt install xclip
if vim.fn.executable("xclip") == 1 then
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
end

require("config.lazy")
