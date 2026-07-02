# NTAP-B

OpenWrt/Linux node client with AUTH_NODE, CONFIG_PUSH, heartbeat, TAP relay, SOCKS egress, and direct TAP relay.

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