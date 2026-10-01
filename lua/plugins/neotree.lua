-- neo-tree itself is set up by the LazyVim extra `editor.neo-tree`
-- (enabled in lazyvim.json, selected via `vim.g.lazyvim_explorer`
-- in config/options.lua). This file only overrides a few defaults.
return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      close_if_last_window = true,
      window = {
        width = 30,
        position = "left",
      },
      filesystem = {
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = false,
        },
      },
    },
    keys = {
      {
        "<C-n>",
        function()
          require("neo-tree.command").execute({
            source = "filesystem",
            reveal = true,
            toggle = true,
            position = "left",
          })
        end,
        desc = "Toggle Neo-tree",
      },
    },
  },
}
