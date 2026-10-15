#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh native/build.sh
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix release --overwrite
RUNESPELL_RELEASE=_build/prod/rel/runespell
cp scripts/release-launcher.sh "$RUNESPELL_RELEASE/runespell"
chmod +x "$RUNESPELL_RELEASE/runespell"
cp LICENSE README.md AGENTS.md CONTRIBUTING.md THIRD_PARTY_NOTICES.md "$RUNESPELL_RELEASE/"
cp -R docs "$RUNESPELL_RELEASE/"
mkdir -p "$RUNESPELL_RELEASE/licenses"
cp deps/jason/LICENSE "$RUNESPELL_RELEASE/licenses/Jason-MIT.txt"
cp third_party/APACHE-2.0.txt "$RUNESPELL_RELEASE/licenses/"
# Additional notices can be supplied by the toolchain distributor.
if [ -n "${RUNESPELL_NOTICES_DIR:-}" ]; then
  cp -R "$RUNESPELL_NOTICES_DIR/." "$RUNESPELL_RELEASE/licenses/"
fi
if [ -f /usr/share/doc/erlang-base/copyright ]; then
  cp /usr/share/doc/erlang-base/copyright "$RUNESPELL_RELEASE/licenses/Erlang-package-copyright.txt"
fi
RUNESPELL_ARCH=$(uname -m)
RUNESPELL_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
RUNESPELL_ABI=""
if [ "$RUNESPELL_OS" = linux ]; then
  RUNESPELL_LIBC=$(getconf GNU_LIBC_VERSION 2>/dev/null || true)
  if [ -n "$RUNESPELL_LIBC" ]; then
    RUNESPELL_ABI="-$(printf '%s' "$RUNESPELL_LIBC" | tr ' ' '-')"
  else
    RUNESPELL_ABI="-system-libc"
  fi
fi
mkdir -p dist
RUNESPELL_ARCHIVE="dist/runespell-0.1.0-$RUNESPELL_OS-$RUNESPELL_ARCH$RUNESPELL_ABI.tar.gz"
tar -czf "$RUNESPELL_ARCHIVE" -C "$RUNESPELL_RELEASE" .
printf 'Built %s\n' "$RUNESPELL_ARCHIVE"
