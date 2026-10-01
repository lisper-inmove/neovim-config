-- fzf-lua is enabled through the LazyVim extra `editor.fzf`
-- (see lazyvim.json). This spec only provides the fzf binary that
-- fzf-lua looks up via `fzf#exec()`.
return {
  {
    "junegunn/fzf",
    build = "./install --bin",
  },
}
