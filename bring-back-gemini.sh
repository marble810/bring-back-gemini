#!/usr/bin/env bash
# Safe Local State patcher for Google Chrome (macOS/Linux).
set -u

PROGRAM=${0##*/}
DRY_RUN=0
NO_RESTART=0
DISABLE_AI_DOWNLOAD=0
CUSTOM_DIR=""
CHANNEL_ARGS=()

usage() {
  cat <<'EOF'
用法: bring-back-gemini.sh [选项]

安全地修改 Google Chrome 的 Local State，以尝试启用 Ask Gemini/Glic。
仅支持 macOS 和 Linux；JSON 处理需要 python3。

选项:
  --channel NAME          选择 stable、beta、dev 或 canary；可重复或逗号分隔（默认: all）
  --user-data-dir PATH    只处理指定的用户数据目录（便于安全测试）
  --dry-run               仅检查并显示计划；不停止、写入、提权或重启 Chrome
  --no-restart            修改后不重启先前运行的 Chrome
  --disable-ai-download   额外禁用两个本地 AI 模型 flag，并安装
                          GenAILocalFoundationalModelSettings=1 策略；会显示
                          “由您的组织管理”提示（默认关闭）
  -h, --help              显示帮助

退出码: 0=完成/无需更改，1=失败，2=部分完成，64=用法错误。
EOF
}

die_usage() { printf '错误: %s\n' "$*" >&2; usage >&2; exit 64; }

while (($#)); do
  case "$1" in
    --channel)
      (($# >= 2)) || die_usage "--channel 需要参数"
      [[ -n "$2" && "$2" != ,* && "$2" != *, && "$2" != *,,* ]] || die_usage "--channel 不能为空"
      IFS=',' read -r -a _parts <<< "$2"
      CHANNEL_ARGS+=("${_parts[@]}"); shift 2 ;;
    --user-data-dir)
      (($# >= 2)) || die_usage "--user-data-dir 需要参数"
      CUSTOM_DIR=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-restart) NO_RESTART=1; shift ;;
    --disable-ai-download) DISABLE_AI_DOWNLOAD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die_usage "未知参数: $1" ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "错误: 需要 python3，未进行任何修改。" >&2; exit 1; }

OS=$(uname -s)
case "$OS" in
  Darwin|Linux) ;;
  *) echo "错误: 此脚本仅支持 macOS/Linux。" >&2; exit 1 ;;
esac

if ((${#CHANNEL_ARGS[@]} == 0)); then CHANNEL_ARGS=(stable beta dev canary); fi
CHANNELS=()
for ch in "${CHANNEL_ARGS[@]}"; do
  ch=$(printf '%s' "$ch" | tr '[:upper:]' '[:lower:]')
  [[ "$ch" == all ]] && { CHANNELS=(stable beta dev canary); break; }
  case "$ch" in stable|beta|dev|canary) ;; *) die_usage "无效频道: $ch" ;; esac
  seen=0; for old in "${CHANNELS[@]}"; do [[ "$old" == "$ch" ]] && seen=1; done
  ((seen)) || CHANNELS+=("$ch")
done

ROOTS=(); LABELS=(); EXES=()
add_target() { LABELS+=("$1"); ROOTS+=("$2"); EXES+=("$3"); }
if [[ -n "$CUSTOM_DIR" ]]; then
  add_target custom "$CUSTOM_DIR" ""
elif [[ "$OS" == Darwin ]]; then
  for ch in "${CHANNELS[@]}"; do
    case "$ch" in
      stable) add_target stable "$HOME/Library/Application Support/Google/Chrome" "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ;;
      beta) add_target beta "$HOME/Library/Application Support/Google/Chrome Beta" "/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta" ;;
      dev) add_target dev "$HOME/Library/Application Support/Google/Chrome Dev" "/Applications/Google Chrome Dev.app/Contents/MacOS/Google Chrome Dev" ;;
      canary) add_target canary "$HOME/Library/Application Support/Google/Chrome Canary" "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary" ;;
    esac
  done
