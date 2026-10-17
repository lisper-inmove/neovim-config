# 在 Neovim 里跑测试与调试

本配置的测试/调试能力，围绕两个前缀组织：

- **`<Space>t` = 测试的一切** —— 运行 + 调试，Python 与 C++ 都在这里
- **`<Space>d` = 调试器通用操作** —— 断点、单步、面板，对任何调试会话都适用

所以：调试某个测试走 `t`，而调断点/单步走 `d`。

| 目标 | 跑 | 调 | 适配器 |
|---|---|---|---|
| Python / pytest | `<Space>tt` / `<Space>tr` | `<Space>td` | neotest-python + debugpy |
| C++ / gtest | `<Space>tt` / `<Space>tr`（跑前自动编译） | `<Space>tg`（`<Space>td` 走同一套 codelldb 配置，未实测） | neotest_cpp（自写）+ codelldb |

---

## 快捷键

### `<Space>t` —— 测试

| 键 | 功能 |
|---|---|
| `<Space>tt` | **运行当前文件**的所有测试 |
| `<Space>tr` | **运行光标所在的那个测试**（最常用） |
| `<Space>tT` | 运行整个项目（cwd）的测试 |
| `<Space>tl` | 重跑上一次运行 |
| `<Space>td` | **调试光标所在用例**（Python → debugpy，C++ → codelldb） |
| `<Space>tg` | **选择并调试 gtest 用例**（C++，见下） |
| `<Space>ts` | 开关测试摘要面板（列出全部用例与状态） |
| `<Space>to` | 查看最近一次运行的输出（含失败堆栈） |
| `<Space>tO` | 开关输出面板（常驻，边改边看） |
| `<Space>tS` | 停止正在运行的测试 |
| `<Space>tw` | watch 当前文件：保存即重跑 |
| `<Space>ta` | 附加到已启动的测试会话 |

`<Space>td` 调试的是**光标最近的用例**（同 `<Space>tr`），所以光标要放在目标测试
函数上；打断点用 `<Space>dB`，命中后会停在断点处。

### `<Space>d` —— 调试器操作

| 键 | 功能 |
|---|---|
| `<Space>dB` | 打断点 / 取消断点 |
| `<Space>dc` | 继续执行（Continue） |
| `<Space>di` | 单步进入（Step Into） |
| `<Space>dn` | 单步跳过（Step Over） |
| `<Space>do` | 单步跳出（Step Out） |
| `<Space>dt` | 开关 DAP UI 面板 |

⚠️ **`<Space>dps` 不是调试键** —— 它是 Snacks 的 Lua 性能分析器
（"Profiler Scratch Buffer"），由 LazyVim 内置，跟 nvim-dap 无关。

---

## 前置条件

| 项目 | 要求 |
|---|---|
| 插件 | `neotest` + `neotest-python`、自写 `neotest_cpp`（测试）、`nvim-dap-python` + `debugpy`、`codelldb`（调试） |
| Python 项目 | 根目录有 `pyproject.toml`；测试文件命名 `test_*.py` 或 `*_test.py`；根目录有 `.venv/`（`uv sync` 生成） |
| C++ 项目 | 项目根有 `.nvim.yaml`，里面写一行 `target: <相对项目根的二进制路径>`（也可以只写目标名）；用 CMake 配置过一次 Debug 构建（构建目录里有 `CMakeCache.txt`）。项目根 = 有 `.nvim.yaml` / `compile_commands.json` / `CMakeLists.txt` 的目录 |
| treesitter | 需要 python parser 和 cpp parser（用例靠 tree-sitter 解析） |

`lazyvim.plugins.extras.test.core` 只提供 neotest 骨架和 `<Space>t*` 键位，
**`adapters` 默认为空**——真正让测试跑起来的语言适配器必须自己配。

---

## 适配器

两个适配器来源完全不同，排查时要知道区别：

| | C/C++ | Python |
|---|---|---|
| DAP `type` | `codelldb` | `python` |
| 适配器命令 | `~/.local/share/nvim/mason/bin/codelldb` | `~/.local/share/nvim/mason/bin/debugpy-adapter` |
| 谁注册 | `debug.lua` **手写** | `nvim-dap-python` 的 `setup()` |
| Mason 包 | `codelldb` | `debugpy` |
| 谁装的 | `mason-nvim-dap` 自动安装 | `mason.nvim` 的 `ensure_installed` |

