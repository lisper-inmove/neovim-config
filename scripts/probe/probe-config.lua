-- 探针：验证 lua/project_config.lua
-- 跑法：./scripts/probe/run.sh（或 nvim --clean -l scripts/probe/probe-config.lua）
-- 一次性验证，不进仓库。

local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helper.lua")
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
local function contains(label, haystack, needle)
  ok(
    label,
    type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil,
    ("%q 里没有 %q"):format(tostring(haystack), needle)
  )
end

-- ---------- 造 fixture ----------
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
-- CMake 构建目录的判定依据就是它：CMakeCache.txt 里的 CMAKE_BUILD_TYPE
local function make_build_dir(dir, build_type)
  write(
    dir .. "/CMakeCache.txt",
    "# 注释行\nCMAKE_BUILD_TYPE:STRING=" .. build_type .. "\nCMAKE_HOME_DIRECTORY:INTERNAL=/x\n"
  )
end

vim.fn.delete(BASE, "rf")

-- A: 正常路径 —— 只有 target 名字，Debug 目录靠 CMake 配置找出来
write(BASE .. "/proj-a/CMakeLists.txt", "cmake_minimum_required(VERSION 3.16)\n")
write(BASE .. "/proj-a/.nvim.yaml", "target: t_a\n")
make_build_dir(BASE .. "/proj-a/build-debug", "Debug")
write_exe(BASE .. "/proj-a/build-debug/bin/t_a")
write(BASE .. "/proj-a/src/deep/file.cc", "TEST_F(S, N) {}\n")

-- B: 没配置文件 → 不该瞎猜目标名
write(BASE .. "/proj-b/CMakeLists.txt", "x\n")
make_build_dir(BASE .. "/proj-b/build", "Debug")

-- C: 有 target 名字，但项目里没有 CMake 构建目录
write(BASE .. "/proj-c/.nvim.yaml", "target: t_c\n")
write(BASE .. "/proj-c/src/x.cc", "TEST_F(S, N) {}\n")

-- D: YAML 写坏了（嵌套映射）→ 提示 + 退回默认，不炸
write(BASE .. "/proj-d/CMakeLists.txt", "x\n")
write(BASE .. "/proj-d/.nvim.yaml", "foo:\n  bar: 1\n")
make_build_dir(BASE .. "/proj-d/build-debug", "Debug")
write_exe(BASE .. "/proj-d/build-debug/bin/t_d")

-- E: 显式 build_dir 绕过 Debug 查找；二进制直接躺在构建目录根（不在 bin/）
write(BASE .. "/proj-e/.nvim.yaml", "target: t_e\nbuild_dir: build-X\n")
make_build_dir(BASE .. "/proj-e/build-X", "Release")
write_exe(BASE .. "/proj-e/build-X/t_e")

-- F: auto_build / extensions 覆盖
write(BASE .. "/proj-f/.nvim.yaml", "target: t_f\nauto_build: false\nextensions: [cpp]\n")
make_build_dir(BASE .. "/proj-f/build-debug", "Debug")
write_exe(BASE .. "/proj-f/build-debug/bin/t_f")

-- G: 路径写法 + build_args 逃生舱（target 本身就是二进制路径，不再有 binary 字段）
write(BASE .. "/proj-g/.nvim.yaml", 'target: "out/Rel/my_tests"\nbuild_args: [make, -C, out/Rel]\n')

-- H: 多个 Debug 构建目录 → 优先路径里带 debug 的那个
write(BASE .. "/proj-h/.nvim.yaml", "target: t_h\n")
make_build_dir(BASE .. "/proj-h/build-apple", "Debug")
write_exe(BASE .. "/proj-h/build-apple/bin/t_h")
make_build_dir(BASE .. "/proj-h/build-Debug2", "Debug")
write_exe(BASE .. "/proj-h/build-Debug2/bin/t_h")

-- I: 先失败后成功（失败不该被缓存）
write(BASE .. "/proj-i/.nvim.yaml", "target: t_i\n")

-- J: 非 Debug 只有 Release → 该报错并列出找到的东西
write(BASE .. "/proj-j/.nvim.yaml", "target: t_j\n")
make_build_dir(BASE .. "/proj-j/build", "Release")