else
  for ch in "${CHANNELS[@]}"; do
    case "$ch" in
      stable) add_target stable "$HOME/.config/google-chrome" "/opt/google/chrome/chrome" ;;
      beta) add_target beta "$HOME/.config/google-chrome-beta" "/opt/google/chrome-beta/chrome" ;;
      dev) add_target dev "$HOME/.config/google-chrome-unstable" "/opt/google/chrome-unstable/chrome" ;;
      canary) add_target canary "$HOME/.config/google-chrome-canary" "/opt/google/chrome-canary/chrome" ;;
    esac
  done
fi

# Python validates the schema and computes/writes the exact transform. It never invents
# is_glic_eligible, and uses a same-directory temporary file plus os.replace.
run_json() {
  python3 - "$1" "$2" "$3" <<'PY'
import copy, json, os, sys, tempfile
path, mode, disable = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
def reject_constant(value):
    raise ValueError("不允许非标准 JSON 数值: " + value)
with open(path, "rb") as source_file:
    raw = source_file.read()
    source_mode = os.fstat(source_file.fileno()).st_mode
data = json.loads(raw.decode("utf-8"), parse_constant=reject_constant)
if not isinstance(data, dict):
    raise ValueError("Local State 根节点必须是 JSON 对象")
if "browser" in data and not isinstance(data["browser"], dict):
    raise ValueError("Local State 的 browser 必须是对象")

def recurse(value):
    if isinstance(value, dict):
        for key in list(value):
            if key == "is_glic_eligible":
                value[key] = True
            else:
                recurse(value[key])
    elif isinstance(value, list):
        for item in value:
            recurse(item)

new = copy.deepcopy(data)
recurse(new)
new["variations_country"] = "us"
last_path = os.path.join(os.path.dirname(path), "Last Version")
if isinstance(new.get("variations_permanent_consistency_country"), list) and len(new["variations_permanent_consistency_country"]) >= 2 and os.path.isfile(last_path):
    with open(last_path, "r", encoding="utf-8") as f:
        version = f.read().strip()
    if version:
        new["variations_permanent_consistency_country"][0] = version
        new["variations_permanent_consistency_country"][1] = "us"
if disable:
    browser = new.setdefault("browser", {})
    flags = browser.get("enabled_labs_experiments")
    if flags is None:
        flags = []
    elif not isinstance(flags, list):
        raise ValueError("browser.enabled_labs_experiments 必须是数组")
    names = ("optimization-guide-on-device-model", "prompt-api-for-gemini-nano")
    kept = [x for x in flags if not (isinstance(x, str) and any(x == n or x.startswith(n + "@") for n in names))]
    kept.extend(n + "@2" for n in names)
    browser["enabled_labs_experiments"] = kept
changed = new != data
print("CHANGED=" + ("1" if changed else "0"))
if mode == "write" and changed:
    directory = os.path.dirname(path) or "."
    fd, temp = tempfile.mkstemp(prefix=".local-state-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            json.dump(new, f, ensure_ascii=False, indent=2, allow_nan=False)
            f.write("\n"); f.flush(); os.fsync(f.fileno())
        os.chmod(temp, source_mode)
        # Best-effort lock-free compare-before-swap guard. A tiny POSIX race remains
        # between this byte comparison and os.replace, documented in README.
        with open(path, "rb") as current_file:
            if current_file.read() != raw:
                raise RuntimeError("Local State 在计划后再次变化；已中止以避免覆盖并发更新")
        os.replace(temp, path)
        try:
            dfd = os.open(directory, os.O_RDONLY); os.fsync(dfd); os.close(dfd)
        except OSError:
            pass
    except Exception:
        try: os.unlink(temp)
        except OSError: pass
        raise
PY
}

VALID_TARGETS=(); PLAN_CHANGED=()
validation_failed=0
for i in "${!ROOTS[@]}"; do
  state="${ROOTS[$i]}/Local State"
  if [[ ! -f "$state" ]]; then
    printf '[%s] 跳过: 未找到 %s\n' "${LABELS[$i]}" "$state"
    continue
  fi
  if output=$(run_json "$state" validate "$DISABLE_AI_DOWNLOAD" 2>&1); then
    VALID_TARGETS+=("$i")
    if grep -q '^CHANGED=1$' <<< "$output"; then
      PLAN_CHANGED+=("$i"); printf '[%s] 计划修改: %s\n' "${LABELS[$i]}" "$state"
    else
      printf '[%s] 无需修改: %s\n' "${LABELS[$i]}" "$state"
    fi
  else
    printf '[%s] 验证失败: %s\n%s\n' "${LABELS[$i]}" "$state" "$output" >&2
    validation_failed=1
  fi
done
if ((validation_failed)); then echo "错误: 至少一个 Local State 验证失败；未停止 Chrome，未写入任何文件。" >&2; exit 1; fi

if ((DISABLE_AI_DOWNLOAD)); then
  echo "警告: 禁用 AI 下载会安装 Chrome 策略，并可能显示“由您的组织管理”。"
fi
if ((DRY_RUN)); then
  ((DISABLE_AI_DOWNLOAD)) && echo "[dry-run] 将设置 GenAILocalFoundationalModelSettings=1；不会提权或写入。"
  echo "[dry-run] 未停止、写入或重启 Chrome。"
  exit 0
fi

need_pgrep=0
for idx in "${PLAN_CHANGED[@]}"; do [[ -n "${EXES[$idx]}" ]] && need_pgrep=1; done
if ((need_pgrep)) && ! command -v pgrep >/dev/null 2>&1; then
  echo "错误: 计划修改正常频道配置时需要 pgrep；未停止 Chrome，未写入配置。" >&2
  exit 1
fi

STOPPED_EXES=()
RESTART_DONE=0
restart_stopped() {
  local exe failed=0
  if ((NO_RESTART)); then RESTART_DONE=1; return 0; fi
  for exe in "${STOPPED_EXES[@]}"; do
    if [[ -x "$exe" ]]; then
      if [[ "$OS" == Darwin ]]; then
        "$exe" >/dev/null 2>&1 &
      else
        nohup "$exe" >/dev/null 2>&1 &
      fi
    else
      echo "错误: 无法重启，未找到可执行文件: $exe" >&2
      failed=1
    fi
  done
  RESTART_DONE=1
  return "$failed"
}
cleanup_on_exit() {
  local original_status=$?
  trap - EXIT
  if ((RESTART_DONE == 0 && NO_RESTART == 0 && ${#STOPPED_EXES[@]} > 0)); then
    echo "警告: 脚本提前退出，正在尽力重启已停止的 Chrome。" >&2
    restart_stopped || true
  fi
  exit "$original_status"
}
trap cleanup_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

stop_selected() {
  local idx exe pids pid waited alive still_alive pgrep_status already
  for idx in "${PLAN_CHANGED[@]}"; do
    exe=${EXES[$idx]}; [[ -n "$exe" ]] || continue
    # Match the selected channel's known full executable path, never a bare process name.
    pids=$(pgrep -f -- "^${exe//./\\.}([[:space:]]|$)" 2>&1)
    pgrep_status=$?
    if ((pgrep_status == 1)); then continue; fi
    if ((pgrep_status > 1)); then
      printf '错误: 无法发现 [%s] Chrome 进程 (pgrep=%s): %s\n' "${LABELS[$idx]}" "$pgrep_status" "$pids" >&2
      return 1
    fi
    [[ -n "$pids" ]] || continue
    printf '[%s] 正在请求 Chrome 正常退出...\n' "${LABELS[$idx]}"
    kill -TERM $pids 2>/dev/null || true
    waited=0
    while ((waited < 10)); do
      alive=""; for pid in $pids; do kill -0 "$pid" 2>/dev/null && alive+=" $pid"; done
      [[ -z "$alive" ]] && break
      sleep 1; ((waited++))
    done
    if [[ -n "$alive" ]]; then
      echo "警告: Chrome 未在 10 秒内退出，正在强制停止选定频道。" >&2
      kill -KILL $alive 2>/dev/null || true
      sleep 1
      still_alive=""; for pid in $alive; do kill -0 "$pid" 2>/dev/null && still_alive+=" $pid"; done
      if [[ -n "$still_alive" ]]; then
        echo "错误: 无法停止选定频道的 Chrome；为避免并发覆盖，未写入配置。" >&2
        return 1
      fi
    fi
    # Record for restart only after every matched process has actually exited.
    already=0; for old in "${STOPPED_EXES[@]}"; do [[ "$old" == "$exe" ]] && already=1; done
    ((already)) || STOPPED_EXES+=("$exe")
  done
}
if ((${#PLAN_CHANGED[@]})); then
  stop_selected || exit 1
fi

status=0
for idx in "${PLAN_CHANGED[@]}"; do
  state="${ROOTS[$idx]}/Local State"
  if output=$(run_json "$state" write "$DISABLE_AI_DOWNLOAD" 2>&1); then
    if grep -q '^CHANGED=0$' <<< "$output"; then
      printf '[%s] 关闭 Chrome 后已无需修改: %s\n' "${LABELS[$idx]}" "$state"
    else
      printf '[%s] 已修改（未创建备份）: %s\n' "${LABELS[$idx]}" "$state"
    fi
  else
    printf '[%s] 写入失败: %s\n%s\n' "${LABELS[$idx]}" "$state" "$output" >&2
    status=2
  fi
done

if ((DISABLE_AI_DOWNLOAD)); then
  if [[ "$OS" == Darwin ]]; then
    if defaults write com.google.Chrome GenAILocalFoundationalModelSettings -int 1; then
      echo "已设置 macOS com.google.Chrome 策略值。"
    else echo "错误: macOS 策略写入失败。" >&2; status=2; fi
  else
    policy_dir=/etc/opt/chrome/policies/managed
    if [[ -n "${BRING_BACK_GEMINI_POLICY_DIR:-}" ]]; then
      if [[ "${BRING_BACK_GEMINI_TEST_MODE:-}" != 1 ]]; then
        echo "错误: 策略路径覆盖仅允许在 BRING_BACK_GEMINI_TEST_MODE=1 时使用。" >&2
        status=2
        policy_dir=""
      else
        policy_dir=$BRING_BACK_GEMINI_POLICY_DIR
        echo "[test-mode] 使用隔离策略目录: $policy_dir"
      fi
    fi
    if [[ -z "$policy_dir" ]]; then
      policy_file=""
      policy_tmp=""
    else
      policy_file=$policy_dir/bring-back-gemini.json
      policy_tmp=$(mktemp "${TMPDIR:-/tmp}/bring-back-gemini-policy.XXXXXX") || { echo "错误: 无法创建策略临时文件。" >&2; status=2; policy_tmp=""; }
    fi
    if [[ -n "$policy_tmp" ]]; then
      if python3 - "$policy_file" "$policy_tmp" <<'PY'
import json, os, sys
src, dst = sys.argv[1:]
def reject_constant(value): raise ValueError("不允许非标准 JSON 数值: " + value)
data = {}
if os.path.exists(src):
    with open(src, encoding="utf-8") as f: data = json.load(f, parse_constant=reject_constant)
    if not isinstance(data, dict): raise ValueError("策略 JSON 根节点必须是对象")
data["GenAILocalFoundationalModelSettings"] = 1
with open(dst, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2, allow_nan=False); f.write("\n")
PY
      then
        # Only same-directory policy staging and installation are elevated. The final mv
        # is an atomic rename on the policy filesystem; the whole script never runs as root.
        policy_stage="$policy_dir/.bring-back-gemini.$$.tmp"
        if sudo mkdir -p "$policy_dir" &&
           sudo install -m 0644 "$policy_tmp" "$policy_stage" &&
           sudo mv -f "$policy_stage" "$policy_file"; then
          echo "已原子合并 Linux 策略: $policy_file"
        else
          sudo rm -f "$policy_stage" >/dev/null 2>&1 || true
          echo "错误: Linux 策略安装失败。" >&2; status=2
        fi
      else echo "错误: 现有专用策略文件无效，未覆盖。" >&2; status=2; fi
      rm -f "$policy_tmp"
    fi
  fi
fi

if ((NO_RESTART == 0)); then
  restart_stopped || status=2
else
  RESTART_DONE=1
  ((${#STOPPED_EXES[@]})) && echo "已按 --no-restart 要求保持 Chrome 关闭。"
fi

if ((status)); then echo "部分操作未完成；请查看以上错误。" >&2; else echo "完成。请在 chrome://policy 和 Chrome 界面中验证结果。"; fi
exit "$status"
