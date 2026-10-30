#!/usr/bin/env bash
# Vokop release policy differs intentionally from upstream Forkop.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
# No inherited automatically publishing workflow may run in the user's fork.
if [ -d "$ROOT_DIR/.github/workflows" ]; then
  if grep -R -E 'action-gh-release|gh release create|sourceforge|uploads\.github' "$ROOT_DIR/.github/workflows"; then
    fail "automatic release publishing must remain absent until explicitly configured"
  fi
fi
grep -Fq 'c.VOKOP_RELEASE_REPO = env("VOKOP_RELEASE_REPO", "");' "$ROOT_DIR/vokop/files/usr/lib/core/constants.uc" ||
  fail "unverified automatic release source must be disabled by default"
set +e
output="$(sh "$ROOT_DIR/install.sh" 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || fail "unverified remote installer must fail closed"
printf '%s' "$output" | grep -Fq 'Automatic Vokop installation is disabled' || fail "installer must explain staged deployment"
printf 'Vokop release safety policy checks passed\n'
