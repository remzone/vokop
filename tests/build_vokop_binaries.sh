#!/bin/sh
# Tests only the generated build orchestration with a fake compiler, no upstream code.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
cat > "$TMP/fake-go" <<'FAKE'
#!/bin/sh
set -eu
case "$1" in
  version) echo 'go version test-double linux/amd64'; exit 0 ;;
  tool) printf 'linux/amd64\nlinux/arm\n'; exit 0 ;;
  build)
    [ "$GOTOOLCHAIN" = local ] && [ "$CGO_ENABLED" = 0 ]
    [ "$GOPROXY" = https://proxy.golang.org ] && [ "$GOSUMDB" = sum.golang.org ]
    while [ "$#" -gt 0 ]; do
      if [ "$1" = -o ]; then shift; printf '%s/%s fake binary\n' "$GOARCH" "$GOARM" > "$1"; exit 0; fi
      shift
    done
    exit 3 ;;
  *) exit 4 ;;
esac
FAKE
chmod +x "$TMP/fake-go"
GO="$TMP/fake-go" OUT="$TMP/out" "$ROOT/tools/build-vokop-binaries.sh" amd64 armv6 >/dev/null
[ -f "$TMP/out/amd64/vokop-vk-client" ]
[ -f "$TMP/out/armv6/vokop-fetch" ]
(cd "$TMP/out" && sha256sum -c SHA256SUMS >/dev/null)
if GO="$TMP/fake-go" OUT="$TMP/invalid" "$ROOT/tools/build-vokop-binaries.sh" invalid >/dev/null 2>&1; then
  echo 'invalid architecture accepted' >&2; exit 1
fi
[ ! -e "$TMP/invalid/SHA256SUMS" ]
echo 'PASS build orchestration with fake compiler (not a transport compilation)'
