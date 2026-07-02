#!/bin/sh
set -eu

PACKAGE=""
VALIDATOR=""
SERVER_ADDR=""
NODE_ID=""
NODE_KEY=""
TAP_NAME="ntap-b0"
MTU="1400"
BRIDGE_CHECK_NAME=""
PREFLIGHT_ON_START="1"
LOG_LEVEL="info"
LOG_FILE="/tmp/ntap-b.log"
ENABLE_SERVICE=0
START_SERVICE=0
RUN_VALIDATOR=0
STRICT_SERVICE=0
SKIP_CONFIG=0
SKIP_PREFLIGHT=0
REPORT="/tmp/ntap-b-device-validation.txt"
DRY_RUN=0

usage() {
    cat <<EOF
Usage: sh openwrt-install.sh --package PATH [options]

Required unless --skip-config is used:
  --server-addr HOST:PORT
  --node-id ID
  --node-key KEY

Options:
  --package PATH          NTAP-B OpenWrt .apk or .ipk package.
  --validator PATH        Device validator script copied to the target.
  --tap-name NAME         TAP name. Default: ntap-b0.
  --mtu MTU               TAP MTU. Default: 1400.
  --bridge-name NAME      Set UCI bridge_check_name and validate that bridge.
  --preflight-on-start N  Set UCI preflight_on_start. Default: 1.
  --log-level LEVEL       UCI log_level. Default: info.
  --log-file PATH         UCI log_file. Default: /tmp/ntap-b.log.
  --enable                Enable /etc/init.d/ntap-b.
  --start                 Start /etc/init.d/ntap-b.
  --run-validator         Run the validator after install/config/preflight.
  --strict-service        Ask the validator to fail if service is not running.
  --report PATH           Validator report path. Default: /tmp/ntap-b-device-validation.txt.
  --skip-config           Install package only; do not write UCI config.
  --skip-preflight        Do not run /etc/init.d/ntap-b check.
  --dry-run               Print intended actions without changing the target.
  -h, --help              Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --package)
            [ "$#" -ge 2 ] || { echo "--package requires a value" >&2; exit 2; }
            PACKAGE=$2
            shift 2
            ;;
        --validator)
            [ "$#" -ge 2 ] || { echo "--validator requires a value" >&2; exit 2; }
            VALIDATOR=$2
            shift 2
            ;;
        --server-addr)
            [ "$#" -ge 2 ] || { echo "--server-addr requires a value" >&2; exit 2; }
            SERVER_ADDR=$2
            shift 2
            ;;
        --node-id)
            [ "$#" -ge 2 ] || { echo "--node-id requires a value" >&2; exit 2; }
            NODE_ID=$2
            shift 2
            ;;
        --node-key)
            [ "$#" -ge 2 ] || { echo "--node-key requires a value" >&2; exit 2; }
            NODE_KEY=$2
            shift 2
            ;;
        --tap-name)
            [ "$#" -ge 2 ] || { echo "--tap-name requires a value" >&2; exit 2; }
            TAP_NAME=$2
            shift 2
            ;;
        --mtu)
            [ "$#" -ge 2 ] || { echo "--mtu requires a value" >&2; exit 2; }
            MTU=$2
            shift 2
            ;;
        --bridge-name)
            [ "$#" -ge 2 ] || { echo "--bridge-name requires a value" >&2; exit 2; }
            BRIDGE_CHECK_NAME=$2
            shift 2
            ;;
        --preflight-on-start)
            [ "$#" -ge 2 ] || { echo "--preflight-on-start requires a value" >&2; exit 2; }
            PREFLIGHT_ON_START=$2
            shift 2
            ;;
        --log-level)
            [ "$#" -ge 2 ] || { echo "--log-level requires a value" >&2; exit 2; }
            LOG_LEVEL=$2
            shift 2
            ;;
        --log-file)
            [ "$#" -ge 2 ] || { echo "--log-file requires a value" >&2; exit 2; }
            LOG_FILE=$2
            shift 2
            ;;
        --enable)
            ENABLE_SERVICE=1
            shift
            ;;
        --start)
            START_SERVICE=1
            shift
            ;;
        --run-validator)
            RUN_VALIDATOR=1
            shift
            ;;
        --strict-service)
            STRICT_SERVICE=1
            shift
            ;;
        --report)
            [ "$#" -ge 2 ] || { echo "--report requires a value" >&2; exit 2; }
            REPORT=$2
            shift 2
            ;;
        --skip-config)
            SKIP_CONFIG=1
            shift
            ;;
        --skip-preflight)
            SKIP_PREFLIGHT=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
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

