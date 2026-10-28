-- fzf-lua is enabled through the LazyVim extra `editor.fzf`
-- (see lazyvim.json). This spec only provides the fzf binary that
-- fzf-lua looks up via `fzf#exec()`.
return {
  {
    "junegunn/fzf",
    build = "./install --bin",
  },
  -- Standalone Ag (the_silver_searcher) search via fzf-lua, using
  -- fzf-lua's `cmd` override. Output format `path:line:col:match`
  -- (ag --column) matches what fzf-lua's grep parse expects, so no
  -- other option changes are needed. Search with <leader>sA or :Ag.
  {
    "ibhagwan/fzf-lua",
    init = function()
      -- :Ag user command. `init` (not `config`) so we don't override
      -- LazyVim's fzf-lua setup; load the plugin explicitly on demand.
      vim.api.nvim_create_user_command("Ag", function()
        require("lazy").load({ plugins = "fzf-lua" })
        require("fzf-lua").grep({
          cmd = "ag --column --nogroup --color --smart-case",
          input_prompt = "Ag> ",
        })
      end, { desc = "Grep with Ag (Root Dir)" })
    end,
    keys = {
      {
        "<leader>sA",
        LazyVim.pick("grep", {
          cmd = "ag --column --nogroup --color --smart-case",
          input_prompt = "Ag> ",
        }),
        desc = "Grep with Ag (Root Dir)",
      },
    },
  },
}
