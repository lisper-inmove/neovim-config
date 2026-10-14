# 新机器安装指南

把这份 Neovim 配置（LazyVim 16.0.1）装上并达到可用状态 —— **打包装箱、开箱即用**。

---

## 前置条件

| 项目 | 要求 | 说明 |
|---|---|---|
| 系统 | deps: Debian / Ubuntu（有 `apt`） | 其他发行版用 `--skip-deps` 自行装依赖 |
| 权限 | 普通用户，需 `sudo` 装系统包 | **不要用 root 跑**（配置会装进 `/root`） |
| 网络 | 能访问 GitHub | clone 仓库 + 下载 nvim + 拉插件 |
| GitHub | SSH key 或 HTTPS 可达 | SSH 失败会自动回退 HTTPS |

**不需要预先装 Neovim** —— 脚本会检测并按需从 GitHub 官方 release 安装（Ubuntu 仓库里的 neovim 是 0.9.5，**版本太低**，LazyVim 16.x 要求 ≥ 0.11.2，脚本不会用它）。

---

## 快速开始

新机器上（只需要这个脚本）：

```bash
# 方式一：从仓库取脚本（推荐，永远最新）
curl -fsSL https://raw.githubusercontent.com/lisper-inmove/neovim-config/v1/install.sh -o /tmp/install-nvim.sh
bash /tmp/install-nvim.sh

# 方式二：已 clone 过仓库
bash ~/.config/nvim/install.sh

# 新机器无人值守（全部自动确认）
bash /tmp/install-nvim.sh --yes
```

装完打开新终端（或 `source ~/.zshrc`），运行 `nvim` 即可。首次启动还会自动安装 Mason 的 LSP/格式化工具（约 1-2 分钟）。

### 命令行选项

| 选项 | 作用 |
|---|---|
| `-y, --yes` | 全部自动确认，不交互（适合新机器一次性执行） |
| `--upgrade-nvim` | 即使已有可用 nvim，也升级到最新稳定版 |
| `--skip-deps` | 跳过 apt 系统依赖安装（自己管理依赖时用） |
| `-h, --help` | 显示帮助 |

### 可覆盖的环境变量

```bash
REPO_URL=git@github.com:xxx/fork.git NVIM_DIR=~/.config/nvim bash install.sh
```

| 变量 | 默认值 |
|---|---|
| `REPO_URL` / `REPO_URL_HTTPS` | `lisper-inmove/neovim-config` 的 SSH / HTTPS 地址 |
| `NVIM_DIR` | `~/.config/nvim` |
| `NVIM_OPT_DIR` | `~/.opt/nvim`（nvim 二进制解压位置） |
| `NVIM_BIN_DIR` | `~/.bin`（nvim 软链目录，需在 PATH 中） |

---

## 脚本做什么

七个阶段，**幂等** —— 重复执行不产生副作用，可当作"修复/更新"工具反复跑。

| 阶段 | 内容 |
|---|---|
| 0 | 前置检查：拒绝 root、确认 curl/tar/apt 可用 |
| 1 | apt 安装 `git build-essential curl unzip xclip ripgrep fd-find`（仅装缺的） |
| 2 | 检测 nvim 版本；不满足 ≥ 0.11.2 时下载官方 tarball 到 `~/.opt/nvim`，软链到 `~/.bin/nvim`。**够用就不动你的版本**（升级需显式 `--upgrade-nvim`） |
| 3 | 确保 `~/.bin` 在 PATH 中（幂等写入 `.zshrc`/`.bashrc`） |
| 4 | `~/.config/nvim` 已有则**备份**为 `nvim.bak.<时间戳>`，再 clone 本仓库；已存在同仓库则 `git pull --ff-only` 更新（有未提交改动时跳过，不覆盖你） |
| 5 | `nvim --headless "+Lazy! sync"` 按 `lazy-lock.json` 装齐全部插件 |
| 6 | 可选依赖检查（只提示，不阻断），见下 |
| 7 | 打印后续步骤 |

