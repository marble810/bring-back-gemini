#!/usr/bin/env bash
# One-command bootstrap for Bring Back Gemini (macOS/Linux).
set -u

REPO=${BBG_REPO:-marble810/bring-back-gemini}
PAYLOAD_COMMIT=${BBG_PAYLOAD_COMMIT:-ca624fd0e2df6e6cb2d44b53b4fca1e51b1f8b73}
RAW_ROOT=${BBG_RAW_ROOT:-https://raw.githubusercontent.com/$REPO}

die() { printf '错误: %s\n' "$*" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || die "需要 curl"
command -v python3 >/dev/null 2>&1 || die "需要 python3"

case "$REPO" in
  *[!A-Za-z0-9._/-]*|/*|*/|*//*|*/*/*) die "BBG_REPO 格式无效: $REPO" ;;
esac

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/bring-back-gemini-run.XXXXXX") || die "无法创建临时目录"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

[[ "$PAYLOAD_COMMIT" =~ ^[0-9A-Fa-f]{40}$ ]] || die "BBG_PAYLOAD_COMMIT 必须是 40 位十六进制值"

printf '正在下载 %s@%s ...\n' "$REPO" "$PAYLOAD_COMMIT"
base="$RAW_ROOT/$PAYLOAD_COMMIT"
payload="$tmp_dir/bring-back-gemini.sh"
curl -fsSL --connect-timeout 15 --max-time 60 "$base/bring-back-gemini.sh" -o "$payload" || die "无法下载主脚本"
chmod 700 "$payload"
printf '已下载 %s@%s。\n' "$REPO" "$PAYLOAD_COMMIT"

run_payload() {
  # 交互终端下把 stdin 切到 /dev/tty：管道执行时 stdin 是 EOF，
  # 否则 payload 的“是否关闭 Chrome”确认会静默跳过。无 tty 时保持原样，
  # 仍走 payload 的非交互自动继续回退。用子 shell 试开 /dev/tty 探测，
  # 因为 MSYS 上 -r /dev/tty 在无控制终端时也会误报为可读。
  if (exec </dev/tty) 2>/dev/null; then
    bash "$payload" "$@" </dev/tty
  else
    bash "$payload" "$@"
  fi
  local status=$?
  return "$status"
}

if (($#)); then
  run_payload "$@"
  exit $?
fi

# 把现状检查的结果直接展示在主菜单上方，不再作为独立选项。
# 现状检查只做 validate/打印计划，不会停止、写入、提权或重启 Chrome。
preview_file="$tmp_dir/preview.txt"
printf '正在检查 Chrome 现状（只查看，不修改任何文件）…\n\n'
bash "$payload" --check </dev/null >"$preview_file" 2>&1
preview_rc=$?
if (( preview_rc != 0 )); then
  # 验证失败等：原样打印预览后退出，不进入菜单、不继续修改。
  cat "$preview_file"
  exit "$preview_rc"
fi

# 解析每个 "[label] status: path" 行，并按公共前缀截断路径。
p_lines=(); p_paths=()
while IFS= read -r line; do
  p_lines+=("$line")
  if [[ "$line" =~ ^\[([a-z]+)\]\ (计划修改|无需修改|验证失败):\ (.*)$ ]]; then
    p_paths+=("${BASH_REMATCH[3]}")
  elif [[ "$line" =~ ^\[([a-z]+)\]\ 跳过:\ 未找到\ (.*)$ ]]; then
    p_paths+=("${BASH_REMATCH[2]}")
  fi
done < <(grep -E '^\[[a-z]+\] ' "$preview_file" || true)

if ((${#p_paths[@]})); then
  common="${p_paths[0]}"
  for p in "${p_paths[@]:1}"; do
    while [[ -n "$common" && "$p" != "$common"* ]]; do
      common="${common%?}"
    done
    [[ -z "$common" ]] && break
  done
  # 截到最近的路径分隔符，保留后面的频道目录与文件名。
  common="${common%/*}"
else
  common=""
fi

shorten() {
  local s="$1"
  [[ -n "$common" && "$s" == "$common"/* ]] && s="…/${s#"$common"/}"
  printf '%s' "$s"
}

has_present=0
for line in "${p_lines[@]}"; do
  if [[ "$line" =~ ^\[([a-z]+)\]\ (计划修改|无需修改|验证失败):\ (.*)$ ]]; then
    label="${BASH_REMATCH[1]}"; status="${BASH_REMATCH[2]}"; path="${BASH_REMATCH[3]}"
    has_present=1
  elif [[ "$line" =~ ^\[([a-z]+)\]\ 跳过:\ 未找到\ (.*)$ ]]; then
    label="${BASH_REMATCH[1]}"; status="跳过(未找到)"; path="${BASH_REMATCH[2]}"
  else
    continue
  fi
  printf '  [%-6s] %s  %s\n' "$label" "$status" "$(shorten "$path")"
done

if ((has_present == 0)); then
  printf '\n未检测到任何可处理的 Chrome 配置。退出。\n'
  exit 0
fi

if (exec </dev/tty) 2>/dev/null; then
  cat >/dev/tty <<'EOF'

接下来怎么做？（上方是现状检查结果：只是看了看，什么都没改）
  1) 应用到所有检测到的频道          （默认）
  2) 仅应用到 Chrome Stable
  3) 应用全部频道，并禁用本地 AI 模型下载
  0) 退出
EOF
  choice=""; got=0
  for _ in 1 2 3; do
    printf '请输入 [1]: ' >/dev/tty
    IFS= read -r choice </dev/tty || { choice=""; break; }
    choice=${choice:-1}
    case "$choice" in 1|2|3|0) got=1; break ;; *) echo "无效选择: $choice" >/dev/tty ;; esac
  done
  if ((got == 0)); then
    [[ -z "$choice" ]] && { echo '已取消。'; exit 0; }
    die '多次无效输入，已取消'
  fi
else
  # 非交互环境：预览已展示，不再自动修改，避免管道执行造成意外改动。
  exit 0
fi
case "$choice" in
  1) run_payload ;;
  2) run_payload --channel stable ;;
  3) run_payload --disable-ai-download ;;
  0) echo '已取消。'; exit 0 ;;
esac
exit $?
