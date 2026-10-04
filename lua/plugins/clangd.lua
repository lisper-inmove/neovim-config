-- ~/.config/nvim/lua/plugins/clangd.lua
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      -- 让 clangd 通过 compile_commands.json 里的真实编译器(/usr/bin/c++ -> g++-13)
      -- 查询系统头文件路径。
      -- 否则 clangd 自行探测 /usr/lib/gcc 时会选中 gcc-14, 但本机只装了
      -- libgcc-14-dev 而没有 libstdc++-14-dev, 于是连 <filesystem> 都找不到。
      local clangd = opts.servers and opts.servers.clangd
      if not clangd then
        return
      end
      clangd.cmd = vim.list_extend(clangd.cmd or { "clangd" }, {
        "--query-driver=/usr/bin/c++",
      })
    end,
  },
}
