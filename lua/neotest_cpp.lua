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
--   手动绑定（结果落盘到项目外），且不做构建集成。一个项目的用例全编进同一个
--   二进制（路径来自项目根的 .nvim.yaml，见 lua/project_config.lua），
--   gtest 全名（Suite.Test）写在 TEST_F 的第一个参数里，用 --gtest_filter
--   就能精确定位，所以自写反而更短，也不需要任何手工映射。

local lib = require("neotest.lib")
local project_config = require("project_config")

local M = {}

-- 二进制、构建命令这些「跟项目走」的值全部来自项目根的 .nvim.yaml
-- （project_config.DEFAULTS 里只有 auto_build / extensions；target 没有默认值，
-- 因为目标名必然因项目而异）。这里只收插件 spec 那一层的全局覆盖，
-- 优先级低于项目自己的 .nvim.yaml。
---@type table
M.opts = {}

-- 覆盖默认配置（可选）：在插件 spec 里写
--   opts = { adapters = { ["neotest_cpp"] = { auto_build = false } } }
-- LazyVim 的 test extra 会自动调用这个 setup。
-- 注意优先级：项目根 .nvim.yaml  >  这里传的 opts  >  project_config.DEFAULTS
-- （项目文件更具体，所以压过全局；写在这里的键仍会被同名项目的配置盖掉）
---@param opts? table
function M.setup(opts)
  M.opts = opts or {}
end

-- neotest 用 name 拼 adapter_id（"%s:%s" % {name, root}），必须有
M.name = "neotest_cpp"

-- 某个项目根下解析好的配置。
-- 用 project_config 的找根，和 debug.lua 的 <Space>tg 保持同一套定义——
-- 以前两边各写一份（这边只认 CMake 标志、那边用 cwd），从子目录进来会对不上。
---@param root string
---@return project_config.Resolved
local function cfg(root)
  return project_config.resolve(root, M.opts)
end

---@param path string
---@return string|nil
function M.root(path)
  return project_config.find_root(path)
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
  if not ext then
    return false
  end
  -- 扩展名清单也按文件所属项目取（.nvim.yaml 的 extensions 可以覆盖）。
  -- 用 extensions_for_path 而不是 resolve_for_path：这个函数在 neotest 的
  -- fast event context 里被每个候选文件调用，不能做 CMake 探测、不能 notify
  -- （vim.fn.getcwd / vim.notify 在那里会抛 E5560，实测）。
  -- 之前用 resolve_for_path 会抛错，导致 neotest 的 _update_positions 整个中止，
  -- <leader>tr 就报 "No tests found"。
  if not vim.tbl_contains(project_config.extensions_for_path(file_path, M.opts), ext) then
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
---@param build_args string[]
---@return boolean
local function build_sync(dir, build_args)
  local ok, res = pcall(function()
    return vim.system(build_args, { cwd = dir, text = true }):wait()
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
  local c = cfg(dir) -- 本项目的配置：二进制、构建命令、是否自动编译
  local binary = c.binary
  local filter = build_filter(args.tree)

  if not binary then
    -- c.problem 里写着「为什么定位不到二进制 + 下一步」，直接给用户看。
    -- 返回 nil 让 neotest 报错，别拼一条 binary=nil 的命令去跑。
    lib.notify(c.problem or "定位不到测试二进制", vim.log.levels.ERROR)
    return nil
  end

  if args.strategy == "dap" then
    -- 调试：program 必须就是二进制本身，不能套一层 shell，否则 dap 会去调 bash。
    -- 所以这里同步编译，保证调试的是最新代码。
    if c.auto_build and not build_sync(dir, c.build_args) then
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

  if c.auto_build then
    -- 先增量编译再跑，两者输出都进 neotest 的 output 面板：
    -- 编译不过时你看到的是编译错误，而不是一个过期的二进制在跑
    local build = c.build_hint
    -- 注意用 project_config.shell_quote 而不是 vim.fn.shellescape：
    -- build_spec 跑在 neotest 的 fast event context 里，后者会抛 E5560（实测）
    local run = table.concat(vim.tbl_map(project_config.shell_quote, command), " ")
    command = { "bash", "-c", ("cd %s && %s && exec %s"):format(project_config.shell_quote(dir), build, run) }
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
