# 项目结构

返回 [[index]]。

```text
run.sh / run.ps1          # 一条命令入口：锁定提交并下载主脚本
bring-back-gemini.sh      # macOS/Linux 主实现
bring-back-gemini.ps1     # Windows 主实现
tests/test_scripts.py     # 黑盒临时目录测试
tests/Invoke-WithMockPolicy.ps1 # 隔离注册表策略的测试助手
docs/                     # Project Navigator 文档
README.md                 # 中文用户文档
LICENSE                   # MIT 许可证
```

两份主脚本各自包含平台检测、频道目录映射、JSON 计划、进程处理、原子写入和可选策略写入。两个 `run.*` 启动器把分支解析为不可变提交、从该提交下载主脚本后显示菜单或透传参数。测试通过命令行调用生产脚本，而不复制变换逻辑。参见 [[code-map]] 与 [[diagrams]]。
