#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VOKOP_BIN="$ROOT_DIR/vokop/files/usr/bin/vokop"
VOKOP_LIB="$ROOT_DIR/vokop/files/usr/lib"
PACKAGE_UC="$VOKOP_LIB/service/package.uc"
VOKOP_MAKEFILE="$ROOT_DIR/vokop/Makefile"
LUCI_UCI_DEFAULTS="$ROOT_DIR/luci-app-vokop/root/etc/uci-defaults/50_luci-vokop"
BUILD_SCRIPT="$ROOT_DIR/build.sh"
WORK_DIR="$(mktemp -d)"
export VOKOP_PACKAGE_UPGRADE_STATE="$WORK_DIR/package-was-running"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -r "$PACKAGE_UC" ] ||
  fail "service/package.uc must own package lifecycle logic"
if grep -n -E 'require\("uci"\)\.cursor|uci -q|uci", "-q"' "$PACKAGE_UC" >/dev/null 2>&1; then
  fail "service/package.uc must use core.uci instead of direct UCI cursor or CLI access"
fi
grep -Fq 'require("core.uci")' "$PACKAGE_UC" ||
  fail "service/package.uc must import core.uci"
grep -Fq 'package_prerm: [ "service/package.uc", "prerm", 1 ]' "$VOKOP_BIN" ||
  fail "vokop entrypoint must dispatch package prerm cleanup through service/package.uc"
grep -Fq 'package_postinst: [ "service/package.uc", "postinst", 0 ]' "$VOKOP_BIN" ||
  fail "vokop entrypoint must dispatch package postinst recovery through service/package.uc"
grep -Fq 'luci_postinst: [ "service/package.uc", "luci-postinst", 0 ]' "$VOKOP_BIN" ||
  fail "vokop entrypoint must dispatch LuCI postinstall cleanup through service/package.uc"
grep -Fq '#!/bin/sh' "$LUCI_UCI_DEFAULTS" ||
  fail "LuCI uci-defaults must remain a shell script because OpenWrt default_postinst runs it through shell"
grep -Fq '/usr/bin/vokop luci_postinst' "$LUCI_UCI_DEFAULTS" ||
  fail "LuCI uci-defaults must delegate cache/rpcd handling to ucode"
if grep -E 'rm -f /var/luci-indexcache|rm -f /tmp/luci-indexcache|logger -t "vokop"' "$LUCI_UCI_DEFAULTS" >/dev/null; then
  fail "LuCI uci-defaults must not own cache/logger shell logic"
fi

if grep -n -E 'grep -q "105 vokop"|sed -i "/105 vokop|vokop_dont_touch_dhcp=.*uci|cp /etc/config/vokop|rm -f /tmp/luci-indexcache|killall -HUP rpcd' "$VOKOP_MAKEFILE" "$BUILD_SCRIPT" >/dev/null; then
  fail "package scripts must not keep backend/LuCI lifecycle business logic in shell"
fi
grep -Fq '#!/usr/bin/ucode' "$VOKOP_MAKEFILE" ||
  fail "vokop Makefile package hooks must use ucode entrypoints"
grep -Fq '/usr/bin/vokop package_prerm' "$VOKOP_MAKEFILE" ||
  fail "vokop Makefile prerm must delegate cleanup to package_prerm"
grep -Fq '/usr/bin/vokop package_postinst' "$VOKOP_MAKEFILE" ||
  fail "vokop Makefile postinst must restore a service that was running before upgrade"
grep -Fq '/usr/bin/vokop package_prerm upgrade' "$BUILD_SCRIPT" ||
  fail "manual APK pre-upgrade must record and stop the running service"
grep -Fq '/usr/bin/vokop package_postinst' "$BUILD_SCRIPT" ||
  fail "manual packages must restore a service that was running before upgrade"
if grep -Fq '/usr/bin/vokop luci_postinst' "$BUILD_SCRIPT"; then
  fail "manual package hooks must let default_postinst run luci_postinst exactly once through uci-defaults"
