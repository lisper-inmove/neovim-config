-- C++ / GoogleTest 的 neotest 适配器
--
-- 为什么需要它：
--   <leader>tr（跑光标最近用例）和 <leader>tt（跑整个文件）都由 neotest 驱动，
--   而 neotest 自己不认识任何语言，必须靠适配器解析用例。此前只注册了
--   neotest-python，它对非 .py 文件直接返回 false，所以在 .cc 文件里
--   光标停在哪一行都是 "No tests found"（和行号无关）。
--
-- 为什么自己写、不用现成的 alfaix/neotest-gtest：
--   那个插件要求在 neotest summary 里用 :ConfigureGtest 把「测试 → 可执行文件」
--   手动绑定（结果落盘到项目外），且不做构建集成。本项目所有用例都编进同一个
--   二进制 build-Debug/bin/LearnCPP_Test，gtest 全名（Suite.Test）写在
--   TEST_F 的第一个参数里，用 --gtest_filter 就能精确定位，
--   所以自写反而更短，也不需要任何手工映射。

local lib = require("neotest.lib")

local M = {}

---@class neotest_cpp.Config
---@field binary string 可执行文件（相对项目根）
---@field build_args string[] 构建命令（在项目根执行）
---@field auto_build boolean 运行前先增量编译（避免跑旧二进制）
---@field extensions string[] 视为测试源码的扩展名

---@type neotest_cpp.Config
M.config = {
  binary = "build-Debug/bin/LearnCPP_Test",
  build_args = { "cmake", "--build", "build-Debug", "--target", "LearnCPP_Test" },
  auto_build = true,
  extensions = { "cc", "cpp", "cxx" },
}

-- 覆盖默认配置（可选）：在插件 spec 里写
--   opts = { adapters = { ["neotest_cpp"] = { auto_build = false } } }
-- LazyVim 的 test extra 会自动调用这个 setup
---@param opts? neotest_cpp.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- neotest 用 name 拼 adapter_id（"%s:%s" % {name, root}），必须有
M.name = "neotest_cpp"

-- 项目根：以 compile_commands.json / CMakeLists.txt 为标志向上查找
local find_root = lib.files.match_root_pattern("compile_commands.json", "CMakeLists.txt")

---@param path string
---@return string|nil
function M.root(path)
  return find_root(path)
end

