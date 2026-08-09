# 代码地图

返回 [[index]]。

## [[../run.sh]] / [[../run.ps1]]

- 解析 `marble810/bring-back-gemini@main` 的提交 SHA。
- 从不可变提交下载 `checksums.sha256` 与对应平台主脚本。
- 校验 SHA-256，随后显示安全菜单；有参数时原样转交主脚本。
- 被 README 的一条命令调用；调用对应的 `bring-back-gemini.*`。

## [[../bring-back-gemini.sh]]

- `usage` / 参数循环：CLI 与退出码。
- 频道映射：Stable/Beta/Dev/Canary 用户目录及已知可执行路径。
- `run_json`：嵌入 Python 的验证、递归变换、备份和原子替换。
- `stop_selected`：按完整路径正常退出、限时等待和强停。
- 末段：平台策略安装及可选重启。

## [[../bring-back-gemini.ps1]]

- `param` / `Show-Help`：兼容 Windows PowerShell 5.1 的参数面。
- `ConvertTo-OrdinalJsonTree` / `Get-ExactJsonValue`：大小写精确的结构键访问。
- `Assert-SafeJsonNumbers` / `Convert-LocalState`：数值、80 层限制、递归变换与源哈希快照。
- `$changedPlans`：验证完成后的进程处理；写入循环会重新读取并在提交前校验哈希。
- `File.Replace`：同卷原子替换并直接生成精确的被替换文件备份；注册表段按管理员身份决定 Auto 范围。
- `Restart-CapturedChrome` / `finally`：所有退出路径统一尽力重启实际捕获的标准候选路径。

## [[../checksums.sha256]]

记录两份主脚本的发布哈希。修改主脚本后必须重新生成，否则远程启动器会拒绝运行。

## [[../tests/test_scripts.py]]

黑盒覆盖递归、国家字段、flag 保留/规范化、幂等、备份、根/深度/schema 异常与 dry-run。策略测试通过 [[../tests/Invoke-WithMockPolicy.ps1]] 隔离注册表。参见 [[diagrams]]。
