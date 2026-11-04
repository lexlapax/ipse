#!/usr/bin/env bash
set -euo pipefail
umask 077
proof=/home/lexlapax/projects/lexlapax/ipse/_build/verification/recall33-current-frozen-20261104-01
group=/home/lexlapax/projects/lexlapax/ipse/_build/verification/regression-groups-frozen-20261104-02/serial
runtime=$group/source
state=/dev/shm/ipse-recall33-current-frozen-20261104-01
cd "$runtime"
sha256sum --check --status "$group/evidence/source.sha256"
sha256sum --check --status "$group/evidence/runtime.sha256"
sha256sum --check --status "$group/evidence/dependencies.sha256"
find _build/test/lib priv deps -name .git -prune -o \( -type f -o -type l \) -print | awk '$0 != "_build/test/lib/ipse/.mix/.mix_test_failures"' | LC_ALL=C sort > "$proof/runtime-pathset.before.txt"
cmp -s "$group/evidence/runtime-pathset.txt" "$proof/runtime-pathset.before.txt"
find _build/test/lib -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/runtime-links.before.txt"
cmp -s "$group/evidence/runtime.links" "$proof/runtime-links.before.txt"
cd "$proof"
sha256sum --check --status fixture.sha256
test ! -e launch.claim
test ! -e "$state"
mkdir -m 700 "$state" "$state/home" "$state/tmp"
dd if=/dev/zero of="$state/quota-probe" bs=1048576 count=32 conv=fsync status=none
rm -- "$state/quota-probe"
paths=()
for ebin in "$runtime"/_build/test/lib/*/ebin; do paths+=(-pa "$ebin"); done
cd "$runtime"
env -i PATH=/usr/bin:/bin:/home/lexlapax/.cargo/bin LC_ALL=C.utf8 HOME="$state/home" TMPDIR="$state/tmp" IPSE_HOME="$state/home/.ipse" RUSTUP_HOME=/home/lexlapax/.rustup ERL_FLAGS='+S 2:2 +A 2' elixir "${paths[@]}" /home/lexlapax/projects/lexlapax/ipse/_build/verification/regression-group-launcher-20261104-01/preflight.exs > "$proof/preflight.log" 2>&1
cd "$proof"
(set -C; printf 'one fresh canonical33 positive; exact current runtime; retention-only test override; no old-root replay\n' > launch.claim)
sync -f launch.claim
date -u +%FT%TZ > started-utc.txt
cd "$runtime"
if env -i PATH=/usr/bin:/bin:/home/lexlapax/.cargo/bin LC_ALL=C.utf8 HOME="$state/home" TMPDIR="$state/tmp" IPSE_HOME="$state/home/.ipse" RUSTUP_HOME=/home/lexlapax/.rustup ERL_FLAGS='+S 2:2 +A 2' IPSE_TEST_RECALL_MANY=1 elixir "${paths[@]}" "$proof/entry.exs" > "$proof/raw-private.log" 2>&1; then result=0; else result=$?; fi
source_post=0
sha256sum --check --status "$group/evidence/source.sha256" || source_post=$?
runtime_post=0
sha256sum --check --status "$group/evidence/runtime.sha256" || runtime_post=$?
deps_post=0
sha256sum --check --status "$group/evidence/dependencies.sha256" || deps_post=$?
pathset_post=0
find _build/test/lib priv deps -name .git -prune -o \( -type f -o -type l \) -print | awk '$0 != "_build/test/lib/ipse/.mix/.mix_test_failures"' | LC_ALL=C sort > "$proof/runtime-pathset.after.txt"
cmp -s "$group/evidence/runtime-pathset.txt" "$proof/runtime-pathset.after.txt" || pathset_post=1
find _build/test/lib -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/runtime-links.after.txt"
cmp -s "$group/evidence/runtime.links" "$proof/runtime-links.after.txt" || pathset_post=1
fixture_post=0
cd "$proof"
sha256sum --check --status fixture.sha256 || fixture_post=$?
printf 'test_exit=%s\nsource_post=%s\nruntime_post=%s\ndeps_post=%s\nfixture_post=%s\npathset_links_post=%s\n' "$result" "$source_post" "$runtime_post" "$deps_post" "$fixture_post" "$pathset_post" > status.txt
cat status.txt
if [ "$source_post" -ne 0 ] || [ "$runtime_post" -ne 0 ] || [ "$deps_post" -ne 0 ] || [ "$fixture_post" -ne 0 ] || [ "$pathset_post" -ne 0 ]; then exit 74; fi
exit "$result"
