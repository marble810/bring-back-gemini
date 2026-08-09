# Bring Back Gemini

用脚本安全地调整 Google Chrome `Local State`，尝试恢复 **Ask Gemini / Glic** 的客户端资格信息。无需重装 Chrome，也不会删除或重建用户配置文件。

> **不保证功能一定出现。** Ask Gemini 还取决于 Chrome 版本、Google 登录账号、服务端灰度、语言/地区以及企业策略。脚本只修改明确列出的本地字段。

## 一条命令运行

与 MAS 的启动方式类似，下面的命令只负责从本仓库下载启动器；启动器内置经过发布验证的不可变主脚本提交 SHA，从该提交下载主脚本并核对 `checksums.sha256`，随后显示操作菜单。默认菜单项是无副作用的 Dry-run。

### Windows

```powershell
irm https://raw.githubusercontent.com/marble810/bring-back-gemini/refs/heads/main/run.ps1 | iex
```

### macOS / Linux

需要 `curl` 与 `python3`（部分全新 macOS 需要先安装 Python 3）：

```bash
curl -fsSL https://raw.githubusercontent.com/marble810/bring-back-gemini/refs/heads/main/run.sh | bash
```

执行前请核对域名和仓库名。远程执行始终以 HTTPS 下载到的启动器为信任起点；SHA-256 校验用于确认后续主脚本与同一不可变提交中的清单一致，不能替代对启动器本身和仓库权限的信任。启动器不依赖 GitHub API，因此不会消耗未认证 API 配额；发布新主脚本时需要同步更新启动器内置的提交 SHA。

