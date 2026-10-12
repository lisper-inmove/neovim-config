#!/usr/bin/env bash
# =============================================================================
#  Neovim 配置安装脚本 —— 新机器一键可用
#
#  仓库:  git@github.com:lisper-inmove/neovim-config.git
#  用法:  bash install.sh [选项]        (详细说明见 install.md)
#
#  脚本是幂等的：重复执行不会破坏已有安装。
# =============================================================================
set -uo pipefail

# ------------------------------- 常量配置 ------------------------------------
# 均可用环境变量覆盖（方便从 fork 安装或集成测试）
REPO_URL="${REPO_URL:-git@github.com:lisper-inmove/neovim-config.git}"
REPO_URL_HTTPS="${REPO_URL_HTTPS:-https://github.com/lisper-inmove/neovim-config.git}"
NVIM_DIR="${NVIM_DIR:-$HOME/.config/nvim}"
NVIM_OPT_DIR="${NVIM_OPT_DIR:-$HOME/.opt/nvim}"   # nvim 二进制安装位置（与 dotfiles 布局一致）
NVIM_BIN_DIR="${NVIM_BIN_DIR:-$HOME/.bin}"        # 软链目录（在 .zshrc 的 PATH 中）
NVIM_MIN_VERSION="0.11.2"               # LazyVim 16.x 的硬性要求
NVIM_FALLBACK_VERSION="0.12.6"          # GitHub API 不可用时的兜底版本
APT_DEPS=(git build-essential curl unzip xclip ripgrep fd-find)

# ------------------------------- 输出着色 ------------------------------------
if [ -t 1 ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  BLUE=$'\033[34m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; DIM=""; NC=""
fi
say()  { printf '%s\n' "$*"; }
step() { printf '\n%s==>%s %s\n' "$BLUE" "$NC" "$*"; }
ok()   { printf '  %s[ok]%s   %s\n' "$GREEN" "$NC" "$*"; }
skip() { printf '  %s[skip]%s %s\n' "$DIM" "$NC" "$*"; }
warn() { printf '  %s[warn]%s %s\n' "$YELLOW" "$NC" "$*"; }
err()  { printf '  %s[err]%s  %s\n' "$RED" "$NC" "$*"; }
die()  { err "$*"; exit 1; }

# ------------------------------- 命令行选项 ----------------------------------
ASSUME_YES=0
UPGRADE_NVIM=0
SKIP_DEPS=0
usage() {
  cat <<'USAGE'
用法: bash install.sh [选项]

选项:
  -y, --yes            全部自动确认，不交互（适合新机器一次性执行）
      --upgrade-nvim   即使已有 nvim 能跑，也升级到最新稳定版
      --skip-deps      跳过 apt 系统依赖安装
  -h, --help           显示本帮助
USAGE
}
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)         ASSUME_YES=1 ;;
    --upgrade-nvim)   UPGRADE_NVIM=1 ;;
    --skip-deps)      SKIP_DEPS=1 ;;
    -h|--help)        usage; exit 0 ;;
    *) die "未知选项: $1（用 -h 查看帮助）" ;;
  esac
  shift
done

