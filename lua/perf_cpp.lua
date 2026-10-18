-- 对单个 gtest 用例做 perf 采样，并把 perf report 开在浮窗终端里
--
-- 入口（键位注册见 lua/plugins/neotest-cpp.lua）：
--   <leader>tp  光标所在用例（复用 neotest_cpp 的 TEST_F 解析）
--   <leader>tP  从 --gtest_list_tests 里选用例
--
-- 二进制、构建命令、是否自动编译都来自 lua/project_config.lua
-- （项目根 .nvim.yaml > 插件 opts > 默认），换项目不需要改这个文件。
--
-- 为什么不是「跑一次然后 perf」：
--   单元测试通常几十微秒就结束，perf 默认 4000Hz 也只能采到个位数样本。
--   这里用 --gtest_repeat=-1 一直重复，再用 timeout 限制总时长，
--   快的用例攒够样本、慢的用例最多也只跑 10 秒。
--   采样频率降到 999Hz，10 秒约 1 万样本、几十 MB，足够看调用链。

local project_config = require("project_config")

local M = {}

local SAMPLE_SECONDS = 10
local SAMPLE_FREQ = 999

-- 数据文件放 /tmp：一次采样可能几十 MB，重启自动清掉。
-- 文件名按用例名固定，重跑同一个用例会覆盖上一次的数据。
local DATA_DIR = "/tmp/nvim-perf"

---@return project_config.Resolved
local function cfg()
  return project_config.resolve_for_buffer()
end

---@param label string
---@return string
local function datafile_for(label)
  vim.fn.mkdir(DATA_DIR, "p")
  return ("%s/%s.data"):format(DATA_DIR, (label:gsub("[^%w_.-]", "_")))
end

-- 定位不到二进制时不拼一条 binary=nil 的命令去跑：c.problem 里已经写好了
-- 「为什么没找到 + 下一步」，和 debug.lua 的 ensure_binary 保持一致。
-- 二进制还没构建过但项目能给出构建命令时先放行，让 run_profile 编译后再检查，
-- 这样第一次使用不用手动先 make。
---@param c project_config.Resolved
---@return string|nil
local function ensure_binary(c)
  if c.binary and vim.fn.executable(c.binary) == 1 then
    return c.binary
  end
  if c.binary and #(c.build_args or {}) > 0 then
    return c.binary
  end

  local msg = c.problem or ("测试可执行文件不存在：%s"):format(tostring(c.binary))
  if c.build_hint ~= "" then
    msg = msg .. "\n构建命令：" .. c.build_hint
  end
  vim.notify(msg, vim.log.levels.ERROR)
  return nil
end

-- 同步等一次增量编译。走 perf 之前必须保证二进制是最新的，
-- 否则采到的是旧代码的性能（做法与 neotest_cpp.lua 里的 build_sync 一致）。
---@param c project_config.Resolved
---@return boolean
local function build_sync(c)
  local ok, res = pcall(function()
    return vim.system(c.build_args, { cwd = c.root, text = true }):wait()
  end)
  if not ok or res.code ~= 0 then
    local out = ok and ((res.stderr ~= "" and res.stderr) or res.stdout or "") or tostring(res)
    vim.notify("编译失败:\n" .. tostring(out):sub(1, 1000), vim.log.levels.ERROR)
    return false
  end
  return true
end

