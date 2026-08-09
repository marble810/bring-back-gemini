# 技术栈

返回 [[index]]。

| 范围 | 技术 | 原因 |
|---|---|---|
| 远程启动 | GitHub Raw、HTTPS、SHA-256 | 使用启动器内置的发布提交 SHA，并校验同提交中的主脚本 |
| macOS/Linux | Bash、curl + Python 3 标准库 | Shell 负责平台操作，Python 正确处理递归 JSON 与原子替换 |
| Windows | PowerShell 5.1/7 + .NET | 原生下载、哈希、JSON、进程、注册表与文件 API |
| 测试 | Python `unittest` | 黑盒调用脚本，fixture 全在临时目录 |
| 文档 | Markdown、WikiLinks、Mermaid | 轻量、可导航 |

无第三方运行时包。Linux 仅在安装可选策略时调用 `sudo`。PowerShell 为保证 `ConvertTo-Json -Depth 100` 不截断，拒绝超过 80 层的 JSON；还拒绝非有限数值和绝对值超过 `2^53-1` 的整数形式数值，避免 5.1 序列化损失。详见 [[how-to-modify]]。