confirm() { # $1=提示语
  [ "$ASSUME_YES" = 1 ] && return 0
  printf '%s [Y/n] ' "$1"
  local ans=""
  read -r ans || ans=""
  case "$ans" in ""|y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ------------------------------- 工具函数 ------------------------------------
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# 比较版本号: version_ge 0.12.5 0.11.2 → 成功
version_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

# sudo 前缀（非 root 环境需要提权）
SUDO=""
if [ "$(id -u)" != "0" ]; then
  if cmd_exists sudo; then
    SUDO="sudo"
  fi
fi

apt_install() { # $@ = 包名
  local to_install=()
  local p
  for p in "$@"; do
    dpkg -s "$p" >/dev/null 2>&1 || to_install+=("$p")
  done
  if [ "${#to_install[@]}" -eq 0 ]; then
    skip "apt 依赖已全部安装"
    return 0
  fi
  say "  需要安装: ${BOLD}${to_install[*]}${NC}"
  $SUDO apt-get update -qq || die "apt-get update 失败（检查网络或软件源）"
  $SUDO apt-get install -y "${to_install[@]}" || die "apt 安装失败"
  ok "apt 依赖安装完成"
}

# 从 GitHub API 获取 neovim 最新稳定版号，失败则用兜底版本
latest_nvim_version() {
  local tag
  tag="$(curl -fsSL --max-time 20 \
    https://api.github.com/repos/neovim/neovim/releases/latest 2>/dev/null \
    | grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')"
  if [ -n "$tag" ] && printf '%s' "$tag" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf '%s' "$tag"
  else
    warn "无法查询 neovim 最新版本，使用兜底版本 v$NVIM_FALLBACK_VERSION" >&2
    printf '%s' "$NVIM_FALLBACK_VERSION"
  fi
}

# 判断是否需要（重新）安装 nvim（0=需要, 1=不需要）
need_nvim_install() {
  [ "$UPGRADE_NVIM" = 1 ] && return 0
  if ! cmd_exists nvim; then
    return 0
  fi
  local ver
  ver="$(nvim --version 2>/dev/null | head -n1 | sed -E 's/^NVIM v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
  if ! printf '%s' "$ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    return 0 # 版本号解析不出来（如 nightly），当不满足处理
  fi
  if version_ge "$ver" "$NVIM_MIN_VERSION"; then
    return 1 # 已满足要求
  fi
  return 0
}

install_nvim() {
  local version="$1"
  local platform arch asset url tmp tarball
  case "$(uname -s)" in
    Linux)  platform="linux" ;;
    Darwin) platform="macos" ;;
    *) die "不支持的系统: $(uname -s)（本脚本面向 Linux）" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "不支持的架构: $(uname -m)" ;;
  esac
  asset="nvim-$platform-$arch.tar.gz"
  url="https://github.com/neovim/neovim/releases/download/v$version/$asset"

  say "  安装 neovim v$version → ${BOLD}$NVIM_OPT_DIR${NC}"
  tmp="$(mktemp -d)"
  tarball="$tmp/$asset"
  if ! curl -fL --progress-bar --max-time 600 -o "$tarball" "$url"; then
    rm -rf "$tmp"
    die "下载失败: $url"
  fi
  if ! tar -xzf "$tarball" -C "$tmp"; then
    rm -rf "$tmp"
    die "解压失败: $tarball"
  fi
  [ -x "$tmp/nvim-$platform-$arch/bin/nvim" ] || { rm -rf "$tmp"; die "压缩包结构异常，未找到 bin/nvim"; }

  # 原子替换：先解到临时目录再搬过去，失败时保留原安装
  mkdir -p "$NVIM_BIN_DIR"
  if [ -e "$NVIM_OPT_DIR" ] && [ ! -d "$NVIM_OPT_DIR" ]; then
    rm -f "$NVIM_OPT_DIR"                       # 旧软链，清掉
  elif [ -d "$NVIM_OPT_DIR" ]; then
    local backup="$NVIM_OPT_DIR.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$NVIM_OPT_DIR" "$backup"
    say "  已备份旧版本 → $backup"
  fi
  mv "$tmp/nvim-$platform-$arch" "$NVIM_OPT_DIR"
  rm -rf "$tmp"
  ln -sfn "$NVIM_OPT_DIR/bin/nvim" "$NVIM_BIN_DIR/nvim"
  ok "nvim v$version 安装完成: $NVIM_BIN_DIR/nvim"
}

# 确保 ~/.bin 在 PATH 中（幂等写入 shell rc）
ensure_path() {
  case ":$PATH:" in
    *":$NVIM_BIN_DIR:"*) ok "$NVIM_BIN_DIR 已在 PATH 中"; return 0 ;;
  esac
  local rc="$HOME/.bashrc"
  case "${SHELL:-}" in
    *zsh) rc="$HOME/.zshrc" ;;
    *bash) rc="$HOME/.bashrc" ;;
  esac
  if [ -f "$rc" ] && grep -qF "$NVIM_BIN_DIR" "$rc"; then
    ok "$rc 中已有 PATH 配置（重新打开终端生效）"
    return 0
  fi
  {
    printf '\n# 用户级可执行文件 (added by nvim-config install.sh)\n'
    printf 'export PATH=%s:$PATH\n' "$NVIM_BIN_DIR"
  } >> "$rc"
  ok "已把 $NVIM_BIN_DIR 写入 $rc（重新打开终端生效）"
}

