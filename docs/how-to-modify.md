# 如何安全修改

返回 [[index]]。

1. 先阅读 [[code-map]] 和 [[diagrams]]；两平台的行为契约应保持一致。
2. JSON 新变换必须先在内存计划阶段完成，不能在全量验证前产生副作用。
3. 保持 `is_glic_eligible` 精确大小写匹配；不得在缺失时创建。
4. 不得把现状检查接到进程、写文件、注册表、`defaults` 或 `sudo` 路径。
5. Local State 实写必须从同目录临时文件原子替换，并且不得创建或保留备份。
6. 进程匹配只能使用选中频道的已知规范完整路径；自定义目录正式修改时必须由用户先关闭 Chrome。
7. 新增策略必须明确选择，且 Linux 只能提权同目录策略暂存/安装步骤。
8. 停止 Chrome 前必须询问用户确认（交互环境回答 `n`/`no` 则取消且不写入；非交互环境默认继续）。停止 Chrome 后必须重新读取和变换 Local State，并在提交前比较源字节，不得写入停止前缓存的计划对象。
9. Windows 使用 `MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)` 进行无备份同卷替换；POSIX 比较后替换仍有微小无锁竞态，不能描述为严格 CAS。
10. Linux 策略路径覆盖必须同时受测试模式变量保护；测试只能指向临时目录。
11. 修改任一主脚本后，把两个启动器内置的 `BBG_PAYLOAD_COMMIT` 默认值更新到新提交；启动器必须从该不可变提交下载主脚本。
12. `run.sh` / `run.ps1` 的默认仓库、发布提交、菜单和参数透传应保持一致；远程下载测试只能使用本地 HTTP fixture。
13. `variations_permanent_overridden_country` 必须始终写入 `us`；`browser.enabled_labs_experiments` 必须始终规范化为包含 `glic@1`（移除 `glic`/`glic@N` 变体），`-DisableAIDownload` 时再追加两个 Nano `@2` flag。这两个都是 Chrome 已知配置，缺失时允许创建，但 flag 列表类型异常必须拒绝。

验证：

```bash
bash -n bring-back-gemini.sh
bash -n run.sh
python -m unittest discover -s tests -v
```

PowerShell 可用时还要运行解析器检查，并分别查看 `-Help` 与 `--help`。测试必须始终传自定义用户目录；任何需要策略的测试都应走现状检查或隔离/替代策略命令，绝不能触及真实 Chrome 配置、策略或进程。用户行为和限制见 [[../README|README]]。
