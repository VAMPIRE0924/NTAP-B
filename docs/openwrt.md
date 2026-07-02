# OpenWrt Notes

NTAP-B is the only component that targets OpenWrt in the current landing plan.
The OpenWrt package follows the standard SDK package layout with a package
Makefile plus `files/etc/config` and `files/etc/init.d` service files.

## Implemented

```text
scripts/openwrt/package/ntap-b/Makefile
scripts/openwrt/package/ntap-b/files/etc/config/ntap-b
scripts/openwrt/package/ntap-b/files/etc/init.d/ntap-b
scripts/openwrt/prepare-ntap-b-package.ps1
scripts/openwrt/build-ntap-b-sdk.sh
```

The current package keeps NTAP-B small: it links OpenSSL/libcrypto, requires
`kmod-tun` and `ip-full`, and does not link SQLite or Web UI dependencies.

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

The report is written to `_release/openwrt/ntap-b-size-report.txt`. Without a
target SDK, it records the host Linux binary size and marks the OpenWrt `.ipk`
build as skipped.

## Pending

```text
select target device architecture
install matching OpenWrt SDK or ImageBuilder
compile ntap-b as a target musl .ipk
record final .ipk size
validate on OpenWrt rootfs or hardware
bridge ntap-b TAP into br-lan
run 24-hour device stability test
```
