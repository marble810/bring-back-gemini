param(
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [Parameter(Mandatory=$true)][string]$ProfilePath
)

# Registry-only test doubles. All profile work still goes through the production script;
# no real Chrome policy key is read or written.
function global:Test-Path {
    param([Parameter(Position=0)]$Path, [Parameter(ValueFromRemainingArguments=$true)]$Rest)
    if ([string]$Path -like 'HK*:*') { return $true }
    return Microsoft.PowerShell.Management\Test-Path -Path $Path @Rest
}
function global:New-Item {
    param([Parameter(Position=0)]$Path, [switch]$Force, [Parameter(ValueFromRemainingArguments=$true)]$Rest)
    if ([string]$Path -like 'HK*:*') { return [pscustomobject]@{ PSPath=$Path } }
    return Microsoft.PowerShell.Management\New-Item -Path $Path -Force:$Force @Rest
}
function global:New-ItemProperty {
    param($Path, $Name, $PropertyType, $Value, [switch]$Force, [Parameter(ValueFromRemainingArguments=$true)]$Rest)
    if ([string]$Path -notlike 'HK*:*') { throw '测试只允许模拟注册表策略写入' }
    return [pscustomobject]@{ Path=$Path; Name=$Name; Value=$Value }
}

& $ScriptPath -UserDataDir $ProfilePath -DisableAIDownload -NoRestart
exit $LASTEXITCODE
