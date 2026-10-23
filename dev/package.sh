#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
IPSE_BUILD_COMMIT=${IPSE_BUILD_COMMIT:-$(git rev-parse HEAD 2>/dev/null || true)}
export IPSE_BUILD_COMMIT
sh dev/build-native.sh
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix compile --force --warnings-as-errors
IPSE_VERSION=$(MIX_ENV=prod mix run --no-start -e 'IO.write(Mix.Project.config()[:version])')
IPSE_RELEASE=_build/prod/rel/ipse
# Recreate generated staging so an upgraded toolchain or removed application
# cannot leave obsolete runtime files in the next archive.
rm -rf "$IPSE_RELEASE"
MIX_ENV=prod mix release --overwrite --path "$IPSE_RELEASE"
cp dev/release-launcher.sh "$IPSE_RELEASE/ipse"
chmod +x "$IPSE_RELEASE/ipse"
cp LICENSE README.md AGENTS.md CONTRIBUTING.md SECURITY.md THIRD_PARTY_NOTICES.md "$IPSE_RELEASE/"
cp dev/verify-release.exs "$IPSE_RELEASE/"
rm -rf "$IPSE_RELEASE/docs" "$IPSE_RELEASE/licenses"
cp -R docs "$IPSE_RELEASE/"
mkdir -p "$IPSE_RELEASE/licenses"
MIX_ENV=prod mix run --no-start dev/copy-package-notices.exs "$IPSE_RELEASE/licenses"
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
IPSE_ARCHIVE="dist/ipse-$IPSE_VERSION-$IPSE_OS-$IPSE_ARCH$IPSE_ABI.tar.gz"
tar -czf "$IPSE_ARCHIVE" -C "$IPSE_RELEASE" .
printf 'Built %s\n' "$IPSE_ARCHIVE"