# clone 仓库（优先 SSH，失败回退 HTTPS），并设置 upstream 便于后续 git pull
clone_config_repo() {
  say "  clone 配置仓库 → $NVIM_DIR"
  if ! GIT_SSH_COMMAND="ssh -o BatchMode=yes" git clone "$REPO_URL" "$NVIM_DIR" 2>/dev/null; then
    say "  SSH clone 失败（新机器可能还没配 GitHub SSH key），尝试 HTTPS…"
    git clone "$REPO_URL_HTTPS" "$NVIM_DIR" || \
      die "clone 失败。请先配置 GitHub 访问方式后重试（见 install.md 的'常见问题'）"
  fi
  # 让后续的 git pull --ff-only 能直接工作
  local branch
  branch="$(git -C "$NVIM_DIR" symbolic-ref --short HEAD 2>/dev/null || true)"
  if [ -n "$branch" ]; then
    git -C "$NVIM_DIR" config "branch.$branch.remote" origin
    git -C "$NVIM_DIR" config "branch.$branch.merge" "refs/heads/$branch"
  fi
  ok "配置仓库已就位"
}

# 安装/更新配置文件仓库
setup_config() {
  mkdir -p "$(dirname "$NVIM_DIR")"
  if [ -d "$NVIM_DIR/.git" ]; then
    local origin
    origin="$(git -C "$NVIM_DIR" remote get-url origin 2>/dev/null || true)"
    if [ "$origin" = "$REPO_URL" ] || [ "$origin" = "$REPO_URL_HTTPS" ]; then
      say "  配置仓库已存在，尝试更新…"
      if [ -n "$(git -C "$NVIM_DIR" status --porcelain)" ]; then
        warn "本地有未提交的改动，跳过 git pull（避免覆盖你的修改）"
      else
        git -C "$NVIM_DIR" pull --ff-only && ok "已更新到最新" \
          || warn "git pull 失败，继续使用当前版本"
      fi
      return 0
    fi
    warn "$NVIM_DIR 是其他 git 仓库，将备份后重新 clone"
  elif [ -e "$NVIM_DIR" ]; then
    warn "$NVIM_DIR 已存在且不是本仓库"
  else
    clone_config_repo
    return 0
  fi

  # 走到这里说明需要备份已有目录
  local backup="$NVIM_DIR.bak.$(date +%Y%m%d-%H%M%S)"
  say "  备份已有配置: $NVIM_DIR → $backup"
  mv "$NVIM_DIR" "$backup" || die "备份失败"
  clone_config_repo
}

# 引导 lazy.nvim 安装全部插件（使用 lazy-lock.json 锁定版本）
bootstrap_plugins() {
  local nvim_bin
  nvim_bin="$(command -v nvim || true)"
  if [ -z "$nvim_bin" ] && [ -x "$NVIM_BIN_DIR/nvim" ]; then
    nvim_bin="$NVIM_BIN_DIR/nvim"
    warn "$NVIM_BIN_DIR 还不在当前 PATH 中，本次直接用绝对路径调用"
  fi
  [ -n "$nvim_bin" ] || die "找不到 nvim 可执行文件"

  say "  运行 headless 安装插件（首次约 3-5 分钟，取决于网速）…"
  local log
  log="$(mktemp)"
  if ! "$nvim_bin" --headless "+Lazy! sync" +qa >"$log" 2>&1; then
    err "插件安装过程有报错，日志尾部如下:"
    tail -n 30 "$log" >&2
    rm -f "$log"
    die "引导失败。可手动执行 nvim 后运行 :Lazy sync 查看详情"
  fi
  rm -f "$log"
  ok "插件已按 lazy-lock.json 安装完成"
}

