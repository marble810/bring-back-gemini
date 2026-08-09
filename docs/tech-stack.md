# 技术栈

返回 [[index]]。

| 范围 | 技术 | 原因 |
|---|---|---|
| 远程启动 | GitHub Raw、HTTPS | 使用启动器内置的发布提交 SHA 从该提交下载主脚本 |
| macOS/Linux | Bash、curl + Python 3 标准库 | Shell 负责平台操作，Python 正确处理递归 JSON 与原子替换 |
| Windows | PowerShell 5.1/7 + .NET | 原生下载、JSON、进程、注册表与文件 API |
| 测试 | Python `unittest` | 黑盒调用脚本，fixture 全在临时目录 |
| 文档 | Markdown、WikiLinks、Mermaid | 轻量、可导航 |

无第三方运行时包。Linux 仅在安装可选策略时调用 `sudo`。PowerShell 用 `ConvertTo-OrdinalJsonTree` 保持键名大小写精确，并用 `ConvertTo-Json -Depth 100` 写出。详见 [[how-to-modify]]。
