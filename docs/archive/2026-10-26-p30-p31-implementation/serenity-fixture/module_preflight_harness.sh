#!/bin/sh
# REVIEW ONLY: this intentionally opens two device controls and may load
# host kernel modules and create default loop indices. Never unload/remove.
# No loop ioctl, mapper ioctl, Btrfs mount or device write is issued.
set -eu
image='sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af'
program='/tmp/ipse-module-preflight-build/module-preflight'
expected_hash='687be2268a4720eebb0cc5d6671684b0275f7ff32700fd7e8d20e1a3ccf6f64f'
[ -f "$program" ] && [ ! -L "$program" ] || exit 2
actual=$(sha256sum "$program"); actual=${actual%% *}; [ "$actual" = "$expected_hash" ] || exit 2
nonce=$(elixir -e 'IO.write(Base.encode16(:crypto.strong_rand_bytes(16), case: :lower))')
case "$nonce" in *[!0-9a-f]*|'') exit 2;; esac
[ "${#nonce}" -eq 32 ] || exit 2
# This owner-only workspace directory is intentionally retained as the
# persistent recovery location, including if any step fails.
parent=$(mktemp -d /home/lexlapax/projects/lexlapax/ipse/.serenity-module-receipt.XXXXXXXX)
chmod 0700 "$parent"
mkdir -m 0755 "$parent/ledger"
stage=$(mktemp -d /tmp/ipse-module-stage.XXXXXXXX)
chmod 0755 "$stage"
cp -- "$program" "$stage/module-preflight"
chmod 0700 "$stage/module-preflight"
stage_identity=$(stat -c '%d:%i' "$stage")
ledger_identity=$(stat -c '%d:%i' "$parent/ledger")
program_identity=$(stat -c '%d:%i' "$stage/module-preflight")
uid=$(id -u)
printf 'NONCE=%s\nRECEIPT_PARENT=%s\nLEDGER=%s/ledger\nLEDGER_IDENTITY=%s\nSTAGE=%s\nSTAGE_IDENTITY=%s\nPROGRAM_IDENTITY=%s:0:700\nPROGRAM_SHA256=%s\nORIGINAL_UID=%s\n' "$nonce" "$parent" "$parent" "$ledger_identity" "$stage" "$stage_identity" "$program_identity" "$expected_hash" "$uid"
# Persist host observations before the first device-control open.
{
 printf 'nonce=%s kernel=%s\n' "$nonce" "$(uname -r)"
 stat -c 'control=%n type=%F major=%t minor=%T uid=%u gid=%g mode=%a dev=%d inode=%i' /dev/loop-control /dev/mapper/control
 for module in loop dm_mod; do if [ -d "/sys/module/$module" ]; then printf 'module_before=%s:present\n' "$module"; else printf 'module_before=%s:absent\n' "$module"; fi; done
 for node in /sys/class/block/loop*; do [ -e "$node" ] || continue; printf 'loop_index_before=%s\n' "${node##*/}"; done
} > "$parent/before.txt"
sync -f "$parent/before.txt"
sync -f "$parent"
# These two uniquely owned directories start traversable but non-writable by
# others; after chown both become root-owned 0700. No user project is mounted.
for path in "$stage" "$parent/ledger"; do
 docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN \
  --mount "type=bind,source=$path,destination=/stage" --entrypoint /usr/bin/sh "$image" -c 'set -eu; chown -R 0:0 /stage; chmod 0700 /stage'
done
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = "$stage_identity:0:700" ] || exit 3
[ "$(stat -c '%d:%i:%u:%a' "$parent/ledger")" = "$ledger_identity:0:700" ] || exit 3
# Record the container-create attempt before handing device paths to Docker;
# an interrupted create or daemon-side effect remains unknown.
printf 'docker_create=pending\n' > "$parent/docker-create.pending"
sync -f "$parent/docker-create.pending"
sync -f "$parent"
# The exact control devices are separately mapped; no block device is mapped.
container=$(docker create --pull never --network none --read-only --cap-drop ALL --cap-add SYS_ADMIN \
 --pids-limit 8 --memory 64m --cpus 0.5 \
 --device /dev/loop-control:/dev/loop-control:r --device /dev/mapper/control:/dev/mapper/control:r \
 --mount "type=bind,source=$stage,destination=/work/tools,readonly" \
 --mount "type=bind,source=$parent/ledger,destination=/work/fixture-ledger" \
 --entrypoint /work/tools/module-preflight "$image" "$nonce")
printf 'CONTAINER_ID=%s\n' "$container"
case "$container" in *[!0-9a-f]*|'') exit 4;; esac
[ "${#container}" -eq 64 ] || exit 4
[ "$(docker inspect --format '{{.Id}} {{.Image}} {{.HostConfig.Privileged}} {{.HostConfig.NetworkMode}}' "$container")" = "$container $image false none" ] || exit 4
printf 'container=%s\nmodule_open=pending\n' "$container" > "$parent/container.txt"
sync -f "$parent/container.txt"
sync -f "$parent"
# A timeout or failure preserves the container, both directories and all
# modules/indices. CLI timeout is not proof that the container stopped.
set +e
timeout 30s docker start -a "$container" > "$parent/container.stdout" 2> "$parent/container.stderr"
status=$?
set -e
{
 printf 'docker_start_exit=%s\n' "$status"
 for module in loop dm_mod; do if [ -d "/sys/module/$module" ]; then printf 'module_after=%s:present\n' "$module"; else printf 'module_after=%s:absent\n' "$module"; fi; done
 for node in /sys/class/block/loop*; do [ -e "$node" ] || continue; printf 'loop_index_after=%s\n' "${node##*/}"; done
} > "$parent/after.txt"
sync -f "$parent/container.stdout"
sync -f "$parent/container.stderr"
sync -f "$parent/after.txt"
sync -f "$parent"
[ "$status" -eq 0 ] || { printf '%s\n' 'UNKNOWN: preserve exact container, stage and ledger'; exit 5; }
[ "$(docker inspect --format '{{.Id}} {{.State.Running}} {{.State.ExitCode}}' "$container")" = "$container false 0" ] || { printf '%s\n' 'UNKNOWN: preserve exact container, stage and ledger'; exit 5; }
# Deliberately retain even successful resources for independently reviewed
# inspection and cleanup; modules/default indices are never removed here.
printf '%s\n' 'CONTROL_OPENS_OBSERVED: retain exact container, stage and persistent receipt for review'
