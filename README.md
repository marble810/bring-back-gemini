<h1 align="center">BRING-BACK-GEMINI - 还我Gemini按钮</h1>

<p align="center">
  <img src="design/hero.png" alt="Bring Back Gemini - 还我Gemini按钮" />
</p>

<p align="center">将Chrome上消失的"问问 Gemini"按钮找回来，仅需一条指令</p>

# 快速开始

**Windows（PowerShell 5.1 / 7）**

```powershell
irm https://raw.githubusercontent.com/marble810/bring-back-gemini/refs/heads/main/run.ps1 | iex
```

**macOS / Linux（需要 `curl` 与 `python3`）**

```bash
curl -fsSL https://raw.githubusercontent.com/marble810/bring-back-gemini/refs/heads/main/run.sh | bash
```

## 前言

> [!TIP]
> **Q. 我的"问问 Gemini"按钮为什么消失了？**
>
> 它没坏，只是按你的 IP 判了个地区。Chrome 在安装/更新时会根据当前 IP 判定地区并把结果写本地；一旦被判为"不提供服务的地区"，按钮就被隐藏。

> [!TIP]
> **Q. 怎么把它找回来？先完全退出 Chrome，再改一个文件。**
>
> 启用 Chrome 的 Glic / 「Ask Gemini」，手动改用户数据目录里的 `Local State`，重点动这些值：
>
> ```json
> {
>   "browser": {
>     "enabled_labs_experiments": [
>       "glic@1"
>     ]
>   },
>
>   "variations_country": "us",
>   "variations_permanent_overridden_country": "us",
>   "variations_permanent_consistency_country": [
>     "当前 Chrome 版本",
>     "us"
>   ]
> }
> ```
>
> 真正关键的是 **`glic@1`**（强制开启 Glic Feature）和 **`variations_permanent_overridden_country = "us"`**（让地区过滤按美国判断）；`variations_country` 和 `variations_permanent_consistency_country` 建议一并设为美国。`is_glic_eligible = true` 可以保留，但它更像资格状态缓存，不是核心开关。
>
> 改完重启 Chrome，到 `chrome://glic/internals` 确认 `Enabled by Chrome Flags` 和 `Passed country filter` 都变成 ✅。

> [!TIP]
> **Q. 有没有更方便的方法？**
>
> **Bring Back Gemini。** 一条指令把上面那套手动改 `Local State` 的流程自动化——无需重装 Chrome，不删除或重建用户配置文件，顺手把校验、原子替换、按频道关闭重启这些容易出错的环节都包了。

> [!WARNING]
> **这工具不保证按钮一定能回来。**
>
> Ask Gemini 能否出现还取决于 Chrome 版本、登录的 Google 账号、服务端灰度、语言/地区以及企业策略。脚本只修改明确列出的本地字段——不碰概率、不碰服务端、不碰 Google 账号资格。
>
> **先做现状检查，看清当前配置和将要做的修改，再决定是否应用。**

## 使用

### 一条命令运行

> 不想读文档？直接跑下面这条。默认先做现状检查（只查看，不修改任何文件），确认后才应用。

下面的命令只负责从本仓库下载启动器；启动器内置经过发布验证的不可变主脚本提交 SHA，从该提交下载主脚本，随后先做现状检查（不修改任何文件），再确认是否应用。

#### Windows

```powershell
irm https://raw.githubusercontent.com/marble810/bring-back-gemini/refs/heads/main/run.ps1 | iex
```

#### macOS / Linux

需要 `curl` 与 `python3`（部分全新 macOS 需要先安装 Python 3）：

```bash
curl -fsSL https://raw.githubusercontent.com/marble810/bring-back-gemini/refs/heads/main/run.sh | bash
```

执行前请核对域名和仓库名。远程执行始终以 HTTPS 下载到的启动器为信任起点；启动器从内置的不可变提交 SHA 下载主脚本，不能替代对启动器本身和仓库权限的信任。启动器不依赖 GitHub API，因此不会消耗未认证 API 配额；发布新主脚本时需要同步更新启动器内置的提交 SHA。

参数也可以直接透传：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/marble810/bring-back-gemini/refs/heads/main/run.ps1))) -ForwardArguments @('-Check')
```

```bash
curl -fsSL https://raw.githubusercontent.com/marble810/bring-back-gemini/refs/heads/main/run.sh | bash -s -- --check
```

### 本地运行

先完全保存工作；脚本仅在确有配置变化时才会尝试关闭对应 Chrome，并在之后重启（可禁用重启）。建议先做现状检查。

#### macOS / Linux

依赖：`bash`、`python3`。Linux 的可选策略安装还需要 `sudo`。

```bash
chmod +x bring-back-gemini.sh
./bring-back-gemini.sh --check
./bring-back-gemini.sh --channel stable
./bring-back-gemini.sh --channel beta,dev --no-restart
./bring-back-gemini.sh --user-data-dir /tmp/chrome-fixture --check
```

#### Windows

支持 Windows PowerShell 5.1 与 PowerShell 7：

```powershell
.\bring-back-gemini.ps1 -Check
.\bring-back-gemini.ps1 -Channel stable
.\bring-back-gemini.ps1 -Channel beta,dev -NoRestart
.\bring-back-gemini.ps1 -UserDataDir C:\Temp\chrome-fixture -Check
```

默认检测 Stable、Beta、Dev、Canary；`--channel` / `-Channel` 可缩小范围。自定义目录只处理该目录，不匹配或停止任何 Chrome 可执行文件；**对自定义目录执行正式修改前，必须自行确认使用它的 Chrome 已完全关闭**。完整参数见 `--help` / `-Help`。

### 脚本做什么

对每个存在的 `Local State`：

1. 先验证所有选中文件是安全 JSON 对象；任一验证失败则完全不停止 Chrome、不写文件。
2. 递归地把**已有、大小写完全匹配**的 `is_glic_eligible` 改为布尔值 `true`，不会凭空创建该键。
3. 把顶层 `variations_country` 设为 `us`。
4. 把顶层 `variations_permanent_overridden_country` 设为 `us`——这是 Chromium 官方留给测试/开发的 permanent country override，优先级高于第 5 项的 consistency cache。
5. 若 `variations_permanent_consistency_country` 是至少两项的数组，且同目录有 `Last Version`，则把前两项设为去除首尾空白的版本号和 `us`。缺少版本文件不妨碍其他修改。
6. 始终把 `browser.enabled_labs_experiments` 规范化为包含 `glic@1`（即 `chrome://flags/#glic → Enabled` 的持久化等价物）：移除任何 `glic`、`glic@0`、`glic@1`、`glic@2` 旧值后加入 `glic@1`，其余 flag（含非字符串项）原样保留。
7. 使用同目录临时文件原子替换 `Local State`，尽量保留文件权限与无关 JSON；按要求不创建备份。