-- TEST_F(Suite, Name) 在 tree-sitter-cpp 里被解析成：
--   function_definition
--     function_declarator
--       identifier            "TEST_F"
--       parameter_list
--         parameter_declaration  Suite
--         parameter_declaration  Name
-- （实测确认；不是 call_expression，网上常见的 call_expression 查询在这里 0 匹配）
-- 参数用 (_) 通配，避免跟 tree-sitter-cpp 版本走。
M.query = [[
  (function_definition
    declarator: (function_declarator
      declarator: (identifier) @_macro
      (#eq? @_macro "TEST_F")
      parameters: (parameter_list
        (_) @suite.name
        (_) @test.name))) @test.definition
]]

-- 同步读文本文件（项目里的文件都很小）。
-- 不用 neotest.lib.files.read：它是 @async 的，只能在 nio 协程里调，
-- 而 is_test_file 这种纯判断函数不该依赖调用方在不在协程里。
---@param path string
---@return string|nil
local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local content = fd:read("*a")
  fd:close()
  return content
end

---@param file_path string
---@return boolean
function M.is_test_file(file_path)
  local ext = file_path:match("%.([%w_]+)$")
  if not ext or not vim.tbl_contains(M.config.extensions, ext) then
    return false
  end
  -- 只有含 gtest 宏的文件才当作测试文件（同一棵树下也有普通源文件）
  local content = read_file(file_path)
  return content ~= nil and content:find("TEST_F%s*%(") ~= nil
end

---@param file_path string
---@param source string
---@param nodes table<string, userdata>
---@return neotest.Position|nil
function M.build_position(file_path, source, nodes)
  local suite, name, definition = nodes["suite.name"], nodes["test.name"], nodes["test.definition"]
  if not (suite and name and definition) then
    return nil
  end
  return {
    type = "test",
    path = file_path,
    -- 用 gtest 全名（Suite.Test），与 --gtest_list_tests、<leader>tg 选择器里
    -- 看到的名字一致，后面 --gtest_filter 可以直接用
    name = vim.treesitter.get_node_text(suite, source) .. "." .. vim.treesitter.get_node_text(name, source),
    range = { definition:range() },
  }
end

---@param path string
---@return neotest.Tree
function M.discover_positions(path)
  return lib.treesitter.parse_positions(path, M.query, {
    nested_tests = false,
    -- 字符串形式 → neotest 可以放到子进程里解析，不卡编辑器；
    -- 写成函数则只能主进程解析（neotest 的 build_position 若是函数会禁用子进程）
    build_position = 'require("neotest_cpp").build_position',
  })
end

-- 把子树里所有用例的 gtest 全名拼成 --gtest_filter 的值（gtest 用 : 表示「或」）
---@param tree neotest.Tree
---@return string|nil
local function build_filter(tree)
  if tree:data().type == "dir" then
    return nil -- 整个目录：不过滤，跑全部
  end
  local names = {}
  for _, pos in tree:iter() do
    if pos.type == "test" then
      names[#names + 1] = pos.name
    end
  end
  if #names == 0 then
    return nil
  end
  return table.concat(names, ":")
end

-- 同步等一次增量编译（调试路径用），失败时把编译输出通知出来
---@param dir string
---@return boolean
local function build_sync(dir)
  local ok, res = pcall(function()
    return vim.system(M.config.build_args, { cwd = dir, text = true }):wait()
  end)
  if not ok or res.code ~= 0 then
    local out = ok and ((res.stderr ~= "" and res.stderr) or res.stdout or "") or tostring(res)
    lib.notify("编译失败:\n" .. tostring(out):sub(1, 1000), vim.log.levels.ERROR)
    return false
  end
  return true
end

---@param args neotest.RunArgs
---@return neotest.RunSpec|nil
function M.build_spec(args)
  local position = args.tree:data()
  local dir = M.root(position.path) or vim.uv.cwd()
  local binary = dir .. "/" .. M.config.binary
  local filter = build_filter(args.tree)

  if args.strategy == "dap" then
    -- 调试：program 必须就是二进制本身，不能套一层 shell，否则 dap 会去调 bash。
    -- 所以这里同步编译，保证调试的是最新代码。
    if M.config.auto_build and not build_sync(dir) then
      return nil -- 编译失败：交给 neotest 报错，别拿旧二进制去调试
    end
    return {
      command = filter and { binary, "--gtest_filter=" .. filter } or { binary },
      cwd = dir,
      -- neotest 的 dap strategy 直接用这张表当 DAP 配置（适配器里 codelldb 见 debug.lua）
      strategy = {
        type = "codelldb",
        request = "launch",
        name = "neotest-cpp: " .. (filter or "全部"),
        program = binary,
        args = filter and { "--gtest_filter=" .. filter } or {},
        cwd = dir,
        stopOnEntry = false,
      },
    }
  end

  local command = filter and { binary, "--gtest_filter=" .. filter } or { binary }

  if M.config.auto_build then
    -- 先增量编译再跑，两者输出都进 neotest 的 output 面板：
    -- 编译不过时你看到的是编译错误，而不是一个过期的二进制在跑
    local build = table.concat(vim.tbl_map(vim.fn.shellescape, M.config.build_args), " ")
    local run = table.concat(vim.tbl_map(vim.fn.shellescape, command), " ")
    command = { "bash", "-c", ("cd %s && %s && exec %s"):format(vim.fn.shellescape(dir), build, run) }
  end

  return { command = command, cwd = dir }
end

-- 解析 gtest 输出，把每个用例的通过/失败映射回 neotest 的 position id。
-- 没解析到的用例（段错误、用例根本没起来）由 neotest 自己按「失败」兜底，
-- 所以这里只需要认 [       OK ] / [  FAILED  ] / [  SKIPPED ] 三种行。
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function M.results(spec, result, tree)
  local id_by_name = {}
  for _, pos in tree:iter() do
    if pos.type == "test" then
      id_by_name[pos.name] = pos.id
    end
  end

  local content = read_file(result.output)
  if not content then
    return {}
  end

  local results = {}
  local current_name, current_block

  ---@param status neotest.ResultStatus
  local function flush(status)
    if current_name and id_by_name[current_name] then
      local r = { status = status }
      if status ~= "passed" and current_block and #current_block > 0 then
        local message = table.concat(current_block, "\n"):gsub("^%s+", ""):sub(1, 2000)
        r.short = message
        r.errors = { { message = message } }
      end
      results[id_by_name[current_name]] = r
    end
    current_name, current_block = nil, nil
  end

  for line in content:gmatch("[^\n]*") do
    local name = line:match("^%[%s+RUN%s+%]%s+(%S+)")
    if name then
      current_name, current_block = name, {}
    elseif current_name then
      local escaped = vim.pesc(current_name)
      if line:match("^%[%s+OK%s+%]%s+" .. escaped .. "%s") then -- [       OK ] Tester.X (1 ms)
        flush("passed")
      elseif line:match("^%[%s+FAILED%s+%]%s+" .. escaped .. "%s") then
        flush("failed")
      elseif line:match("^%[%s+SKIPPED%s+%]%s+" .. escaped .. "%s") then
        flush("skipped")
      elseif not line:match("^%[%-") then
        -- 用例内的输出先攒着，失败时当作错误信息（[----------] 分隔行不要）
        current_block[#current_block + 1] = line
      end
    end
  end

  return results
end

return M
