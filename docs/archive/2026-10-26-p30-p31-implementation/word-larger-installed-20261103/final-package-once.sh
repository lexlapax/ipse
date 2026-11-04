#!/bin/bash
set -euo pipefail
set -C
umask 077
proof=/dev/shm/ipse-word-larger-proof-20261103-01
candidate=/dev/shm/ipse-word-installed-final-20261103-01
cd "$candidate"
for dir in "$candidate" "$candidate/task-package-home" "$candidate/task-package-tmp" "$candidate/task-mix-home" "$candidate/task-hex-home" "$candidate/task-cargo"; do
  if [ ! -d "$dir" ] || [ -L "$dir" ] || [ "$(stat -c '%u:%a' "$dir")" != "$(id -u):700" ]; then exit 1; fi
done
for path in "$proof/final-package.claim" "$proof/final-package.log" "$proof/final-package.status"; do
  if [ -e "$path" ] || [ -L "$path" ]; then exit 1; fi
done
printf '%s  %s\n' '130eb7a99a84c09377a98e8d3a9309ba5200b35593e023322d9943e185d45a39' "$proof/final-package-source.sha256" '8907cfc464ab9400b4d96ae6d6902cfa8144c81f920e59d46c7edca58964976b' "$proof/word-vertical-live.sha256" | sha256sum --quiet -c
sha256sum --quiet -c "$proof/final-package-source.sha256"
sha256sum --quiet -c "$proof/word-vertical-live.sha256"
cmp mix.lock /home/lexlapax/projects/lexlapax/ipse/.document-default-package-JSTWB1/source/mix.lock
cmp native/ipse-pdf/Cargo.lock /home/lexlapax/projects/lexlapax/ipse/.document-default-package-JSTWB1/source/native/ipse-pdf/Cargo.lock
printf '%s\n' 'one isolated offline default package; base label f1 plus reviewed overlay' > "$proof/final-package.claim"
for name in $(compgen -e); do
  case "$name" in IPSE_*|MIX_*|HEX_*|ERL_FLAGS|ERL_AFLAGS|ERL_ZFLAGS|ERL_LIBS|ELIXIR_ERL_OPTIONS|ELIXIR_OPTS|LD_PRELOAD|LD_LIBRARY_PATH|RUSTFLAGS|RUSTC_WRAPPER|RUSTC_WORKSPACE_WRAPPER|CARGO_ENCODED_RUSTFLAGS|CARGO_BUILD_TARGET|CARGO_TARGET_DIR) unset "$name" ;; esac
done
export TMPDIR="$candidate/task-package-tmp" IPSE_HOME="$candidate/task-package-home" MIX_HOME="$candidate/task-mix-home" HEX_HOME="$candidate/task-hex-home" CARGO_HOME="$candidate/task-cargo"
export IPSE_BUILD_COMMIT=f1d84fc280873d6c7630666f545614a45fad2c44 IPSE_BUILD_PDF=1 MIX_OFFLINE=1 HEX_OFFLINE=1 CARGO_NET_OFFLINE=true ERL_FLAGS='+S 2:2 +A 2'
set +e
./dev/package.sh > "$proof/final-package.log" 2>&1
package_status=$?
set -e
post_status=0
sha256sum --quiet -c "$proof/final-package-source.sha256" || post_status=1
sha256sum --quiet -c "$proof/word-vertical-live.sha256" || post_status=1
find . \( -path './_build' -o -path './deps' -o -path './dist' -o -path './task-*' -o -path './priv/ipse-runner' -o -path './priv/ipse-pdf' -o -path './priv/ipse-pdf-notices' -o -path './priv/extension-bundles' \) -prune -o -type f -print | LC_ALL=C sort > "$proof/final-package-post.files"
cmp "$proof/final-package-source.files" "$proof/final-package-post.files" || post_status=1
find . \( -path './_build' -o -path './deps' -o -path './dist' -o -path './task-*' -o -path './priv/ipse-runner' -o -path './priv/ipse-pdf' -o -path './priv/ipse-pdf-notices' -o -path './priv/extension-bundles' \) -prune -o -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/final-package-post.links"
cmp "$proof/final-package-source.links" "$proof/final-package-post.links" || post_status=1
printf 'package_exit=%s\npostcheck_exit=%s\n' "$package_status" "$post_status" > "$proof/final-package.status"
if [ "$package_status" -ne 0 ] || [ "$post_status" -ne 0 ]; then exit 1; fi
