VOKOP_SOURCE_ROOT:=$(abspath $(dir $(realpath $(lastword $(MAKEFILE_LIST))))/..)
include $(TOPDIR)/rules.mk
PKG_NAME:=vokop-fetch
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later
PKG_BUILD_DEPENDS:=$(if $(VOKOP_GO_ROOT),,golang/host)
PKG_BUILD_PARALLEL:=1
GO_PKG:=vokop/fetch
include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

# Pure-Go static binaries: the SDK default external linker requires cgo.
GO_PKG_VARS += CGO_ENABLED=0 GOFLAGS="-buildvcs=false"
GO_PKG_DEFAULT_LDFLAGS:=-buildid $(SOURCE_DATE_EPOCH) -linkmode internal
# Optional preinstalled official Go >= 1.25.5 for SDK feeds with older Go.
ifneq ($(VOKOP_GO_ROOT),)
GO_PKG_VARS += PATH="$(VOKOP_GO_ROOT)/bin:$(PATH)"
endif

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