say() {
    printf '%s\n' "$*"
}

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        say "DRY-RUN: $*"
    else
        "$@"
    fi
}

set_uci() {
    key=$1
    value=$2
    shown=$value
    [ "$key" = "node_key" ] && shown="<masked>"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "DRY-RUN: uci set ntap-b.node.$key='$shown'"
    else
        uci set "ntap-b.node.$key=$value"
    fi
}

if [ -z "$PACKAGE" ]; then
    echo "--package is required" >&2
    usage >&2
    exit 2
fi

if [ ! -f "$PACKAGE" ] && [ "$DRY_RUN" -ne 1 ]; then
    echo "missing package: $PACKAGE" >&2
    exit 1
fi

if [ "$SKIP_CONFIG" -ne 1 ]; then
    if [ -z "$SERVER_ADDR" ] || [ -z "$NODE_ID" ] || [ -z "$NODE_KEY" ]; then
        echo "--server-addr, --node-id, and --node-key are required unless --skip-config is used" >&2
        exit 2
    fi
fi

say "NTAP-B OpenWrt package install"
say "Package=$PACKAGE"
say "ServerAddr=$SERVER_ADDR"
say "NodeId=$NODE_ID"
say "NodeKey=<masked>"
say "TapName=$TAP_NAME"
say "BridgeCheckName=$BRIDGE_CHECK_NAME"

case "$PACKAGE" in
    *.apk)
        if ! command -v apk >/dev/null 2>&1 && [ "$DRY_RUN" -ne 1 ]; then
            echo "apk command not found on target" >&2
            exit 1
        fi
        run apk add --allow-untrusted "$PACKAGE"
        ;;
    *.ipk)
        if ! command -v opkg >/dev/null 2>&1 && [ "$DRY_RUN" -ne 1 ]; then
            echo "opkg command not found on target" >&2
            exit 1
        fi
        run opkg install "$PACKAGE"
        ;;
    *)
        echo "unsupported package type: $PACKAGE" >&2
        exit 2
        ;;
esac

if [ "$SKIP_CONFIG" -ne 1 ]; then
    if ! command -v uci >/dev/null 2>&1 && [ "$DRY_RUN" -ne 1 ]; then
        echo "uci command not found on target" >&2
        exit 1
    fi
    set_uci enabled 1
    set_uci server_addr "$SERVER_ADDR"
    set_uci node_id "$NODE_ID"
    set_uci node_key "$NODE_KEY"
    set_uci tap_name "$TAP_NAME"
    set_uci mtu "$MTU"
    set_uci bridge_check_name "$BRIDGE_CHECK_NAME"
    set_uci preflight_on_start "$PREFLIGHT_ON_START"
    set_uci log_level "$LOG_LEVEL"
    set_uci log_file "$LOG_FILE"
    run uci commit ntap-b
fi

if [ "$SKIP_PREFLIGHT" -ne 1 ]; then
    run /etc/init.d/ntap-b check
fi

if [ "$ENABLE_SERVICE" -eq 1 ]; then
    run /etc/init.d/ntap-b enable
fi

if [ "$START_SERVICE" -eq 1 ]; then
    run /etc/init.d/ntap-b start
fi

if [ "$RUN_VALIDATOR" -eq 1 ]; then
    if [ -z "$VALIDATOR" ]; then
        echo "--validator is required with --run-validator" >&2
        exit 2
    fi
    if [ ! -f "$VALIDATOR" ] && [ "$DRY_RUN" -ne 1 ]; then
        echo "missing validator: $VALIDATOR" >&2
        exit 1
    fi

    validator_args="--report $REPORT"
    if [ -n "$BRIDGE_CHECK_NAME" ]; then
        validator_args="$validator_args --bridge-name $BRIDGE_CHECK_NAME"
    fi
    if [ "$STRICT_SERVICE" -eq 1 ]; then
        validator_args="$validator_args --strict-service"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        say "DRY-RUN: sh $VALIDATOR $validator_args"
    else
        # shellcheck disable=SC2086
        sh "$VALIDATOR" $validator_args
    fi
fi

say "OpenWrt install flow complete."
