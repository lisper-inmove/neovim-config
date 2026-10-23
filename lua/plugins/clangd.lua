-- ~/.config/nvim/lua/plugins/clangd.lua
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local clangd = opts.servers and opts.servers.clangd
      if not clangd then
        return
      end
      -- clangd 23 起 --function-arg-placeholders 必须显式给布尔值,
      -- 否则启动时报 "Value specified by --function-arg-placeholders is invalid"。
      clangd.cmd = vim.tbl_map(function(a)
        if a == "--function-arg-placeholders" then
          return "--function-arg-placeholders=true"
        end
        return a
      end, clangd.cmd or { "clangd" })
      -- 通过 compile_commands.json 里的真实编译器查询系统头文件路径。
      -- 本项目(afss)用的是 conda 工具链 /home/JC1136/cpp20 下的 g++,
      -- 之前只配了 /usr/bin/c++, 导致 clangd 无法调用真实编译器,
      -- 报 "System include extraction: driver clang not found in PATH"。
      clangd.cmd = vim.list_extend(clangd.cmd or { "clangd" }, {
        "--query-driver=/home/JC1136/cpp20/bin/*",
        "--query-driver=/usr/bin/c++",
      })
      -- clangd 23 废弃 offsetEncoding 扩展, 改走标准 positionEncodings。
      if clangd.capabilities then
        clangd.capabilities.offsetEncoding = nil
      end
    end,
  },
}