现状检查绝不停止、写入、提权或重启。自定义目录适合测试。正常频道仅按内置的规范完整可执行路径匹配进程；匹配到 Chrome 在运行时，脚本会**先询问是否关闭**（回答 `n`/`no` 则取消，不停止、不写入；非交互环境自动继续），然后请求正常退出并限时等待，超时才警告并强制停止；不会按裸进程名任意杀进程。Windows 会匹配每个频道在 Program Files、Program Files (x86) 和用户目录中的全部标准候选路径，并只重启实际捕获的路径。非标准安装位置、符号链接或包装器路径仍可能无法匹配，此时必须先手动关闭 Chrome。

### 可选：禁用本地 AI 下载

此项**默认关闭**：

```bash
./bring-back-gemini.sh --disable-ai-download
```

```powershell
.\bring-back-gemini.ps1 -DisableAIDownload -PolicyScope Auto
```

启用后会在上述 `glic@1` 规范化之外，再把 `optimization-guide-on-device-model@2` 与 `prompt-api-for-gemini-nano@2` 规范化，保留其他 flag（包括非字符串项），并设置官方整数策略 [`GenAILocalFoundationalModelSettings=1`](https://chromeenterprise.google/policies/#GenAILocalFoundationalModelSettings)：

- Windows：`HKCU` 或 `HKLM\SOFTWARE\Policies\Google\Chrome`；`Auto` 严格按当前是否管理员选择 User/Machine。
- macOS：`defaults` 域 `com.google.Chrome`。
- Linux：合并专用文件 `/etc/opt/chrome/policies/managed/bring-back-gemini.json`；仅同目录暂存和 `mkdir/install/mv` 策略步骤使用 `sudo`，最后以同文件系统重命名替换，不会以 root 重跑整个脚本。

**这会让 Chrome 可能显示"由您的组织管理"。** 它禁用共享的本地基础模型，不等同于禁用服务端 Ask Gemini，也不保证删除已经下载的模型。

### 安全与限制

> [!WARNING]
> **脚本不创建备份。** 真正写入后无法用它还原原文件——先做现状检查，运行前自行复制一份 Chrome 用户数据目录最保险。

- Chrome 运行时可能覆盖 `Local State`，因此脚本只在计划变更时处理选中频道进程。
- **脚本不创建备份。** 实际写入后无法通过本工具自动恢复原文件；请优先运行现状检查，并自行决定是否在运行前复制整个 Chrome 用户数据目录。
- 写入前会再次比较源文件字节，发现并发变化就删除本次临时产物并拒绝覆盖。检查与原子替换之间仍有极小的无锁竞态窗口，因此不是严格 CAS。
- JSON 根不是对象、`browser` 类型异常、或模型 flag 列表类型异常时拒绝写入，避免破坏未知结构。
- 修改 Chrome 内部状态并非 Google 支持的公开配置接口；Chrome 升级可能改变或忽略这些字段。
- 请在完成后查看 `chrome://policy`、`chrome://version` 并验证目标账号。退出码：`0` 完成，`1` 完全失败，`2` 部分完成，`64` 脚本检测到的用法错误。PowerShell 参数绑定发生在脚本代码之前，因此未知参数或 `ValidateSet` 失败可能由 PowerShell 自身返回 `1`。

## 开发

修改任一主脚本后，把两个启动器内置的 `BBG_PAYLOAD_COMMIT` 默认值更新到新提交。

完整验证：

```bash
python -m unittest discover -s tests -v
bash -n bring-back-gemini.sh
bash -n run.sh
pwsh -NoProfile -Command '$e=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "bring-back-gemini.ps1"),[ref]$null,[ref]$e) | Out-Null; if ($e.Count) { $e; exit 1 }'
```

测试只使用临时自定义目录；不会操作真实 Chrome 配置、进程或策略。Linux 策略测试路径覆盖只有同时设置 `BRING_BACK_GEMINI_TEST_MODE=1` 与 `BRING_BACK_GEMINI_POLICY_DIR` 才会启用，生产使用不应设置它们。架构入口见 [[docs/index]]。
