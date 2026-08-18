#!/bin/bash
# Fetches ghostty's zig dependencies into the zig cache using curl.
#
# Why: zig's builtin HTTP client is blocked by the network policy on some
# machines (curl is fine). So we loop: ask zig which dependency is missing,
# download it with curl, and insert it into the cache via `zig fetch <file>`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIG="$ROOT/vendor/zig/zig-aarch64-macos-0.15.2/zig"
export ZIG_GLOBAL_CACHE_DIR="$ROOT/vendor/zig-cache/global"
export ZIG_LOCAL_CACHE_DIR="$ROOT/vendor/zig-cache/local"

cd "$ROOT/vendor/ghostty"

for _ in $(seq 1 100); do
  # Run the real build: lazy dependencies (e.g. pkg/highway's sub-deps) only
  # surface once the build graph actually needs them, so `zig build --fetch`
  # alone misses some.
  out=$("$ZIG" build -Doptimize=ReleaseFast -Demit-xcframework=false -Demit-macos-app=false 2>&1) && {
    echo "build succeeded, all dependencies fetched"
    exit 0
  }
  url=$(echo "$out" | grep -oE 'https://[^"]+\.(tar\.gz|tar\.xz|tar\.zst|tgz|zip)' | head -1)
  if [ -z "$url" ]; then
    echo "no fetchable URL in zig output:" >&2
    echo "$out" >&2
    exit 1
  fi
  echo "fetching $url"
  tmp="$(mktemp -d)/$(basename "$url")"
  curl -fsSL "$url" -o "$tmp"
  "$ZIG" fetch "$tmp" > /dev/null
  rm -f "$tmp"
done

echo "gave up after 100 iterations" >&2
exit 1