**codelldb 是手写注册的**（`debug.lua` 里显式写全路径，不依赖 PATH），
因为 mason-nvim-dap 会自动装适配器、可能覆盖手写的配置。

**Python 侧有个坑**：`mason-nvim-dap` 的 `automatic_installation` 也可能去注册
python 适配器，从而覆盖 `nvim-dap-python` 注册的那个。`python.lua` 里专门加了
空 handler 把这条路堵死：

```lua
{ "jay-babu/mason-nvim-dap.nvim", optional = true,
  opts = { handlers = { python = function() end } } },
```

---

## 会话怎么跑起来

### Python / pytest

**运行**由 neotest 驱动：发现用例 → 用列表里的解释器执行 `neotest.py` 脚本
→ pytest 跑完把结果写进 JSON → neotest 解析。

**调试**（`<Space>td`）走 neotest 的 `strategy = "dap"`：neotest 构造一个
`type = "python"` 的 DAP 配置交给 debugpy 适配器。

⚠️ 因此 neotest 的 `python` 配置项必须是**单个解释器路径**，不能用
`{ "uv", "run", "python" }`，否则调试会话会静默卡死。详见常见问题。

### C++ / gtest —— 运行（`<Space>tr` / `<Space>tt`）

**运行**由 neotest + 自写的 `neotest_cpp` 适配器驱动（`lua/neotest_cpp.lua`）：

1. **发现用例**：tree-sitter-cpp 解析文件里的 `TEST_F(Suite, Name)`，
   用例名取 gtest 全名（`Tester.OpenCV_Edge_Detect`），和 `<Space>tg`
   列表、`--gtest_list_tests` 里看到的一致。
2. **运行**：先按项目配置增量编译（LearnCPP 拼出来的是
   `cmake --build build-Debug --target LearnCPP_Test`），
   再跑 `<二进制> --gtest_filter=<光标所在用例>`。编译输出和测试输出都在
   `<Space>to` 里——编译不过时你看到的是编译错误，而不是旧二进制在跑。
3. **解析**：读 gtest 的 `[ OK ]` / `[ FAILED ]` 行回填状态与失败信息。

⚠️ **OpenCV 用例会开图像窗口并阻塞**：用例里有 `cv::imshow` + `waitKey(0)`，
要在窗口里按任意键，测试才结束、neotest 才出结果。

⚠️ 此前只有一个 `neotest-python` 适配器，它对 `.cc` 文件直接返回 false，
所以 `<Space>tr` 在 C++ 文件里**任何行**都是 "No tests found"（与行号无关）。

### C++ / gtest —— 调试（`<Space>tg`）

1. **先构建**，否则会提示找不到二进制（构建命令从项目 `.nvim.yaml` 里的
   `target` 和找到的 Debug 构建目录拼出来，找不到二进制时的报错里会直接
   把它写出来）。
2. 按 `<Space>tg`，从列表里选用例：
   - `▶ 运行全部测试`
   - `⌨ 手动输入过滤器…`（gtest 语法：全称 `Tester.OpenCV_Hist_Match`，或通配 `*Hist*`）
   - 直接选某个具体用例（`Suite.TestName`）

用例列表是执行 `<二进制> --gtest_list_tests` 解析出来的，过滤器通过
`--gtest_filter=` 传给调试目标。

路径约定：二进制与构建命令**不再是写死的**，由项目根 `.nvim.yaml` 里的
`target` 加上从 CMake 配置里找到的 Debug 构建目录拼出来（见下节）。
项目根和 neotest 那边用同一个函数——从当前缓冲区文件向上找 `.nvim.yaml` /
`compile_commands.json` / `CMakeLists.txt`，所以**在任意 cwd 启动 nvim 都能用**
（以前这里取 cwd，必须先在项目根打开 nvim）。

配置选择器（`:lua require("dap").continue()` 无会话时）里的配置名会带项目
目标名，且在**进入 cpp 文件时重建**——`config.name` 只能是字符串、又只能
在插件加载时写一次，不重建的话在 A 项目里启动会顶着 B 项目的名字。
定位不到二进制时这张表是空的（nvim-dap 会说没有可用配置），比塞一条
`program=nil` 的坏配置报错清楚；详细原因看 `<Space>tg` 的通知。

不在测试列表场景下，也可以用 `:lua require("dap").continue()` 走
`dap.configurations.cpp` 里注册的两个配置（全部 / 手动 filter）。

