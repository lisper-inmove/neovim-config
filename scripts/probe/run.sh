#!/usr/bin/env bash
# 跑 scripts/probe/ 下的全部探针。
#
#   ./scripts/probe/run.sh
#
# 环境变量：
#   NVIM=...            nvim 可执行文件（默认 nvim）
#   PROBE_PROJECT=...   真实 C++ 项目路径（默认 /home/inmove/code/LearnCPP）
#
# 说明：`nvim -l` 的退出码是可信的（脚本里 os.exit(1) 会传出去）。
# 但走真实配置的那个探针用的是 `-c "luafile"` —— 那种模式下脚本里抛 Lua 错误
# 退出码仍是 0（实测），所以它靠打印 __PROBE_OK__ 标记行来判断。
set -u
cd "$(dirname "$0")" || exit 1
HERE=$(pwd)

NVIM=${NVIM:-nvim}
export PROBE_PROJECT=${PROBE_PROJECT:-/home/inmove/code/LearnCPP}
out=$(mktemp)
trap 'rm -f "$out"' EXIT

fail=0
total=0
failed_names=()

run_clean() {
  local f=$1 total_name
  total_name=$(basename "$f" .lua)
  total=$((total + 1))
  printf '  %-22s ' "$total_name"
  if "$NVIM" --clean -l "$HERE/$f" >"$out" 2>&1; then
    printf '%s\n' "$(grep -E '^[0-9]+ passed' "$out" | tail -1)"
  else
    echo "FAILED"
    sed 's/^/      /' "$out" | tail -20
    fail=1
    failed_names+=("$total_name")
  fi
}

run_real_config() {
  local f=$1 total_name
  total_name=$(basename "$f" .lua)
  total=$((total + 1))
  printf '  %-22s ' "$total_name"
  if "$NVIM" --headless -c "luafile $HERE/$f" -c 'qa!' >"$out" 2>&1 && grep -q '__PROBE_OK__' "$out"; then
    printf '%s\n' "$(grep -E '^[0-9]+ passed' "$out" | tail -1)"
  else
    echo "FAILED"
    grep -vE '^(__PROBE_|$)' "$out" | tail -20 | sed 's/^/      /'
    fail=1
    failed_names+=("$total_name")
  fi
}

echo "探针（$NVIM，真实项目: $PROBE_PROJECT）"
run_clean probe-yaml.lua
run_clean probe-config.lua
run_clean probe-fastctx.lua
run_clean probe-debug.lua
run_real_config probe-real-session.lua

echo
if [ "$fail" -ne 0 ]; then
  echo "失败: ${failed_names[*]}（共 $total 个探针）"
  exit 1
fi
echo "全部 $total 个探针通过"
