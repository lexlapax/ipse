#!/bin/bash
set -euo pipefail
export TMPDIR=/dev/shm
# Only names are read; inherited IPSE settings must not select another helper or authority.
while IFS= read -r name; do
  case "$name" in IPSE_*) unset "$name" ;; esac
done < <(compgen -e)
unset MIX_ENV ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS MIX_BUILD_PATH MIX_DEPS_PATH LD_PRELOAD LD_LIBRARY_PATH ERL_FLAGS
export ERL_FLAGS='+S 2:2'
export IPSE_TEST_SOURCE_PHASE_PROBE=1 IPSE_TEST_RECALL_PROVIDER_TIMEOUT_MS=5000
unset IPSE_TEST_RECALL_TIMING IPSE_TEST_RECALL_SPARSE IPSE_TEST_RECALL_REAPPEAR
snapshot=/dev/shm/ipse-source-phase-f44-20261103-01
output=/dev/shm/ipse-source-phase-controls-f44-20261103-01
cd "$snapshot"
# The four hashes are independently reviewed values supplied at launch after build.
[ "$#" -eq 4 ] || exit 1
for expected in "$@"; do [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || exit 1; done
expected_runtime=$1
expected_files=$2
expected_symlinks=$3
expected_launch=$4
pinned_manifests() {
  printf '%s  %s\n' "$expected_runtime" phase-fixture/runtime.sha256 | sha256sum -c >/dev/null &&
  printf '%s  %s\n' "$expected_files" phase-fixture/runtime.files | sha256sum -c >/dev/null &&
  printf '%s  %s\n' "$expected_symlinks" phase-fixture/runtime.symlinks | sha256sum -c >/dev/null &&
  printf '%s  %s\n' "$expected_launch" phase-fixture/launch-inputs.sha256 | sha256sum -c >/dev/null &&
  printf '%s  %s\n' eeac5b834535d76ab0d743badece040b391d7a7beb15532b904866c2df7ecb43 phase-fixture/source.sha256 | sha256sum -c >/dev/null
}
pinned_manifests

all_source() {
  printf '%s  %s\n' c475a44fc89d5c6067b9eb98b6bfe993f860ac032a930bdd92bf8538b04fb873 phase-fixture/all-source.files | sha256sum -c >/dev/null &&
  printf '%s  %s\n' 7fab8eff0fb7b6286a46735a373737b35ee5ee63980774adb36e8b9d559484d4 phase-fixture/all-source.symlinks | sha256sum -c >/dev/null &&
  printf '%s  %s\n' 5a1de2262b98f1ced417accf702c97d8cbcab301f6b9e4fca731693632bd2a0c phase-fixture/all-source.sha256 | sha256sum -c >/dev/null &&
  cut -c 67- phase-fixture/all-source.sha256 | cmp - phase-fixture/all-source.files &&
  sha256sum -c phase-fixture/all-source.sha256 >/dev/null &&
  LC_ALL=C find . \( -path ./phase-fixture -o -path ./deps -o -path ./_build -o -path ./priv/extension-bundles -o -path ./priv/ipse-runner -o -path ./priv/ipse-pdf -o -path ./priv/ipse-pdf-notices \) -prune -o -type f -print | LC_ALL=C sort | cmp - phase-fixture/all-source.files &&
  LC_ALL=C find . \( -path ./phase-fixture -o -path ./deps -o -path ./_build -o -path ./priv/extension-bundles -o -path ./priv/ipse-runner -o -path ./priv/ipse-pdf -o -path ./priv/ipse-pdf-notices \) -prune -o -type l -printf '%p\t%l\n' | LC_ALL=C sort | cmp - phase-fixture/all-source.symlinks
}
runtime_membership() {
  LC_ALL=C find _build/test/lib priv -type f -print | LC_ALL=C sort | cmp - phase-fixture/runtime.files &&
  cut -c 67- phase-fixture/runtime.sha256 | cmp - phase-fixture/runtime.files &&
  LC_ALL=C find _build/test/lib priv -type l -printf '%p\t%l\n' | LC_ALL=C sort | cmp - phase-fixture/runtime.symlinks
}
[ -d "$snapshot" ] && [ ! -L "$snapshot" ] || exit 1
[ ! -e "$output" ] && [ ! -L "$output" ] || exit 1
sha256sum -c phase-fixture/source.sha256 >/dev/null
all_source
sha256sum -c phase-fixture/runtime.sha256 >/dev/null
runtime_membership
sha256sum -c phase-fixture/launch-inputs.sha256 >/dev/null
mkdir -m 700 "$output"
[ "$(stat -c %u:%a "$output")" = "$(id -u):700" ] || exit 1
set -o noclobber
printf 'one-shot\n' > "$output/claim"
postcheck() {
  rc=$?
  trap - EXIT
  post=0
  { pinned_manifests && sha256sum -c phase-fixture/source.sha256 && all_source && sha256sum -c phase-fixture/runtime.sha256 && runtime_membership && sha256sum -c phase-fixture/launch-inputs.sha256; } > "$output/postcheck.log" 2>&1 || post=1
  printf 'run_exit=%s postcheck_exit=%s\n' "$rc" "$post" > "$output/status"
  if [ "$post" -ne 0 ]; then exit 1; fi
  exit "$rc"
}
trap postcheck EXIT
set --
for beam_path in "$snapshot"/_build/test/lib/*/ebin; do
  [ -d "$beam_path" ] && [ ! -L "$beam_path" ] || exit 1
  set -- "$@" -pa "$beam_path"
done
for mode in single split8; do
  case_root="$output/$mode"
  mkdir -m 700 "$case_root"
  [ "$(stat -c %u:%a "$case_root")" = "$(id -u):700" ] || exit 1
  set +e
  TMPDIR="$case_root" IPSE_TEST_SOURCE_PHASE_MODE="$mode" elixir "$@" phase-fixture/run.exs 2>&1 | elixir phase-fixture/redact.exs > "$output/$mode.log"
  statuses=("${PIPESTATUS[@]}")
  set -e
  [ "${statuses[0]}" -eq 0 ] && [ "${statuses[1]}" -eq 0 ] || exit 1
  mapfile -t roots < <(sed -n 's/^SOURCE_TIMING_FIXTURE_ROOT=//p' "$output/$mode.log")
  [ "${#roots[@]}" -eq 1 ] || exit 1
  case "${roots[0]}" in "$case_root"/ipse-native-recall-*) ;; *) exit 1 ;; esac
  [ -d "${roots[0]}" ] && [ ! -L "${roots[0]}" ] || exit 1
  [ "$(stat -c %u:%a "${roots[0]}")" = "$(id -u):700" ] || exit 1
  printf '%s\n' "${roots[0]}" > "$output/$mode.root"
done
elixir "$@" phase-fixture/compare.exs "$(cat "$output/single.root")" "$(cat "$output/split8.root")" > "$output/comparison.json"
printf 'comparison completed\n' > "$output/completed"
