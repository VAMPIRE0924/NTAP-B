#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SdkPath = $env:OPENWRT_SDK,
    [string]$OutputRoot = "_release\openwrt",
    [switch]$RequireSdk
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReleaseRoot = Join-Path $RepoRoot "_release"
$OutRoot = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    [System.IO.Path]::GetFullPath($OutputRoot)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputRoot))
}
$Stage = Join-Path $OutRoot "ntap-b-sdk-package"
$Report = Join-Path $OutRoot "ntap-b-size-report.txt"

function Assert-UnderPath {
    param([string]$Path, [string]$Parent)
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    if (-not $resolvedPath.StartsWith($resolvedParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside expected directory: $resolvedPath"
    }
}

function Copy-Dir {
    param([string]$From, [string]$To)
    if (-not (Test-Path -LiteralPath $From)) {
        throw "Missing path: $From"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $To) | Out-Null
    Copy-Item -LiteralPath $From -Destination $To -Recurse -Force
}

function ConvertTo-WslPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $drive = $full.Substring(0, 1).ToLowerInvariant()
    $rest = $full.Substring(2).Replace('\', '/')
    return "/mnt/$drive$rest"
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
if (Test-Path -LiteralPath $Stage) {
    Assert-UnderPath -Path $Stage -Parent $ReleaseRoot
    Remove-Item -LiteralPath $Stage -Recurse -Force
}

Copy-Dir (Join-Path $PSScriptRoot "package\ntap-b") $Stage
Copy-Dir (Join-Path $RepoRoot "src\common") (Join-Path $Stage "src\common")
Copy-Dir (Join-Path $RepoRoot "src\b") (Join-Path $Stage "src\b")
New-Item -ItemType Directory -Force -Path (Join-Path $Stage "conf") | Out-Null
Copy-Item -LiteralPath (Join-Path $RepoRoot "conf\ntap-b.conf.example") `
    -Destination (Join-Path $Stage "conf\ntap-b.conf.example") -Force

$linuxBin = Join-Path $RepoRoot "build\linux\bin\ntap-b"
$baseline = @()
$baseline += "NTAP-B OpenWrt package staging report"
$baseline += "GeneratedAt=$(Get-Date -Format o)"
$baseline += "PackageStage=$Stage"
$baseline += "SdkPath=$SdkPath"
if (Test-Path -LiteralPath $linuxBin) {
    $baseline += "HostLinuxBinary=$linuxBin"
    $baseline += "HostLinuxSizeBytes=$((Get-Item -LiteralPath $linuxBin).Length)"
    $wslBin = ConvertTo-WslPath -Path $linuxBin
    $wslTmp = "/tmp/ntap-b-strip-size-$PID"
    & wsl.exe -d Ubuntu-24.04 -- cp $wslBin $wslTmp 2>$null
    $copyExit = $LASTEXITCODE
    $stripExit = 1
    if ($copyExit -eq 0) {
        & wsl.exe -d Ubuntu-24.04 -- strip $wslTmp 2>$null
        $stripExit = $LASTEXITCODE
        $stripResult = if ($stripExit -eq 0) {
            & wsl.exe -d Ubuntu-24.04 -- stat -c%s $wslTmp 2>$null
        } else {
            @()
        }
        & wsl.exe -d Ubuntu-24.04 -- rm -f $wslTmp 2>$null
    } else {
        $stripResult = @()
    }
    if ($copyExit -eq 0 -and $stripExit -eq 0 -and -not [string]::IsNullOrWhiteSpace(($stripResult -join ""))) {
        $baseline += "HostLinuxStrippedSizeBytes=$(($stripResult | Select-Object -Last 1).Trim())"
    } else {
        $baseline += "HostLinuxStrippedSizeBytes=unavailable"
    }
} else {
    $baseline += "HostLinuxBinary=missing; run scripts/build-wsl.ps1 first"
}

if ([string]::IsNullOrWhiteSpace($SdkPath)) {
    $baseline += "OpenWrtSdkStatus=missing"
    $baseline += "OpenWrtBuild=skipped; set OPENWRT_SDK or pass -SdkPath after selecting target architecture"
    $baseline | Set-Content -LiteralPath $Report -Encoding ASCII
    Write-Host "Staged OpenWrt package: $Stage"
    Write-Host "Wrote size baseline: $Report"
    if ($RequireSdk) {
        throw "OpenWrt SDK path is required."
    }
    return
}

if (-not (Test-Path -LiteralPath $SdkPath)) {
    $baseline += "OpenWrtSdkStatus=not_found"
    $baseline | Set-Content -LiteralPath $Report -Encoding ASCII
    throw "OpenWrt SDK path not found: $SdkPath"
}

$sdkPackage = Join-Path $SdkPath "package\ntap-b"
if (Test-Path -LiteralPath $sdkPackage) {
    Assert-UnderPath -Path $sdkPackage -Parent $SdkPath
    Remove-Item -LiteralPath $sdkPackage -Recurse -Force
}
Copy-Item -LiteralPath $Stage -Destination $sdkPackage -Recurse -Force
$baseline += "OpenWrtSdkStatus=staged"
$baseline += "OpenWrtSdkPackage=$sdkPackage"
$baseline += "OpenWrtBuild=not_run_by_powershell_helper; run scripts/openwrt/build-ntap-b-sdk.sh inside Linux/WSL for SDK compile"
$baseline | Set-Content -LiteralPath $Report -Encoding ASCII
Write-Host "Staged package into SDK: $sdkPackage"
Write-Host "Wrote report: $Report"