参数也可以直接透传：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/marble810/bring-back-gemini/refs/heads/main/run.ps1))) -ForwardArguments @('-DryRun')
```

```bash
curl -fsSL https://raw.githubusercontent.com/marble810/bring-back-gemini/refs/heads/main/run.sh | bash -s -- --dry-run
```

## 本地运行

先完全保存工作；脚本仅在确有配置变化时才会尝试关闭对应 Chrome，并在之后重启（可禁用重启）。建议先 dry-run。

### macOS / Linux

依赖：`bash`、`python3`。Linux 的可选策略安装还需要 `sudo`。

```bash
chmod +x bring-back-gemini.sh
./bring-back-gemini.sh --dry-run
./bring-back-gemini.sh --channel stable
./bring-back-gemini.sh --channel beta,dev --no-restart
./bring-back-gemini.sh --user-data-dir /tmp/chrome-fixture --dry-run
```

### Windows

支持 Windows PowerShell 5.1 与 PowerShell 7：

```powershell
.\bring-back-gemini.ps1 -DryRun
.\bring-back-gemini.ps1 -Channel stable
.\bring-back-gemini.ps1 -Channel beta,dev -NoRestart
.\bring-back-gemini.ps1 -UserDataDir C:\Temp\chrome-fixture -DryRun
```

默认检测 Stable、Beta、Dev、Canary；`--channel` / `-Channel` 可缩小范围。自定义目录只处理该目录，不匹配或停止任何 Chrome 可执行文件；**对自定义目录执行非 dry-run 前，必须自行确认使用它的 Chrome 已完全关闭**。完整参数见 `--help` / `-Help`。

## 脚本做什么

对每个存在的 `Local State`：

1. 先验证所有选中文件是安全 JSON 对象；任一验证失败则完全不停止 Chrome、不写文件。
2. 递归地把**已有、大小写完全匹配**的 `is_glic_eligible` 改为布尔值 `true`，不会凭空创建该键。
3. 把顶层 `variations_country` 设为 `us`。
4. 若 `variations_permanent_consistency_country` 是至少两项的数组，且同目录有 `Last Version`，则把前两项设为去除首尾空白的版本号和 `us`。缺少版本文件不妨碍其他修改。
5. 实际写入前在原文件旁创建唯一的 `Local State.backup-时间戳`，再用同目录临时文件原子替换；尽量保留文件权限与无关 JSON。

Dry-run 绝不停止、写入、提权或重启。自定义目录适合测试。正常频道仅按内置的规范完整可执行路径匹配进程，先请求正常退出并限时等待，超时才警告并强制停止；不会按裸进程名任意杀进程。Windows 会匹配每个频道在 Program Files、Program Files (x86) 和用户目录中的全部标准候选路径，并只重启实际捕获的路径。非标准安装位置、符号链接或包装器路径仍可能无法匹配，此时必须先手动关闭 Chrome。PowerShell 对 JSON 采用明确的保守嵌套上限 **80 层**（输出仍使用 `ConvertTo-Json -Depth 100`），超过上限会在停止或写入前拒绝。

### 可选：禁用本地 AI 下载

此项**默认关闭**：

```bash
./bring-back-gemini.sh --disable-ai-download
```

```powershell
.\bring-back-gemini.ps1 -DisableAIDownload -PolicyScope Auto
```

启用后会规范化 `optimization-guide-on-device-model@2` 与 `prompt-api-for-gemini-nano@2`，保留其他 flag（包括非字符串项），并设置官方整数策略 [`GenAILocalFoundationalModelSettings=1`](https://chromeenterprise.google/policies/#GenAILocalFoundationalModelSettings)：

- Windows：`HKCU` 或 `HKLM\SOFTWARE\Policies\Google\Chrome`；`Auto` 严格按当前是否管理员选择 User/Machine。
- macOS：`defaults` 域 `com.google.Chrome`。
- Linux：合并专用文件 `/etc/opt/chrome/policies/managed/bring-back-gemini.json`；仅同目录暂存和 `mkdir/install/mv` 策略步骤使用 `sudo`，最后以同文件系统重命名替换，不会以 root 重跑整个脚本。

**这会让 Chrome 可能显示“由您的组织管理”。** 它禁用共享的本地基础模型，不等同于禁用服务端 Ask Gemini，也不保证删除已经下载的模型。

## 安全、备份与限制

- Chrome 运行时可能覆盖 `Local State`，因此脚本只在计划变更时处理选中频道进程。
- 每次实际 Local State 变更都有独立备份；无变化不会制造备份。Windows 的备份由原子 `File.Replace` 直接保存被替换的精确文件；macOS/Linux 备份来自用于计算变换的原始字节快照。恢复时先完全退出 Chrome，再复制备份覆盖原文件。
- 写入前会再次比较源文件字节/哈希，发现并发变化就删除本次临时产物并拒绝覆盖。检查与原子替换之间仍有极小的无锁竞态窗口，因此不是严格 CAS；Windows 的 `File.Replace` 精确备份仍保留实际被替换字节，而 POSIX 备份是检查前快照，极晚到达的并发写入无法由该备份捕获。
- JSON 根不是对象、`browser` 类型异常、或模型 flag 列表类型异常时拒绝写入，避免破坏未知结构。
- PowerShell 递归拒绝 NaN、正负 Infinity、溢出成 Infinity 的数值；为避免 Windows PowerShell 5.1 静默改写，还保守拒绝绝对值超过 `9007199254740991` 的整数或整数形式浮点数。即使某些超大整数在特定运行时可表示，也需要先手工处理。
- 修改 Chrome 内部状态并非 Google 支持的公开配置接口；Chrome 升级可能改变或忽略这些字段。
- 请在完成后查看 `chrome://policy`、`chrome://version` 并验证目标账号。退出码：`0` 完成，`1` 完全失败，`2` 部分完成，`64` 脚本检测到的用法错误。PowerShell 参数绑定发生在脚本代码之前，因此未知参数或 `ValidateSet` 失败可能由 PowerShell 自身返回 `1`。

## 与 `go-chrome-ai` 的区别

本项目是独立的脚本式重实现，不复制或修改参考仓库。它保留核心 Local State 变换，但更保守：不重装 Chrome、不重建配置文件；先全量验证；逐次唯一备份和原子替换；dry-run 无副作用；只按选中频道的已知路径停止进程；并把会产生托管提示的“禁用 AI 下载”从参考实现的侵入式默认开启改成**明确选择、默认关闭**。macOS/Linux 与 Windows 分别使用平台原生脚本，便于审阅，无需 Go 构建产物。

## 开发与文档

修改任一主脚本后，必须同步更新清单：

```bash
# Linux
sha256sum bring-back-gemini.sh bring-back-gemini.ps1 > checksums.sha256

# macOS
shasum -a 256 bring-back-gemini.sh bring-back-gemini.ps1 > checksums.sha256
```

完整验证：

```bash
python -m unittest discover -s tests -v
bash -n bring-back-gemini.sh
bash -n run.sh
pwsh -NoProfile -Command '$e=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "bring-back-gemini.ps1"),[ref]$null,[ref]$e) | Out-Null; if ($e.Count) { $e; exit 1 }'
```

测试只使用临时自定义目录；不会操作真实 Chrome 配置、进程或策略。Linux 策略测试路径覆盖只有同时设置 `BRING_BACK_GEMINI_TEST_MODE=1` 与 `BRING_BACK_GEMINI_POLICY_DIR` 才会启用，生产使用不应设置它们。架构入口见 [[docs/index]]。
