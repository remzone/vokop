# Vokop VK TURN transport staging

Upstream: https://github.com/cacggghp/vk-turn-proxy
Pinned commit: `e8a96967dc66f3dbd631596ea6a8b9fe03f9be69`.
Original GPLv3 LICENSE and MIT/Pion file headers retained in `vk-turn-proxy/`.
This directory is a source snapshot, not a binary download or an installer.

## Independent patch

`patches/0001-vokop-wan-mark-unattended.patch` is applicable to the pinned upstream
source. It is already applied to the adjacent snapshot. It adds:

- Linux SO_MARK `0x08000000` before connect/listen for outbound transport sockets.
  Failure to set mark aborts creation instead of silently falling back.
- Marked pure-Go DNS for peer and dynamic TURN relay resolution; direct IP DNS
  avoids FakeIP recursion, supports UDP and TCP resolver calls.
- HTTP/3 disabled in TLS-client to prevent QUIC bypassing the socket dialer.
- Marked TLS-client dialer, Yandex HTTP/WebSocket, TURN TCP/UDP, Pion transport
  Dial/Listen adapters and manual-captcha proxy dialer.
- Loopback sockets are not marked. Local VLESS TCP listener remains unchanged.
- `-unattended=true` default: CAPTCHA_REQUIRED is reported and credentials are
  locked out for 24 hours without invoking automated solvers or opening a browser.

Expected binary installation name: `/usr/bin/vokop-vk-client`.
The supervisor must use VLESS mode and a loopback-only listener. It must not send
raw upstream logs to the panel: upstream errors can contain response bodies.
Process/listener existence is NOT an end-to-end health signal.

## Routing assumptions

The routing integration must exempt mark `0x08000000` before transparent proxy
rules, and ensure that mark uses WAN routing, including IPv6 if supported.
Socket marks alone do not create policy routing, override unrelated VPN rules,
or fix conflicting packages. DNS addresses are intentionally direct WAN traffic.
Procd requires root or suitable capabilities; never silently retry unmarked.
Current code only has the Linux mark implementation and is intended for OpenWrt.

## Verification status

Source callsites reviewed. No transport binary, live VK call, CAPTCHA flow,
router network mutation or OpenWrt SDK build executed. Official Go 1.25.5 is available and gofmt syntax validation passed.
Upstream code execution approval is pending; compilation and live validation
are not claimed.

Architecture candidates from upstream workflow: amd64, arm64, armv7, 386,
mips/mipsle softfloat, mips64le and riscv64. These are NOT hardware test claims.

## OpenWrt package recipe

`../vokop-vk-turn/Makefile` builds the local patched snapshot with the standard
OpenWrt packages-feed Go builder. Keep the entire Vokop repository layout in the
feed; copying the package folder alone omits its adjacent source tree. Source
pin: `e8a96967dc66f3dbd631596ea6a8b9fe03f9be69`; no downloaded binary is executed
at install time. The target binary is CGO-disabled and Linux-only. SDK `packages`
feed must be present and its Go host version must satisfy `go.mod` (1.25.5+).
The recipe has not yet been built in an OpenWrt SDK.

### Procd supervisor contract

Use a foreground process (no daemonization):

```
/usr/bin/vokop-vk-client -vless -unattended=true \
  -listen 127.0.0.1:LOCAL_PORT -peer SERVER_IP_OR_HOST:PORT \
  -vk-link https://vk.com/call/join/EXAMPLE -n 2
```

Optional upstream transport choice: `-udp` (default is TURN TCP).
Optional relay override: `-turn HOST -port PORT`, validated by the controller.
Do not pass `-debug`, `-no-dtls`, or `-unattended=false` through subscriptions.
Use argument arrays, not shell command strings; validate loopback listener locally.
The inner sing-box VLESS outbound points at the loopback listener with the
panel-supplied VLESS UUID. Peer is the VK TURN server, not the Xray inbound.
SIGTERM/SIGINT are supported; allow at least five seconds before SIGKILL.
Procd start/respawn does not prove remote connectivity. Test through the inner
VLESS path and roll back desired configuration on failure. On CAPTCHA_REQUIRED,
stop retrying or show user action required rather than tight restart loops.

The package has no init script: Vokop's orchestrator owns lifecycle and must keep
it disabled until the user explicitly enables a validated subscription.

### Sanitized status file

Optional `-status-file /var/run/vokop/PROFILE.status` writes only one enum and a
newline: `starting`, `ready`, `captcha_required`, or `error`. Writes are atomic
with file mode 0600. The parent directory must exist and be owned by the local
supervisor. Never take this path from a subscription. Startup fails if the first
status cannot be written. `captcha_required` is latched until process restart.
`ready` means an internal transport session exists, NOT that the VLESS tunnel or
Internet works. Keep the independent end-to-end health probe. On process exit a
file can be stale; process supervision must override stale status.

## Cross-builds without running transport code

From the repository root, with official Go available:

```
GO=/absolute/path/to/go ./tools/build-vokop-binaries.sh
```

Optional arguments choose targets, for example `amd64 arm64 mipsle`. Default
matrix: amd64, arm64, armv7, armv6, 386, mips/mipsle softfloat,
mips64/mips64le softfloat, riscv64. It builds both `vokop-vk-client` and
`vokop-fetch`, writes `dist/binaries/<target>/` plus `SHA256SUMS`, and never runs
those binaries. It only fetches dependencies through the Go module proxy with
checksum verification, and disables toolchain auto-download. Compilation requires
an existing suitable Go toolchain. ABI/CPU/kernel compatibility is still a
separate device test. A successful binary build is NOT an installable IPK/APK.

## OpenWrt SDK feed integration

Use a matching official SDK for the target router/release. Keep source outside
its tree and add `src-link vokop /absolute/path/to/vokop` to its feeds configuration.
Install the SDK's normal packages feed first, including a compatible `golang/host`.
Then install Vokop feed packages and build their SDK targets:

```
./scripts/feeds update vokop
./scripts/feeds install -p vokop vokop vokop-vk-turn vokop-fetch luci-app-vokop
make defconfig
make package/vokop-vk-turn/compile V=s
make package/vokop-fetch/compile V=s
make package/vokop/compile V=s
make package/luci-app-vokop/compile V=s
```

Check the actual SDK output package names and architecture before installation.
Old SDK Go host packages may not satisfy the upstream module version; updating
that build dependency is not equivalent to claiming support for old OpenWrt.
The existing generic `build.sh` packaging flow does not by itself compile or
include these architecture-specific Go transport/helper packages. Ship all
required matching packages together, or use a correctly configured SDK pipeline.
No package should start a tunnel or change routing merely on installation.
