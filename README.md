# NTAP-B

OpenWrt/Linux node client with AUTH_NODE, CONFIG_PUSH, heartbeat, TAP relay, A-controlled Linux bridge attach, SOCKS egress, and direct TAP relay.

This repository is exported from the NTAP integration workspace. Keep git
history source-only: do not commit build output, runtime databases, logs, or
generated release archives. Final release packages belong in GitHub Releases.

## Build

    make
    make config-test

## Layout

    src/common/  shared protocol and helpers
    src/b/  component source
    conf/        minimal example config
    scripts/openwrt/  OpenWrt package, UCI, procd, and SDK staging helpers
    docs/             OpenWrt staging and SDK notes

## OpenWrt

Stage the OpenWrt package and host-size baseline without committing generated
output:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\openwrt\prepare-ntap-b-package.ps1

Build the final .ipk only after the target architecture is selected and the
matching OpenWrt SDK is available:

    OPENWRT_SDK=/path/to/openwrt-sdk sh scripts/openwrt/build-ntap-b-sdk.sh

At runtime, NTAP-A controls TAP bridge attachment through the node
ridge_name field carried in CONFIG_PUSH.