include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-vokop

VOKOP_SOURCE_VERSION:=$(or $(VOKOP_PACKAGE_VERSION),$(VOKOP_VERSION))
VOKOP_HAS_RELEASE_VERSION:=$(if $(filter dev,$(VOKOP_SOURCE_VERSION)),,$(VOKOP_SOURCE_VERSION))
VOKOP_COMPILED_VERSION:=$(if $(VOKOP_HAS_RELEASE_VERSION),$(VOKOP_SOURCE_VERSION),$(or $(VOKOP_SOURCE_VERSION),dev))
VOKOP_RELEASE_VERSION_VALID:=$(if $(VOKOP_HAS_RELEASE_VERSION),$(shell printf '%s\n' '$(VOKOP_SOURCE_VERSION)' | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' && printf '1'),1)

ifeq ($(VOKOP_RELEASE_VERSION_VALID),)
$(error VOKOP_PACKAGE_VERSION and VOKOP_VERSION must use x.y.z format)
endif

PKG_VERSION:=$(or $(VOKOP_HAS_RELEASE_VERSION),0.0.0)
PKG_RELEASE:=
PKG_PO_VERSION:=$(PKG_VERSION)

LUCI_TITLE:=LuCI Vokop app
LUCI_DEPENDS:=+luci-base +vokop
LUCI_PKGARCH:=all
LUCI_LANG.ru:=Русский (Russian)
LUCI_LANG.en:=English
LUCI_MAINTAINER:=Vokop contributors
LUCI_DESCRIPTION:=Rule-based Vokop LuCI app with hybrid sing-box + zapret orchestration
LUCI_MINIFY_JS:=0

PKG_LICENSE:=GPL-2.0-or-later
LUCI_LANGUAGES:=en ru

define Build/Prepare/$(PKG_NAME)
	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(VOKOP_COMPILED_VERSION)/g' $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/vokop/main.js
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