---

## 项目根配置 `.nvim.yaml`

C++ 的目标名放在**项目根目录的 `.nvim.yaml`** 里（解析逻辑见
`lua/project_config.lua`）。换一个 C++ 项目只要在新项目根加这个文件，
不用改 nvim 配置。

```yaml
# <项目根>/.nvim.yaml
target: build-Debug/bin/LearnCPP_Test    # 相对项目根的路径
```

`target` 两种写法都认：

| 写法 | 语义 | 二进制怎么定 |
|---|---|---|
| `build-Debug/bin/LearnCPP_Test` | **相对项目根的路径** | 直接 `<项目根>/<target>` |
| `LearnCPP_Test` | 目标名 | 在探测到的 Debug 构建目录里按名字找 |

含路径分隔符（`/`）就当路径，否则当目标名。**推荐写路径**——产物放在哪
一目了然，也不依赖「按名字能找到」。纯名字适合懒得写路径、或产物位置
本来就是标准布局的项目。

两种写法下，构建命令里的 `--target` 都取**文件名**（`LearnCPP_Test`），
因为 CMake 只吃目标名、不吃目录。

### 构建目录（Debug）是怎么找出来的

不论 `target` 写哪种形式，**构建目录**都从 CMake 自己的配置里找：

1. 在项目根下扫含 `CMakeCache.txt` 的目录（往下最多 3 层，跳过
   `.git` / `CMakeFiles` / `node_modules` / `.venv`）
2. 读每个缓存里的 `CMAKE_BUILD_TYPE`，取值为 `Debug` 的那个
3. 只在 `target` 写**纯名字**时才多一步：在选中的构建目录里按名字找可执行文件，
   先试 `<构建目录>/bin/<名字>`、`<构建目录>/<名字>`，没有再全目录找
4. 构建命令 = `cmake --build <相对项目根的构建目录> --target <文件名>`

⚠️ **为什么读 `CMakeCache.txt` 而不是 `CMakePresets.json`**：预设文件可能是
过期的。LearnCPP 的 `CMakePresets.json` 现在还写着 Windows 的
`F:/codes/...` 和 `build/debug`，跟实际在用的 `build-Debug` 对不上；
构建目录里的缓存才是「这次构建真的用的配置」。

⚠️ **为什么纯名字模式要「按名字找」而不是拼 `<构建目录>/bin/<名字>`**：`bin/`
那层是 `config/googletest.cmake` 里 `set_target_properties(... RUNTIME_OUTPUT_DIRECTORY
".../bin")` 定的，属于普通变量、**不进 `CMakeCache.txt`**，所以读不到，只能找。
（实际项目的产物布局千奇百怪，按名字找反而更稳。）
**这也正是 target 支持直接写路径的原因**：位置只有你知道时，就别让程序猜。

找不到时不会瞎猜，报错里会写清卡在哪一步（见「常见问题」）。

### 可选字段（CMake 布局特殊时才用）

```yaml
target: build-Debug/bin/LearnCPP_Test
build_dir: build-Debug     # 固定用这个构建目录，跳过 Debug 自动查找
build_args: [make, -j]     # 干脆自己写整条构建命令
auto_build: false          # 跑/调之前不自动编译
extensions: [cc, cpp]      # 哪些扩展名可能算测试文件（默认 cc/cpp/cxx）
```

`build_args` 写了就**整体覆盖**推导值，不做拼接混合——免得出现
「二进制指向 A 目录、构建命令还是 cmake 那套」这种半吊子状态。
`auto_build` 默认 `true`，但**没有可用的构建命令时它恒为 false**（不会去跑空命令）。

### 几点行为

- **改完立刻生效**，不用重启 nvim（文件按 mtime 缓存）。
- **YAML 写坏了不炸**：给一条 warning 说明第几行哪里不对，退回默认继续跑。
- 解析器是自带的 YAML 子集（`lua/yaml_lite.lua`）：支持扁平 `key: value`、
  `#` 注释、引号、布尔/数字、块列表和 `[a, b]` 行内列表。
  **不支持嵌套映射**，写了会明确报错——本机没有 yaml/yq/ruby/PyYAML，
  自写子集是为了不引入任何外部依赖。
- **找不到构建目录时每次都重找**（失败结果不缓存）。所以你刚 `cmake configure`
  完切回 nvim 按 `<Space>tr` 就能用，不用重启。
