#!/bin/bash
set -euo pipefail
set -C
umask 077
proof=/dev/shm/ipse-word-larger-proof-20261103-01
candidate=/dev/shm/ipse-word-installed-final-20261103-01
output=/dev/shm/ipse-word-installed-large-run-20261103-01
archive="$candidate/dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz"
cd "$candidate"
for dir in "$candidate" "$candidate/task-package-home" "$candidate/task-package-tmp"; do
  if [ ! -d "$dir" ] || [ -L "$dir" ] || [ "$(stat -c '%u:%a' "$dir")" != "$(id -u):700" ]; then exit 1; fi
done
for path in "$output" "$proof/final-installed.claim" "$proof/final-installed.log" "$proof/final-installed.status"; do
  if [ -e "$path" ] || [ -L "$path" ]; then exit 1; fi
done
printf '%s  %s\n' '42b084dd2990bc8a2a20de3c40cbd4ea6e92260697d930aae5ed374a408ad918' "$archive" 'e06b60ea4e3514913f04cb1a9a507068e1a026c0f40e30660957dbdbdcf61582' test/support/documents_setup.exs '3aaedfabab951a0d42d1a4c1abd11985674cc3fd2ff7b54e8ad5bdf665220414' dev/verification/documents_setup_installed.exs '130eb7a99a84c09377a98e8d3a9309ba5200b35593e023322d9943e185d45a39' "$proof/final-package-source.sha256" | sha256sum --quiet -c
sha256sum --quiet -c "$proof/final-package-source.sha256"
printf '%s\n' 'one fresh installed large-Word Collection verification; do not replay' > "$proof/final-installed.claim"
sync -f "$proof/final-installed.claim"
for name in $(compgen -e); do
  case "$name" in IPSE_*|MIX_*|HEX_*|ERL_FLAGS|ERL_AFLAGS|ERL_ZFLAGS|ERL_LIBS|ELIXIR_ERL_OPTIONS|ELIXIR_OPTS|LD_PRELOAD|LD_LIBRARY_PATH|RELEASE_*) unset "$name" ;; esac
done
export TMPDIR="$candidate/task-package-tmp" IPSE_HOME="$candidate/task-package-home" ERL_FLAGS='+S 2:2 +A 2'
set +e
elixir dev/verification/documents_setup_installed.exs "$archive" "$output" > "$proof/final-installed.log" 2>&1
status=$?
set -e
post=0
printf '%s  %s\n' '42b084dd2990bc8a2a20de3c40cbd4ea6e92260697d930aae5ed374a408ad918' "$archive" 'e06b60ea4e3514913f04cb1a9a507068e1a026c0f40e30660957dbdbdcf61582' test/support/documents_setup.exs '3aaedfabab951a0d42d1a4c1abd11985674cc3fd2ff7b54e8ad5bdf665220414' dev/verification/documents_setup_installed.exs | sha256sum --quiet -c || post=1
sha256sum --quiet -c "$proof/final-package-source.sha256" || post=1
tar -tzf "$archive" > "$proof/final-installed-archive.members" || post=1
cmp "$proof/final-archive.members" "$proof/final-installed-archive.members" || post=1
if [ -d "$output/release" ] && [ ! -L "$output/release" ]; then
  (cd "$output/release" && find . -type f -print | LC_ALL=C sort > "$proof/final-installed-release.files" && xargs -d '\n' sha256sum < "$proof/final-installed-release.files" > "$proof/final-installed-release.sha256" && find . -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/final-installed-release.links") || post=1
else post=1; fi
printf 'verifier_exit=%s\npostcheck_exit=%s\n' "$status" "$post" > "$proof/final-installed.status"
sync -f "$proof/final-installed.status"
if [ "$status" -ne 0 ] || [ "$post" -ne 0 ]; then exit 1; fi
