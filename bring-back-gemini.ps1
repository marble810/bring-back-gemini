#requires -Version 5.1
[CmdletBinding()]
param(
    [string[]]$Channel = @('all'),
    [string]$UserDataDir,
    [switch]$DryRun,
    [switch]$NoRestart,
    [switch]$DisableAIDownload,
    [ValidateSet('Auto', 'User', 'Machine')]
    [string]$PolicyScope = 'Auto',
    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if (-not ('BringBackGemini.NativeFile' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace BringBackGemini {
    public static class NativeFile {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "MoveFileExW")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool MoveFileEx(
            string existingFileName,
            string newFileName,
            uint flags);
    }
}
'@
}

function Replace-FileWithoutBackup([string]$ReplacementPath, [string]$DestinationPath) {
    # Preserve the destination ACL, then atomically rename the same-volume temp file over it.
    $acl = Get-Acl -LiteralPath $DestinationPath
    Set-Acl -LiteralPath $ReplacementPath -AclObject $acl
    $replaceExistingAndWriteThrough = [uint32]9
    $ok = [BringBackGemini.NativeFile]::MoveFileEx(
        $ReplacementPath, $DestinationPath, $replaceExistingAndWriteThrough)
    if (-not $ok) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw (New-Object ComponentModel.Win32Exception($code))
    }
}

function Show-Help {
@'
用法: .\bring-back-gemini.ps1 [选项]

安全地修改 Google Chrome 的 Local State，以尝试启用 Ask Gemini/Glic。
兼容 Windows PowerShell 5.1 和 PowerShell 7（Windows）。

选项:
  -Channel stable,beta,...  stable、beta、dev、canary 或 all（默认 all）
  -UserDataDir PATH         只处理指定用户数据目录（便于安全测试）
  -DryRun                   仅检查并显示计划；不停止、写入、提权或重启
  -NoRestart                修改后不重启先前运行的 Chrome
  -DisableAIDownload        禁用两个本地 AI 模型 flag 并设置策略（默认关闭）
  -PolicyScope Auto|User|Machine
                            策略注册表范围；Auto 按管理员身份选择 Machine/User
  -Help                     显示帮助

注意: -DisableAIDownload 会设置 GenAILocalFoundationalModelSettings=1，
并可能令 Chrome 显示“由您的组织管理”。
退出码: 0=完成/无需更改，1=失败，2=部分完成，64=用法错误。
'@
}

if ($Help) { Show-Help; exit 0 }
if ($env:OS -ne 'Windows_NT') {
    [Console]::Error.WriteLine('错误: 此 PowerShell 脚本仅支持 Windows。')
    exit 1
}

$channels = New-Object System.Collections.Generic.List[string]
foreach ($item in $Channel) {
    foreach ($part in ($item -split ',')) {
        $name = $part.Trim().ToLowerInvariant()
        if ($name -eq 'all') {
            $channels.Clear()
            @('stable','beta','dev','canary') | ForEach-Object { $channels.Add($_) }
            break
        }
        if (@('stable','beta','dev','canary') -notcontains $name) {
            [Console]::Error.WriteLine("错误: 无效频道: $part")
            Show-Help
            exit 64
        }
        if (-not $channels.Contains($name)) { $channels.Add($name) }
    }
    if ($channels.Count -eq 4 -and $Channel -contains 'all') { break }
}
if ($channels.Count -eq 0) {
    [Console]::Error.WriteLine('错误: 至少选择一个频道。')
    exit 64
}

function Get-ChromeExeCandidates([string[]]$Candidates) {
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in $Candidates) {
        if ($candidate) { $result.Add([IO.Path]::GetFullPath($candidate)) }
    }
    return ,([string[]]$result.ToArray())
}