- 项目根 = 从当前文件向上找 `.nvim.yaml` / `compile_commands.json` /
  `CMakeLists.txt` 里最近的那个目录；`.nvim.yaml` 自己也是定根的标志，
  非 CMake 项目（比如纯 Makefile）单靠它就能被认出来。

优先级：**项目 `.nvim.yaml` > 插件 spec 里传的 opts > 内置默认**
（项目文件更具体，所以压过全局）。内置默认只有 `auto_build = true` 和
`extensions`——**`target` 故意不给默认值**，目标名必然因项目而异，
瞎猜一个只会在新项目里报出更莫名其妙的错。

---

## 相关配置

| 文件 | 内容 |
|---|---|
| `lazyvim.json` | 启用 `lazyvim.plugins.extras.test.core` |
| `lua/project_config.lua` | **项目根 `.nvim.yaml` 的读取、CMake Debug 构建目录探测、二进制定位**，被下面两个模块共用 |
| `lua/yaml_lite.lua` | 自带的 YAML 子集解析器（本机没有 yq/ruby/PyYAML，见下节说明） |
| `lua/plugins/python.lua` | neotest-python adapter、`nvim-dap-python`、debugpy |
| `lua/neotest_cpp.lua` | **自写的 C++/gtest neotest 适配器**（解析 `TEST_F`、拼 `--gtest_filter`、解析 gtest 输出） |
| `lua/plugins/neotest-cpp.lua` | 把上面这个适配器挂进 neotest 的 `adapters` |
| `lua/plugins/debug.lua` | codelldb 适配器、gtest 配置、`<Space>d*` 键位、DAP UI |
| `<项目根>/.nvim.yaml` | 各 C++ 项目自己的二进制/构建命令（不在本仓库里） |

neotest 侧的核心配置：

```lua
-- lua/plugins/python.lua
["neotest-python"] = {
  runner = "pytest",
  python = ".venv/bin/python",   -- 不能写成 { "uv", "run", "python" }，见下
},
```

```lua
-- lua/plugins/neotest-cpp.lua
adapters = {
  -- 空表 = 不覆盖任何东西，一切按项目根的 .nvim.yaml（没有就按内置默认）。
  -- LazyVim 只在表非空时才调 adapter.setup()，所以空表 = 不调用 setup。
  ["neotest_cpp"] = {},
},
```

内置默认（`lua/project_config.lua` 的 `M.DEFAULTS`，仅在字段缺失时生效）：
只有 `auto_build = true` 和 `extensions`。**`target` 没有默认值**——每个
项目都得在 `.nvim.yaml` 里自己写。注：`TEST_P` 之类的参数化宏没解析
（本项目没有用到）。

---

## 与 LazyVim 官方 `dap.core` 的关系 ⚠️

**`lazyvim.plugins.extras.dap.core` 没有启用**，`<Space>d` 组全部来自本仓库的
`debug.lua`。所以官方那套更全的键位你都没有——包括 REPL、条件断点、
Run to Cursor、表达式求值、变量面板等。

**启用前务必注意：官方键位与你现有的同名键含义不同，会静默改变行为。**

| 键 | 你的 `debug.lua` | 官方 `dap.core` |
|---|---|---|
| `<Space>dB` | 打断点 | **条件断点** |
| `<Space>db` | （未定义） | 打断点 |
| `<Space>dn` | 单步跳过 | （未定义；官方用 `dO`） |
| `<Space>dt` | **开关 DAP UI** | **终止调试（Terminate）** |
| `<Space>du` | （未定义） | 开关 DAP UI |

最危险的是 `dt`：启用后它会从"开关面板"变成"**杀掉当前调试会话**"。

想用官方那套，正确做法是**启用 extra 并删掉 `debug.lua` 里重复的键位定义**，
而不是两者叠加。

---

## 常见问题

**Q（测试）: 提示 "No tests found"？**
先确认是哪种文件——**Python 和 C++ 是两个不同的适配器**，排查方式不一样：

- C++（`.cc`/`.cpp`/`.cxx`）：适配器是自写的 `neotest_cpp`，按**内容**判断
  （必须含 `TEST_F(`），root 是有 `.nvim.yaml` / `compile_commands.json` /
  `CMakeLists.txt` 的目录。**注意 `tests/tester.cc` 这类文件里其实一个
  `TEST_F(` 都没有**，对它报 "No tests found" 是正确的。
