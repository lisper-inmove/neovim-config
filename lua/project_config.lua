-- 项目根的 C++ 测试/调试配置：读 <项目根>/.nvim.yaml
--
-- 为什么需要它：
--   debug.lua（<Space>tg 走 codelldb）和 neotest_cpp.lua（<Space>tr/tt 跑 gtest）
--   都得知道「测试二进制在哪、怎么构建」。这些值原本写死成 LearnCPP 的
--   build-Debug/bin/LearnCPP_Test，换个项目就得改 nvim 配置；而且两边各写一份，
--   项目根的定义还不一样（debug 用 cwd，neotest 向上找 CMakeLists.txt）。
--   现在统一由项目根的 .nvim.yaml 提供，两边读同一份、用同一个找根函数。
--
-- 配置文件是项目根的 .nvim.yaml（解析器见 lua/yaml_lite.lua），target 两种写法都行：
--   1) 相对项目根的路径（推荐，产物放哪一目了然）
--        target: build-Debug/bin/LearnCPP_Test
--   2) 纯目标名（不想写路径时，让 CMake 配置帮着找）
--        target: LearnCPP_Test
-- 构建目录不写也行，从 CMake 自己的配置里找（见下面 locate_debug_build_dir）。
--
-- 优先级（后者覆盖前者）：
--   内置默认 M.DEFAULTS  ←  插件 spec 的 opts  ←  项目 .nvim.yaml
--   项目文件最具体，所以压过全局的插件 spec。插件 spec 那一层由调用方
--   （neotest_cpp.setup）收下后作为 defaults 参数传进来。
--
-- 逃生舱字段（CMake 布局特殊时才需要）：
--   build_dir: build-Debug      # 跳过自动查找，直接用这个（相对项目根）
--   build_args: [make, -j]      # 整条构建命令自己写
--   auto_build: false           # 跑/调之前不自动编译
--   extensions: [cc, cpp]       # 哪些扩展名可能算测试文件

local M = {}

M.CONFIG_FILE = ".nvim.yaml"

-- 项目根标志。配置文件名排第一个——非 CMake 项目只要放了 .nvim.yaml 也能定根。
M.ROOT_MARKERS = { M.CONFIG_FILE, "compile_commands.json", "CMakeLists.txt" }

-- 找构建目录时跳过的重目录（进 CMakeFiles 会翻几千个文件，纯浪费时间）
local SKIP_DIRS = {
  [".git"] = true,
  ["node_modules"] = true,
  ["CMakeFiles"] = true,
  [".venv"] = true,
  ["venv"] = true,
}

-- 从项目根往下最多找几层（够 build/、build-Debug/、out/Debug/ 这些常见布局）
local BUILD_DIR_MAX_DEPTH = 3

---@class project_config.Defaults
---@field target? string 二进制相对项目根的路径；或只写目标名（= 二进制文件名）
---@field build_dir? string 构建目录（相对项目根）
---@field build_args? string[] 整条构建命令
---@field auto_build boolean 跑/调之前先增量编译
---@field extensions string[] 视为测试源码的扩展名

---@type project_config.Defaults
M.DEFAULTS = {
  -- target 故意不给默认值：不同项目目标名必然不同，瞎猜一个
  -- (比如写死 LearnCPP_Test) 只会在别的项目里报出更莫名其妙的错。
  auto_build = true,
  extensions = { "cc", "cpp", "cxx" },
}

---@class project_config.Resolved
---@field root string 项目根（绝对路径）
---@field target string|nil CMake 目标名
---@field name string|nil 用于列表标题与通知文案（就是 target）
---@field build_dir string|nil Debug 构建目录（绝对路径）
---@field binary string|nil 测试可执行文件（绝对路径）
---@field build_args string[] 构建命令（在 root 下执行；空 = 没有可用的构建命令）
---@field build_hint string 构建命令的展示形式，用于报错提示
---@field auto_build boolean 实际是否会自动编译（build_args 为空时恒为 false）
---@field extensions string[]
---@field problem string|nil 说不清楚 binary 在哪儿时的原因，直接给用户看

---@param start string 文件或目录路径
---@return string|nil 最近的含标志文件的祖先目录
function M.find_root(start)
  if not start or start == "" then
    return nil
  end
  return vim.fs.root(start, M.ROOT_MARKERS)
