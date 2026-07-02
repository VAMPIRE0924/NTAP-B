#!/bin/sh
set -u

REPORT="/tmp/ntap-b-device-validation.txt"
BRIDGE_NAME=""
STRICT_SERVICE=0
REPORT_ONLY=0
BIN="/usr/sbin/ntap-b"
INIT="/etc/init.d/ntap-b"
CONFIG="/etc/config/ntap-b"
FAILS=0
WARNS=0

usage() {
    cat <<EOF
Usage: sh device-validate.sh [options]

Options:
  --bridge-name NAME     Validate that NAME exists and ntap-b can preflight it.
  --report PATH          Write the validation report to PATH.
  --binary PATH          ntap-b binary path. Default: /usr/sbin/ntap-b.
  --strict-service       Fail when the OpenWrt service is disabled or stopped.
  --report-only          Always exit 0 after writing the report.
  -h, --help             Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --bridge-name)
            [ "$#" -ge 2 ] || { echo "--bridge-name requires a value" >&2; exit 2; }
            BRIDGE_NAME=$2
            shift 2
            ;;
        --report)
            [ "$#" -ge 2 ] || { echo "--report requires a value" >&2; exit 2; }
            REPORT=$2
            shift 2
            ;;
        --binary)
            [ "$#" -ge 2 ] || { echo "--binary requires a value" >&2; exit 2; }
            BIN=$2
            shift 2
            ;;
        --strict-service)
            STRICT_SERVICE=1
            shift
            ;;
        --report-only)
            REPORT_ONLY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

report_dir=$(dirname "$REPORT")
if [ -n "$report_dir" ] && [ "$report_dir" != "." ]; then
    mkdir -p "$report_dir" 2>/dev/null || true
fi
: > "$REPORT" || {
    echo "cannot write report: $REPORT" >&2
    exit 1
}

line() {
    printf '%s\n' "$*" | tee -a "$REPORT"
}

ok() {
    line "OK   $*"
}

warn() {
    WARNS=$((WARNS + 1))
    line "WARN $*"
}

fail() {
    FAILS=$((FAILS + 1))
    line "FAIL $*"
}

run_check() {
    label=$1
    shift
    tmp=${TMPDIR:-/tmp}/ntap-b-device-validate.$$.out
    "$@" > "$tmp" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "$label"
    else
        fail "$label exited $rc"
    fi
    if [ -s "$tmp" ]; then
        sed 's/^/  | /' "$tmp" | tee -a "$REPORT"
    fi
    rm -f "$tmp"
    return "$rc"
}

run_warn_check() {
    label=$1
    shift
    tmp=${TMPDIR:-/tmp}/ntap-b-device-validate.$$.out
    "$@" > "$tmp" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "$label"
    else
        warn "$label exited $rc"
    fi
    if [ -s "$tmp" ]; then
        sed 's/^/  | /' "$tmp" | tee -a "$REPORT"
    fi
    rm -f "$tmp"
    return 0
}

pkg_present() {
    name=$1
    if command -v apk >/dev/null 2>&1; then
        apk info -e "$name" >/dev/null 2>&1
        return $?
    fi
    if command -v opkg >/dev/null 2>&1; then
        opkg status "$name" 2>/dev/null | grep -q '^Status: .* installed'
        return $?
    fi
    return 2
}

check_package() {
    name=$1
    pkg_present "$name"
    rc=$?
    case "$rc" in
        0) ok "package installed: $name" ;;
        1) fail "package missing: $name" ;;
        *) warn "no supported package manager to verify: $name" ;;
    esac
}

check_any_package() {
    label=$1
    shift
    found=0
    manager_missing=0
    for name in "$@"; do
        pkg_present "$name"
        rc=$?
        if [ "$rc" -eq 0 ]; then
            ok "$label installed: $name"
            found=1
            break
        fi
        if [ "$rc" -eq 2 ]; then
            manager_missing=1
        fi
    done
    if [ "$found" -eq 0 ]; then
        if [ "$manager_missing" -eq 1 ]; then
            warn "no supported package manager to verify: $label"
        else
            fail "$label package missing: $*"
        fi
    fi
}

line "NTAP-B OpenWrt device validation"
line "Report=$REPORT"
line "Binary=$BIN"
line "BridgeName=$BRIDGE_NAME"
line "StrictService=$STRICT_SERVICE"
line ""

if [ -x "$BIN" ]; then
    ok "binary is executable: $BIN"
else
    fail "binary is not executable: $BIN"
fi

if [ -x "$INIT" ]; then
    ok "init script is executable: $INIT"
else
    fail "init script is not executable: $INIT"
fi

if [ -f "$CONFIG" ]; then
    ok "UCI config exists: $CONFIG"
else
    fail "UCI config missing: $CONFIG"
fi

check_package ntap-b
check_package kmod-tun
check_package libc
check_any_package "OpenSSL runtime" libopenssl3 libopenssl libopenssl1.1

if [ -e /dev/net/tun ]; then
    ok "/dev/net/tun exists"
else
    fail "/dev/net/tun is missing"
fi

if [ -n "$BRIDGE_NAME" ]; then
    if command -v ip >/dev/null 2>&1; then
        run_check "bridge exists: $BRIDGE_NAME" ip link show "$BRIDGE_NAME" || true
    elif [ -d "/sys/class/net/$BRIDGE_NAME" ]; then
        ok "bridge exists through sysfs: $BRIDGE_NAME"
    else
        fail "cannot verify bridge, and sysfs entry is missing: $BRIDGE_NAME"
    fi
fi

if [ -x "$BIN" ]; then
    if [ -n "$BRIDGE_NAME" ]; then
        run_check "ntap-b check-env --bridge-name $BRIDGE_NAME" "$BIN" check-env --bridge-name "$BRIDGE_NAME" || true
    else
        run_check "ntap-b check-env" "$BIN" check-env || true
    fi
fi

if [ -x "$INIT" ]; then
    run_check "/etc/init.d/ntap-b check" "$INIT" check || true

    if "$INIT" enabled >/dev/null 2>&1; then
        ok "service enabled"
    else
        if [ "$STRICT_SERVICE" -eq 1 ]; then
            fail "service is not enabled"
        else
            warn "service is not enabled"
        fi
    fi

    if "$INIT" status >/dev/null 2>&1; then
        ok "service status is running"
    else
        if [ "$STRICT_SERVICE" -eq 1 ]; then
            fail "service is not running"
        else
            warn "service is not running"
        fi
    fi
fi

if command -v uci >/dev/null 2>&1; then
    line ""
    line "UCI node settings:"
    for option in enabled server_addr node_id node_key tap_name mtu bridge_check_name preflight_on_start log_level log_file; do
        value=$(uci -q get "ntap-b.node.$option" 2>/dev/null || true)
        if [ -n "$value" ]; then
            if [ "$option" = "node_key" ]; then
                line "  node_key=<masked>"
            else
                line "  $option=$value"
            fi
        fi
    done
else
    warn "uci command is not available"
fi

line ""
line "Summary: failures=$FAILS warnings=$WARNS"
line "Report written: $REPORT"

if [ "$FAILS" -ne 0 ] && [ "$REPORT_ONLY" -ne 1 ]; then
    exit 1
fi
exit 0
