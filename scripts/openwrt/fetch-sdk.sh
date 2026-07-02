#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
VERSION=${OPENWRT_VERSION:-25.12.5}
TARGET=${OPENWRT_TARGET:-x86}
SUBTARGET=${OPENWRT_SUBTARGET:-64}
BASE_URL=${OPENWRT_BASE_URL:-"https://downloads.openwrt.org/releases/$VERSION/targets/$TARGET/$SUBTARGET"}
OUT_ROOT=${OUT_ROOT:-"$ROOT/_release/openwrt/sdk"}
REPORT=${REPORT:-"$ROOT/_release/openwrt/openwrt-sdk-fetch-report.txt"}
FORCE=${OPENWRT_SDK_FORCE:-0}
CURL_TIMEOUT=${OPENWRT_CURL_TIMEOUT:-120}
CURL_RETRY=${OPENWRT_CURL_RETRY:-2}
REFRESH=${OPENWRT_FETCH_REFRESH:-0}

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "missing required command: $1" >&2
        exit 1
    fi
}

ensure_under_out_root() {
    path=$1
    case "$path" in
        "$OUT_ROOT"/*) ;;
        *)
            echo "refusing to operate outside OUT_ROOT: $path" >&2
            exit 1
            ;;
    esac
}

need_cmd curl
need_cmd sha256sum
need_cmd tar
need_cmd awk
need_cmd sed

mkdir -p "$OUT_ROOT" "$(dirname "$REPORT")"

SHA_FILE="$OUT_ROOT/sha256sums-$VERSION-$TARGET-$SUBTARGET"
if [ "$REFRESH" = "1" ] || [ ! -f "$SHA_FILE" ]; then
    curl -fsSL --connect-timeout 20 --max-time "$CURL_TIMEOUT" --retry "$CURL_RETRY" \
        "$BASE_URL/sha256sums" -o "$SHA_FILE"
fi
SDK_NAME=$(awk '/openwrt-sdk-.*\.tar\.(zst|xz|gz)$/ {name=$2; sub(/^\*/, "", name); print name; exit}' "$SHA_FILE")
if [ -z "$SDK_NAME" ]; then
    echo "no OpenWrt SDK archive found in $BASE_URL/sha256sums" >&2
    exit 1
fi
case "$SDK_NAME" in
    *.tar.zst) need_cmd zstd ;;
esac

ARCHIVE="$OUT_ROOT/$SDK_NAME"
SDK_DIR=$(printf "%s\n" "$SDK_NAME" | sed 's/\.tar\..*$//')
SDK_PATH="$OUT_ROOT/$SDK_DIR"
ensure_under_out_root "$ARCHIVE"
ensure_under_out_root "$SDK_PATH"

if [ "$REFRESH" = "1" ] || [ ! -f "$ARCHIVE" ]; then
    curl -fL --connect-timeout 20 --max-time "$CURL_TIMEOUT" --retry "$CURL_RETRY" \
        "$BASE_URL/$SDK_NAME" -o "$ARCHIVE.tmp"
    mv "$ARCHIVE.tmp" "$ARCHIVE"
fi

(cd "$OUT_ROOT" && grep "[ *]$SDK_NAME\$" "$SHA_FILE" | sha256sum -c -)

if [ -d "$SDK_PATH" ] && [ "$FORCE" != "1" ]; then
    if [ -f "$SDK_PATH/Makefile" ]; then
        {
            echo "OpenWrt SDK fetch report"
            date -u '+GeneratedAt=%Y-%m-%dT%H:%M:%SZ'
            echo "Version=$VERSION"
            echo "Target=$TARGET"
            echo "Subtarget=$SUBTARGET"
            echo "BaseUrl=$BASE_URL"
            echo "Archive=$ARCHIVE"
            echo "SdkPath=$SDK_PATH"
            echo "Status=already_extracted"
        } > "$REPORT"
        echo "$SDK_PATH"
        exit 0
    fi
    echo "SDK path exists but does not look complete: $SDK_PATH" >&2
    exit 1
fi

case "$ARCHIVE" in
    *.tar.zst)
        need_cmd zstd
        [ "$FORCE" = "1" ] && rm -rf "$SDK_PATH"
        tar --zstd -xf "$ARCHIVE" -C "$OUT_ROOT"
        ;;
    *.tar.xz)
        [ "$FORCE" = "1" ] && rm -rf "$SDK_PATH"
        tar -xJf "$ARCHIVE" -C "$OUT_ROOT"
        ;;
    *.tar.gz)
        [ "$FORCE" = "1" ] && rm -rf "$SDK_PATH"
        tar -xzf "$ARCHIVE" -C "$OUT_ROOT"
        ;;
    *)
        echo "unsupported SDK archive type: $ARCHIVE" >&2
        exit 1
        ;;
esac

if [ ! -f "$SDK_PATH/Makefile" ]; then
    echo "extracted SDK does not contain Makefile: $SDK_PATH" >&2
    exit 1
fi

{
    echo "OpenWrt SDK fetch report"
    date -u '+GeneratedAt=%Y-%m-%dT%H:%M:%SZ'
    echo "Version=$VERSION"
    echo "Target=$TARGET"
    echo "Subtarget=$SUBTARGET"
    echo "BaseUrl=$BASE_URL"
    echo "Archive=$ARCHIVE"
    echo "SdkPath=$SDK_PATH"
    echo "Status=ready"
} > "$REPORT"

echo "$SDK_PATH"
