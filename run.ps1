#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardArguments
)

$ErrorActionPreference = 'Stop'
$repo = if ($env:BBG_REPO) { $env:BBG_REPO } else { 'marble810/bring-back-gemini' }
$payloadCommit = if ($env:BBG_PAYLOAD_COMMIT) { $env:BBG_PAYLOAD_COMMIT } else { '54b03a60da24cce2345779ad68644ee0000ca730' }
$rawRoot = if ($env:BBG_RAW_ROOT) { $env:BBG_RAW_ROOT.TrimEnd('/') } else { "https://raw.githubusercontent.com/$repo" }

if ($repo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') {
    throw "BBG_REPO 格式无效: $repo"
}
if ($payloadCommit -notmatch '^[0-9A-Fa-f]{40}$') {
    throw 'BBG_PAYLOAD_COMMIT 必须是 40 位十六进制值'
}

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('bring-back-gemini-run-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tempDir) | Out-Null
try {
    Write-Host "正在下载 $repo@$payloadCommit ..."
    $headers = @{ 'User-Agent' = 'bring-back-gemini-bootstrap' }
    $base = "$rawRoot/$payloadCommit"
    $payloadPath = Join-Path $tempDir 'bring-back-gemini.ps1'
    Invoke-WebRequest -Uri "$base/bring-back-gemini.ps1" -Headers $headers -UseBasicParsing -OutFile $payloadPath
    Write-Host "已下载 $repo@$payloadCommit。"

    $hostExe = (Get-Process -Id $PID).Path
    if (-not $hostExe) { throw '无法确定当前 PowerShell 可执行文件' }

    $payloadArguments = @()
    if ($ForwardArguments -and $ForwardArguments.Count -gt 0) {
        $payloadArguments = @($ForwardArguments)
    } else {
        # 把现状检查的结果直接展示在主菜单上方，不再作为独立选项。
        Write-Host ''
        Write-Host '正在检查 Chrome 现状（只查看，不修改任何文件）…'
        Write-Host ''
        $preview = & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $payloadPath -Check 2>&1
        $previewRc = $LASTEXITCODE
        if ($previewRc -ne 0) {
            # 验证失败等：原样打印预览后退出，不进入菜单、不继续修改。
            $preview | Out-Host
            throw "预览失败，退出码: $previewRc"
        }

        # 解析每个 "[label] status: path" 行，并按公共前缀截断路径。
        $pLines = New-Object System.Collections.Generic.List[object]
        $pPaths = New-Object System.Collections.Generic.List[string]
        foreach ($l in $preview) {
            $line = "$l"
            if ($line -match '^\[([a-z]+)\]\s+(计划修改|无需修改|验证失败):\s+(.*)$') {
                $pLines.Add([pscustomobject]@{ Label = $Matches[1]; Status = $Matches[2]; Path = $Matches[3] })
                $pPaths.Add($Matches[3]) | Out-Null
            } elseif ($line -match '^\[([a-z]+)\]\s+跳过:\s+未找到\s+(.*)$') {
                $pLines.Add([pscustomobject]@{ Label = $Matches[1]; Status = '跳过(未找到)'; Path = $Matches[2] })
                $pPaths.Add($Matches[2]) | Out-Null
            }
        }

        $common = ''
        if ($pPaths.Count -gt 0) {
            $common = $pPaths[0]
            if ($pPaths.Count -gt 1) {
                foreach ($p in $pPaths[1..($pPaths.Count - 1)]) {
                    while ($common -and -not $p.StartsWith($common)) { $common = $common.Substring(0, $common.Length - 1) }
                    if (-not $common) { break }
                }
            }
            # 截到最近的路径分隔符，保留后面的频道目录与文件名。
            $idx = [Math]::Max($common.LastIndexOf('\'), $common.LastIndexOf('/'))
            if ($idx -ge 0) { $common = $common.Substring(0, $idx) } else { $common = '' }
        }
        $hasPresent = $false
        foreach ($e in $pLines) {
            if ($e.Status -ne '跳过(未找到)') { $hasPresent = $true }
            $sp = $e.Path
            if ($common -and $sp.StartsWith("$common\")) { $sp = '…\' + $sp.Substring($common.Length + 1) }
            elseif ($common -and $sp.StartsWith("$common/")) { $sp = '…/' + $sp.Substring($common.Length + 1) }
            Write-Host ('  [{0,-6}] {1}  {2}' -f $e.Label, $e.Status, $sp)
        }

        if (-not $hasPresent) {
            Write-Host ''
            Write-Host '未检测到任何可处理的 Chrome 配置。退出。'
            return
        }

        Write-Host ''
        Write-Host '接下来怎么做？（上方是现状检查结果：只是看了看，什么都没改）'
        Write-Host '  1) 应用到所有检测到的频道          （默认）'
        Write-Host '  2) 仅应用到 Chrome Stable'
        Write-Host '  3) 应用全部频道，并禁用本地 AI 模型下载'
        Write-Host '  0) 退出'
        $choice = ''
        $ok = $false
        for ($try = 0; $try -lt 3; $try++) {
            try { $r = Read-Host '请输入 [1]' } catch { Write-Host '已取消。'; return }
            $r = "$r".Trim()
            if ([string]::IsNullOrWhiteSpace($r)) { $r = '1' }
            if ($r -in '1', '2', '3', '0') { $choice = $r; $ok = $true; break }
            Write-Host "无效选择: $r"
        }
        if (-not $ok) { throw '多次无效输入，已取消' }
        switch ($choice) {
            '1' { $payloadArguments = @() }
            '2' { $payloadArguments = @('-Channel', 'stable') }
            '3' { $payloadArguments = @('-DisableAIDownload') }
            '0' { Write-Host '已取消。'; return }
        }
    }

    & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $payloadPath @payloadArguments
    if ($LASTEXITCODE -ne 0) { throw "主脚本退出码: $LASTEXITCODE" }
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