end

-- 当前缓冲区的项目根。无文件缓冲区（[No Name]）退回 cwd，
-- 这样 :lua 里手动调用不会因为没有文件名就报错。
---@return string
function M.root_for_buffer()
  local name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if name ~= "" then
    local root = M.find_root(name)
    if root then
      return root
    end
  end
  return vim.uv.cwd() or "."
end

---@param path string
---@return boolean
local function is_abs(path)
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil -- 后者兼容 Windows 盘符
end

-- vim.notify 在 fast event context 里会抛 E5560（实测：nvim_echo must not be
-- called in a fast event context），而 neotest 的 nio 协程就是 fast context。
-- 统一走这个：快速上下文里排到主循环再发，别让一条提示把整个扫描打断。
---@param msg string
---@param level integer
local function notify_safe(msg, level)
  if vim.in_fast_event() then
    vim.schedule(function()
      vim.notify(msg, level)
    end)
  else
    vim.notify(msg, level)
  end
end

-- vim.fn.shellescape 的纯 Lua 版。同样是因为 fast event context：
-- vim.fn.shellescape 在那里抛 E5560（实测）。只用来拼给人看的构建提示，
-- 按 shell 规则加引号就够了。
---@param s string
---@return string
local function shell_quote(s)
  if s == "" then
    return "''"
  end
  if s:match("^[%w_%-%./:=@%%+,]+$") then
    return s
  end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- neotest_cpp.build_spec 拼 shell 命令时也要用（它同样跑在 fast context 里）
M.shell_quote = shell_quote

---@param root string
---@param path string
---@return string
local function abs_from(root, path)
  return is_abs(path) and path or (root .. "/" .. path)
end

-- 能在命令里写成相对项目根就写相对（cmake --build build-Debug 比一长串绝对路径好读，
-- 报错提示也短）。项目外的路径只能保持绝对。
---@param root string
---@param path string
---@return string
local function rel_to_root(root, path)
  local prefix = root .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return path
end

---@param value any
---@param fallback string[]
---@return string[]
local function as_str_list(value, fallback)
  if type(value) == "table" and #value > 0 then
    for _, v in ipairs(value) do
      if type(v) ~= "string" then
        return fallback
      end
    end
    return value
  end
  return fallback
end

-- ---------------------------------------------------------------- 配置文件读取

-- 按根缓存解析好的配置，并记住当时的 mtime：
-- 改完 .nvim.yaml 直接生效，不用重启 nvim（代价只是一次 fs_stat）。
---@type table<string, { mtime: table|nil, data: table }>
local config_cache = {}

-- 读并解析 <root>/.nvim.yaml。文件不存在、YAML 坏了都只是退回空表 + 提示，
-- 不让一个手滑的缩进把 <Space>tr 整个搞挂。
---@param root string
---@return table
function M.raw(root)
  local path = root .. "/" .. M.CONFIG_FILE
  local stat = vim.uv.fs_stat(path)
  local mtime = stat and stat.mtime or nil
  local cached = config_cache[root]
  if cached and vim.deep_equal(cached.mtime, mtime) then
    return cached.data
  end

  local data = {}
  if mtime then
    local fd = io.open(path, "r")
    if fd then
      local content = fd:read("*a")
      fd:close()
      local parsed, err = require("yaml_lite").parse(content)
      if err then
        notify_safe(("%s 解析失败，改用内置默认：%s"):format(path, err), vim.log.levels.WARN)
      else
        data = parsed or {}
      end
    end
  end

  config_cache[root] = { mtime = mtime, data = data }
  return data
end

-- ---------------------------------------------------------------- CMake 探测

