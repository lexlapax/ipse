#!/bin/sh
# Build only: this creates an owner-only /tmp candidate and never runs it.
# The diagnostic binary is opt-in and must not be executed before review.
set -eu
build=$(mktemp -d /tmp/ipse-live-candidate.XXXXXXXX)
chmod 0700 "$build"
printf 'CANDIDATE=%s\n' "$build"
mkdir -p "$build/tools/bin" "$build/tools/lib" "$build/tools/share" "$build/runtime/lib" "$build/runtime/priv" "$build/project/lib/ipse" "$build/project/priv"
rustc --edition=2021 --cfg ipse_live_reviewed diagnostic_entry.rs -o "$build/tools/bin/ipse-diagnostic"
rustc --edition=2024 --cfg ipse_live_reviewed loop_owner_main.rs -o "$build/tools/bin/ipse-loop-owner"
rustc --edition=2021 owner_guardian_main.rs -o "$build/tools/bin/ipse-owner-guardian"
rustc --edition=2021 peer_listener_container.rs -o "$build/tools/bin/peer_listener"
rustc --edition=2021 -C opt-level=z -C strip=symbols -C panic=abort /tmp/ipse-serenity-barrier-private/native/ipse-runner.rs -o "$build/project/priv/ipse-runner"
cp "$build/project/priv/ipse-runner" "$build/runtime/priv/ipse-runner"
cp -a /tmp/ipse-serenity-barrier-graph/build/lib/. "$build/runtime/lib/"
rm "$build/runtime/lib/ipse/priv"
ln -s ../../priv "$build/runtime/lib/ipse/priv"
cp /tmp/ipse-serenity-barrier-graph/project/lib/ipse/runner.ex "$build/project/lib/ipse/runner.ex"
elixirc --ignore-module-conflict -pa "$build/runtime/lib/*/ebin" -o "$build/runtime/lib/ipse/ebin" "$build/project/lib/ipse/runner.ex"
cp diagnostic_stage_container.exs "$build/tools/share/diagnostic-stage.exs"
for tool in dmsetup losetup mkfs.btrfs mount umount blkid; do cp -L "/usr/bin/$tool" "$build/tools/bin/$tool"; done
for lib in libblkid.so.1 libc.so.6 libdevmapper.so.1.02 libgcc_s.so.1 libgcrypt.so.20 libgpg-error.so.0 liblzo2.so.2 libm.so.6 libmount.so.1 libsmartcols.so.1 libsystemd.so.0 libudev.so.1 libuuid.so.1 libz.so.1 libzstd.so.1; do cp -L "/usr/lib/$lib" "$build/tools/lib/$lib"; done
chmod 0700 "$build/tools/bin/ipse-diagnostic" "$build/tools/bin/ipse-loop-owner" "$build/tools/bin/ipse-owner-guardian" "$build/tools/bin/peer_listener" "$build/runtime/priv/ipse-runner" "$build/project/priv/ipse-runner"
sha256sum "$build/tools/bin/ipse-diagnostic" "$build/tools/bin/ipse-loop-owner" "$build/tools/bin/ipse-owner-guardian" "$build/tools/bin/peer_listener" "$build/runtime/priv/ipse-runner" "$build/tools/share/diagnostic-stage.exs"
printf '%s\n' 'BUILD_ONLY: no candidate binary was executed'
