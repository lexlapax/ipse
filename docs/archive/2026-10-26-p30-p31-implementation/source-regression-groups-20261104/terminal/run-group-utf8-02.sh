#!/usr/bin/env bash
set -euo pipefail
umask 077
if [ "$#" -ne 3 ] || [ "$1" != --run ]; then
  printf '%s\n' 'Disabled: reviewed copies, receipt pin, aggregate capacity and scheduling required.' >&2
  exit 64
fi
case "$2" in serial|parallel-1|parallel-2|parallel-3) group_name=$2 ;; *) exit 64 ;; esac
case "$3" in *[!0-9a-f]*|'') exit 64 ;; esac
[ "${#3}" -eq 64 ]
draft_root=/home/lexlapax/projects/lexlapax/ipse/_build/verification/regression-group-launcher-20261104-01
if [ "$group_name" = serial ]; then
  group_root=/home/lexlapax/projects/lexlapax/ipse/_build/verification/regression-groups-frozen-20261104-02/serial
else
  group_root=/home/lexlapax/projects/lexlapax/ipse/_build/verification/regression-groups-frozen-20261104-01/$group_name
fi
evidence=$group_root/evidence
printf '%s  %s\n' "$3" "$group_root/run-pins.sha256" | sha256sum --check --status
sha256sum --check --status "$group_root/run-pins.sha256"
cd "$group_root/source"
sha256sum --check --status "$evidence/source.sha256"
sha256sum --check --status "$evidence/runtime.sha256"
sha256sum --check --status "$evidence/dependencies.sha256"
git ls-files -z --cached | sha256sum --check --status "$evidence/cached-paths.sha256"
[ "$(GIT_OPTIONAL_LOCKS=0 git rev-parse HEAD)" = "$(cat "$evidence/git-head.txt")" ]
find _build/test/lib priv deps -name .git -prune -o \( -type f -o -type l \) -print | awk '$0 != "_build/test/lib/ipse/.mix/.mix_test_failures"' | LC_ALL=C sort > "$evidence/runtime-pathset.pre.txt"
cmp -s "$evidence/runtime-pathset.txt" "$evidence/runtime-pathset.pre.txt"
find _build/test/lib -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$evidence/runtime-links.pre.txt"
cmp -s "$evidence/runtime.links" "$evidence/runtime-links.pre.txt"
find bin dev docs examples extensions lib native priv test \( -type f -o -type l \) -print | LC_ALL=C sort > "$evidence/source-pathset.pre.txt"
cmp -s "$evidence/source-pathset.txt" "$evidence/source-pathset.pre.txt"
find . -mindepth 1 -maxdepth 1 -printf '%f\t%y\t%i\t%m\t%U\t%G\n' | LC_ALL=C sort > "$evidence/top-level-outputs.pre.txt"
while IFS= read -r line; do
  link_path=${line%% -> *}
  link_target=${line#* -> }
  [ "$(readlink -- "$link_path")" = "$link_target" ]
done < "$evidence/source.links"
mapfile -t test_files < "$group_root/test-files.txt"
[ "${#test_files[@]}" -gt 0 ]
code_paths=()
for directory in "$PWD"/_build/test/lib/*/ebin; do code_paths+=(-pa "$directory"); done
hex_archives=$(cat "$evidence/hex-archives.path")
[ -d "$hex_archives" ]
(cd "$hex_archives"; sha256sum --check --status "$evidence/hex-archives.sha256")
mix_failure_metadata=_build/test/lib/ipse/.mix/.mix_test_failures
record_mix_metadata() {
  if [ -L "$mix_failure_metadata" ]; then return 74
  elif [ -f "$mix_failure_metadata" ]; then sha256sum -- "$mix_failure_metadata"
  elif [ -e "$mix_failure_metadata" ]; then return 74
  else printf '%s\n' 'absent'; fi
}
record_mix_metadata > "$evidence/mix-failures.pre.txt"
protected_tmp_parent=$(cat "$evidence/protected-tmp-parent.path")
case "$protected_tmp_parent" in /tmp|/dev/shm) ;; *) exit 64 ;; esac
fixture=$(mktemp -d "$protected_tmp_parent/ipse-regression-$group_name-XXXXXX")
chmod 700 "$fixture"
mkdir -m 700 "$fixture/tmp"
printf '%s\n' "$fixture" > "$evidence/fixture-root.txt"
if dd if=/dev/zero of="$fixture/quota-probe" bs=1048576 count=32 conv=fsync status=none; then
  rm -- "$fixture/quota-probe"
else
  printf 'quota_probe=failed\ntest_dispatched=false\n' > "$evidence/status.txt"
  exit 70
fi
clean_env=(env -i LC_ALL=C.utf8 PATH=/usr/bin:/bin:/home/lexlapax/.cargo/bin HOME="$group_root/home" IPSE_HOME="$group_root/home/.ipse" TMPDIR="$fixture/tmp" MIX_HOME="$group_root/mix-home" HEX_HOME="$group_root/hex-home" MIX_ARCHIVES="$hex_archives" MIX_ENV=test HEX_OFFLINE=1 RUSTUP_HOME=/home/lexlapax/.rustup CARGO_TARGET_DIR="$group_root/cargo-target" ERL_FLAGS='+S 2:2 +A 2' GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0)
"${clean_env[@]}" elixir "${code_paths[@]}" "$draft_root/preflight.exs" > "$evidence/preflight.log" 2>&1
(set -C; printf 'one explicit complete Mix group; no automatic retry\n' > "$evidence/test.claim")
sync -f "$evidence/test.claim"
if "${clean_env[@]}" mix test --no-compile --no-deps-check --max-cases 2 "${test_files[@]}" > "$evidence/raw-private.log" 2>&1; then
  test_status=0
else
  test_status=$?
fi
source_status=0
sha256sum --check --status "$evidence/source.sha256" || source_status=$?
runtime_status=0
sha256sum --check --status "$evidence/runtime.sha256" || runtime_status=$?
deps_status=0
sha256sum --check --status "$evidence/dependencies.sha256" || deps_status=$?
find _build/test/lib priv deps -name .git -prune -o \( -type f -o -type l \) -print | awk '$0 != "_build/test/lib/ipse/.mix/.mix_test_failures"' | LC_ALL=C sort > "$evidence/runtime-pathset.post.txt"
pathset_status=0
cmp -s "$evidence/runtime-pathset.txt" "$evidence/runtime-pathset.post.txt" || pathset_status=$?
find _build/test/lib -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$evidence/runtime-links.post.txt"
links_status=0
cmp -s "$evidence/runtime.links" "$evidence/runtime-links.post.txt" || links_status=$?
find bin dev docs examples extensions lib native priv test \( -type f -o -type l \) -print | LC_ALL=C sort > "$evidence/source-pathset.post.txt"
find . -mindepth 1 -maxdepth 1 -printf '%f\t%y\t%i\t%m\t%U\t%G\n' | LC_ALL=C sort > "$evidence/top-level-outputs.post.txt"
LC_ALL=C comm -23 "$evidence/top-level-outputs.pre.txt" "$evidence/top-level-outputs.post.txt" > "$evidence/original-top-level-changes.txt"
LC_ALL=C comm -13 "$evidence/top-level-outputs.pre.txt" "$evidence/top-level-outputs.post.txt" > "$evidence/new-top-level-outputs.txt"
top_level_status=0
[ ! -s "$evidence/original-top-level-changes.txt" ] || top_level_status=1
[ "$(wc -l < "$evidence/new-top-level-outputs.txt")" -le 512 ] || top_level_status=1
[ "$(wc -c < "$evidence/new-top-level-outputs.txt")" -le 65536 ] || top_level_status=1
source_paths_status=0
cmp -s "$evidence/source-pathset.txt" "$evidence/source-pathset.post.txt" || source_paths_status=$?
source_links_status=0
while IFS= read -r line; do
  link_path=${line%% -> *}
  link_target=${line#* -> }
  [ "$(readlink -- "$link_path")" = "$link_target" ] || source_links_status=1
done < "$evidence/source.links"
git_status=0
git ls-files -z --cached | sha256sum --check --status "$evidence/cached-paths.sha256" || git_status=$?
[ "$(GIT_OPTIONAL_LOCKS=0 git rev-parse HEAD)" = "$(cat "$evidence/git-head.txt")" ] || git_status=1
mix_metadata_status=0
record_mix_metadata > "$evidence/mix-failures.post.txt" || mix_metadata_status=$?
hex_status=0
(cd "$hex_archives"; sha256sum --check --status "$evidence/hex-archives.sha256") || hex_status=$?
printf 'test_exit=%s\nsource_post=%s\nruntime_post=%s\ndeps_post=%s\npathset_post=%s\nlinks_post=%s\nsource_paths_post=%s\nsource_links_post=%s\ngit_post=%s\nmix_metadata_type_post=%s\nhex_archive_post=%s\noriginal_top_level_and_new_output_bound_post=%s\n' "$test_status" "$source_status" "$runtime_status" "$deps_status" "$pathset_status" "$links_status" "$source_paths_status" "$source_links_status" "$git_status" "$mix_metadata_status" "$hex_status" "$top_level_status" > "$evidence/status.txt"
cat "$evidence/status.txt"
if [ "$source_status" -ne 0 ] || [ "$runtime_status" -ne 0 ] || [ "$deps_status" -ne 0 ] || [ "$pathset_status" -ne 0 ] || [ "$links_status" -ne 0 ] || [ "$source_paths_status" -ne 0 ] || [ "$source_links_status" -ne 0 ] || [ "$git_status" -ne 0 ] || [ "$mix_metadata_status" -ne 0 ] || [ "$hex_status" -ne 0 ] || [ "$top_level_status" -ne 0 ]; then exit 74; fi
exit "$test_status"