$targets = New-Object System.Collections.Generic.List[object]
if ($UserDataDir) {
    $targets.Add([pscustomobject]@{ Label='custom'; Root=[IO.Path]::GetFullPath($UserDataDir); Exes=@() })
} else {
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    $pf = [Environment]::GetFolderPath('ProgramFiles')
    $pfx86 = [Environment]::GetFolderPath('ProgramFilesX86')
    foreach ($name in $channels) {
        switch ($name) {
            'stable' {
                $root = Join-Path $local 'Google\Chrome\User Data'
                $exes = Get-ChromeExeCandidates @((Join-Path $pf 'Google\Chrome\Application\chrome.exe'), (Join-Path $pfx86 'Google\Chrome\Application\chrome.exe'), (Join-Path $local 'Google\Chrome\Application\chrome.exe'))
            }
            'beta' {
                $root = Join-Path $local 'Google\Chrome Beta\User Data'
                $exes = Get-ChromeExeCandidates @((Join-Path $pf 'Google\Chrome Beta\Application\chrome.exe'), (Join-Path $pfx86 'Google\Chrome Beta\Application\chrome.exe'), (Join-Path $local 'Google\Chrome Beta\Application\chrome.exe'))
            }
            'dev' {
                $root = Join-Path $local 'Google\Chrome Dev\User Data'
                $exes = Get-ChromeExeCandidates @((Join-Path $pf 'Google\Chrome Dev\Application\chrome.exe'), (Join-Path $pfx86 'Google\Chrome Dev\Application\chrome.exe'), (Join-Path $local 'Google\Chrome Dev\Application\chrome.exe'))
            }
            'canary' {
                $root = Join-Path $local 'Google\Chrome SxS\User Data'
                $exes = Get-ChromeExeCandidates @((Join-Path $local 'Google\Chrome SxS\Application\chrome.exe'))
            }
        }
        $targets.Add([pscustomobject]@{ Label=$name; Root=$root; Exes=$exes })
    }
}

$script:MaxSupportedJsonDepth = 80

function ConvertTo-OrdinalJsonTree($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IList]) {
        $items = New-Object System.Collections.ArrayList
        foreach ($entry in $Value) { [void]$items.Add((ConvertTo-OrdinalJsonTree $entry)) }
        return ,([object[]]$items.ToArray())
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $dictionary = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
        foreach ($property in @($Value.PSObject.Properties)) {
            $dictionary.Add($property.Name, (ConvertTo-OrdinalJsonTree $property.Value))
        }
        return $dictionary
    }
    return $Value
}

function Test-JsonObject($Value) {
    return ($null -ne $Value -and $Value -is [System.Collections.IDictionary])
}

function Get-ExactJsonValue($Object, [string]$Name) {
    if ($Object -is [System.Collections.IDictionary] -and $Object.ContainsKey($Name)) {
        return [pscustomobject]@{ Found=$true; Value=$Object[$Name] }
    }
    return [pscustomobject]@{ Found=$false; Value=$null }
}

function Get-JsonNestingDepth($Value) {
    if ($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsPrimitive) { return 0 }
    $maximum = 0
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys)) {
            $child = Get-JsonNestingDepth $Value[$key]
            if ($child -gt $maximum) { $maximum = $child }
        }
        return (1 + $maximum)
    }
    if ($Value -is [System.Collections.IList]) {
        foreach ($entry in $Value) {
            $child = Get-JsonNestingDepth $entry
            if ($child -gt $maximum) { $maximum = $child }
        }
        return (1 + $maximum)
    }
    return 0
}

function Assert-SafeJsonNumbers($Value) {
    if ($null -eq $Value) { return }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys)) { Assert-SafeJsonNumbers $Value[$key] }
        return
    }
    if ($Value -is [System.Collections.IList]) {
        foreach ($entry in $Value) { Assert-SafeJsonNumbers $entry }
        return
    }
    $typeCode = [Type]::GetTypeCode($Value.GetType())
    if ($typeCode -eq [TypeCode]::Single -or $typeCode -eq [TypeCode]::Double) {
        $number = [double]$Value
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
            throw 'Local State 包含 NaN 或 Infinity 等非有限数值'
        }
        if ([Math]::Truncate($number) -eq $number -and [Math]::Abs($number) -gt 9007199254740991.0) {
            throw 'Local State 包含超出可互操作精确整数范围的浮点整数'
        }
        return
    }
    if ($typeCode -in @([TypeCode]::Int64, [TypeCode]::UInt64, [TypeCode]::Decimal)) {
        $decimal = [decimal]$Value
        if ([decimal]::Truncate($decimal) -eq $decimal -and [Math]::Abs($decimal) -gt [decimal]9007199254740991) {
            throw 'Local State 包含超出可互操作精确整数范围的整数'
        }
    }
}

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-FileSha256([string]$Path) {
    return Get-BytesSha256 ([IO.File]::ReadAllBytes($Path))
}

