-- 回归探针：neotest 会在 **fast event context**（libuv 回调/nio 协程）里调
-- is_test_file 和 build_spec。那里 vim.fn.getcwd / vim.fn.shellescape /
-- vim.notify 都会抛 E5560（实测），所以这些代码路径只能用 uv / io / vim.fs。
--
-- 症状：is_test_file 一抛错，neotest 的 _update_positions 整个中止，
--       <leader>tr 就报 "No tests found"。
--
-- 跑法：./scripts/probe/run.sh（或 nvim --clean -l scripts/probe/probe-fastctx.lua）

local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helper.lua")
H.rtp("neotest", "nvim-nio")

local BASE = H.tmp .. "/fixtures-fastctx"
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

-- fixture：一个正常项目 + 一个「没有 .nvim.yaml / 没有标志文件」的目录
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

vim.fn.delete(BASE, "rf")
write(BASE .. "/proj/CMakeLists.txt", "x\n")
write(BASE .. "/proj/.nvim.yaml", "target: build-Debug/bin/t\n")
write(BASE .. "/proj/build-Debug/CMakeCache.txt", "CMAKE_BUILD_TYPE:STRING=Debug\n")
write_exe(BASE .. "/proj/build-Debug/bin/t")
write(BASE .. "/proj/tests/case.cc", "TEST_F(S, N) {}\n")
write(BASE .. "/proj/tests/plain.cc", "int main() {}\n")
write(BASE .. "/outside/notes.txt", "hi\n")
write(BASE .. "/outside/x.cc", "TEST_F(S, N) {}\n") -- 有 gtest 宏，但不在任何项目里

local nt = require("neotest_cpp")
local pc = require("project_config")

-- 在 libuv 回调里跑 = 真正的 fast event context
local results, done = {}, false
local timer = vim.uv.new_timer()
timer:start(10, 0, function()
  local function trial(label, fn)
    local okk, res = pcall(fn)
    results[#results + 1] = { label = label, ok = okk, res = res }
  end

  trial("is_test_file(项目内的 .cc，含 TEST_F)", function()
    return nt.is_test_file(BASE .. "/proj/tests/case.cc")
  end)
  trial("is_test_file(项目内的 .cc，无 TEST_F)", function()
    return nt.is_test_file(BASE .. "/proj/tests/plain.cc")
  end)
  trial("is_test_file(项目外的 .cc)", function()
    return nt.is_test_file(BASE .. "/outside/x.cc")
  end)
  trial("is_test_file(.txt)", function()
    return nt.is_test_file(BASE .. "/outside/notes.txt")
  end)
  trial("resolve(项目根)", function()
    return pc.resolve(BASE .. "/proj")
  end)
  trial("resolve_for_path(项目内文件)", function()
    return pc.resolve_for_path(BASE .. "/proj/tests/case.cc")
  end)
  trial("resolve_for_path(项目外文件)", function()
    return pc.resolve_for_path(BASE .. "/outside/x.cc")
  end)

  -- build_spec 也跑在同一个 fast context 里，它拼 shell 命令时同样不能用 vim.fn.*
  local fake_tree = {
    data = function()
      return { type = "test", path = BASE .. "/proj/tests/case.cc", id = "id", name = "S.N" }
    end,
    iter = function()
      return function()
        return nil
      end
    end,
  }
  trial("build_spec(普通运行)", function()
    return nt.build_spec({ tree = fake_tree })
  end)
  trial("build_spec(dap)", function()
    nt.setup({ auto_build = false }) -- 别真去编译
    local r = nt.build_spec({ tree = fake_tree, strategy = "dap" })
    nt.setup({})
    return r
  end)
  done = true
end)
vim.wait(5000, function()
  return done
end, 50)

local expect = {
  ["is_test_file(项目内的 .cc，含 TEST_F)"] = true,
  ["is_test_file(项目内的 .cc，无 TEST_F)"] = false,
  ["is_test_file(项目外的 .cc)"] = true, -- 有 TEST_F 就认（扩展名走默认）
  ["is_test_file(.txt)"] = false,
}
for _, r in ipairs(results) do
  ok(r.label .. " 在 fast context 里不抛错", r.ok, r.ok and "" or ("E5560 之类: " .. tostring(r.res)))
  if r.ok and expect[r.label] ~= nil then
    ok(r.label .. " 返回值正确", r.res == expect[r.label], ("got %s"):format(tostring(r.res)))
  end
end

ok("9 项都跑到了", #results == 9, ("只跑了 %d 项 —— 可能中途抛错"):format(#results))

-- build_spec 的产物形状也要对
for _, r in ipairs(results) do
  if r.label == "build_spec(普通运行)" and r.ok and type(r.res) == "table" then
    local cmd = table.concat(r.res.command, " ")
    ok("build_spec 普通运行带上构建步骤", cmd:find("cmake", 1, true) ~= nil, cmd)
    ok("build_spec 普通运行带上二进制", cmd:find("build-Debug/bin/t", 1, true) ~= nil, cmd)
  end
  if r.label == "build_spec(dap)" and r.ok and type(r.res) == "table" then
    ok(
      "build_spec dap 的 program 是二进制",
      r.res.strategy.program == BASE .. "/proj/build-Debug/bin/t",
      tostring(r.res.strategy.program)
    )
  end
end

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then
  print("\n失败项：")
  for _, x in ipairs(failures) do
    print("  ✗ " .. x)
  end
  os.exit(1)
end
print("全部通过")
