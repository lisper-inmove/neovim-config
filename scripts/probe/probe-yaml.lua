-- 探针：验证 lua/yaml_lite.lua 支持/拒绝的语法边界
-- 跑法：./scripts/probe/run.sh（或 nvim --clean -l scripts/probe/probe-yaml.lua）

local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helper.lua")
H.rtp()

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

local ok_req, yaml = pcall(require, "yaml_lite")
if not ok_req then
  print("FATAL: require('yaml_lite') 失败: " .. tostring(yaml))
  os.exit(1)
end

-- 成功解析的用例
local function parse_ok(label, src, want)
  local got, err = yaml.parse(src)
  if err then
    ok(label, false, "意外报错: " .. err)
  else
    eq(label, got, want)
  end
end

-- 必须报错的用例（报错要给人看，所以断言「有错且信息里含关键词」）
local function parse_err(label, src, keyword)
  local got, err = yaml.parse(src)
  if err == nil then
    ok(label, false, "本该报错却返回了: " .. vim.inspect(got))
  else
    ok(label, err:find(keyword, 1, true) ~= nil, ("报错信息里没有 %q: %s"):format(keyword, err))
  end
end

-- ---------- 基本 ----------
parse_ok("空字符串 → 空表", "", {})
parse_ok("只有注释和空行 → 空表", "# 注释\n\n   \n", {})
parse_ok("单个 key", "target: LearnCPP_Test", { target = "LearnCPP_Test" })
parse_ok("多个 key", "target: A\nbuild_dir: b", { target = "A", build_dir = "b" })
parse_ok("键里有 - _ .", "auto-build: 1\nmy_key: 2\na.b: 3", { ["auto-build"] = 1, my_key = 2, ["a.b"] = 3 })

-- ---------- 标量类型 ----------
parse_ok("true/false → boolean", "auto_build: true\nother: false", { auto_build = true, other = false })
parse_ok("整数 → number", "n: 42", { n = 42 })
parse_ok("小数 → number", "n: 1.5", { n = 1.5 })
parse_ok("负号开头不误判成列表", "n: -1", { n = -1 })
parse_ok("双引号去引号", 'binary: "out/Rel/my tests"', { binary = "out/Rel/my tests" })
parse_ok("单引号去引号", "binary: 'out/Rel'", { binary = "out/Rel" })
parse_ok("null → 键消失", "a: null\nb: 1", { b = 1 })

-- ---------- 注释 ----------
parse_ok("整行注释被忽略", "# 说明\ntarget: A", { target = "A" })
parse_ok("行尾注释被去掉", "target: A # 说明", { target = "A" })
parse_ok("引号里的 # 不当注释", 'target: "a#b"', { target = "a#b" })
parse_ok("紧贴值的 # 不当注释", "target: a#b", { target = "a#b" })

-- ---------- 列表 ----------
parse_ok("块列表（缩进）", "extensions:\n  - cc\n  - cpp\n", { extensions = { "cc", "cpp" } })
parse_ok("块列表（不缩进也认）", "extensions:\n- cc\n- cpp\n", { extensions = { "cc", "cpp" } })
parse_ok(
  "块列表后面还能跟别的 key",
  "extensions:\n  - cc\nbuild_dir: b",
  { extensions = { "cc" }, build_dir = "b" }
)
parse_ok("行内列表", "extensions: [cc, cpp, cxx]", { extensions = { "cc", "cpp", "cxx" } })
parse_ok("行内列表带引号和空格", 'extensions: [ "cc" , cpp ]', { extensions = { "cc", "cpp" } })
parse_ok("行内空列表", "extensions: []", { extensions = {} })
parse_ok("列表项本身是数字", "nums:\n  - 1\n  - 2", { nums = { 1, 2 } })

-- ---------- 真实配置文件长相 ----------
parse_ok(
  "LearnCPP 的实际配置（含注释与行尾注释）",
  [[
# C++ 测试/调试配置
target: LearnCPP_Test        # 只要名字，Debug 构建目录由 CMake 配置自动找

auto_build: true
extensions:
  - cc
  - cpp
  - cxx
]],
  { target = "LearnCPP_Test", auto_build = true, extensions = { "cc", "cpp", "cxx" } }
)

-- ---------- CRLF（Windows 上编辑过的文件）----------
parse_ok("CRLF 行尾", "target: A\r\nbuild_dir: b\r\n", { target = "A", build_dir = "b" })

-- ---------- 值里含冒号（split 只能切第一个冒号）----------
parse_ok("值里有冒号", "binary: out/a:b", { binary = "out/a:b" })
parse_ok("Windows 盘符路径", "binary: F:/codes/x", { binary = "F:/codes/x" })

-- ---------- 必须报错 ----------
parse_err("重复 key", "target: A\ntarget: B", "重复")
parse_err("嵌套映射", "foo:\n  bar: 1", "嵌套")
parse_err("裸 key（没冒号）", "target LearnCPP_Test", "第 1 行")
parse_err("列表项没有归属 key", "- cc", "没有归属")

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then
  print("\n失败项：")
  for _, x in ipairs(failures) do
    print("  ✗ " .. x)
  end
  os.exit(1)
end
print("全部通过")