### 安装布局（与 dotfiles 风格一致，全部在用户态）

```
~/.opt/nvim/          # nvim 二进制（GitHub 官方 release）
~/.bin/nvim           # 软链 → ~/.opt/nvim/bin/nvim
~/.config/nvim/       # 本配置仓库（git 管理）
~/.local/share/nvim/  # 插件、Mason 工具（脚本不动，nvim 自动管理）
```

旧版本升级时会备份到 `~/.opt/nvim.bak.<时间戳>`。

---

## 可选依赖（缺失只提示，不影响安装）

| 功能 | 依赖 | 启用方式 |
|---|---|---|
| AI 对话/代码解释 (`<leader>ac` 等) | `DEEPSEEK_API_KEY` | `echo 'export DEEPSEEK_API_KEY=sk-xxx' >> ~/.zshrc` |
| 本地模型 (`<leader>op`) | ollama + `codegemma:7b-instruct` | `ollama pull codegemma:7b-instruct` |

---

## 日常使用

| 快捷键 | 功能 |
|---|---|
| `<Space>e` | 打开文件树 |
| `<Space>ff` / `<Space>/` | 找文件 / 全文搜索 |
| `gd` / `K` | 跳定义 / 查文档（clangd） |
| `<Space>dB` | 打断点 |
| `<Space>tg` | **选择 gtest 用例调试**（C++ 项目 / LearnCPP） |
| `<Space>dt` | 开关调试面板 |
| `<C-n>` | neo-tree 文件树 |
| `<Space>ac` / `<Space>op` | AI 对话 / 本地模型 |

---

## 常见问题

**Q: SSH clone 失败（新机器没配 key）？**
脚本会自动回退 HTTPS。若私有仓库 HTTPS 也要认证，先配好其一：
```bash
ssh-keygen -t ed25519 -C "you@example.com"   # 然后把公钥加到 GitHub
# 或：gh auth login
```
也可以直接指定地址：`REPO_URL=https://.../neovim-config.git bash install.sh`

**Q: 端口/网速慢，插件装了很久？**
正常，首次 3-5 分钟。中断了不要紧，重跑脚本（或进 nvim 执行 `:Lazy sync`）会继续。

**Q: 装完 `nvim` 命令找不到？**
`~/.bin` 还没进当前终端 PATH。新开一个终端，或 `source ~/.zshrc`。

**Q: 想更新配置/插件？**
```bash
bash ~/.config/nvim/install.sh        # 拉配置 + 装齐插件（幂等）
bash ~/.config/nvim/install.sh --upgrade-nvim   # 顺带升级 nvim 本体
```

**Q: 装完某些功能仍报错？**
进入 nvim 执行 `:checkhealth` 看完整报告；`:Lazy` 看插件状态；`:Mason` 看 LSP/工具。

**Q: 剪贴板 yank 失败（Wayland）？**
`init.lua` 硬编码了 `xclip`（X11）。纯 Wayland 会话需要改用它：
```lua
-- init.lua 里把 xclip 换成 wl-copy/wl-paste，或直接删掉 vim.g.clipboard
-- （新版本 Neovim 在 X11/Wayland 下自带剪贴板支持）
```

**Q: 装完不想用了？**
删掉 `~/.config/nvim` 和 `~/.local/share/nvim` 即可；旧配置在 `~/.config/nvim.bak.<时间戳>`。

---

## 本配置包含什么

- **LazyVim 16.0.1**（`lazy-lock.json` 锁定插件版本，跨机器可复现）
- 语言增强：clangd(C/C++)、cmake、json、markdown
- 调试：nvim-dap + codelldb（gtest 断点调试，见 `lua/plugins/debug.lua`）
- 文件树 neo-tree、模糊搜索 fzf
- AI：llm.nvim (DeepSeek)、ollama.nvim（可选）

修改配置：直接编辑 `~/.config/nvim/` 下的 Lua 文件，commit + push，其他机器重跑脚本即可同步。
