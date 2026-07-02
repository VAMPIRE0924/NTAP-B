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
```

OpenWrt target-SDK `.ipk` compilation, bridge automation, DHCP validation, and
device-size reporting on the selected hardware target remain later-phase work.