function Set-GlicEligibleRecursive($Value) {
    if ($null -eq $Value) { return }
    if ($Value -is [System.Collections.IList]) {
        foreach ($entry in $Value) { Set-GlicEligibleRecursive $entry }
        return
    }
    if ($Value -isnot [System.Collections.IDictionary]) { return }
    foreach ($key in @($Value.Keys)) {
        if ([string]::Equals([string]$key, 'is_glic_eligible', [StringComparison]::Ordinal)) {
            $Value[$key] = $true
        } else {
            Set-GlicEligibleRecursive $Value[$key]
        }
    }
}

function Convert-LocalState([string]$Path, [bool]$Disable) {
    $sourceBytes = [IO.File]::ReadAllBytes($Path)
    $sourceHash = Get-BytesSha256 $sourceBytes
    $text = [Text.Encoding]::UTF8.GetString($sourceBytes)
    $rootProbe = $text.TrimStart()
    if ($rootProbe.StartsWith([string][char]0xFEFF, [StringComparison]::Ordinal)) {
        $rootProbe = $rootProbe.Substring(1).TrimStart()
    }
    if ($rootProbe.Length -eq 0 -or $rootProbe[0] -ne '{') {
        throw 'Local State 根节点必须以 { 开始且必须是 JSON 对象'
    }
    try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "JSON 解析失败: $($_.Exception.Message)" }
    $data = ConvertTo-OrdinalJsonTree $parsed
    if (-not (Test-JsonObject $data)) { throw 'Local State 根节点必须是 JSON 对象' }
    Assert-SafeJsonNumbers $data
    $depth = Get-JsonNestingDepth $data
    if ($depth -gt $script:MaxSupportedJsonDepth) {
        throw "Local State JSON 嵌套深度 $depth 超过 PowerShell 安全上限 $script:MaxSupportedJsonDepth"
    }
    $browserEntry = Get-ExactJsonValue $data 'browser'
    if ($browserEntry.Found -and -not (Test-JsonObject $browserEntry.Value)) {
        throw 'Local State 的 browser 必须是对象'
    }

    $before = $data | ConvertTo-Json -Depth 100 -Compress
    Set-GlicEligibleRecursive $data
    $countryEntry = Get-ExactJsonValue $data 'variations_country'
    $data['variations_country'] = 'us'

    $permanentEntry = Get-ExactJsonValue $data 'variations_permanent_consistency_country'
    $lastVersion = Join-Path ([IO.Path]::GetDirectoryName($Path)) 'Last Version'
    if ($permanentEntry.Found -and $permanentEntry.Value -is [System.Collections.IList] -and $permanentEntry.Value.Count -ge 2 -and [IO.File]::Exists($lastVersion)) {
        $version = [IO.File]::ReadAllText($lastVersion, [Text.Encoding]::UTF8).Trim()
        if ($version.Length -gt 0) {
            $permanentEntry.Value[0] = $version
            $permanentEntry.Value[1] = 'us'
        }
    }

    if ($Disable) {
        if (-not $browserEntry.Found) {
            $browser = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
            $data.Add('browser', $browser)
        } else { $browser = $browserEntry.Value }
        $flagEntry = Get-ExactJsonValue $browser 'enabled_labs_experiments'
        if (-not $flagEntry.Found -or $null -eq $flagEntry.Value) { $flags = @() }
        elseif ($flagEntry.Value -isnot [System.Collections.IList]) { throw 'browser.enabled_labs_experiments 必须是数组' }
        else { $flags = @($flagEntry.Value) }
        $normalized = New-Object System.Collections.ArrayList
        foreach ($flag in $flags) {
            $remove = $false
            if ($flag -is [string]) {
                foreach ($base in @('optimization-guide-on-device-model','prompt-api-for-gemini-nano')) {
                    if ($flag -ceq $base -or $flag.StartsWith(($base + '@'), [StringComparison]::Ordinal)) { $remove = $true }
                }
            }
            if (-not $remove) { [void]$normalized.Add($flag) }
        }
        [void]$normalized.Add('optimization-guide-on-device-model@2')
        [void]$normalized.Add('prompt-api-for-gemini-nano@2')
        $browser['enabled_labs_experiments'] = [object[]]$normalized.ToArray()
    }

    $after = $data | ConvertTo-Json -Depth 100 -Compress
    return [pscustomobject]@{ Data=$data; Changed=($before -cne $after); SourceHash=$sourceHash }
}

