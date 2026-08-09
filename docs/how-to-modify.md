# 如何安全修改

返回 [[index]]。

1. 先阅读 [[code-map]] 和 [[diagrams]]；两平台的行为契约应保持一致。
2. JSON 新变换必须先在内存计划阶段完成，不能在全量验证前产生副作用。
3. 保持 `is_glic_eligible` 精确大小写匹配；不得在缺失时创建。
4. 不得把 dry-run 接到进程、写文件、注册表、`defaults` 或 `sudo` 路径。
5. Local State 实写必须先产生唯一备份，再从同目录临时文件原子替换。
6. 进程匹配只能使用选中频道的已知规范完整路径；自定义目录非 dry-run 时必须由用户先关闭 Chrome。
7. 新增策略必须明确选择，且 Linux 只能提权同目录策略暂存/安装步骤。
8. PowerShell JSON 深度上限为 80；提高它必须同时证明 `ConvertTo-Json -Depth 100` 不会截断。不得放宽非有限数值和 `2^53-1` 整数范围保护而无跨 5.1/7 的字节级证明。
9. 停止 Chrome 后必须重新读取和变换 Local State，并在提交前比较源哈希/字节，不得写入停止前缓存的计划对象。
10. Windows 备份必须由 `File.Replace` 的 backup 参数生成；POSIX 比较后替换仍有微小无锁竞态，不能描述为严格 CAS。
11. Linux 策略路径覆盖必须同时受测试模式变量保护；测试只能指向临时目录。
12. 修改任一主脚本后必须重新生成 `checksums.sha256`；启动器必须从同一不可变提交下载清单和主脚本。
13. `run.sh` / `run.ps1` 的默认仓库、菜单和参数透传应保持一致；远程下载测试只能使用本地 HTTP fixture。

验证：

```bash
bash -n bring-back-gemini.sh
bash -n run.sh
python -m unittest discover -s tests -v
```

PowerShell 可用时还要运行解析器检查，并分别查看 `-Help` 与 `--help`。测试必须始终传自定义用户目录；任何需要策略的测试都应 dry-run 或隔离/替代策略命令，绝不能触及真实 Chrome 配置、策略或进程。用户行为和限制见 [[../README|README]]。
