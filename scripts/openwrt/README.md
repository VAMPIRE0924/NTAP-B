# scripts/openwrt

OpenWrt package support for NTAP-B.

Contents:

```text
package/ntap-b/Makefile        OpenWrt SDK package Makefile
package/ntap-b/files/          procd init script and default UCI config
prepare-ntap-b-package.ps1     Windows helper: stage SDK package + local size baseline
build-ntap-b-sdk.sh            Linux/WSL helper: stage and optionally build in an SDK
```

Use `prepare-ntap-b-package.ps1` without an SDK to verify the package staging
and local x64 size baseline. The report is written to
`_release/openwrt/ntap-b-size-report.txt`.

Runtime bridge behavior is controlled by NTAP-A node config. When A sends a
non-empty `bridge_name` in CONFIG_PUSH, NTAP-B attaches its TAP interface to
that Linux bridge and exits clearly if the bridge is missing.

Set `OPENWRT_SDK` or pass `-SdkPath` after the target device architecture is
selected. The Linux/WSL helper can then copy the package into the SDK, build an
actual `.ipk`, and append the final package size to the report.
