-- 端到端验证 debug.lua：真加载插件 spec、真调它的 config()，看 dap 里落了什么。
-- 跑法：./scripts/probe/run.sh（或 nvim --clean -l scripts/probe/probe-debug.lua）

local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helper.lua")
H.rtp("nvim-dap")
H.rtp("neotest", "nvim-nio")

local BASE = H.tmp .. "/fixtures"
local REAL = H.real_project

local pass, fail = 0, 0
local failures = {}
local function ok(label, cond, detail)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    failures[#failures + 1] = ("%s\n       %s"):format(label, detail or "")
  end
end
local function eq(label, got, want)
  ok(label, vim.deep_equal(got, want), ("got  %s\n       want %s"):format(vim.inspect(got), vim.inspect(want)))
end

-- 造一个「另一个项目」：也是 target 名字 + CMake 认出来的 Debug 目录，
-- 用来验证配置名/路径不是插件加载时冻结的
local function write(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local fd = assert(io.open(path, "w"))
  fd:write(content)
  fd:close()
end
local function write_exe(path)
  write(path, "#!/bin/sh\n")
  vim.fn.setfperm(path, "rwxr-xr-x")
end

write(BASE .. "/proj-other/CMakeLists.txt", "x\n")
write(BASE .. "/proj-other/.nvim.yaml", "target: Other_Test\n")
write(BASE .. "/proj-other/build-debug/CMakeCache.txt", "CMAKE_BUILD_TYPE:STRING=Debug\n")
write_exe(BASE .. "/proj-other/build-debug/bin/Other_Test")
write(BASE .. "/proj-other/src/o.cc", "TEST_F(S, N) {}\n")

-- 真加载 debug.lua，取出 nvim-dap 那条 spec，调它的 config()
local chunk = assert(loadfile(H.repo .. "/lua/plugins/debug.lua"))
local dap_spec
for _, s in ipairs(chunk()) do
  if s[1] == "mfussenegger/nvim-dap" then
    dap_spec = s
  end
end
ok("debug.lua 里有 nvim-dap 的 spec", dap_spec ~= nil, "没找到")

-- 打开 LearnCPP 里的真实文件，再执行 config()
vim.cmd.edit(REAL .. "/tests/CMakeLists.txt")
dap_spec.config()
local dap = require("dap")

eq("codelldb 适配器已注册", type(dap.adapters.codelldb), "table")
eq(
  "codelldb 可执行文件路径",
  dap.adapters.codelldb.executable.command,
  vim.fn.stdpath("data") .. "/mason/bin/codelldb"
)

local cfgs = dap.configurations.cpp
ok("dap.configurations.cpp 有两个配置", cfgs ~= nil and #cfgs == 2, vim.inspect(cfgs and #cfgs))

-- 当前缓冲区是 CMakeLists.txt，但它在 LearnCPP 根下，应该解析到 LearnCPP
eq("配置名来自项目里的 target（不是写死的字面量）", cfgs[1].name, "调试 LearnCPP_Test (全部)")
eq("program 指向真实二进制", cfgs[1].program, REAL .. "/build-Debug/bin/LearnCPP_Test")
eq("cwd 是项目根", cfgs[1].cwd, REAL)
ok(
  "program 是字符串而不是函数（启动时不看当前缓冲区）",
  type(cfgs[1].program) == "string",
  type(cfgs[1].program)
)
ok("cwd 是字符串而不是函数", type(cfgs[1].cwd) == "string", type(cfgs[1].cwd))
ok("program 这个文件真的存在", vim.fn.executable(cfgs[1].program) == 1, cfgs[1].program)
eq("type 是 codelldb", cfgs[1].type, "codelldb")
eq("request 是 launch", cfgs[1].request, "launch")

-- 换到「另一个项目」的 cpp 文件：FileType autocmd 应该重建配置
vim.cmd.edit(BASE .. "/proj-other/src/o.cc")
vim.bo.filetype = "cpp"
local cfgs2 = dap.configurations.cpp
eq("换项目后配置名跟着换（没有在插件加载时冻住）", cfgs2[1].name, "调试 Other_Test (全部)")
eq("换项目后 program 也跟着换", cfgs2[1].program, BASE .. "/proj-other/build-debug/bin/Other_Test")
eq("换项目后 cwd 也跟着换", cfgs2[1].cwd, BASE .. "/proj-other")

-- 切回 LearnCPP 再确认一次（防止只是单向漂移）
vim.cmd.edit(REAL .. "/tests/template_tester.cc")
vim.bo.filetype = "cpp"
eq("切回 LearnCPP 也对", dap.configurations.cpp[1].program, REAL .. "/build-Debug/bin/LearnCPP_Test")

-- 定位不到二进制的项目：不该塞坏配置进去
write(BASE .. "/proj-nowhere/CMakeLists.txt", "x\n")
write(BASE .. "/proj-nowhere/.nvim.yaml", "target: nope\n")
vim.cmd.edit(BASE .. "/proj-nowhere/a.cc")
vim.bo.filetype = "cpp"
eq("定位不到二进制时配置表为空（而不是 program=nil 的坏配置）", dap.configurations.cpp, {})

eq("<leader>tg 已注册", vim.fn.maparg("<leader>tg", "n", false, true).desc, "Debug gtest (可选 filter)")

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then
  print("\n失败项：")
  for _, x in ipairs(failures) do
    print("  ✗ " .. x)
  end
  os.exit(1)
end
print("全部通过")
