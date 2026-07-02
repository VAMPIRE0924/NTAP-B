#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Version = "25.12.5",
    [string]$Target = "x86",
    [string]$Subtarget = "64",
    [string]$BaseUrl = "",
    [string]$OutputRoot = "_release/openwrt/sdk-cache",
    [string]$WslOutputRoot = "/root/ntap-openwrt-sdk",
    [string]$WslDistro = "Ubuntu-24.04",
    [switch]$DownloadInWsl,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReleaseRoot = Join-Path $RepoRoot "_release"
$script = Join-Path $RepoRoot "scripts\openwrt\fetch-sdk.sh"
if (-not (Test-Path -LiteralPath $script)) {
    throw "Missing script: $script"
}

function ConvertTo-WslPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $drive = $full.Substring(0, 1).ToLowerInvariant()
    $rest = $full.Substring(2).Replace('\', '/')
    return "/mnt/$drive$rest"
}

$outRootFull = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    [System.IO.Path]::GetFullPath($OutputRoot)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputRoot))
}
$releaseFull = [System.IO.Path]::GetFullPath($ReleaseRoot).TrimEnd('\', '/')
if (-not $outRootFull.StartsWith($releaseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot must stay under _release: $outRootFull"
}
if ($WslOutputRoot.Contains("'")) {
    throw "WslOutputRoot must not contain single quotes."
}
$wslOutRoot = if ([string]::IsNullOrWhiteSpace($WslOutputRoot)) {
    ConvertTo-WslPath -Path $outRootFull
} else {
    $WslOutputRoot
}

$effectiveBaseUrl = if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    "https://downloads.openwrt.org/releases/$Version/targets/$Target/$Subtarget"
} else {
    $BaseUrl.TrimEnd("/")
}

if (-not $DownloadInWsl) {
    $ProgressPreference = "SilentlyContinue"
    New-Item -ItemType Directory -Force -Path $outRootFull | Out-Null
    $shaPath = Join-Path $outRootFull "sha256sums-$Version-$Target-$Subtarget"
    Invoke-WebRequest -Uri "$effectiveBaseUrl/sha256sums" -OutFile $shaPath -TimeoutSec 120
    $sdkLine = Get-Content -LiteralPath $shaPath | Where-Object {
        $_ -match '\s\*?(openwrt-sdk-.*\.tar\.(zst|xz|gz))$'
    } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($sdkLine)) {
        throw "No OpenWrt SDK archive found in $effectiveBaseUrl/sha256sums"
    }
    $sdkName = (($sdkLine -split '\s+')[-1]).TrimStart('*')
    $archivePath = Join-Path $outRootFull $sdkName
    if ($Force -or -not (Test-Path -LiteralPath $archivePath)) {
        $tmpPath = "$archivePath.tmp"
        if (Test-Path -LiteralPath $tmpPath) {
            Remove-Item -LiteralPath $tmpPath -Force
        }
        Invoke-WebRequest -Uri "$effectiveBaseUrl/$sdkName" -OutFile $tmpPath -TimeoutSec 1800
        Move-Item -LiteralPath $tmpPath -Destination $archivePath -Force
    }

    $wslSha = ConvertTo-WslPath -Path $shaPath
    $wslArchive = ConvertTo-WslPath -Path $archivePath
    wsl.exe -d $WslDistro -- bash -lc "mkdir -p '$wslOutRoot' && cp '$wslSha' '$wslOutRoot/' && cp '$wslArchive' '$wslOutRoot/'"
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

$envParts = @(
    "OPENWRT_VERSION='$Version'",
    "OPENWRT_TARGET='$Target'",
    "OPENWRT_SUBTARGET='$Subtarget'",
    "OUT_ROOT='$wslOutRoot'"
)
if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) {
    $envParts += "OPENWRT_BASE_URL='$BaseUrl'"
}
if ($Force) {
    $envParts += "OPENWRT_SDK_FORCE=1"
}

$wslScript = ConvertTo-WslPath -Path $script
$command = ($envParts -join " ") + " sh '$wslScript'"
wsl.exe -d $WslDistro -- bash -lc $command
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
