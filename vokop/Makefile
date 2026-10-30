include $(TOPDIR)/rules.mk

PKG_NAME:=vokop

VOKOP_SOURCE_VERSION:=$(or $(VOKOP_PACKAGE_VERSION),$(VOKOP_VERSION))
VOKOP_HAS_RELEASE_VERSION:=$(if $(filter dev,$(VOKOP_SOURCE_VERSION)),,$(VOKOP_SOURCE_VERSION))
VOKOP_COMPILED_VERSION:=$(if $(VOKOP_HAS_RELEASE_VERSION),$(VOKOP_SOURCE_VERSION),$(or $(VOKOP_SOURCE_VERSION),dev))
VOKOP_RELEASE_VERSION_VALID:=$(if $(VOKOP_HAS_RELEASE_VERSION),$(shell printf '%s\n' '$(VOKOP_SOURCE_VERSION)' | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' && printf '1'),1)

ifeq ($(VOKOP_RELEASE_VERSION_VALID),)
$(error VOKOP_PACKAGE_VERSION and VOKOP_VERSION must use x.y.z format)
endif

PKG_VERSION:=$(or $(VOKOP_HAS_RELEASE_VERSION),0.0.0)
PKG_RELEASE:=

PKG_MAINTAINER:=Vokop contributors
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/vokop
	SECTION:=net
	CATEGORY:=Network
	DEPENDS:=+vokop-fetch +vokop-vk-turn +ca-bundle +kmod-inet-diag +kmod-netlink-diag +kmod-tun +curl +ucode +ucode-mod-fs +ucode-mod-uci +kmod-nft-tproxy +coreutils-base64 +bind-dig +nftables +kmod-nft-nat +ip-full
	CONFLICTS:=podkop luci-app-podkop forkop luci-app-forkop https-dns-proxy nextdns luci-app-passwall luci-app-passwall2
	TITLE:=Vokop backend service
	URL:=https://github.com/remzone/vokop
	PKGARCH:=all
endef

define Package/vokop/description
	Rule-based Vokop backend with hybrid sing-box + zapret orchestration
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/vokop/prerm
#!/usr/bin/ucode

if (getenv("IPKG_INSTROOT") == null || getenv("IPKG_INSTROOT") == "")
	system("/usr/bin/vokop package_prerm " + (ARGV[0] || "") + " >/dev/null 2>&1");

exit(0);
endef

define Package/vokop/postinst
#!/bin/sh

[ -n "$${IPKG_INSTROOT}" ] && exit 0
VOKOP_LIB=/usr/lib/vokop ucode -L /usr/lib/vokop /usr/lib/vokop/config/migration.uc migrate || exit $$?
/usr/bin/vokop package_postinst
endef

define Package/vokop/conffiles
/etc/config/vokop
/etc/config/vokop_management
endef

define Package/vokop/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/vokop $(1)/etc/init.d/vokop
	$(INSTALL_BIN) ./files/etc/init.d/vokop-management $(1)/etc/init.d/vokop-management
	$(INSTALL_BIN) ./files/etc/init.d/vokop-vkturn $(1)/etc/init.d/vokop-vkturn

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/vokop $(1)/etc/config/vokop
	$(INSTALL_CONF) ./files/etc/config/vokop_management $(1)/etc/config/vokop_management

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/vokop $(1)/usr/bin/vokop

	$(INSTALL_DIR) $(1)/usr/lib/vokop
	$(CP) ./files/usr/lib/. $(1)/usr/lib/vokop/

	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(VOKOP_COMPILED_VERSION)/g' $(1)/usr/lib/vokop/core/constants.uc
endef

$(eval $(call BuildPackage,vokop))