# Validate and plan every selected JSON before querying/stopping Chrome or writing anything.
$plans = New-Object System.Collections.Generic.List[object]
$validationFailed = $false
foreach ($target in $targets) {
    $path = Join-Path $target.Root 'Local State'
    if (-not [IO.File]::Exists($path)) {
        Write-Host "[$($target.Label)] 跳过: 未找到 $path"
        continue
    }
    try {
        $result = Convert-LocalState $path ([bool]$DisableAIDownload)
        $plans.Add([pscustomobject]@{ Target=$target; Path=$path; Changed=$result.Changed })
        if ($result.Changed) { Write-Host "[$($target.Label)] 计划修改: $path" }
        else { Write-Host "[$($target.Label)] 无需修改: $path" }
    } catch {
        [Console]::Error.WriteLine("[$($target.Label)] 验证失败: $path`n$($_.Exception.Message)")
        $validationFailed = $true
    }
}
if ($validationFailed) {
    [Console]::Error.WriteLine('错误: 至少一个 Local State 验证失败；未停止 Chrome，未写入任何文件。')
    exit 1
}

if ($DisableAIDownload) { Write-Warning '禁用 AI 下载会安装 Chrome 策略，并可能显示“由您的组织管理”。' }
if ($DryRun) {
    if ($DisableAIDownload) { Write-Host '[dry-run] 将设置 GenAILocalFoundationalModelSettings=1；不会写注册表。' }
    Write-Host '[dry-run] 未停止、写入或重启 Chrome。'
    exit 0
}

$changedPlans = @($plans | Where-Object { $_.Changed })
$restartExecutables = New-Object System.Collections.Generic.List[string]
$status = 0
$restartDone = $false
function Restart-CapturedChrome {
    if ($script:restartDone) { return }
    $script:restartDone = $true
    if ($NoRestart) {
        if ($restartExecutables.Count -gt 0) { Write-Host '已按 -NoRestart 要求保持 Chrome 关闭。' }
        return
    }
    foreach ($exe in $restartExecutables) {
        try { Start-Process -FilePath $exe -ErrorAction Stop }
        catch {
            [Console]::Error.WriteLine("错误: 重启失败: $exe`n$($_.Exception.Message)")
            if ($script:status -eq 0) { $script:status = 2 }
        }
    }
}

