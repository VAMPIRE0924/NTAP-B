# NTAP-B

NTAP-B 是部署在 OpenWrt 或 Linux 网关上的节点客户端。它连接 NTAP-A，完成节点鉴权，创建本地 TAP 设备，并按 NTAP-A 下发的 `bridge_name` 把 TAP 接入本地网桥，例如 `br-lan`。

NTAP-B 的设计目标是轻量、可交互安装、适合 OpenWrt 小内存设备。Web 管理和复杂策略不放在 B 端，统一由 NTAP-A 管理。

## 下载和部署

正式部署请下载 GitHub Release 里的编译产物，不要直接拿源码目录里的临时构建文件部署。

最新版本：

https://github.com/VAMPIRE0924/NTAP-B/releases/latest

OpenWrt 客户侧部署通常需要复制这几个文件到目标设备 `/tmp`：

```text
NTAP-B-<version>-openwrt-ntap-b-0.1-r1.apk
NTAP-B-<version>-openwrt-install.sh
NTAP-B-<version>-openwrt-device-validate.sh
NTAP-B-<version>-openwrt-RUNNING.txt
NTAP-B-<version>-openwrt-METADATA.txt
```

客户友好的安装方式：

```sh
sh /tmp/NTAP-B-<version>-openwrt-install.sh --interactive
```

脚本会依次询问：

- OpenWrt 包路径
- NTAP-A 地址
- Node ID
- Node Key
- TAP 名称
- 网桥预检名称，通常是 `br-lan`
- 是否启用和启动服务
- 是否运行设备验证脚本

自动化部署可以使用长命令：

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

安装后可以单独运行验证：

```sh
sh /tmp/NTAP-B-<version>-openwrt-device-validate.sh --bridge-name br-lan --strict-service
```

## 运行方式

OpenWrt 包安装后会提供：

```text
/usr/sbin/ntap-b
/etc/config/ntap-b
/etc/init.d/ntap-b
```

常用命令：

```sh
/etc/init.d/ntap-b check
/etc/init.d/ntap-b enable
/etc/init.d/ntap-b start
logread -f | grep ntap-b
```

`bridge_check_name` 只用于本地安装前预检；真正运行时是否挂接网桥，以 NTAP-A 下发的 `CONFIG_PUSH bridge_name` 为准。

## 源码构建

普通 Linux 开发验证：

```sh
make
make config-test
```

OpenWrt 包构建请使用匹配目标架构的 OpenWrt SDK：

```sh
OPENWRT_SDK=/path/to/openwrt-sdk sh scripts/openwrt/build-ntap-b-sdk.sh
OPENWRT_SDK=/path/to/openwrt-sdk sh scripts/openwrt/verify-package.sh _release/openwrt/package-output/ntap-b-0.1-r1.apk
```

## 目录

```text
src/b/          NTAP-B 节点客户端源码
src/common/     三端共享协议、日志、网络、时间、buffer 等公共代码
conf/           最小配置示例
scripts/openwrt OpenWrt 包、UCI、procd、SDK 构建和设备验证脚本
docs/openwrt.md OpenWrt 构建和设备验证说明
Makefile        单仓库构建入口
```

## 部署注意

- OpenWrt 目标需要 `/dev/net/tun`、`kmod-tun` 和 OpenSSL 运行库。
- 16MB/32MB flash 设备要确认剩余空间和依赖包来源。
- Node Key 不应写进公开日志或截图；安装脚本输出会做掩码。
- Release 包和源码提交是两条线：源码仓库保持干净，编译产物只放 GitHub Release。
