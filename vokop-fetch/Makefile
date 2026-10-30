VOKOP_SOURCE_ROOT:=$(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
include $(TOPDIR)/rules.mk
PKG_NAME:=vokop-fetch
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later
PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
GO_PKG:=vokop/fetch
include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/vokop-fetch
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Vokop marked HTTPS subscription fetcher
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(VOKOP_SOURCE_ROOT)/tools/vokop-fetch/. $(PKG_BUILD_DIR)/
endef

define Package/vokop-fetch/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/fetch $(1)/usr/bin/vokop-fetch
endef
$(eval $(call GoBinPackage,vokop-fetch))
$(eval $(call BuildPackage,vokop-fetch))
