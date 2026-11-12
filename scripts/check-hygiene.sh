#!/usr/bin/env bash
# Fail if throwaway agent/probe files or a stub README were committed.
set -euo pipefail

# Do not mask a failing `git ls-files` (e.g. outside a git repository) with
# `|| true` inside the same pipeline: the check must fail closed.
# Only the `probe_` prefix is rejected: `_probe_` occurs inside legitimate
# regression test names, so matching it here would fail real test files.
files="$(git ls-files)"
bad="$(
  printf '%s\n' "$files" |
    grep -E '(^|/)(zz_|tmp_|_scratch_|dbg_|probe_)' || true
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
