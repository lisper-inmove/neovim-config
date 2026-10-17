-- 真实会话验证：用**用户自己的配置**（不是 --clean）跑，走 lazy.nvim 的加载路径。
-- 跑法：./scripts/probe/run.sh（或 nvim --headless -c "luafile scripts/probe/probe-real-session.lua" -c "qa!"）

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

local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helper.lua")
local REAL = H.real_project
local TEST_FILE = REAL .. "/tests/tester.cc"

-- 等 lazy 把 neotest / nvim-dap 拉起来（docs/testing.md 里记的坑：
-- 消费者只在 setup() 之后才挂到模块上）
local ok_lazy, lazy = pcall(require, "lazy")
ok("lazy.nvim 可用", ok_lazy, tostring(lazy))
if ok_lazy then
  lazy.load({ plugins = { "neotest", "nvim-dap" } })
  vim.wait(60000, function()
    return package.loaded["neotest"] ~= nil and package.loaded["dap"] ~= nil
  end, 200)
end

ok("neotest 已加载", package.loaded["neotest"] ~= nil)
ok("nvim-dap 已加载", package.loaded["dap"] ~= nil)

-- project_config 在真实 rtp 下能被 require 到
local ok_pc, pc = pcall(require, "project_config")
ok("require('project_config') 可用（走真实 runtimepath）", ok_pc, tostring(pc))
if ok_pc then
  eq("真实项目根", pc.find_root(TEST_FILE), REAL)
  eq("真实二进制", pc.resolve(REAL).binary, REAL .. "/build-Debug/bin/LearnCPP_Test")
end

-- neotest 那边：适配器得在列表里，且 root 与 project_config 一致
local ok_nt, nt = pcall(require, "neotest_cpp")
ok("require('neotest_cpp') 可用", ok_nt, tostring(nt))
if ok_nt then
  eq("neotest_cpp.name", nt.name, "neotest_cpp")
  eq("neotest_cpp.root == project_config.find_root", nt.root(TEST_FILE), REAL)

  local ncfg = require("neotest.config")
  local found = false
  for _, a in ipairs(ncfg.adapters or {}) do
    if a.name == "neotest_cpp" then
      found = true
    end
  end
  ok(
    "neotest.config.adapters 里有 neotest_cpp",
    found,
    vim.inspect(vim.tbl_map(function(a)
      return a.name
    end, ncfg.adapters or {}))
  )
end

-- is_test_file 走真实文件（新代码路径会给它解析项目配置）
if ok_nt then
  -- 注意 tester.cc 里根本没有 TEST_F（实测 0 处），拿它当「是测试文件」的样例
  -- 会得到 false——那是 is_test_file 按内容判断的正确行为，不是回归。
  ok("is_test_file(template_tester.cc) == true", nt.is_test_file(REAL .. "/tests/template_tester.cc") == true)
  ok("is_test_file(tester.cc，无 TEST_F) == false", nt.is_test_file(TEST_FILE) == false)
  ok("is_test_file(.py) == false", nt.is_test_file(H.repo .. "/init.lua") == false)
end

-- debug.lua 那边：开一个真实 cpp 文件，FileType autocmd 应重建配置
vim.cmd.edit(TEST_FILE)
vim.bo.filetype = "cpp"
local dap = require("dap")
local cfgs = dap.configurations and dap.configurations.cpp
ok("dap.configurations.cpp 有配置", cfgs ~= nil and #cfgs == 2, vim.inspect(cfgs))
if cfgs and cfgs[1] then
  eq("配置名带项目二进制名", cfgs[1].name, "调试 LearnCPP_Test (全部)")
  eq("program 指向真实二进制", cfgs[1].program, REAL .. "/build-Debug/bin/LearnCPP_Test")
  eq("cwd 是项目根", cfgs[1].cwd, REAL)
  ok("二进制确实可执行", vim.fn.executable(cfgs[1].program) == 1, cfgs[1].program)
end
eq("codelldb 适配器已注册", type(dap.adapters.codelldb), "table")

-- 最深一层集成：neotest 真正会拿去执行的那条命令
if ok_nt then
  local tfile = REAL .. "/tests/template_tester.cc"
  local fake_tree = {
    data = function()
      return { type = "file", path = tfile, id = tfile, name = "template_tester.cc" }
    end,
    iter = function()
      return function()
        return nil
      end
    end,
  }

  local spec = nt.build_spec({ tree = fake_tree })
  ok("build_spec 返回了 spec", spec ~= nil, "返回 nil")
  if spec then
    local cmd = table.concat(spec.command, " ")
    ok("命令里带上了 CMake 构建步骤", cmd:find("cmake", 1, true) ~= nil, cmd)
    ok("命令里带上了 --target LearnCPP_Test", cmd:find("LearnCPP_Test", 1, true) ~= nil, cmd)
    ok("构建目录用的是相对项目根的路径", cmd:find("build-Debug", 1, true) ~= nil, cmd)
    ok("命令里带上了真实二进制", cmd:find(REAL .. "/build-Debug/bin/LearnCPP_Test", 1, true) ~= nil, cmd)
    eq("spec.cwd 是项目根", spec.cwd, REAL)
  end

  -- dap strategy 那条路：关掉 auto_build 再调，否则它会真去编译
  nt.setup({ auto_build = false })
  local dap_spec = nt.build_spec({ tree = fake_tree, strategy = "dap" })
  nt.setup({})
  ok("dap strategy 返回了 spec", dap_spec ~= nil, "返回 nil")
  if dap_spec then
    eq(
      "dap program 就是二进制本身（不能套 shell）",
      dap_spec.strategy.program,
      REAL .. "/build-Debug/bin/LearnCPP_Test"
    )
    eq("dap 适配器类型", dap_spec.strategy.type, "codelldb")
    eq("dap cwd 是项目根", dap_spec.strategy.cwd, REAL)
  end
end

print("")
print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then
  print("失败项：")
  for _, x in ipairs(failures) do
    print("  ✗ " .. x)
  end
  print("__PROBE_FAILED__")
  os.exit(1)
else
  print("全部通过")
  print("__PROBE_OK__")
end