-- 解析 --gtest_list_tests 的输出（格式：`Suite.` 下一行缩进列出用例名）。
-- 和 <leader>tg 的 list_tests 是同一套解析；两边各自保留一份，
-- 避免 <leader>tg 所在文件的加载时机影响 perf 入口。
---@param bin string
---@return string[]
local function list_tests(bin)
  local lines = vim.fn.systemlist({ bin, "--gtest_list_tests" })
  local tests, suite = {}, nil
  for _, line in ipairs(lines) do
    if line:match("^%S.*%.$") then
      suite = line:gsub("%.$", "") -- "Tester." → "Tester"
    elseif suite and line:match("^%s+%S") then
      tests[#tests + 1] = suite .. "." .. vim.trim(line)
    end
  end
  return tests
end

-- 光标所在（或最近的前一个）用例的 gtest 全名。
-- 直接用 neotest_cpp.discover_positions：TEST_F 的 tree-sitter 查询只维护一份，
-- 不在 perf 这边重写（两处解析迟早会跟 tree-sitter 版本走散）。
-- 解析失败（没有 tree-sitter-cpp、缓冲区没名字…）时返回 nil，调用方退回选择器。
---@return string|nil
function M.test_at_cursor()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return nil
  end

  -- 先确保 neotest 本体已加载并跑完 LazyVim 的 config。
  -- 直接 require("neotest_cpp") 会先加载 neotest.lib，触发 Lazy 的模块加载，
  -- 而它的 config 又要 require("neotest_cpp") —— 形成循环（实测）。
  -- 交互路径下按键会先加载插件，这里是给 :lua 直接调用兜底。
  pcall(require, "neotest")

  -- discover_positions 是 nio 异步函数，普通上下文里直接调会报
  -- "Cannot call async function from non-async context"。
  -- 放到 nio.run 里跑，再用 vim.wait 等结果；单个文件的解析是毫秒级。
  local has_nio, nio = pcall(require, "nio")
  if not has_nio then
    return nil
  end

  local tree, done
  nio.run(function()
    local ok, t = pcall(function()
      return require("neotest_cpp").discover_positions(path)
    end)
    if ok then
      tree = t
    end
    done = true
  end)
  vim.wait(2000, function()
    return done == true
  end)
  if not tree then
    return nil
  end

  local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- neotest 的 range 从 0 开始
  local containing, preceding, preceding_row
  for _, pos in tree:iter() do
    if pos.type == "test" and pos.range then
      local start_row, end_row = pos.range[1], pos.range[3]
      if start_row <= row and row <= end_row then
        containing = pos
        break
      end
      if start_row <= row and (not preceding_row or start_row > preceding_row) then
        preceding, preceding_row = pos, start_row
      end
    end
  end

  local pos = containing or preceding
  return pos and pos.name or nil
end

---@param c project_config.Resolved
---@param filter string|nil
---@param label string
local function run_profile(c, filter, label)
  if c.auto_build then
    vim.notify("perf 前先增量编译…", vim.log.levels.INFO)
    if not build_sync(c) then
      return
    end
  end

  if vim.fn.executable(c.binary) ~= 1 then
    local msg = ("找不到测试可执行文件：%s"):format(c.binary)
    if c.build_hint ~= "" then
      msg = msg .. "\n构建命令：" .. c.build_hint
    end
    vim.notify(msg, vim.log.levels.ERROR)
    return
  end

  local data = datafile_for(label)

  local cmd = {
    "perf", "record",
    "-F", tostring(SAMPLE_FREQ),
    "-g", "--call-graph", "dwarf",
    "-o", data,
    "--",
    "timeout", ("%ds"):format(SAMPLE_SECONDS),
    c.binary,
  }
  -- 空过滤器不传：gtest 里 --gtest_filter= 空值匹配不到任何用例
  if filter and filter ~= "" then
    cmd[#cmd + 1] = "--gtest_filter=" .. filter
  end
  cmd[#cmd + 1] = "--gtest_repeat=-1" -- 一直重复，由 timeout 截止
  cmd[#cmd + 1] = "--gtest_brief=1" -- 只报失败，但每轮仍有两行，stdout 直接丢弃

  vim.notify(("perf 采样中（%d 秒）：%s"):format(SAMPLE_SECONDS, label), vim.log.levels.INFO)

  -- stdout 丢弃：brief 模式每轮仍会打印两行，跑 10 秒能到几万行，
  -- 捕获进内存没有意义。perf 自己的进度/错误在 stderr，保留用于失败提示。
  vim.system(cmd, { cwd = c.root, text = true, stdout = false }, function(res)
    -- on_exit 在 fast event context 里，UI 操作统一 schedule 回主循环
    vim.schedule(function()
      local stat = vim.uv.fs_stat(data)
      if not stat or stat.size == 0 then
        local err = (res and res.stderr or ""):gsub("%s+$", "")
        if err == "" then
          err = "退出码 " .. tostring(res and res.code or "?")
        end
        vim.notify("perf 采样失败：" .. err, vim.log.levels.ERROR)
        return
      end

      -- perf record 遇到已存在的输出会把旧文件改名成 .old；采样成功后清掉，
      -- 免得反复按 <leader>tp 在 /tmp 里堆双份数据。
      vim.fn.delete(data .. ".old")

      -- timeout 杀掉测试进程时 perf record 返回 124，这是正常路径；
      -- 成功与否只看数据文件有没有内容。
      local msg = ("perf 数据：%s（%.1f MB）"):format(data, stat.size / 1024 / 1024)
      if (c.binary or ""):find("build%-[Dd]ebug") or (c.build_dir or ""):find("[Dd]ebug") then
        msg = msg
          .. "\n当前是 Debug(-O0) 构建，优化后的热点会不同；"
          .. "要看真实性能可把 .nvim.yaml 的 target 和 build_dir 都指向 RelWithDebInfo 构建"
      end
      vim.notify(msg, vim.log.levels.INFO)

      Snacks.terminal.open({ "perf", "report", "-i", data }, { cwd = c.root })
    end)
  end)
end

---@param c project_config.Resolved
local function pick_and_profile(c)
  -- 选择器要先执行 --gtest_list_tests，二进制不存在就列不出用例；
  -- 第一次使用时先编译一次（run_profile 里还会再增量编译，代价很小）。
  if vim.fn.executable(c.binary) ~= 1 then
    if not (c.auto_build and build_sync(c)) then
      vim.notify(("测试可执行文件不存在，无法列出用例：%s"):format(c.binary), vim.log.levels.ERROR)
      return
    end
  end

  local tests = list_tests(c.binary)
  if #tests == 0 then
    vim.notify(
      ("未能从二进制列出测试，请先构建：%s"):format(c.build_hint),
      vim.log.levels.WARN
    )
    return
  end
  table.insert(tests, 1, "▶ 运行全部测试")
  table.insert(tests, 2, "⌨ 手动输入过滤器…")
  vim.ui.select(tests, { prompt = "选择要 perf 的测试:" }, function(choice)
    if choice == nil then
      return -- 取消
    end
    if choice == "▶ 运行全部测试" then
      run_profile(c, nil, "all")
    elseif choice == "⌨ 手动输入过滤器…" then
      vim.ui.input(
        { prompt = "gtest_filter (如 *Hist* 或 Tester.OpenCV_Hist_Match; 留空=全部): " },
        function(input)
          if input == nil then
            return
          end
          local filter = input ~= "" and input or nil
          run_profile(c, filter, filter or "all")
        end
      )
    else
      run_profile(c, choice, choice)
    end
  end)
end

-- <leader>tp：perf 光标所在用例
function M.profile_cursor()
  local c = cfg()
  if not ensure_binary(c) then
    return
  end

  local name = M.test_at_cursor()
  if not name then
    vim.notify("光标不在任何 gtest 用例内，改为手动选择", vim.log.levels.WARN)
    pick_and_profile(c)
    return
  end

  run_profile(c, name, name)
end

-- <leader>tP：从测试列表选用例
function M.profile_picker()
  local c = cfg()
  if not ensure_binary(c) then
    return
  end
  pick_and_profile(c)
end

return M
