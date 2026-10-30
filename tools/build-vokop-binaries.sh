#!/bin/sh
# Cross-compile only. Does not execute any generated transport/helper binaries.
# Requires the official Go toolchain, >= the version in transport/go.mod.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
GO=${GO:-go}
OUT=${OUT:-"$ROOT/dist/binaries"}
"$GO" version
mkdir -p "$OUT"
STAGE=$(mktemp -d "$OUT/.build-XXXXXX")
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM

# No toolchain auto-downloads and no unverified direct dependency fetch fallback.
export GOTOOLCHAIN=local GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org
export GONOSUMDB='' GOPRIVATE='' GONOPROXY=''
export CGO_ENABLED=0 GOOS=linux
if [ "$#" -eq 0 ]; then
    set -- amd64 arm64 armv7 armv6 386 mips mipsle mips64 mips64le riscv64
fi
for target do
    arm=''
    case "$target" in
        amd64|arm64|386|mips|mipsle|mips64|mips64le|riscv64) arch=$target ;;
        armv7) arch=arm; arm=7 ;;
        armv6) arch=arm; arm=6 ;;
        *) echo "Unsupported target: $target" >&2; exit 2 ;;
    esac
    "$GO" tool dist list | grep -qx "linux/$arch" || {
        echo "Go toolchain does not support linux/$arch" >&2; exit 2;
    }
    export GOARCH=$arch GOARM=$arm GOMIPS=softfloat GOMIPS64=softfloat
    mkdir -p "$STAGE/$target"
    echo "Building $target (no binaries will be run)"
    (cd "$ROOT/transport/vk-turn-proxy" && "$GO" build -mod=readonly -trimpath \
        -tags 'netgo osusergo' -ldflags='-s -w' -o "$STAGE/$target/vokop-vk-client" ./client)
    (cd "$ROOT/tools/vokop-fetch" && "$GO" build -mod=readonly -trimpath \
        -tags 'netgo osusergo' -ldflags='-s -w' -o "$STAGE/$target/vokop-fetch" .)
done
(cd "$STAGE" && find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | xargs sha256sum > SHA256SUMS)
# Publish outputs only after every requested compilation succeeds.
for target do
    mkdir -p "$OUT/$target"
    cp "$STAGE/$target/vokop-vk-client" "$STAGE/$target/vokop-fetch" "$OUT/$target/"
done
cp "$STAGE/SHA256SUMS" "$OUT/SHA256SUMS"
echo "Built targets: $*"
echo "Hashes: $OUT/SHA256SUMS"
echo "Compilation is not an OpenWrt SDK build or a router connectivity test."
