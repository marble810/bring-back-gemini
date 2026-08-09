#!/usr/bin/env bash
# One-command bootstrap for Bring Back Gemini (macOS/Linux).
set -u

REPO=${BBG_REPO:-marble810/bring-back-gemini}
PAYLOAD_COMMIT=${BBG_PAYLOAD_COMMIT:-1e74e4637a72405e5a2c1968a485cdfdd6a24aab}
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
manifest="$tmp_dir/checksums.sha256"
payload="$tmp_dir/bring-back-gemini.sh"
curl -fsSL --connect-timeout 15 --max-time 60 "$base/checksums.sha256" -o "$manifest" || die "无法下载校验清单"
curl -fsSL --connect-timeout 15 --max-time 60 "$base/bring-back-gemini.sh" -o "$payload" || die "无法下载主脚本"

expected=$(awk '$2 == "bring-back-gemini.sh" { print tolower($1); exit }' "$manifest")
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die "校验清单缺少有效的 bring-back-gemini.sh 哈希"
actual=$(python3 - "$payload" <<'PY'
import hashlib, sys
with open(sys.argv[1], "rb") as f:
    print(hashlib.sha256(f.read()).hexdigest())
PY
) || die "无法计算脚本哈希"
[[ "$actual" == "$expected" ]] || die "主脚本 SHA-256 校验失败"
chmod 700 "$payload"
printf '已验证提交 %s，SHA-256 匹配。\n' "$PAYLOAD_COMMIT"

run_payload() {
  bash "$payload" "$@"
  local status=$?
  return "$status"
}

if (($#)); then
  run_payload "$@"
  exit $?
fi

choice=""
if [[ -r /dev/tty ]]; then
  cat >/dev/tty <<'EOF'

请选择操作：
  1) Dry-run：只预览，不修改（推荐）
  2) 应用到 Chrome Stable
  3) 应用到所有检测到的 Chrome 频道
  4) 应用全部频道，并禁用本地 AI 模型下载
  0) 退出
EOF
  printf '请输入 [1]: ' >/dev/tty
  IFS= read -r choice </dev/tty || choice=""
fi
choice=${choice:-1}
case "$choice" in
  1) run_payload --dry-run ;;
  2) run_payload --channel stable ;;
  3) run_payload ;;
  4) run_payload --disable-ai-download ;;
  0) echo "已取消。"; exit 0 ;;
  *) die "无效选择: $choice" ;;
esac
exit $?
