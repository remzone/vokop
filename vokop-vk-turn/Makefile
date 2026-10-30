# SPDX-License-Identifier: GPL-3.0-or-later
# Keep this package directory beside transport/ when adding the repository feed.
VOKOP_SOURCE_ROOT:=$(abspath $(dir $(realpath $(lastword $(MAKEFILE_LIST))))/..)

include $(TOPDIR)/rules.mk

PKG_NAME:=vokop-vk-turn
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_SOURCE_VERSION:=e8a96967dc66f3dbd631596ea6a8b9fe03f9be69
PKG_LICENSE:=GPL-3.0-only MIT
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_DEPENDS:=$(if $(VOKOP_GO_ROOT),,golang/host)
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/cacggghp/vk-turn-proxy
GO_PKG_BUILD_PKG:=$(GO_PKG)/client
GO_PKG_TAGS:=netgo osusergo

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

# Pure-Go static binaries: the SDK default external linker requires cgo.
GO_PKG_VARS += CGO_ENABLED=0 GOFLAGS="-buildvcs=false"
GO_PKG_DEFAULT_LDFLAGS:=-buildid $(SOURCE_DATE_EPOCH) -linkmode internal
# Optional preinstalled official Go >= 1.25.5 for SDK feeds with older Go.
ifneq ($(VOKOP_GO_ROOT),)
GO_PKG_VARS += PATH="$(VOKOP_GO_ROOT)/bin:$(PATH)"
endif

define Package/vokop-vk-turn
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Vokop patched VK TURN transport
  URL:=https://github.com/cacggghp/vk-turn-proxy
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle
endef

define Package/vokop-vk-turn/description
  Pinned VK TURN VLESS sidecar with mandatory WAN socket marks and unattended
  CAPTCHA handling. Managed by Vokop; does not enable services on installation.
  Requires a Go host toolchain compatible with source go.mod (Go 1.25.5+).
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	$(CP) $(VOKOP_SOURCE_ROOT)/transport/vk-turn-proxy/. $(PKG_BUILD_DIR)/
endef

define Package/vokop-vk-turn/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/client $(1)/usr/bin/vokop-vk-client
	$(INSTALL_DIR) $(1)/usr/share/licenses/vokop-vk-turn
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE $(1)/usr/share/licenses/vokop-vk-turn/LICENSE
endef

$(eval $(call GoBinPackage,vokop-vk-turn))
$(eval $(call BuildPackage,vokop-vk-turn))
