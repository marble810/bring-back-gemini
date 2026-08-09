# AGENTS.md — bring-back-gemini 开发约定

## 发布流程:启动器 pin(血泪教训)

`run.sh` / `run.ps1` 内置 `BBG_PAYLOAD_COMMIT` 默认值,从该提交下载主脚本。**修改任一主脚本后必须同步更新两个启动器的 pin。**

1. **SHA 禁止手写或猜测**(曾因手写错 33 位导致线上 404)。只从 `git rev-parse <commit>` 取完整 40 位 SHA。
2. 写入 pin 前核对:
   ```bash
   git rev-parse --verify <pin>^{commit}      # pin 必须是仓库内真实提交
   git cat-file -e <pin>:bring-back-gemini.ps1  # 该提交里必须有两个主脚本
   ```
3. 推送后验证 raw URL 返回 200:
   ```bash
   curl -sI https://raw.githubusercontent.com/marble810/bring-back-gemini/<pin>/bring-back-gemini.ps1
   ```
4. 提交顺序按仓库惯例分两步:先提交主脚本(payload),再提交启动器(pin 同步),如 `chore: pin launchers to ... revision <sha>`。
5. 推送后 raw.githubusercontent.com 有 CDN 传播延迟(`max-age=300`),代理环境(如 Clash fake-IP)可能更久。端到端验证失败时,先判断是"内容未传播"还是"真错误":用 `api.github.com` 查 main 真实 blob,与本地 `git rev-parse <commit>:<file>` 对比。

## 测试防线

- tests 用环境变量覆盖 pin,**测不到默认值**——默认 pin 的错误只能靠 `test_launcher_default_pins_exist_in_repo` 拦住(它用 `git rev-parse` / `git cat-file` 验证启动器默认 pin 是仓库内真实提交且含 payload 文件)。改 pin 时该测试必须保持通过。
- 完整验证(改任何脚本后):
  ```bash
  python -m unittest discover -s tests -v
  bash -n bring-back-gemini.sh && bash -n run.sh
  pwsh -NoProfile -Command '$e=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "bring-back-gemini.ps1"),[ref]$null,[ref]$e) | Out-Null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "run.ps1"),[ref]$null,[ref]$e) | Out-Null; if ($e.Count) { $e; exit 1 }'
  ```

## 命名约定

- "dry-run" 已更名为**现状检查**,旗标为 `--check` / `-Check`,输出前缀 `[现状检查]`。新文案禁止重新引入 dry-run 术语;`--dry-run` / `-DryRun` 已彻底移除,无别名。
