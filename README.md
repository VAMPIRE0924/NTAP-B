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
    scripts/openwrt/  OpenWrt package, UCI, procd, SDK, and device validation helpers
    docs/             OpenWrt staging and SDK notes

## OpenWrt

Stage the OpenWrt package and host-size baseline without committing generated
output:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\openwrt\prepare-ntap-b-package.ps1

Build the final OpenWrt .apk or .ipk only after the target architecture is
selected and the matching OpenWrt SDK is available:

OPENWRT_SDK=/path/to/openwrt-sdk sh scripts/openwrt/build-ntap-b-sdk.sh
OPENWRT_SDK=/path/to/openwrt-sdk sh scripts/openwrt/verify-package.sh _release/openwrt/package-output/ntap-b-0.1-r1.apk

After installing the compiled package on the target, run the device validator:

    sh scripts/openwrt/device-validate.sh --bridge-name br-lan --strict-service

Release assets also include an OpenWrt target install helper that can install
the package, write UCI node config, preflight, enable/start procd, and run the
validator:

    sh /tmp/NTAP-B-<version>-openwrt-install.sh --package /tmp/NTAP-B-<version>-openwrt-ntap-b-0.1-r1.apk --server-addr '<ntap-a-host>:8024' --node-id '<node-id-from-ntap-a>' --node-key '<node-key-from-ntap-a>' --bridge-name br-lan --enable --start --run-validator --validator /tmp/NTAP-B-<version>-openwrt-device-validate.sh --strict-service

From the integration workspace, scripts/openwrt/deploy-remote.ps1 can copy the
compiled release assets to a reachable OpenWrt target over SSH/SCP, run the
install helper, and fetch the device validation report. Prefer NTAP_NODE_KEY or
NodeKeyFile so the node key does not have to be typed into the command line.

At runtime, NTAP-A controls TAP bridge attachment through the node
bridge_name field carried in CONFIG_PUSH.

On OpenWrt, /etc/init.d/ntap-b check runs the local preflight. Optional UCI
settings bridge_check_name and preflight_on_start only affect local deployment
checks; runtime bridge attachment still comes from NTAP-A.