-- K: target 写成**相对项目根的路径** → 直接指向二进制，不再按名字找
write(BASE .. "/proj-k/.nvim.yaml", "target: build-k/out/k_test\n")
make_build_dir(BASE .. "/proj-k/build-k", "Debug")
write_exe(BASE .. "/proj-k/build-k/out/k_test")
-- 同一项目里还有个同名但位置不同的诱饵，确认路径写法不会去猜
write_exe(BASE .. "/proj-k/build-k/bin/k_test")

-- L: 路径写法 + 还没构建 → binary 仍给出来、auto_build 为 true（跑前会先编译）
write(BASE .. "/proj-l/.nvim.yaml", "target: build-l/bin/l_test\n")
make_build_dir(BASE .. "/proj-l/build-l", "Debug")

-- M: 路径写法 + 显式 build_dir（构建目录不去探测）
write(BASE .. "/proj-m/.nvim.yaml", "target: custom/place/m_test\nbuild_dir: build-M\n")
write(BASE .. "/proj-m/build-M/CMakeCache.txt", "CMAKE_BUILD_TYPE:STRING=Release\n")
write_exe(BASE .. "/proj-m/custom/place/m_test")

-- ---------- 开测 ----------
local ok_req, pc = pcall(require, "project_config")
if not ok_req then
  print("FATAL: require('project_config') 失败: " .. tostring(pc))
  os.exit(1)
end

