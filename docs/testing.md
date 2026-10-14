# 在 Neovim 里跑测试与调试

本配置的测试/调试能力，围绕两个前缀组织：

- **`<Space>t` = 测试的一切** —— 运行 + 调试，Python 与 C++ 都在这里
- **`<Space>d` = 调试器通用操作** —— 断点、单步、面板，对任何调试会话都适用

所以：调试某个测试走 `t`，而调断点/单步走 `d`。

| 目标 | 跑 | 调 | 适配器 |
|---|---|---|---|
| Python / pytest | `<Space>tt` 等 | `<Space>td` | debugpy |
| C++ / gtest | （在 `<Space>tg` 的列表里选"运行全部"） | `<Space>tg` | codelldb |

---

## 快捷键

### `<Space>t` —— 测试

| 键 | 功能 |
|---|---|
| `<Space>tt` | **运行当前文件**的所有测试 |
| `<Space>tr` | **运行光标所在的那个测试**（最常用） |
| `<Space>tT` | 运行整个项目（cwd）的测试 |
| `<Space>tl` | 重跑上一次运行 |
| `<Space>td` | **调试光标所在 pytest 用例**（debugpy，可打断点、单步） |
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
| 插件 | `neotest` + `neotest-python`（测试）、`nvim-dap-python` + `debugpy`（调试）、`codelldb`（C++） |
| Python 项目 | 根目录有 `pyproject.toml`；测试文件命名 `test_*.py` 或 `*_test.py`；根目录有 `.venv/`（`uv sync` 生成） |
| C++ 项目 | 二进制在 `<项目根>/build-Debug/bin/LearnCPP_Test` |
| treesitter | 需要 python parser |

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

### C++ / gtest（`<Space>tg`）

1. **先构建**，否则会提示找不到二进制：
   ```bash
   cmake --build build-Debug -j
   ```
2. 按 `<Space>tg`，从列表里选用例：
   - `▶ 运行全部测试`
   - `⌨ 手动输入过滤器…`（gtest 语法：全称 `Tester.OpenCV_Hist_Match`，或通配 `*Hist*`）
   - 直接选某个具体用例（`Suite.TestName`）

用例列表是执行 `<二进制> --gtest_list_tests` 解析出来的，过滤器通过
`--gtest_filter=` 传给调试目标。

路径约定（`debug.lua` 里写死）：二进制必须是
`<项目根>/build-Debug/bin/LearnCPP_Test`，项目根取 nvim 的 cwd。

不在测试列表场景下，也可以用 `:lua require("dap").continue()` 走
`dap.configurations.cpp` 里注册的两个配置（全部 / 手动 filter）。

---

## 相关配置

| 文件 | 内容 |
|---|---|
| `lazyvim.json` | 启用 `lazyvim.plugins.extras.test.core` |
| `lua/plugins/python.lua` | neotest-python adapter、`nvim-dap-python`、debugpy |
| `lua/plugins/debug.lua` | codelldb 适配器、gtest 配置、`<Space>d*` 键位、DAP UI |

neotest 侧的核心配置：

```lua
-- lua/plugins/python.lua
["neotest-python"] = {
  runner = "pytest",
  python = ".venv/bin/python",   -- 不能写成 { "uv", "run", "python" }，见下
},
```

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
按顺序排查：
1. 文件名是否匹配 `test_*.py`（neotest-python 按文件名判断，不看内容）
2. 项目根有没有 `pyproject.toml`——adapter 靠它确定 root
3. 光标是否在 nvim 打开的文件里（不带参数的调用会回退到当前缓冲区）
4. 看日志确认 adapter 是否被识别：
   ```bash
   tail -30 ~/.local/state/nvim/neotest.log
   ```

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
`debug.lua` 写死了路径 `<cwd>/build-Debug/bin/LearnCPP_Test`。
先构建，并确认是在 **LearnCPP 项目根**打开 nvim（cwd 决定路径）。

**Q（调试）: `<Space>tg` 的选择列表是空的？**
二进制存在但 `--gtest_list_tests` 没输出。手动验证：
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
- `discover_positions` 是 nio 异步函数，必须在 `nio.run()` 里调用。
- 结果不在回调里返回：用 `require("neotest").state.status_counts(adapter_id)`
  读，等 `running` 归零才算跑完。adapter_id 形如
  `neotest-python:/绝对路径/项目根`。

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
