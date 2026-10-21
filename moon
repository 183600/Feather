#!/usr/bin/env bash
# MoonBit command entrypoint used by the automation workflow.
# Never pretend tests passed: a missing toolchain is a hard failure so CI
# cannot go green without actually compiling and running the suite.
set -euo pipefail

REAL_MOON="${MOON_BIN:-}"
if [[ -z "$REAL_MOON" ]]; then
  if command -v moon >/dev/null 2>&1; then
    REAL_MOON="$(command -v moon)"
  elif [[ -x "$HOME/.moon/bin/moon" ]]; then
    REAL_MOON="$HOME/.moon/bin/moon"
  fi
fi

if [[ -z "$REAL_MOON" || ! -x "$REAL_MOON" ]]; then
  echo "error: MoonBit toolchain not found (set MOON_BIN or install moon into ~/.moon/bin)" >&2
  exit 127
fi

exec "$REAL_MOON" "$@"
