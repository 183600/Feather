#!/usr/bin/env bash
# Fail if throwaway agent/probe files or a stub README were committed.
set -euo pipefail

bad="$(
  git ls-files |
    grep -E '(^|/)(zz_|tmp_|_scratch_|dbg_)' || true
)"
if [[ -n "$bad" ]]; then
  echo "error: scratch/probe files must not be committed:" >&2
  echo "$bad" >&2
  echo "Use descriptive test names, or keep throwaway scripts in /tmp." >&2
  exit 1
fi

if grep -q 'currently contains the design/implementation plan' README.md; then
  echo "error: README regressed to the old plan-only stub" >&2
  exit 1
fi

if ! grep -q '^## Features' README.md; then
  echo "error: README is missing the feature overview" >&2
  exit 1
fi

echo "repository hygiene: ok"
