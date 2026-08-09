#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardArguments
)

$ErrorActionPreference = 'Stop'
$repo = if ($env:BBG_REPO) { $env:BBG_REPO } else { 'marble810/bring-back-gemini' }
$payloadCommit = if ($env:BBG_PAYLOAD_COMMIT) { $env:BBG_PAYLOAD_COMMIT } else { '891bf25722913d29690f6691f940f235d5bfec2e' }
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
    $manifestPath = Join-Path $tempDir 'checksums.sha256'
    $payloadPath = Join-Path $tempDir 'bring-back-gemini.ps1'
    Invoke-WebRequest -Uri "$base/checksums.sha256" -Headers $headers -UseBasicParsing -OutFile $manifestPath
    Invoke-WebRequest -Uri "$base/bring-back-gemini.ps1" -Headers $headers -UseBasicParsing -OutFile $payloadPath

    $expected = $null
    foreach ($line in [IO.File]::ReadAllLines($manifestPath)) {
        if ($line -match '^([0-9A-Fa-f]{64})\s+\*?bring-back-gemini\.ps1\s*$') {
            $expected = $Matches[1].ToLowerInvariant()
            break
        }
    }
    if (-not $expected) { throw '校验清单缺少有效的 bring-back-gemini.ps1 哈希' }
    $actual = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $expected) { throw '主脚本 SHA-256 校验失败' }
    Write-Host "已验证提交 $payloadCommit，SHA-256 匹配。"

    $payloadArguments = @()
    if ($ForwardArguments -and $ForwardArguments.Count -gt 0) {
        $payloadArguments = @($ForwardArguments)
    } else {
        Write-Host ''
        Write-Host '请选择操作：'
        Write-Host '  1) Dry-run：只预览，不修改（推荐）'
        Write-Host '  2) 应用到 Chrome Stable'
        Write-Host '  3) 应用到所有检测到的 Chrome 频道'
        Write-Host '  4) 应用全部频道，并禁用本地 AI 模型下载'
        Write-Host '  0) 退出'
        try { $choice = Read-Host '请输入 [1]' } catch { $choice = '' }
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
        switch ($choice) {
            '1' { $payloadArguments = @('-DryRun') }
            '2' { $payloadArguments = @('-Channel', 'stable') }
            '3' { $payloadArguments = @() }
            '4' { $payloadArguments = @('-DisableAIDownload') }
            '0' { Write-Host '已取消。'; return }
            default { throw "无效选择: $choice" }
        }
    }

    $hostExe = (Get-Process -Id $PID).Path
    if (-not $hostExe) { throw '无法确定当前 PowerShell 可执行文件' }
    & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $payloadPath @payloadArguments
    if ($LASTEXITCODE -ne 0) { throw "主脚本退出码: $LASTEXITCODE" }
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