try {
if ($changedPlans.Count -gt 0) {
    $selectedExecutables = @($changedPlans | ForEach-Object { $_.Target.Exes } | Where-Object { $_ } | Select-Object -Unique)
    if ($selectedExecutables.Count -gt 0) {
        try { $chromeProcesses = @(Get-CimInstance Win32_Process | Where-Object {
            $processPath = $_.ExecutablePath
            if (-not $processPath) { return $false }
            foreach ($selectedPath in $selectedExecutables) {
                if ($processPath.Equals($selectedPath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
            }
            return $false
        }) } catch {
            [Console]::Error.WriteLine("错误: 无法安全查询 Chrome 进程；未写入任何文件: $($_.Exception.Message)")
            exit 1
        }
        if ($chromeProcesses.Count -gt 0) {
            foreach ($process in $chromeProcesses) {
                $captured = $false
                foreach ($recorded in $restartExecutables) {
                    if ($recorded.Equals($process.ExecutablePath, [StringComparison]::OrdinalIgnoreCase)) { $captured = $true }
                }
                if (-not $captured) { $restartExecutables.Add($process.ExecutablePath) }
                try {
                    $runtimeProcess = Get-Process -Id $process.ProcessId -ErrorAction Stop
                    [void]$runtimeProcess.CloseMainWindow()
                } catch { }
            }
            $deadline = [DateTime]::UtcNow.AddSeconds(10)
            do {
                $remaining = @($chromeProcesses | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
                if ($remaining.Count -eq 0) { break }
                Start-Sleep -Milliseconds 250
            } while ([DateTime]::UtcNow -lt $deadline)
            if ($remaining.Count -gt 0) {
                Write-Warning 'Chrome 未在 10 秒内退出，正在强制停止选定频道的进程。'
                foreach ($process in $remaining) { Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue }
                Start-Sleep -Milliseconds 500
                $remaining = @($remaining | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
                if ($remaining.Count -gt 0) {
                    [Console]::Error.WriteLine('错误: 无法停止选定频道的 Chrome；为避免并发覆盖，未写入配置。')
                    exit 1
                }
            }
        }
    }
}

foreach ($plan in $changedPlans) {
    $temp = $null
    try {
        # The file may have changed while Chrome was shutting down. Re-read and recompute
        # immediately before writing; never serialize the pre-shutdown plan object.
        $fresh = Convert-LocalState $plan.Path ([bool]$DisableAIDownload)
        if (-not $fresh.Changed) {
            Write-Host "[$($plan.Target.Label)] 关闭 Chrome 后已无需修改: $($plan.Path)"
            continue
        }
        $directory = [IO.Path]::GetDirectoryName($plan.Path)
        $temp = Join-Path $directory ('.local-state-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        $json = $fresh.Data | ConvertTo-Json -Depth 100
        [IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        # Verify the exact byte snapshot used to build this output is still current.
        if ((Get-FileSha256 $plan.Path) -cne $fresh.SourceHash) {
            throw 'Local State 在计划后再次变化；为避免覆盖并发更新，已中止该目标'
        }
        # Atomic same-volume replacement through ReplaceFileW with a null backup path.
        Replace-FileWithoutBackup $temp $plan.Path
        $temp = $null
        Write-Host "[$($plan.Target.Label)] 已修改（未创建备份）: $($plan.Path)"
    } catch {
        if ($temp -and [IO.File]::Exists($temp)) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        [Console]::Error.WriteLine("[$($plan.Target.Label)] 写入失败: $($plan.Path)`n$($_.Exception.Message)")
        $status = 2
    }
}

if ($DisableAIDownload) {
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $effectiveScope = $PolicyScope
        if ($effectiveScope -eq 'Auto') { if ($isAdmin) { $effectiveScope = 'Machine' } else { $effectiveScope = 'User' } }
        if ($effectiveScope -eq 'Machine' -and -not $isAdmin) { throw 'Machine 策略需要管理员权限；请以管理员运行或选择 -PolicyScope User。' }
        $registryPath = if ($effectiveScope -eq 'Machine') { 'HKLM:\SOFTWARE\Policies\Google\Chrome' } else { 'HKCU:\SOFTWARE\Policies\Google\Chrome' }
        if (-not (Test-Path $registryPath)) { [void](New-Item -Path $registryPath -Force) }
        [void](New-ItemProperty -Path $registryPath -Name 'GenAILocalFoundationalModelSettings' -PropertyType DWord -Value 1 -Force)
        Write-Host "已设置 $effectiveScope 策略: GenAILocalFoundationalModelSettings=1"
    } catch {
        [Console]::Error.WriteLine("错误: Windows 策略写入失败: $($_.Exception.Message)")
        $status = 2
    }
}

} catch {
    [Console]::Error.WriteLine("错误: 操作中止: $($_.Exception.Message)")
    if ($status -eq 0) { $status = 1 }
} finally {
    Restart-CapturedChrome
}

if ($status -ne 0) { [Console]::Error.WriteLine('部分或全部操作未完成；请查看以上错误。') }
else { Write-Host '完成。请在 chrome://policy 和 Chrome 界面中验证结果。' }
exit $status
