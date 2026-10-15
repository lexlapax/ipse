#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh native/build.sh
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix release --overwrite
IPSE_RELEASE=_build/prod/rel/ipse
cp scripts/release-launcher.sh "$IPSE_RELEASE/ipse"
chmod +x "$IPSE_RELEASE/ipse"
cp LICENSE README.md AGENTS.md CONTRIBUTING.md THIRD_PARTY_NOTICES.md "$IPSE_RELEASE/"
cp scripts/verify-release.exs "$IPSE_RELEASE/"
rm -rf "$IPSE_RELEASE/docs" "$IPSE_RELEASE/licenses"
cp -R docs "$IPSE_RELEASE/"
mkdir -p "$IPSE_RELEASE/licenses"
cp deps/jason/LICENSE "$IPSE_RELEASE/licenses/Jason-MIT.txt"
cp third_party/APACHE-2.0.txt "$IPSE_RELEASE/licenses/"
# Additional notices can be supplied by the toolchain distributor.
if [ -n "${IPSE_NOTICES_DIR:-}" ]; then
  cp -R "$IPSE_NOTICES_DIR/." "$IPSE_RELEASE/licenses/"
fi
if [ -f /usr/share/doc/erlang-base/copyright ]; then
  cp /usr/share/doc/erlang-base/copyright "$IPSE_RELEASE/licenses/Erlang-package-copyright.txt"
fi
IPSE_ARCH=$(uname -m)
IPSE_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
IPSE_ABI=""
if [ "$IPSE_OS" = linux ]; then
  IPSE_LIBC=$(getconf GNU_LIBC_VERSION 2>/dev/null || true)
  if [ -n "$IPSE_LIBC" ]; then
    IPSE_ABI="-$(printf '%s' "$IPSE_LIBC" | tr ' ' '-')"
  else
    IPSE_ABI="-system-libc"
  fi
fi
mkdir -p dist
IPSE_ARCHIVE="dist/ipse-0.1.0-$IPSE_OS-$IPSE_ARCH$IPSE_ABI.tar.gz"
tar -czf "$IPSE_ARCHIVE" -C "$IPSE_RELEASE" .
printf 'Built %s\n' "$IPSE_ARCHIVE"
