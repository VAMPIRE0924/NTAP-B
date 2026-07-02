include $(TOPDIR)/rules.mk

PKG_NAME:=ntap-b
PKG_VERSION:=0.1
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/ntap-b
  SECTION:=net
  CATEGORY:=Network
  TITLE:=NTAP-B TAP node client
  DEPENDS:=+libopenssl +kmod-tun
endef

define Package/ntap-b/description
  NTAP-B is the lightweight OpenWrt/Linux node client. It connects to NTAP-A,
  consumes CONFIG_PUSH, bridges a local TAP device, and provides SOCKS/direct
  egress without SQLite or Web UI dependencies.
endef

NTAP_COMMON_SRCS := \
	src/common/buffer.c \
	src/common/config.c \
	src/common/direct_token.c \
	src/common/hash.c \
	src/common/log.c \
	src/common/net.c \
	src/common/proto.c \
	src/common/tap_linux.c \
	src/common/time.c \
	src/common/wire.c

NTAP_B_SRCS := \
	src/b/config.c \
	src/b/control_client.c \
	src/b/env_check.c \
	src/b/main.c

define Build/Prepare
	$(RM) -r $(PKG_BUILD_DIR)
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/src/common
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/src/b
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/conf
	$(CP) ./src/common/* $(PKG_BUILD_DIR)/src/common/
	$(CP) ./src/b/* $(PKG_BUILD_DIR)/src/b/
	$(CP) ./conf/ntap-b.conf.example $(PKG_BUILD_DIR)/conf/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS) \
		-Isrc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror \
		$(patsubst %,$(PKG_BUILD_DIR)/%,$(NTAP_COMMON_SRCS)) \
		$(patsubst %,$(PKG_BUILD_DIR)/%,$(NTAP_B_SRCS)) \
		$(TARGET_LDFLAGS) -lcrypto -pthread \
		-o $(PKG_BUILD_DIR)/ntap-b
endef

define Package/ntap-b/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ntap-b $(1)/usr/sbin/ntap-b
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/ntap-b $(1)/etc/init.d/ntap-b
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/ntap-b $(1)/etc/config/ntap-b
	$(INSTALL_DIR) $(1)/etc/ntap
	$(INSTALL_CONF) ./conf/ntap-b.conf.example $(1)/etc/ntap/ntap-b.conf.example
endef

$(eval $(call BuildPackage,ntap-b))