- Python：文件名必须匹配 `test_*.py`（neotest-python 按**文件名**判断，不看内容），
  且项目根要有 `pyproject.toml`。

其余通用排查：
1. 光标是否在 nvim 打开的文件里（不带参数的调用会回退到当前缓冲区）
2. ⚠️ **先看日志，别只看界面**。如果适配器回调抛了错（最常见的是在 fast event
   context 里调了 `vim.fn.getcwd` / `vim.notify`，报 E5560），neotest 会**静默**
   中止位置扫描，界面上就是一句 "No tests found"，看不到任何错误原因：
   ```bash
   grep -E "E5560|Couldn't find positions|ERROR" ~/.local/state/nvim/neotest.log | tail
   ```
3. 确认 adapter 在列表里：
   ```vim
   :lua print(vim.inspect(vim.tbl_map(function(a) return a.name end, require("neotest.config").adapters)))
   ```
4. 直接问适配器自己：
   ```vim
   :lua print(require("neotest_cpp").is_test_file(vim.api.nvim_buf_get_name(0)))
   :lua print(vim.inspect(require("project_config").resolve_for_buffer()))
   ```
5. 改过 `lua/neotest_cpp.lua` / `lua/project_config.lua` 后**必须重启 nvim**——
   Lua 模块加载后缓存在 `package.loaded`，改文件不会热更新。

**Q（测试/调试）: 为什么不能用 `uv run python`，明明终端里都这么用？**
因为 `<Space>td` 调试时，neotest 会把解释器命令**原样**塞进 debugpy 的
`python` 字段，而 debugpy 只接受**单个解释器路径**。
`{ "uv", "run", "python" }` 是三个元素，实测后果是：会话建立后**永不结束、
无结果输出**（不是报错，是静默卡死）。

实测对照（同样是 `<Space>td`）：

| `python` 取值 | 结果 |
|---|---|
| `{ "uv", "run", "python" }` | ✗ 会话卡死，无结果 |
| `{ ".venv/bin/python" }` | ✓ 正常，2 passed |
| `".venv/bin/python"` | ✓ 正常，2 passed |

代价是不再自动 sync 依赖：**改动 `pyproject.toml` 后要自己跑一次 `uv sync`**，
否则会 ImportError。

**Q（测试）: 想确认测试确实被跑起来了？**
看 neotest 日志里的进程退出码：
```bash
grep 'exited with code' ~/.local/state/nvim/neotest.log | tail
```

**Q（测试）: 输出里一大段覆盖率表格很烦？**
那是项目 `pyproject.toml` 里 `addopts` 带了 `--cov=xxx`，不是 nvim 造成的。
去掉它，或改成按需 `uv run pytest --cov=xxx`。

**Q（调试）: 按 `<Space>td` 报 "No adapter for type 'python'"？**
说明 `dap.adapters.python` 没注册。它由 `nvim-dap-python` 提供：
```lua
require("dap-python").setup("debugpy-adapter")
```
其中 `"debugpy-adapter"` 由 Mason 的 `debugpy` 包提供（必须已安装）。
本配置已包含这两者。

**Q（调试）: 断点不停 / 会话起不来？**
1. 确认适配器已注册，在 nvim 里执行：
   ```vim
   :lua print(vim.inspect(vim.tbl_keys(require("dap").adapters)))
   ```
   期望看到 `codelldb` 和 `python`。缺哪个就查对应的 Mason 包。
2. **`dap.log` 是每次会话覆盖写的**，所以要跑完立刻看：
   ```bash
   cat ~/.local/state/nvim/dap.log
   ```
3. **日志时间戳是 UTC，比本地时间早 8 小时**。看到"14:58"其实是本地 22:58。

**Q（调试）: 按 `<Space>tg` 提示找不到测试可执行文件？**
报错文案本身分三种情况，看它说哪一句就查哪一段：