# 可选依赖与剪贴板检查（只提示，不阻断）
check_optional() {
  # 剪贴板：init.lua 硬编码了 xclip
  if cmd_exists xclip; then
    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
      warn "检测到纯 Wayland 会话：init.lua 硬编码的是 xclip，yank 可能失败（见 install.md）"
    else
      ok "xclip 可用（剪贴板）"
    fi
  else
    warn "未找到 xclip —— init.lua 的剪贴板配置依赖它"
  fi
  # DeepSeek（llm.nvim）
  if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    ok "DEEPSEEK_API_KEY 已设置（llm.nvim 可用）"
  else
    warn "未设置 DEEPSEEK_API_KEY —— llm.nvim 的 AI 功能不可用"
    say  "       如需启用: echo 'export DEEPSEEK_API_KEY=sk-xxx' >> ~/.zshrc"
  fi
  # Ollama
  if cmd_exists ollama; then
    if ollama list 2>/dev/null | grep -q "codegemma:7b-instruct"; then
      ok "ollama 与 codegemma:7b-instruct 已就绪"
    else
      warn "ollama 已安装但缺少模型 codegemma:7b-instruct"
      say  "       拉取模型: ollama pull codegemma:7b-instruct"
    fi
  else
    warn "未安装 ollama —— 本地模型功能不可用（https://ollama.com）"
  fi
}

# ================================ 主流程 =====================================
main() {
  say "${BOLD}Neovim 配置安装脚本${NC}  (repo: lisper-inmove/neovim-config)"
  say "${DIM}目标: $NVIM_DIR   nvim: ${NVIM_MIN_VERSION}+${NC}"

  # ---- 0. 前置检查 ----
  step "0/7 前置检查"
  if [ "$(id -u)" = "0" ]; then
    die "请不要用 root 运行本脚本（\$HOME 会变成 /root，配置会装错地方）"
  fi
  cmd_exists curl || die "缺少 curl，请先安装: sudo apt install curl"
  cmd_exists tar  || die "缺少 tar，请先安装: sudo apt install tar"
  if [ "$SKIP_DEPS" = 0 ]; then
    cmd_exists apt-get || die "未找到 apt-get（本脚本面向 Debian/Ubuntu）"
  fi
  ok "环境检查通过"

  # ---- 1. 系统依赖 ----
  step "1/7 系统依赖 (apt)"
  if [ "$SKIP_DEPS" = 1 ]; then
    skip "按 --skip-deps 跳过"
  else
    apt_install "${APT_DEPS[@]}"
  fi

  # ---- 2. nvim 二进制 ----
  step "2/7 neovim 二进制"
  if need_nvim_install; then
    local latest
    latest="$(latest_nvim_version)"
    if cmd_exists nvim; then
      local cur
      cur="$(nvim --version 2>/dev/null | head -n1)"
      warn "当前版本不满足要求: $cur"
    fi
    if confirm "  安装 neovim v$latest 到 $NVIM_OPT_DIR ?"; then
      install_nvim "$latest"
    else
      die "已取消。LazyVim 需要 nvim >= $NVIM_MIN_VERSION"
    fi
  else
    local cur
    cur="$(nvim --version 2>/dev/null | head -n1)"
    skip "已有可用版本: $cur（如需升级: $0 --upgrade-nvim）"
  fi

  # ---- 3. PATH ----
  step "3/7 PATH"
  ensure_path

  # ---- 4. 配置文件 ----
  step "4/7 配置文件 $NVIM_DIR"
  setup_config

  # ---- 5. 插件引导 ----
  step "5/7 插件引导 (lazy.nvim)"
  bootstrap_plugins

  # ---- 6. 可选依赖 ----
  step "6/7 可选依赖检查"
  check_optional

  # ---- 7. 完成 ----
  step "7/7 完成"
  say "  启动:  ${BOLD}nvim${NC}   (首次启动会自动安装 Mason 里的 LSP/格式化工具)"
  say "  体检:  ${BOLD}nvim --headless '+checkhealth' +qa${NC}   或进入 nvim 后 :checkhealth"
  say "  文档:  仓库内 ${BOLD}install.md${NC}"
  say ""
  say "  ${GREEN}${BOLD}安装完成 ✔${NC}"
}

main "$@"