fi
if grep -n -E 'Package/vokop/preinst|copy_legacy_config|VOKOP_LEGACY_CONFIG|mode == "preinst"' \
  "$VOKOP_MAKEFILE" "$BUILD_SCRIPT" "$PACKAGE_UC" >/dev/null 2>&1; then
  fail "package hooks and runtime service must not own configuration migration"
fi

rt_tables="$WORK_DIR/rt_tables"
cat >"$rt_tables" <<'EOF'
100 main
105 vokop
200 custom
EOF
VOKOP_PACKAGE_TEST_MODE=1 VOKOP_RT_TABLES="$rt_tables" \
  ucode -L "$VOKOP_LIB" "$PACKAGE_UC" prerm
if grep -Fq '105 vokop' "$rt_tables"; then
  fail "package prerm must remove the Vokop routing table entry"
fi
grep -Fq '200 custom' "$rt_tables" ||
  fail "package prerm must preserve unrelated rt_tables entries"

cat >"$WORK_DIR/vokop-init" <<'SH'
#!/usr/bin/env bash
grep -Fq '105 vokop' "${VOKOP_RT_TABLES:?}" || exit 1
printf '%s\n' 'stop-with-route-table' >>"${VOKOP_STOP_LOG:?}"
SH
chmod 0755 "$WORK_DIR/vokop-init"
cat >"$WORK_DIR/stop-order.state" <<'EOF_UCI'
vokop.settings=settings
vokop.settings.dont_touch_dhcp=1
EOF_UCI
printf '105 vokop\n' >"$WORK_DIR/rt_tables_stop_order"
: >"$WORK_DIR/stop-order.log"
VOKOP_UCI_STATE_FILE="$WORK_DIR/stop-order.state" \
VOKOP_INIT="$WORK_DIR/vokop-init" \
VOKOP_STOP_LOG="$WORK_DIR/stop-order.log" \
VOKOP_BIN="$WORK_DIR/missing-vokop-bin" \
VOKOP_DNS_APPLY_UC="$WORK_DIR/missing-dns-apply.uc" \
VOKOP_SING_BOX_INIT="$WORK_DIR/missing-sing-box-init" \
VOKOP_SING_BOX_BIN="$WORK_DIR/missing-sing-box-bin" \
VOKOP_SING_BOX_CRONET="$WORK_DIR/missing-cronet" \
VOKOP_RT_TABLES="$WORK_DIR/rt_tables_stop_order" \
  ucode -L "$VOKOP_LIB" "$PACKAGE_UC" prerm
grep -Fxq 'stop-with-route-table' "$WORK_DIR/stop-order.log" ||
  fail "package prerm must stop Vokop before removing its routing table name"
[ ! -s "$WORK_DIR/rt_tables_stop_order" ] ||
  fail "package prerm must remove the routing table name after Vokop stops"

touch "$WORK_DIR/luci-indexcache.one" "$WORK_DIR/luci-indexcache.two"
VOKOP_PACKAGE_TEST_MODE=1 VOKOP_LUCI_CACHE_GLOBS="$WORK_DIR/luci-indexcache*" \
  ucode -L "$VOKOP_LIB" "$PACKAGE_UC" luci-postinst
if compgen -G "$WORK_DIR/luci-indexcache*" >/dev/null; then
  fail "luci-postinst must remove LuCI index cache files"
fi

cat >"$WORK_DIR/vokop-bin" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${VOKOP_RESTORE_LOG:?}"
SH
chmod 0755 "$WORK_DIR/vokop-bin"

cat >"$WORK_DIR/dont-touch.state" <<'EOF_UCI'
vokop.settings=settings
vokop.settings.dont_touch_dhcp=1
EOF_UCI
printf '105 vokop\n' >"$WORK_DIR/rt_tables_dont_touch"
: >"$WORK_DIR/restore-dont-touch.log"
VOKOP_UCI_STATE_FILE="$WORK_DIR/dont-touch.state" \
VOKOP_RESTORE_LOG="$WORK_DIR/restore-dont-touch.log" \
VOKOP_BIN="$WORK_DIR/vokop-bin" \
VOKOP_DNS_APPLY_UC="$WORK_DIR/missing-dns-apply.uc" \
VOKOP_SING_BOX_INIT="$WORK_DIR/missing-sing-box-init" \
VOKOP_SING_BOX_BIN="$WORK_DIR/missing-sing-box-bin" \
VOKOP_SING_BOX_CRONET="$WORK_DIR/missing-cronet" \
VOKOP_RT_TABLES="$WORK_DIR/rt_tables_dont_touch" \
  ucode -L "$VOKOP_LIB" "$PACKAGE_UC" prerm
