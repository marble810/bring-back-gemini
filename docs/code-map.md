# 代码地图

返回 [[index]]。

## [[../run.sh]] / [[../run.ps1]]

- 内置经过发布验证的主脚本提交 SHA，不依赖 GitHub API。
- 从该不可变提交下载对应平台主脚本。
- 显示安全菜单；有参数时原样转交主脚本。
- 被 README 的一条命令调用；调用对应的 `bring-back-gemini.*`。

## [[../bring-back-gemini.sh]]

- `usage` / 参数循环：CLI 与退出码。
- 频道映射：Stable/Beta/Dev/Canary 用户目录及已知可执行路径。
- `run_json`：嵌入 Python 的验证、递归变换和无备份原子替换。
- `stop_selected`：按完整路径正常退出、限时等待和强停。
- 末段：平台策略安装及可选重启。

## [[../bring-back-gemini.ps1]]

- `param` / `Show-Help`：兼容 Windows PowerShell 5.1 的参数面。
- `ConvertTo-OrdinalJsonTree`：大小写精确的结构键访问。
- `Convert-LocalState`：解析、递归变换，并保留源字节快照。
- `$changedPlans`：验证完成后的进程处理；写入循环会重新读取，并在提交前做字节比对。
- `MoveFileExW`：同卷覆盖重命名且不保留备份；注册表段按管理员身份决定 Auto 范围。
- `Restart-CapturedChrome` / `finally`：所有退出路径统一尽力重启实际捕获的标准候选路径。

## [[../tests/test_scripts.py]]

黑盒覆盖递归、国家字段、flag 保留/规范化、幂等、无备份写入、根/schema 异常与现状检查。策略测试通过 [[../tests/Invoke-WithMockPolicy.ps1]] 隔离注册表。参见 [[diagrams]]。
