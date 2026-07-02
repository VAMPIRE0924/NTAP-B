#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Version = "",
    [Parameter(Mandatory = $true)]
    [Alias("Host")]
    [string]$TargetHost,
    [string]$User = "root",
    [int]$Port = 22,
    [string]$RemoteDir = "",
    [string]$ServerAddr = "",
    [string]$NodeId = "",
    [string]$NodeKey = "",
    [string]$NodeKeyFile = "",
    [string]$NodeKeyEnv = "NTAP_NODE_KEY",
    [string]$TargetArch = "",
    [string]$BridgeName = "br-lan",
    [string]$TapName = "ntap-b0",
    [string]$Mtu = "1400",
    [switch]$Enable,
    [switch]$Start,
    [switch]$StrictService,
    [switch]$SkipConfig,
    [switch]$SkipPreflight,
    [switch]$TargetDryRun,
    [switch]$DryRun,
    [string]$ReportOut = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$PackageRoot = Join-Path $RepoRoot "_release\packages"
$ReportRoot = Join-Path $RepoRoot "_release\openwrt\device-validation"

function Fail {
    param([Parameter(Mandatory = $true)][string]$Message)
    throw "OpenWrt remote deploy failed: $Message"
}

function Get-LatestPackageVersion {
    if (-not (Test-Path -LiteralPath $PackageRoot)) {
        Fail "package root not found: $PackageRoot"
    }
    $latest = Get-ChildItem -LiteralPath $PackageRoot -Directory | Sort-Object Name | Select-Object -Last 1
    if ($null -eq $latest) {
        Fail "no package version found under $PackageRoot"
    }
    return $latest.Name
}

function Quote-Sh {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value.Contains("'")) {
        Fail "single quotes are not supported in remote shell arguments: $Value"
    }
    return "'$Value'"
}

function Mask-Secrets {
    param([Parameter(Mandatory = $true)][string]$Text)
    if (-not [string]::IsNullOrWhiteSpace($script:ResolvedNodeKey)) {
        return $Text.Replace($script:ResolvedNodeKey, "<masked>")
    }
    return $Text
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $display = Mask-Secrets ("{0} {1}" -f $FilePath, ($Arguments -join " "))
    if ($DryRun) {
        Write-Host "DRY-RUN: $display"
        return
    }
    Write-Host "RUN: $display"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        Fail "command failed: $display"
    }
}

function Invoke-Capture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $display = Mask-Secrets ("{0} {1}" -f $FilePath, ($Arguments -join " "))
    if ($DryRun) {
        Write-Host "DRY-RUN: $display"
        return @()
    }
    Write-Host "RUN: $display"
    $output = & $FilePath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "$Label failed: $display :: $($output -join ' ')"
    }
    return @($output)
}

function Resolve-NodeKey {
    if (-not [string]::IsNullOrWhiteSpace($NodeKey)) {
        return $NodeKey
    }
    if (-not [string]::IsNullOrWhiteSpace($NodeKeyFile)) {
        if (-not (Test-Path -LiteralPath $NodeKeyFile)) {
            Fail "node key file not found: $NodeKeyFile"
        }
        return (Get-Content -LiteralPath $NodeKeyFile -Raw).Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($NodeKeyEnv)) {
        $envValue = [Environment]::GetEnvironmentVariable($NodeKeyEnv)
        if (-not [string]::IsNullOrWhiteSpace($envValue)) {
            return $envValue
        }
    }
    return ""
}

function Get-OpenWrtPackageArch {
    param([Parameter(Mandatory = $true)][string]$Directory)
    $metadata = Join-Path $Directory "NTAP-B-$Version-openwrt-METADATA.txt"
    if (-not (Test-Path -LiteralPath $metadata)) {
        Fail "OpenWrt package metadata missing: $metadata"
    }
    foreach ($line in [System.IO.File]::ReadLines($metadata)) {
        if ($line -match '^\s*arch:\s*(\S+)\s*$') {
            return $Matches[1]
        }
    }
    Fail "OpenWrt package metadata does not contain arch: $metadata"
}