[ ! -s "$WORK_DIR/restore-dont-touch.log" ] ||
  fail "package prerm must skip dnsmasq restore when dont_touch_dhcp is enabled"

cat >"$WORK_DIR/restore.state" <<'EOF_UCI'
vokop.settings=settings
vokop.settings.dont_touch_dhcp=0
EOF_UCI
printf '105 vokop\n' >"$WORK_DIR/rt_tables_restore"
: >"$WORK_DIR/restore.log"
VOKOP_UCI_STATE_FILE="$WORK_DIR/restore.state" \
VOKOP_RESTORE_LOG="$WORK_DIR/restore.log" \
VOKOP_BIN="$WORK_DIR/vokop-bin" \
VOKOP_DNS_APPLY_UC="$WORK_DIR/missing-dns-apply.uc" \
VOKOP_SING_BOX_INIT="$WORK_DIR/missing-sing-box-init" \
VOKOP_SING_BOX_BIN="$WORK_DIR/missing-sing-box-bin" \
VOKOP_SING_BOX_CRONET="$WORK_DIR/missing-cronet" \
VOKOP_RT_TABLES="$WORK_DIR/rt_tables_restore" \
  ucode -L "$VOKOP_LIB" "$PACKAGE_UC" prerm
grep -Fxq 'restore_dnsmasq' "$WORK_DIR/restore.log" ||
  fail "package prerm must restore dnsmasq when dont_touch_dhcp is disabled"

cat >"$WORK_DIR/upgrade-init" <<'SH'
#!/usr/bin/env bash
case "$1" in
  status) exit "${VOKOP_FAKE_STATUS:-0}" ;;
  start) printf '%s\n' start >>"${VOKOP_START_LOG:?}" ;;
esac
SH
chmod 0755 "$WORK_DIR/upgrade-init"
: >"$WORK_DIR/upgrade-start.log"
: >"$WORK_DIR/rt_tables_upgrade"
VOKOP_PACKAGE_TEST_MODE=1 \
VOKOP_INIT="$WORK_DIR/upgrade-init" \
VOKOP_START_LOG="$WORK_DIR/upgrade-start.log" \
VOKOP_RT_TABLES="$WORK_DIR/rt_tables_upgrade" \
  ucode -L "$VOKOP_LIB" "$PACKAGE_UC" prerm upgrade
[ -f "$VOKOP_PACKAGE_UPGRADE_STATE" ] ||
  fail "package pre-upgrade must remember a running service"
VOKOP_PACKAGE_TEST_MODE=1 \
VOKOP_INIT="$WORK_DIR/upgrade-init" \
VOKOP_START_LOG="$WORK_DIR/upgrade-start.log" \
  ucode -L "$VOKOP_LIB" "$PACKAGE_UC" postinst
grep -Fxq start "$WORK_DIR/upgrade-start.log" ||
  fail "package postinst must restart a service that was running before upgrade"
[ ! -e "$VOKOP_PACKAGE_UPGRADE_STATE" ] ||
  fail "package postinst must clear the consumed upgrade state"

VOKOP_PACKAGE_TEST_MODE=1 \
VOKOP_FAKE_STATUS=1 \
VOKOP_INIT="$WORK_DIR/upgrade-init" \
VOKOP_RT_TABLES="$WORK_DIR/rt_tables_upgrade" \
  ucode -L "$VOKOP_LIB" "$PACKAGE_UC" prerm upgrade
[ ! -e "$VOKOP_PACKAGE_UPGRADE_STATE" ] ||
  fail "package pre-upgrade must not mark an already stopped service"

printf 'package lifecycle checks passed\n'