| 报错里说 | 原因 | 怎么办 |
|---|---|---|
| 没找到 CMake 构建目录（没有 CMakeCache.txt） | 从没配置过 | `cmake -B build-Debug -DCMAKE_BUILD_TYPE=Debug` |
| 没找到 `CMAKE_BUILD_TYPE=Debug` 的构建目录 | 配置过但不是 Debug（报错里会列出每个目录的实际值） | 用 `-DCMAKE_BUILD_TYPE=Debug` 重新配置，或在 `.nvim.yaml` 写 `build_dir` 指定 |
| 在构建目录 X 里没找到名为 Y 的可执行文件 | `target` 写的是纯名字，且名字写错或还没构建过 | 先构建（报错里给了命令），或核对 `target`；也可以直接写相对路径 |
| .nvim.yaml 没写 target | 没建配置文件 | 加一行 `target: <相对路径>`（也可以只写目标名） |
| 测试可执行文件不存在：`<路径>` | `target` 写的是路径，但文件不在，且没找到构建目录 | 核对路径是否相对项目根；或补 `build_dir` 让自动编译有命令可用 |

不想猜的话，把光标放进测试文件里执行，一次拿到全部解析结果：
```vim
:lua print(vim.inspect(require("project_config").resolve_for_buffer()))
```
重点看 `root`（是不是解析到了别的项目根）、`build_dir`、`binary`、`problem`。

**Q（调试）: `.nvim.yaml` 改了没反应？**
配置按文件 mtime 缓存，改完存盘即生效。但如果构建目录整个换了位置
（`build-Debug/` 删掉改成 `build/`），进程里的探测缓存可能还指着旧的——
`.nvim.yaml` 存一次或执行下面的命令清掉：
```vim
:lua require("project_config").clear_cache()
```

**Q（调试）: `<Space>tg` 的选择列表是空的？**
二进制存在但 `--gtest_list_tests` 没输出。手动验证（在项目根下）：
```bash
./build-Debug/bin/LearnCPP_Test --gtest_list_tests
```

**Q（调试）: 有 codelldb 进程残留？**
调试会话被强制中断时可能留下 `codelldb --port ...` 进程。
确认没有正在调试的会话后可以手动结束它。

---

## 排查用的内部机制

写自动化脚本时会踩到这些：

**neotest 侧**
- 消费者（`run`/`summary` 等）**只在 `setup()` 执行后才挂到模块上**，
  直接 `require("neotest").run` 可能拿到 nil。要用
  `require("lazy").load({ plugins = { "neotest" } })` 并等待。
- `run.run()` 接受的参数只有：位置 ID 字符串、`{ 位置ID, strategy = ... }`、
  `{ suite = true }`，或什么都不传（跑光标最近用例）。
  传 `{ file = ... }` 之类**无效**，会静默回退到当前缓冲区。
- 该版本 neotest **没有** `get_adapters()` 这个 API。
  列出已注册的适配器用 `require("neotest.config").adapters`（每项有 `name`）。
- `discover_positions` 是 nio 异步函数，必须在 `nio.run()` 里调用。
- 结果不在回调里返回：用 `require("neotest").state.status_counts(adapter_id)`
  读，等 `running` 归零才算跑完。adapter_id 形如
  `neotest-python:/绝对路径/项目根`，由 `("%s:%s"):format(adapter.name, root)`
  拼出来——**自定义适配器必须设 `adapter.name`**，否则这里直接报错。
- `is_test_file` / `root` 可能在**非 nio 协程**的上下文里被调用
  （比如 neotest 的 dap strategy 里）。所以别在它们里面用
  `neotest.lib.files.read`——那是 `@async` 的，会直接报
  "Cannot call async function from non-async context"；自己用 `io.open` 读。
- ⚠️ **`is_test_file` / `build_spec` 实际跑在 fast event context 里**
  （nio 协程由 libuv 回调驱动）。那里下面这些会抛
  `E5560: ... must not be called in a fast event context`：

  | 调用 | fast context 安全？ |
  |---|---|
  | `vim.fn.getcwd()` | ✗ |
  | `vim.fn.shellescape()` | ✗ |
  | `vim.notify()` | ✗（内部是 `nvim_echo`） |
  | `vim.fn.executable()` | ✓ |
  | `vim.uv.*` / `io.*` / `vim.fs.*` / `vim.tbl_map` | ✓ |

  代价很大：只要 `is_test_file` 抛一次错，neotest 的 `_update_positions`
  就整个中止，`<Space>tr` 报 **"No tests found"** —— 而且**界面上什么错误都看不到**，
  只有 `~/.local/state/nvim/neotest.log` 里有 `Couldn't find positions in path ...`
  和 E5560 堆栈。所以这些回调里要发通知就
  `vim.schedule(function() vim.notify(...) end)`；`lua/project_config.lua` 为此专门有
  `notify_safe` / `shell_quote`，`is_test_file` 也只走廉价的 `extensions_for_path`，
  不做 CMake 探测。
