#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PKG=${1:-${OPENWRT_PACKAGE:-"$ROOT/_release/openwrt/package-output/ntap-b-0.1-r1.apk"}}
SDK=${OPENWRT_SDK:-}

if [ ! -f "$PKG" ]; then
    echo "missing OpenWrt package: $PKG" >&2
    exit 1
fi

case "$PKG" in
    *.apk)
        if [ -z "$SDK" ]; then
            echo "OPENWRT_SDK is required to inspect .apk package metadata" >&2
            exit 1
        fi
        APK="$SDK/staging_dir/host/bin/apk"
        if [ ! -x "$APK" ]; then
            echo "missing SDK apk tool: $APK" >&2
            exit 1
        fi
        META=$("$APK" adbdump "$PKG")
        printf '%s\n' "$META"
        printf '%s\n' "$META" | grep -q 'name: ntap-b'
        printf '%s\n' "$META" | grep -q 'depends:'
        printf '%s\n' "$META" | grep -q -- '- kmod-tun'
        printf '%s\n' "$META" | grep -q -- '- libopenssl3'
        printf '%s\n' "$META" | grep -q 'name: usr/sbin'
        printf '%s\n' "$META" | grep -q 'name: ntap-b'
        printf '%s\n' "$META" | grep -q 'name: etc/init.d'
        printf '%s\n' "$META" | grep -q 'name: etc/config'
        ;;
    *.ipk)
        if ! command -v tar >/dev/null 2>&1; then
            echo "tar is required to inspect .ipk packages" >&2
            exit 1
        fi
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT INT TERM
        tar -xzf "$PKG" -C "$tmp"
        tar -xzf "$tmp/control.tar.gz" -C "$tmp"
        tar -tzf "$tmp/data.tar.gz" | tee "$tmp/files.txt"
        grep -q '^Package: ntap-b$' "$tmp/control"
        grep -q 'kmod-tun' "$tmp/control"
        grep -q 'libopenssl' "$tmp/control"
        grep -q 'usr/sbin/ntap-b' "$tmp/files.txt"
        grep -q 'etc/init.d/ntap-b' "$tmp/files.txt"
        grep -q 'etc/config/ntap-b' "$tmp/files.txt"
        ;;
    *)
        echo "unsupported OpenWrt package type: $PKG" >&2
        exit 1
        ;;
esac

echo "OpenWrt package verification OK: $PKG"