function Get-ArchFromOpenWrtProbe {
    param($Output)
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($Output)) {
        $text = ([string]$line).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }
        if ($text -match '^arch\s+(\S+)\s+\d+') {
            $arch = $Matches[1]
            if ($arch -notin @("all", "noarch")) {
                $candidates.Add($arch) | Out-Null
            }
        } elseif ($text -match '^[A-Za-z0-9_.-]+$') {
            $candidates.Add($text) | Out-Null
        }
    }
    if ($candidates.Count -eq 0) {
        return ""
    }
    return $candidates[$candidates.Count - 1]
}

foreach ($tool in @("ssh.exe", "scp.exe")) {
    if ($null -eq (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Fail "$tool was not found in PATH"
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-LatestPackageVersion
}

$packageDir = Join-Path $PackageRoot $Version
if (-not (Test-Path -LiteralPath $packageDir)) {
    Fail "package version not found: $packageDir"
}

$openWrtPackage = @(Get-ChildItem -LiteralPath $packageDir -File | Where-Object {
    $_.Name -like "NTAP-B-$Version-openwrt-*" -and $_.Extension -in @(".apk", ".ipk")
} | Select-Object -First 1)
if ($openWrtPackage.Count -ne 1) {
    Fail "expected exactly one OpenWrt package asset for $Version"
}

$installer = Join-Path $packageDir "NTAP-B-$Version-openwrt-install.sh"
$validator = Join-Path $packageDir "NTAP-B-$Version-openwrt-device-validate.sh"
foreach ($required in @($installer, $validator)) {
    if (-not (Test-Path -LiteralPath $required)) {
        Fail "missing release asset: $required"
    }
}
$packageArch = Get-OpenWrtPackageArch -Directory $packageDir
if (-not [string]::IsNullOrWhiteSpace($TargetArch) -and $TargetArch -ne $packageArch) {
    Fail "TargetArch $TargetArch does not match release package arch $packageArch"
}

$script:ResolvedNodeKey = Resolve-NodeKey
if (-not $SkipConfig) {
    foreach ($pair in @(
        @{ Name = "ServerAddr"; Value = $ServerAddr },
        @{ Name = "NodeId"; Value = $NodeId },
        @{ Name = "NodeKey/NodeKeyFile/$NodeKeyEnv"; Value = $script:ResolvedNodeKey }
    )) {
        if ([string]::IsNullOrWhiteSpace($pair.Value)) {
            Fail "$($pair.Name) is required unless -SkipConfig is used"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($RemoteDir)) {
    $RemoteDir = "/tmp/ntap-$Version"
}

$safeHost = ($TargetHost -replace '[^A-Za-z0-9_.-]', '_')
if ([string]::IsNullOrWhiteSpace($ReportOut)) {
    $ReportOut = Join-Path $ReportRoot "$Version-$safeHost.txt"
}

$target = "$User@$TargetHost"
$remotePackage = "$RemoteDir/$($openWrtPackage[0].Name)"
$remoteInstaller = "$RemoteDir/$(Split-Path -Leaf $installer)"
$remoteValidator = "$RemoteDir/$(Split-Path -Leaf $validator)"
$remoteReport = "$RemoteDir/ntap-b-device-validation.txt"

Write-Host "NTAP-B OpenWrt remote deploy"
Write-Host "Version=$Version"
Write-Host "Target=$target"
Write-Host "Port=$Port"
Write-Host "RemoteDir=$RemoteDir"
Write-Host "Package=$($openWrtPackage[0].FullName)"
Write-Host "PackageArch=$packageArch"
if (-not [string]::IsNullOrWhiteSpace($TargetArch)) {
    Write-Host "TargetArch=$TargetArch"
}
Write-Host "ReportOut=$ReportOut"
Write-Host "TargetDryRun=$TargetDryRun"
Write-Host "DryRun=$DryRun"

$probeCommand = "if command -v apk >/dev/null 2>&1; then apk --print-arch; elif command -v opkg >/dev/null 2>&1; then opkg print-architecture; else uname -m; fi"
$remoteArchOutput = Invoke-Capture -FilePath "ssh.exe" -Arguments @("-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-p", "$Port", $target, $probeCommand) -Label "OpenWrt arch probe"
if (-not $DryRun) {
    $remoteArch = Get-ArchFromOpenWrtProbe -Output $remoteArchOutput
    if ([string]::IsNullOrWhiteSpace($remoteArch)) {
        Fail "unable to detect remote OpenWrt package architecture"
    }
    Write-Host "RemoteArch=$remoteArch"
    if (-not [string]::IsNullOrWhiteSpace($TargetArch) -and $remoteArch -ne $TargetArch) {
        Fail "remote OpenWrt arch $remoteArch does not match TargetArch $TargetArch"
    }
    if ($remoteArch -ne $packageArch) {
        Fail "remote OpenWrt arch $remoteArch does not match release package arch $packageArch"
    }
}

Invoke-External -FilePath "ssh.exe" -Arguments @("-p", "$Port", $target, "mkdir -p $(Quote-Sh $RemoteDir)")
Invoke-External -FilePath "scp.exe" -Arguments @("-P", "$Port", $openWrtPackage[0].FullName, $installer, $validator, "${target}:$RemoteDir/")
Invoke-External -FilePath "ssh.exe" -Arguments @("-p", "$Port", $target, "chmod +x $(Quote-Sh $remoteInstaller) $(Quote-Sh $remoteValidator)")

$installParts = New-Object System.Collections.Generic.List[string]
$installParts.Add("sh") | Out-Null
$installParts.Add((Quote-Sh $remoteInstaller)) | Out-Null
$installParts.Add("--package") | Out-Null
$installParts.Add((Quote-Sh $remotePackage)) | Out-Null
if ($SkipConfig) {
    $installParts.Add("--skip-config") | Out-Null
} else {
    $installParts.Add("--server-addr") | Out-Null
    $installParts.Add((Quote-Sh $ServerAddr)) | Out-Null
    $installParts.Add("--node-id") | Out-Null
    $installParts.Add((Quote-Sh $NodeId)) | Out-Null
    $installParts.Add("--node-key") | Out-Null
    $installParts.Add((Quote-Sh $script:ResolvedNodeKey)) | Out-Null
    $installParts.Add("--tap-name") | Out-Null
    $installParts.Add((Quote-Sh $TapName)) | Out-Null
    $installParts.Add("--mtu") | Out-Null
    $installParts.Add((Quote-Sh $Mtu)) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($BridgeName)) {
        $installParts.Add("--bridge-name") | Out-Null
        $installParts.Add((Quote-Sh $BridgeName)) | Out-Null
    }
}
if ($SkipPreflight) {
    $installParts.Add("--skip-preflight") | Out-Null
}
if ($Enable) {
    $installParts.Add("--enable") | Out-Null
}
if ($Start) {
    $installParts.Add("--start") | Out-Null
}
$installParts.Add("--run-validator") | Out-Null
$installParts.Add("--validator") | Out-Null
$installParts.Add((Quote-Sh $remoteValidator)) | Out-Null
$installParts.Add("--report") | Out-Null
$installParts.Add((Quote-Sh $remoteReport)) | Out-Null
if ($StrictService) {
    $installParts.Add("--strict-service") | Out-Null
}
if ($TargetDryRun) {
    $installParts.Add("--dry-run") | Out-Null
}

$installCommand = ($installParts -join " ")
Invoke-External -FilePath "ssh.exe" -Arguments @("-p", "$Port", $target, $installCommand)

if ($DryRun -or $TargetDryRun) {
    Write-Host "Remote report copy skipped for dry-run."
} else {
    $reportDir = Split-Path -Parent $ReportOut
    if (-not [string]::IsNullOrWhiteSpace($reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    Invoke-External -FilePath "scp.exe" -Arguments @("-P", "$Port", "${target}:$remoteReport", $ReportOut)
    Write-Host "OpenWrt target validation report: $ReportOut"
}
