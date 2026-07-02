# OpenWrt Notes

NTAP-B is the only component that targets OpenWrt in the current landing plan.
Deployment should use the compiled package or binary artifact, not the
integration workspace. The OpenWrt package follows the standard SDK package
layout with a package Makefile plus `files/etc/config` and `files/etc/init.d`
service files.

## Implemented

```text
scripts/openwrt/package/ntap-b/Makefile
scripts/openwrt/package/ntap-b/files/etc/config/ntap-b
scripts/openwrt/package/ntap-b/files/etc/init.d/ntap-b
scripts/openwrt/prepare-ntap-b-package.ps1
scripts/openwrt/build-ntap-b-sdk.sh
scripts/openwrt/fetch-sdk.sh
scripts/openwrt/fetch-sdk.ps1
```

The current package keeps NTAP-B small: it links OpenSSL/libcrypto, requires
`kmod-tun`, and does not link SQLite, Web UI, or `ip-full` dependencies.
NTAP-A owns the runtime `bridge_name` setting through node config and
CONFIG_PUSH. When `bridge_name` is non-empty, NTAP-B attaches the opened TAP
interface to that Linux bridge and fails clearly if the bridge is missing.
The integration workspace verifies this with
`scripts/smoke-phase2-bridge-netns.sh`. It also verifies the DHCP shape with
`scripts/smoke-phase2-bridge-dhcp-netns.sh`: dnsmasq runs behind NTAP-B's
bridge, NTAP-C receives a DHCP lease through the NTAP TAP relay, and the
leased TAP address can ping the bridge gateway.

Run this on a target-like Linux/OpenWrt shell before enabling bridge mode to
preflight TAP privileges and the bridge attach path:

```sh
ntap-b check-env --bridge-name br-lan
```

When installed as an OpenWrt service, the same check is exposed through init.d:

```sh
/etc/init.d/ntap-b check
uci set ntap-b.node.bridge_check_name='br-lan'
uci set ntap-b.node.preflight_on_start='1'
uci commit ntap-b
```

`bridge_check_name` is only a local deployment preflight target. Runtime bridge
attachment still comes from NTAP-A node config through CONFIG_PUSH.

Run this on Windows to stage the package and write a local Linux size baseline:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\openwrt\prepare-ntap-b-package.ps1
```

Run this in Linux/WSL to stage the package, or to build it when `OPENWRT_SDK`
points at the selected target SDK:

```sh
sh scripts/openwrt/build-ntap-b-sdk.sh
OPENWRT_SDK=/path/to/openwrt-sdk sh scripts/openwrt/build-ntap-b-sdk.sh
```

Fetch a selected SDK through WSL when the target is known. This default is only
an x86_64 toolchain smoke; replace version/target/subtarget for the real device:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\openwrt\fetch-sdk.ps1 -Version 25.12.5 -Target x86 -Subtarget 64
```

```sh
SDK=$(OPENWRT_VERSION=25.12.5 OPENWRT_TARGET=x86 OPENWRT_SUBTARGET=64 sh scripts/openwrt/fetch-sdk.sh)
OPENWRT_SDK="$SDK" sh scripts/openwrt/build-ntap-b-sdk.sh
```

The report is written to `_release/openwrt/ntap-b-size-report.txt`. Without a
target SDK, it records the host Linux binary size and marks the OpenWrt package
build as skipped.

The current x86/64 SDK smoke builds
`_release/openwrt/package-output/ntap-b-0.1-r1.apk` and records a package size
of 25,984 bytes. This proves the build chain, not the final device target.

## Pending

```text
select target device architecture
install matching OpenWrt SDK or ImageBuilder
compile ntap-b as a target musl package (.apk on newer OpenWrt, .ipk on older releases)
record final package size
validate on OpenWrt rootfs or hardware
repeat br-lan DHCP behavior on OpenWrt hardware/rootfs
run 24-hour device stability test
```
