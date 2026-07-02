#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT_ROOT=${OUT_ROOT:-"$ROOT/_release/openwrt"}
STAGE="$OUT_ROOT/ntap-b-sdk-package"
REPORT="$OUT_ROOT/ntap-b-size-report.txt"
PACKAGE_OUT="$OUT_ROOT/package-output"
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

ensure_feed_conf() {
    if [ ! -f "$SDK/feeds.conf" ] && [ -f "$SDK/feeds.conf.default" ]; then
        cp "$SDK/feeds.conf.default" "$SDK/feeds.conf"
    fi

    if [ "${OPENWRT_FEED_GITHUB_MIRROR:-1}" = "1" ] && [ -f "$SDK/feeds.conf" ]; then
        sed -i \
            -e 's#https://git.openwrt.org/openwrt/openwrt.git#https://github.com/openwrt/openwrt.git#g' \
            -e 's#https://git.openwrt.org/feed/packages.git#https://github.com/openwrt/packages.git#g' \
            "$SDK/feeds.conf"
    fi
}

ensure_feed_has_package() {
    feed=$1
    package=$2
    index="$SDK/feeds/$feed.index"

    if [ ! -f "$index" ] || ! grep -q "^Package: $package\$" "$index"; then
        rm -rf \
            "$SDK/feeds/$feed" \
            "$SDK/feeds/${feed}_root" \
            "$SDK/feeds/${feed}.tmp" \
            "$SDK/feeds/${feed}.index" \
            "$SDK/feeds/${feed}.targetindex"
        (cd "$SDK" && ./scripts/feeds update "$feed")
    fi

    if [ ! -f "$index" ] || ! grep -q "^Package: $package\$" "$index"; then
        echo "OpenWrtFeedStatus=missing_$package" >> "$REPORT"
        echo "OpenWrt feed '$feed' does not provide package '$package'" >&2
        exit 1
    fi
}

rm -rf "$SDK/package/ntap-b"
mkdir -p "$SDK/package"
cp -R "$STAGE" "$SDK/package/ntap-b"

if [ -x "$SDK/scripts/feeds" ]; then
    ensure_feed_conf
    ensure_feed_has_package base libopenssl
    (cd "$SDK" && ./scripts/feeds install libopenssl)
    echo "OpenWrtFeeds=base:libopenssl" >> "$REPORT"
fi

touch "$SDK/.config"
tmp_config=$(mktemp)
grep -v '^CONFIG_PACKAGE_ntap-b[ =]' "$SDK/.config" > "$tmp_config" || true
printf '%s\n' 'CONFIG_PACKAGE_ntap-b=m' >> "$tmp_config"
mv "$tmp_config" "$SDK/.config"

make -C "$SDK" defconfig
make -C "$SDK" package/ntap-b/compile V=s

PKG=$(find "$SDK/bin/packages" "$SDK/bin/targets" \
    \( -name 'ntap-b_*.ipk' -o -name 'ntap-b-*.apk' -o -name 'ntap-b_*.apk' \) \
    2>/dev/null | sort | tail -n 1 || true)
PKG_FORMAT=unknown
case "$PKG" in
    *.apk) PKG_FORMAT=apk ;;
    *.ipk) PKG_FORMAT=ipk ;;
esac

{
    echo "OpenWrtSdkStatus=built"
    echo "OpenWrtPackageDir=$SDK/package/ntap-b"
    echo "OpenWrtPackage=$PKG"
    echo "OpenWrtPackageFormat=$PKG_FORMAT"
} >> "$REPORT"
if [ -n "$PKG" ] && [ -f "$PKG" ]; then
    mkdir -p "$PACKAGE_OUT"
    cp "$PKG" "$PACKAGE_OUT/"
    COPIED_PKG="$PACKAGE_OUT/$(basename "$PKG")"
    {
        echo "OpenWrtPackageOutput=$COPIED_PKG"
        wc -c < "$PKG" | awk '{print "OpenWrtPackageSizeBytes="$1}'
    } >> "$REPORT"
    case "$PKG_FORMAT" in
        apk) echo "OpenWrtApk=$COPIED_PKG" >> "$REPORT" ;;
        ipk)
            echo "OpenWrtIpk=$COPIED_PKG" >> "$REPORT"
            wc -c < "$PKG" | awk '{print "OpenWrtIpkSizeBytes="$1}' >> "$REPORT"
            ;;
    esac
fi

echo "report: $REPORT"