-- 列项目根下含 CMakeCache.txt 的目录。找到就不再往里走（构建目录不会嵌套）。
---@param root string
---@return string[]
local function find_cmake_build_dirs(root)
  local found = {}
  local function walk(dir, depth)
    if depth > BUILD_DIR_MAX_DEPTH then
      return
    end
    local handle = vim.uv.fs_scandir(dir)
    if not handle then
      return
    end
    local subdirs, has_cache = {}, false
    while true do
      local entry, typ = vim.uv.fs_scandir_next(handle)
      if not entry then
        break
      end
      if typ == nil then -- 软链/特殊文件：scandir 给不出类型时补一次 stat
        local st = vim.uv.fs_stat(dir .. "/" .. entry)
        typ = st and st.type or "other"
      end
      if typ == "directory" then
        if not SKIP_DIRS[entry] then
          subdirs[#subdirs + 1] = entry
        end
      elseif typ == "file" and entry == "CMakeCache.txt" then
        has_cache = true
      end
    end
    if has_cache then
      found[#found + 1] = dir
      return
    end
    for _, name in ipairs(subdirs) do
      walk(dir .. "/" .. name, depth + 1)
    end
  end
  walk(root, 1)
  return found
end

-- 读 CMakeCache.txt 里的 CMAKE_BUILD_TYPE。多配置生成器（VS/Xcode）这里是空的，
-- 返回 nil —— 那种情况我们认不出来，会走「找不到 Debug 构建目录」的提示。
---@param build_dir string
---@return string|nil
local function cache_build_type(build_dir)
  local fd = io.open(build_dir .. "/CMakeCache.txt", "r")
  if not fd then
    return nil
  end
  local build_type
  for line in fd:lines() do
    local v = line:match("^CMAKE_BUILD_TYPE:STRING=(.*)$")
    if v then
      build_type = vim.trim(v)
      break
    end
  end
  fd:close()
  return (build_type ~= "" and build_type) or nil
end

-- 在 root 下挑出 Debug 的那个构建目录。
-- 注意这里读的是构建目录里的 CMakeCache.txt，不是 CMakePresets.json ——
-- 预设文件可能是过期的（LearnCPP 的 CMakePresets 就还写着 Windows 的 build/debug，
-- 跟实际用的 build-Debug 对不上），缓存文件才是「这次构建真的用的配置」。
---@param root string
---@return string|nil dir, string|nil problem
local function locate_debug_build_dir(root)
  local dirs = find_cmake_build_dirs(root)
  if #dirs == 0 then
    return nil,
      ("在 %s 下没找到 CMake 构建目录（没有 CMakeCache.txt）。\n先配置一次，例如：cmake -B build-Debug -DCMAKE_BUILD_TYPE=Debug"):format(
        root
      )
  end

  local debug_dirs, described = {}, {}
  for _, dir in ipairs(dirs) do
    local bt = cache_build_type(dir)
    described[#described + 1] = ("  %s  →  CMAKE_BUILD_TYPE=%s"):format(rel_to_root(root, dir), bt or "(空)")
    if bt and bt:lower() == "debug" then
      debug_dirs[#debug_dirs + 1] = dir
    end
  end

  if #debug_dirs == 0 then
    return nil,
      ("在 %s 下没找到 CMAKE_BUILD_TYPE=Debug 的构建目录。找到的是：\n%s\n用 -DCMAKE_BUILD_TYPE=Debug 配置一次，或在 .nvim.yaml 里写 build_dir 指定。"):format(
        root,
        table.concat(described, "\n")
      )
  end

  if #debug_dirs == 1 then
    return debug_dirs[1]
  end

  -- 多个 Debug 目录：优先名字里带 debug 的，再按路径排序，保证结果稳定可预期
  local named = vim.tbl_filter(function(d)
    return rel_to_root(root, d):lower():find("debug", 1, true) ~= nil
  end, debug_dirs)
  local pool = #named > 0 and named or debug_dirs
  table.sort(pool)
  notify_safe(
    ("找到 %d 个 Debug 构建目录，用 %s（要固定用哪个就在 .nvim.yaml 里写 build_dir）"):format(
      #debug_dirs,
      rel_to_root(root, pool[1])
    ),
    vim.log.levels.WARN
  )
  return pool[1]
end

-- 在构建目录里按名字找可执行文件。
-- 为什么不拼 <build_dir>/bin/<target> 完事：bin/ 那层是 CMakeLists 里
-- set_target_properties(... RUNTIME_OUTPUT_DIRECTORY ".../bin") 定的，
-- 是普通变量、不进 CMakeCache.txt，所以我们读不到，只能按名字找。
-- 快路径先试两个最常见的位置，没有再全目录找（CMakeFiles/ 已在 SKIP_DIRS 里避开）。
---@param build_dir string
---@param target string
---@return string|nil
local function find_binary(build_dir, target)
  for _, cand in ipairs({ build_dir .. "/bin/" .. target, build_dir .. "/" .. target }) do
    if vim.fn.executable(cand) == 1 then
      return cand
    end
  end

  local function search(dir, depth)
    if depth > 4 then
      return nil
    end
    local handle = vim.uv.fs_scandir(dir)
    if not handle then
      return nil
    end
    local subdirs = {}
    while true do
      local entry, typ = vim.uv.fs_scandir_next(handle)
      if not entry then
        break
      end
      if typ == nil then
        local st = vim.uv.fs_stat(dir .. "/" .. entry)
        typ = st and st.type or "other"
      end
      if typ == "directory" then
        if not SKIP_DIRS[entry] then
          subdirs[#subdirs + 1] = entry
        end
      elseif typ == "file" and entry == target then
        local path = dir .. "/" .. entry
        if vim.fn.executable(path) == 1 then
          return path
        end
      end
    end
    for _, name in ipairs(subdirs) do
      local hit = search(dir .. "/" .. name, depth + 1)
      if hit then
        return hit
      end
    end
    return nil
  end

  return search(build_dir, 1)
end

-- 探测结果按根缓存。只缓存**成功**：失败时每次都重来，这样你「刚 cmake configure 完
-- 回 nvim 按 <Space>tr」就能立刻生效，而不用重启 nvim 或手动清缓存。
-- 必须连 target 一起存下来做比对：只按根缓存的话，改了 .nvim.yaml 里的 target
-- 仍会命中旧二进制（旧文件还在，executable 检查照样通过），表现为「配置改了没反应」。
---@type table<string, { target: string, binary: string, build_dir: string }>
local discovery_cache = {}

---@param root string
---@param target string
---@return string|nil binary, string|nil build_dir, string|nil problem
local function discover(root, target)
  local cached = discovery_cache[root]
  -- target 变了、或缓存里的二进制被删了（构建目录换位置之类），都作废重找
  if cached and cached.target == target and vim.fn.executable(cached.binary) == 1 then
    return cached.binary, cached.build_dir
  end

  local build_dir, problem = locate_debug_build_dir(root)
  if not build_dir then
    return nil, nil, problem
  end

  local binary = find_binary(build_dir, target)
  if not binary then
    return nil,
      build_dir,
      ("在构建目录 %s 里没找到名为 %s 的可执行文件。\n先构建：cmake --build %s --target %s"):format(
        rel_to_root(root, build_dir),
        target,
        rel_to_root(root, build_dir),
        target
      )
  end

  discovery_cache[root] = { target = target, binary = binary, build_dir = build_dir }
  return binary, build_dir
end

-- 清掉配置与探测缓存。CMake 布局被大改（比如构建目录整个换位置）之后
-- 手动调一下；平时不用管。
function M.clear_cache()
  config_cache = {}
  discovery_cache = {}
end

-- ---------------------------------------------------------------- 对外解析

-- 把配置展开成实际要用的值。
-- binary / build_args 显式写了就整体覆盖推导值——不做拼接混合，
-- 免得出现「binary 是别的目录、build_args 还是 cmake 那套」这种半吊子状态。
---@param root string 项目根
---@param defaults? table 插件 spec 那一层的全局覆盖（优先级低于项目文件）
---@return project_config.Resolved
function M.resolve(root, defaults)
  -- 浅合并：extensions / build_args 是列表，deep_extend 会按下标合并，
  -- {"cpp"} 覆盖 {"cc","cpp","cxx"} 会得到 {"cpp","cpp","cxx"} 这种怪东西。
  local cfg = vim.tbl_extend("force", M.DEFAULTS, defaults or {}, M.raw(root))

  ---@type string|nil
  local target = type(cfg.target) == "string" and cfg.target or nil
  local build_dir_override = type(cfg.build_dir) == "string" and cfg.build_dir or nil

  -- target 有两种写法：
  --   LearnCPP_Test                  → 目标名：在探测到的 Debug 构建目录里按名字找
  --   build-Debug/bin/LearnCPP_Test  → 含路径分隔符就当**相对项目根的路径**，直接指向二进制
  -- 两种都认，是因为「产物放在哪」有时只有写配置的人知道（比如 RUNTIME_OUTPUT_DIRECTORY
  -- 藏在 CMakeLists 里、缓存里读不到）；不知道时才让 CMake 配置帮着找。
  local target_is_path = target ~= nil and (target:find("/", 1, true) or target:find("\\", 1, true)) ~= nil

  ---@type string|nil
  local binary, build_dir, problem
  if target_is_path then
    binary = abs_from(root, target)
    if build_dir_override then
      build_dir = abs_from(root, build_dir_override)
    else
      local locate_problem
      build_dir, locate_problem = locate_debug_build_dir(root)
      -- 二进制已经在（或构建目录找得到、能靠自动编译产出）就不算问题
      if vim.fn.executable(binary) ~= 1 and not build_dir then
        problem = ("测试可执行文件不存在：%s\n%s"):format(
          binary,
          locate_problem or "而且没找到可用的 Debug 构建目录，没法自动构建"
        )
      end
    end
  elseif target then
    if build_dir_override then
      build_dir = abs_from(root, build_dir_override)
      binary = find_binary(build_dir, target)
      if not binary then
        problem = ("在指定的构建目录 %s 里没找到名为 %s 的可执行文件"):format(
          rel_to_root(root, build_dir),
          target
        )
      end
    else
      binary, build_dir, problem = discover(root, target)
    end
  else
    problem = ("%s 没写 target，不知道该跑哪个测试目标"):format(root .. "/" .. M.CONFIG_FILE)
  end

  -- CMake 只吃目标名（不含目录），所以 --target 一律取二进制/Target 的文件名
  local target_name = vim.fs.basename(binary or target or "")

  -- 构建命令：显式给了就用，否则按探测到的构建目录拼；两样都没有就留空
  local build_args = as_str_list(cfg.build_args, {})
  if #build_args == 0 and build_dir and target_name ~= "" then
    build_args = { "cmake", "--build", rel_to_root(root, build_dir), "--target", target_name }
  end

  return {
    root = root,
    target = target_name ~= "" and target_name or nil,
    name = target_name ~= "" and target_name or nil,
    build_dir = build_dir,
    binary = binary,
    build_args = build_args,
    build_hint = #build_args > 0 and table.concat(vim.tbl_map(shell_quote, build_args), " ") or "",
    -- 没有构建命令就谈不上自动编译，别让调用方去跑一条空命令
    auto_build = cfg.auto_build ~= false and #build_args > 0,
    extensions = as_str_list(cfg.extensions, M.DEFAULTS.extensions),
    problem = problem,
  }
end

-- 按当前缓冲区解析（debug.lua 用：<Space>tg 是「对当前文件的项目」动手）
---@param defaults? table
---@return project_config.Resolved
function M.resolve_for_buffer(defaults)
  return M.resolve(M.root_for_buffer(), defaults)
end

-- 按某个文件路径解析（neotest_cpp 用：位置路径来自 neotest，不一定等于当前缓冲区）
---@param path string
---@param defaults? table
---@return project_config.Resolved
function M.resolve_for_path(path, defaults)
  return M.resolve(M.find_root(path) or vim.uv.cwd() or ".", defaults)
end

-- 只取某个文件所属项目的 extensions。
--
-- 这是给 is_test_file 用的**廉价谓词**：neotest 在 fast event context 里对每个
-- 候选文件调一次，所以这里
--   * 不做 CMake 探测（找不到构建目录时失败不缓存，会退化成每个文件扫一遍目录树）
--   * 不调 vim.notify（fast context 里抛 E5560）
-- 只做「找根 + 读缓存的 YAML」这两件 uv/io 就够的事。
-- 优先级与 resolve 一致：项目 .nvim.yaml > defaults(opts) > 内置默认。
---@param path string
---@param defaults? table
---@return string[]
function M.extensions_for_path(path, defaults)
  local fallback = as_str_list((defaults or {}).extensions, M.DEFAULTS.extensions)
  local root = M.find_root(path)
  if not root then
    return fallback
  end
  return as_str_list(M.raw(root).extensions, fallback)
end

return M
