# NTAP-B

NTAP-B is the NTAP node side. It runs at the customer gateway or internal host, connects to NTAP-A, authenticates as a node, creates the local TAP device, and joins the local network according to configuration delivered by NTAP-A.

NTAP-B is designed to stay small and simple. Management and policy decisions belong to NTAP-A; B should focus on node connectivity and local network attachment.

## Repository Set

NTAP is split into three clean source repositories. Deployable packages are published only through each repository's GitHub Releases.

- [NTAP-A](https://github.com/VAMPIRE0924/NTAP-A): public server, management API, SQLite state, node/TAP authentication, and TapHub relay.
- [NTAP-B](https://github.com/VAMPIRE0924/NTAP-B): node side, installed at the customer gateway or internal host, connects to A, and joins the local network.
- [NTAP-C](https://github.com/VAMPIRE0924/NTAP-C): client side, with a Windows GUI for customers and a Linux command-line entry point.

## Download And Deploy

Use the final packages from GitHub Releases. Do not deploy temporary files from a source checkout.

Latest release:

https://github.com/VAMPIRE0924/NTAP-B/releases/latest

A customer-side node deployment usually uses these release assets:

- node package
- interactive install script
- device validation script
- running notes

Customer-friendly install:

```sh
sh /tmp/<NTAP-B-install-script> --interactive
```

The interactive installer asks for:

- node package path
- NTAP-A address
- Node ID
- Node Key
- TAP name
- bridge preflight name, usually `br-lan`
- whether to enable and start the service
- whether to run device validation

Automation can use the non-interactive parameters documented in the release running notes. Do not expose Node Key in public logs or screenshots; installer output masks it.

## Runtime

After installation, the node package provides a local service entry and config file. Common operations:

```sh
/etc/init.d/ntap-b check
/etc/init.d/ntap-b enable
/etc/init.d/ntap-b start
```

The local bridge preflight setting is only an installation check. Runtime bridge attachment follows the `CONFIG_PUSH bridge_name` value delivered by NTAP-A.

## Source Scope

```text
src/b/       NTAP-B node source
src/common/  shared protocol and utility source
conf/        minimal example config
```

This repository keeps only source code, example config, README, and LICENSE. Final deployable packages live in GitHub Releases.

## License

GPL-3.0-only. See `LICENSE`.
