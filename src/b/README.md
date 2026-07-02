# src/b

NTAP-B OpenWrt/Linux node client.

Current implemented scope:

```text
AUTH_NODE
PING/PONG reconnect loop
CONFIG_PUSH consumption before TAP setup
Linux TAP open/read/write relay path
environment self-check for Linux TAP prerequisites
synthetic TAP_FRAME smoke helpers
SOCKS stream target TCP connect plus bidirectional DATA/CLOSE relay
direct listener from CONFIG_PUSH direct_enabled/direct_port with short-lived token validation
direct TAP_FRAME relay between authenticated direct clients and local Linux TAP
OpenWrt package skeleton, default UCI config, procd init script, and SDK staging helpers
CONFIG_PUSH bridge_name consumption with Linux TAP bridge attach and clear missing-bridge errors
bridge-side DHCP netns validation for NTAP-C lease acquisition through NTAP-B bridged TAP
```

Deployment preflight:

```sh
ntap-b check-env
ntap-b check-env --bridge-name br-lan
```

The second command creates a temporary TAP probe and attaches it to the named
Linux bridge, then closes the probe. Use it before enabling a node `bridge_name`
in NTAP-A.

OpenWrt target-SDK `.ipk` compilation, hardware/rootfs br-lan DHCP repeat
validation, and device-size reporting on the selected hardware target remain
later-phase work.
