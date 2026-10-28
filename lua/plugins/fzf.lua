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
  -- other option changes are needed. Press <leader>sA to search.
  {
    "ibhagwan/fzf-lua",
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