-- 抓通知：有些用例预期会 notify，不想让它糊在输出里
local notes = {}
local real_notify = vim.notify
vim.notify = function(msg, level)
  notes[#notes + 1] = { msg = tostring(msg), level = level }
end
local function note_count()
  return #notes
end

-- 1. 找根
eq("find_root 从嵌套子目录向上找", pc.find_root(BASE .. "/proj-a/src/deep/file.cc"), BASE .. "/proj-a")
eq("find_root 对目录本身也成立", pc.find_root(BASE .. "/proj-a"), BASE .. "/proj-a")
eq("find_root 找不到返回 nil", pc.find_root("/tmp"), nil)
eq("find_root 认 .nvim.yaml 这个标志（无 CMake 的项目）", pc.find_root(BASE .. "/proj-c"), BASE .. "/proj-c")

-- 2. 主路径：target 名字 → CMake 配 Debug 目录 → 按名字找到二进制
local a = pc.resolve(BASE .. "/proj-a")
eq("A.root", a.root, BASE .. "/proj-a")
eq("A.target", a.target, "t_a")
eq("A.name", a.name, "t_a")
eq("A.build_dir 是从 CMakeCache 认出的 Debug 目录", a.build_dir, BASE .. "/proj-a/build-debug")
eq("A.binary 按名字找到（bin/ 不是硬编码的）", a.binary, BASE .. "/proj-a/build-debug/bin/t_a")
eq("A.build_args 用相对构建目录", a.build_args, { "cmake", "--build", "build-debug", "--target", "t_a" })
eq("A.auto_build 默认 true", a.auto_build, true)
eq("A.extensions 默认三项", a.extensions, { "cc", "cpp", "cxx" })
eq("A 没有 problem", a.problem, nil)

-- 3. 没配置文件 → 不瞎猜目标名，明确说不出来
local b = pc.resolve(BASE .. "/proj-b")
eq("B.binary 为 nil", b.binary, nil)
contains("B.problem 指明要写 target", b.problem, "target")
ok("B 仍然给出 extensions（is_test_file 不该因此挂掉）", #b.extensions == 3, vim.inspect(b.extensions))

-- 4. 有 target 但没构建目录
local c = pc.resolve(BASE .. "/proj-c")
eq("C.binary 为 nil", c.binary, nil)
contains("C.problem 提到 CMakeCache.txt", c.problem, "CMakeCache.txt")
contains("C.problem 给出配置建议", c.problem, "-DCMAKE_BUILD_TYPE=Debug")

-- 5. YAML 坏了
local before = note_count()
local d = pc.resolve(BASE .. "/proj-d")
ok("D 坏 YAML 会 notify", note_count() > before, "没通知")
contains("D.problem 是「没写 target」", d.problem, "target")

-- 6. 显式 build_dir 绕过 Debug 检查；二进制不在 bin/ 也能找到
local e = pc.resolve(BASE .. "/proj-e")
eq("E.binary 在构建目录根也能找到", e.binary, BASE .. "/proj-e/build-X/t_e")
eq("E.build_args", e.build_args, { "cmake", "--build", "build-X", "--target", "t_e" })

-- 7. auto_build / extensions 覆盖
local f = pc.resolve(BASE .. "/proj-f")
eq("F.auto_build 被覆盖", f.auto_build, false)
eq("F.extensions 被覆盖", f.extensions, { "cpp" })

-- 8. 逃生舱
local g = pc.resolve(BASE .. "/proj-g")
eq("G.binary 相对根", g.binary, BASE .. "/proj-g/out/Rel/my_tests")
eq("G.build_args 原样使用", g.build_args, { "make", "-C", "out/Rel" })
eq("G.target 归一成文件名", g.target, "my_tests")

-- 9. 多个 Debug 目录 → 稳定选择 + 提示
local before_h = note_count()
local h = pc.resolve(BASE .. "/proj-h")
eq("H 优先路径里带 debug 的那个", h.build_dir, BASE .. "/proj-h/build-Debug2")
ok("H 会提示有多个 Debug 目录", note_count() > before_h, "没通知")

-- 10. 失败结果不缓存：cmake configure 完回 nvim 就能用
local i = pc.resolve(BASE .. "/proj-i")
eq("I 一开始找不到", i.binary, nil)
make_build_dir(BASE .. "/proj-i/build-debug", "Debug")
write_exe(BASE .. "/proj-i/build-debug/bin/t_i")
local i2 = pc.resolve(BASE .. "/proj-i")
eq("I 构建目录出现后立刻能找到（失败没被缓存）", i2.binary, BASE .. "/proj-i/build-debug/bin/t_i")

-- 11. 只有 Release 时要说清楚找到了什么
local j = pc.resolve(BASE .. "/proj-j")
eq("J.binary 为 nil", j.binary, nil)
contains("J.problem 列出实际的 CMAKE_BUILD_TYPE", j.problem, "CMAKE_BUILD_TYPE=Release")

-- 11b. target 写成相对项目根的路径
local k = pc.resolve(BASE .. "/proj-k")
eq("K.binary 直接按路径拼根", k.binary, BASE .. "/proj-k/build-k/out/k_test")
eq("K.build_dir 仍从 CMake 配置探测", k.build_dir, BASE .. "/proj-k/build-k")
eq(
  "K 的 --target 取文件名（不是整条路径）",
  k.build_args,
  { "cmake", "--build", "build-k", "--target", "k_test" }
)
eq("K.target 归一成目标名", k.target, "k_test")
eq("K.name 归一成目标名", k.name, "k_test")
eq("K 没有 problem", k.problem, nil)

-- 11c. 路径写法但二进制还没构建：仍给出路径，auto_build 负责先编译
local l = pc.resolve(BASE .. "/proj-l")
eq("L.binary 仍是完整路径", l.binary, BASE .. "/proj-l/build-l/bin/l_test")
eq("L.auto_build 为 true（跑前会先编译出来）", l.auto_build, true)
eq("L 没有 problem", l.problem, nil)
eq("L 的构建命令", l.build_args, { "cmake", "--build", "build-l", "--target", "l_test" })

-- 11d. 路径写法 + 显式 build_dir（不探测，也就允许非 Debug）
local m = pc.resolve(BASE .. "/proj-m")
eq("M.binary 按路径", m.binary, BASE .. "/proj-m/custom/place/m_test")
eq("M.build_dir 用显式值", m.build_dir, BASE .. "/proj-m/build-M")
eq("M 的 --target 取文件名", m.build_args, { "cmake", "--build", "build-M", "--target", "m_test" })

-- 12. mtime 变化要失效缓存（只改 target，其它字段留着，后面第 17 步还要用）
write(BASE .. "/proj-f/.nvim.yaml", "target: t_f_renamed\nauto_build: false\nextensions: [cpp]\n")
local f2 = pc.resolve(BASE .. "/proj-f")
eq("F 改 YAML 后重新解析（配置缓存按 mtime 失效）", f2.target, "t_f_renamed")

-- 12b. 更狠一点：新旧二进制**都存在**时改 target，必须切到新的。
-- 只按根缓存探测结果的实现会在这里返回旧二进制（旧文件在，executable 检查照样过）
write_exe(BASE .. "/proj-f/build-debug/bin/t_f2")
write(BASE .. "/proj-f/.nvim.yaml", "target: t_f2\nauto_build: false\nextensions: [cpp]\n")
local f3 = pc.resolve(BASE .. "/proj-f")
eq(
  "F 改 target 后切到新二进制（探测缓存要认 target，不能只按根）",
  f3.binary,
  BASE .. "/proj-f/build-debug/bin/t_f2"
)
eq("F3.target", f3.target, "t_f2")

-- 13. 无文件缓冲区回退 cwd，不报错
vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(false, true))
local ok_buf, root_buf = pcall(pc.root_for_buffer)
ok("root_for_buffer 对 [No Name] 不抛异常", ok_buf, tostring(root_buf))
ok("root_for_buffer 回退到 cwd", ok_buf and root_buf == vim.fn.getcwd(), tostring(root_buf))

-- 14. 真实项目：与改动前写死的路径一致
local real_root = pc.find_root(REAL .. "/tests")
eq("真实项目根", real_root, REAL)
local real = pc.resolve(real_root)
eq("真实项目的 Debug 构建目录", real.build_dir, REAL .. "/build-Debug")
eq("真实二进制 = 改动前写死的那个", real.binary, REAL .. "/build-Debug/bin/LearnCPP_Test")
ok("真实二进制可执行", vim.fn.executable(real.binary) == 1, tostring(real.binary))
eq("真实构建命令", real.build_args, { "cmake", "--build", "build-Debug", "--target", "LearnCPP_Test" })
eq("真实项目没有 problem", real.problem, nil)

-- 15. 性能：resolve 会被 is_test_file 频繁调用，不能明显卡手
pc.clear_cache() -- 连探测缓存一起清掉，量的是最坏情况
local t0 = vim.uv.hrtime()
pc.resolve(real_root)
local cold_ms = (vim.uv.hrtime() - t0) / 1e6
local t1 = vim.uv.hrtime()
for _ = 1, 100 do
  pc.resolve(real_root)
end
local warm_ms = (vim.uv.hrtime() - t1) / 1e6 / 100
ok(("冷启动解析 < 200ms（实测 %.1fms）"):format(cold_ms), cold_ms < 200, ("%.1fms"):format(cold_ms))
ok(("缓存后解析 < 2ms（实测 %.3fms）"):format(warm_ms), warm_ms < 2, ("%.3fms"):format(warm_ms))

-- 16. neotest_cpp 与 project_config 的根必须一致
local ok_nt, nt = pcall(require, "neotest_cpp")
if ok_nt then
  eq(
    "neotest_cpp.root == project_config.find_root（真实项目）",
    nt.root(REAL .. "/tests"),
    pc.find_root(REAL .. "/tests")
  )
  eq(
    "neotest_cpp.root 也认 .nvim.yaml 定的根",
    nt.root(BASE .. "/proj-c/src/x.cc"),
    pc.find_root(BASE .. "/proj-c/src/x.cc")
  )
else
  ok("require neotest_cpp", false, tostring(nt))
end

-- 17. 优先级：项目 .nvim.yaml > 插件 spec 的 opts > 内置默认
if ok_nt then
  local nt_m = require("neotest_cpp")
  nt_m.setup({ auto_build = false, extensions = { "zzz" } })
  eq(
    "opts 里的 extensions 生效（项目没写这个字段时）",
    pc.resolve(BASE .. "/proj-a", nt_m.opts).extensions,
    { "zzz" }
  )
  eq("项目 YAML 压过 opts", pc.resolve(BASE .. "/proj-f", nt_m.opts).extensions, { "cpp" })
  eq("项目 YAML 的 auto_build 也压过 opts", pc.resolve(BASE .. "/proj-f", nt_m.opts).auto_build, false)
  nt_m.setup({})
  local d_after = pc.resolve(BASE .. "/proj-d")
  eq("D 走默认 targets（坏 YAML 没留下脏数据）", d_after.target, nil)
end

vim.notify = real_notify

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then
  print("\n失败项：")
  for _, x in ipairs(failures) do
    print("  ✗ " .. x)
  end
  os.exit(1)
end
print("全部通过")
