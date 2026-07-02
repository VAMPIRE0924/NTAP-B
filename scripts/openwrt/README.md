# scripts/openwrt

OpenWrt package support for NTAP-B.

Contents:

```text
package/ntap-b/Makefile        OpenWrt SDK package Makefile
package/ntap-b/files/          procd init script and default UCI config
prepare-ntap-b-package.ps1     Windows helper: stage SDK package + local size baseline
build-ntap-b-sdk.sh            Linux/WSL helper: stage and optionally build in an SDK
fetch-sdk.sh                   Linux/WSL helper: download and verify a selected OpenWrt SDK
fetch-sdk.ps1                  Windows wrapper for fetch-sdk.sh
verify-package.sh              Linux/WSL helper: inspect ntap-b .apk/.ipk metadata and payload
device-validate.sh             OpenWrt target helper: verify installed package, TAP, UCI, and service state
install-package.sh             OpenWrt target helper: install package, write UCI config, preflight, and start service
```

Use `prepare-ntap-b-package.ps1` without an SDK to verify the package staging
and local x64 size baseline. The report is written to
`_release/openwrt/ntap-b-size-report.txt`.

Runtime bridge behavior is controlled by NTAP-A node config. When A sends a
non-empty `bridge_name` in CONFIG_PUSH, NTAP-B attaches its TAP interface to
that Linux bridge and exits clearly if the bridge is missing.

Preflight a target bridge before enabling it in NTAP-A:

```sh
ntap-b check-env --bridge-name br-lan
/etc/init.d/ntap-b check
```

The init script reads optional UCI settings `bridge_check_name` and
`preflight_on_start`. They only control local deployment preflight; runtime
bridge attachment is still controlled by NTAP-A CONFIG_PUSH.

Set `OPENWRT_SDK` after the target device architecture is selected. The
Linux/WSL helper can then copy the package into the SDK, build an actual
OpenWrt package (`.apk` on newer OpenWrt, `.ipk` on older releases), copy it to
`_release/openwrt/package-output/`, and append the final package size to the
report.

Fetch a known target SDK through WSL, then build the package against it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\openwrt\fetch-sdk.ps1 -Version 25.12.5 -Target x86 -Subtarget 64
```

Use `-WslDistro <name>` if the target machine uses a different WSL
distribution name.

```sh
SDK=$(OPENWRT_VERSION=25.12.5 OPENWRT_TARGET=x86 OPENWRT_SUBTARGET=64 sh scripts/openwrt/fetch-sdk.sh)
OPENWRT_SDK="$SDK" sh scripts/openwrt/build-ntap-b-sdk.sh
```

The SDK build helper defaults to a GitHub mirror for OpenWrt feeds because
`git.openwrt.org` can be unstable from WSL. Set
`OPENWRT_FEED_GITHUB_MIRROR=0` to keep the feed URLs from the SDK.

Verify the generated package metadata and payload paths:

```sh
OPENWRT_SDK="$SDK" sh scripts/openwrt/verify-package.sh _release/openwrt/package-output/ntap-b-0.1-r1.apk
```

After installing the compiled package on the OpenWrt target, copy the release
validator asset to `/tmp/` and run it on the device:

```sh
sh /tmp/NTAP-B-<version>-openwrt-device-validate.sh --bridge-name br-lan
sh /tmp/NTAP-B-<version>-openwrt-device-validate.sh --bridge-name br-lan --strict-service
```

The report defaults to `/tmp/ntap-b-device-validation.txt`. The script masks
`node_key` when it records UCI settings.

For a target-side install flow, copy the package, install helper, and validator
release assets to `/tmp/`, then run:

```sh
sh /tmp/NTAP-B-<version>-openwrt-install.sh \
  --package /tmp/NTAP-B-<version>-openwrt-ntap-b-0.1-r1.apk \
  --server-addr '<ntap-a-host>:8024' \
  --node-id '<node-id-from-ntap-a>' \
  --node-key '<node-key-from-ntap-a>' \
  --bridge-name br-lan \
  --enable --start \
  --run-validator \
  --validator /tmp/NTAP-B-<version>-openwrt-device-validate.sh \
  --strict-service
```
