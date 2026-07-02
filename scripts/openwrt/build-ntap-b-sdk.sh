#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT_ROOT=${OUT_ROOT:-"$ROOT/_release/openwrt"}
STAGE="$OUT_ROOT/ntap-b-sdk-package"
REPORT="$OUT_ROOT/ntap-b-size-report.txt"
SDK=${OPENWRT_SDK:-${1:-}}

rm -rf "$STAGE"
mkdir -p "$STAGE/src/common" "$STAGE/src/b" "$STAGE/conf" "$OUT_ROOT"
cp -R "$ROOT/scripts/openwrt/package/ntap-b/." "$STAGE/"
cp -R "$ROOT/src/common/." "$STAGE/src/common/"
cp -R "$ROOT/src/b/." "$STAGE/src/b/"
cp "$ROOT/conf/ntap-b.conf.example" "$STAGE/conf/ntap-b.conf.example"

{
    echo "NTAP-B OpenWrt SDK build report"
    date -u '+GeneratedAt=%Y-%m-%dT%H:%M:%SZ'
    echo "PackageStage=$STAGE"
    echo "SdkPath=$SDK"
} > "$REPORT"

if [ -f "$ROOT/build/linux/bin/ntap-b" ]; then
    echo "HostLinuxBinary=$ROOT/build/linux/bin/ntap-b" >> "$REPORT"
    wc -c < "$ROOT/build/linux/bin/ntap-b" | awk '{print "HostLinuxSizeBytes="$1}' >> "$REPORT"
    tmp=$(mktemp)
    cp "$ROOT/build/linux/bin/ntap-b" "$tmp"
    if strip "$tmp" >/dev/null 2>&1; then
        wc -c < "$tmp" | awk '{print "HostLinuxStrippedSizeBytes="$1}' >> "$REPORT"
    else
        echo "HostLinuxStrippedSizeBytes=unavailable" >> "$REPORT"
    fi
    rm -f "$tmp"
fi

if [ -z "$SDK" ]; then
    {
        echo "OpenWrtSdkStatus=missing"
        echo "OpenWrtBuild=skipped; set OPENWRT_SDK=/path/to/openwrt-sdk after target architecture is selected"
    } >> "$REPORT"
    echo "staged package: $STAGE"
    echo "report: $REPORT"
    exit 0
fi

if [ ! -d "$SDK" ]; then
    echo "OpenWrtSdkStatus=not_found" >> "$REPORT"
    echo "missing OpenWrt SDK: $SDK" >&2
    exit 1
fi

rm -rf "$SDK/package/ntap-b"
mkdir -p "$SDK/package"
cp -R "$STAGE" "$SDK/package/ntap-b"

make -C "$SDK" package/ntap-b/compile V=s

IPK=$(find "$SDK/bin/packages" "$SDK/bin/targets" -name 'ntap-b_*.ipk' 2>/dev/null | sort | tail -n 1 || true)
{
    echo "OpenWrtSdkStatus=built"
    echo "OpenWrtPackageDir=$SDK/package/ntap-b"
    echo "OpenWrtIpk=$IPK"
} >> "$REPORT"
if [ -n "$IPK" ] && [ -f "$IPK" ]; then
    wc -c < "$IPK" | awk '{print "OpenWrtIpkSizeBytes="$1}' >> "$REPORT"
fi

echo "report: $REPORT"
