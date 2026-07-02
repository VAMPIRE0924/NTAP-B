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
```

OpenWrt procd packaging, bridge automation, DHCP validation, and device-size
reporting remain later-phase work.