- 排查这类问题时先看日志，别只看界面：
  ```bash
  grep -E "E5560|Couldn't find positions" ~/.local/state/nvim/neotest.log | tail
  ```
- `neotest.lib.treesitter.parse_positions` 的 `build_position` 传**函数**时会
  **退回主进程解析**（子进程没法传函数）；想保留子进程解析就传字符串，
  如 `'require("neotest_cpp").build_position'`。
- 探针脚本里 `vim.system(...)` 之后一定要 `:wait()`（或在 async 上下文里用
  `vim.system():wait()`）。漏了会留下后台 cmake 进程，和随后的构建抢
  `build-Debug/`，实测表现为 **exit code 2 的假失败**。

**nvim-dap 侧**
- `<Space>d` 组的键位**全部定义在 `debug.lua` 的 `config` 函数里**，
  所以只有 nvim-dap 真正加载后才会注册。headless 脚本里要先
  `require("lazy").load({ plugins = { "nvim-dap" } })` 再等待。
- 判断某个键绑了什么，比翻配置更快：
  ```vim
  :lua print(vim.inspect(vim.fn.maparg("<leader>dt", "n", false, true)))
  ```
  `desc` 字段能直接看出是哪个插件/文件注册的。
- ⚠️ `vim.fn.maparg("<leader>dt", ...)` 认 `<leader>` 记法，但
  `nvim_get_keymap()` 返回的 `lhs` 里 `<Space>` 是**真实空格字符**（`" dt"`）。
  用错形式查会一律查不到——**会让"检查通过"变成假象**。
- `dap.adapters.X` 为 `nil` 就是"适配器没注册"，报错通常是
  `No adapter for type 'X'`。改适配器的注册顺序前，先确认没有别处也在注册同名
  type——`mason-nvim-dap` 的 `automatic_installation` 是常见的覆盖来源。

**探针 / headless 脚本侧**

- ⚠️ **`nvim -l script.lua` 下 `package.path` 不会跟着 `runtimepath` 变**。
  比如这样跑：
  ```bash
  nvim --clean --cmd "set rtp+=~/.config/nvim" -l script.lua
  ```
  脚本里 `package.path` **照样看不到** `~/.config/nvim`，`require` 失败时的
  报错也只列 `package.path` 那几条默认路径——**看起来就像 rtp 没生效**。
  实际上 `require` 走的是 Neovim 自己的 loader，rtp 上的 `lua/` 正常能解析
  （实测：加了 rtp 后 `require("project_config")` 成功，而 `package.path`
  里始终没有那个目录）。

  所以给探针挂依赖用 **rtp** 就够，`--cmd` 和脚本里 append 两种写法都行：
  ```lua
  vim.opt.rtp:append("/home/inmove/.config/nvim")
  vim.opt.rtp:append("/home/inmove/.local/share/nvim/lazy/neotest")
  ```
  **别去改 `package.path`** —— 改了是白费功夫，还会让你以为"配置漏了"。
  目录模块（如 `neotest.lib` → `neotest/lua/neotest/lib/init.lua`）也由这个
  loader 处理，不用自己加 `?/init.lua`。
- 探针想验真实加载链路（lazy.nvim、插件 setup 时机）就别用 `--clean`：
  用 `nvim --headless -c "luafile probe.lua" -c "qa!"` 走用户配置，
  脚本里再用 `require("lazy").load({ plugins = { ... } })` + `vim.wait` 等插件起来。
- ⚠️ **`-c "luafile ..." -c "qa!"` 这种跑法，脚本里抛 Lua 错误退出码仍是 0**
  ——错误只打在 stderr，nvim 照常退出，自动化里**会变成假成功**。实测：

  | 跑法 | 脚本里 `error()` | 脚本里 `os.exit(7)` |
  |---|---|---|
  | `nvim --headless -c "luafile s.lua" -c "qa!"` | **0**（假成功） | 7 |
  | `nvim -l s.lua` | 1 | 7 |

  所以要么在脚本末尾显式 `os.exit(编号)`，要么打印一行标记（如
  `__PROBE_OK__`）再靠 `grep` 判断——本仓库的探针用后者，因为走真实配置时
  用的是 `-c "luafile"`，退出码不可信。
