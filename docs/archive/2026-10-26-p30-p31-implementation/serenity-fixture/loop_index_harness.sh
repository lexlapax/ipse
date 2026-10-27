#!/bin/sh
# REVIEW ONLY: this creates one host-global loop index and NEVER removes it.
# It binds no backing and performs no block I/O, mapper ioctl, mount or unload.
set -eu
set -C
image='sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af'
parent='/home/lexlapax/projects/lexlapax/ipse/.serenity-module-receipt.6Fow8PKP'
ledger="$parent/ledger"
nonce='63ebcfd6bc5a4167223662f0dae3539d'
index=4095
program='/tmp/ipse-loop-index-build/loop-index-create'
expected_hash='ff64c2a44ec7893363f51d93e7ee4eeeeed77d6f27ae7299fee52baa6993aa2d'
[ "$(stat -c '%d:%i:%u:%a' "$ledger")" = '29:13347407:0:700' ] || exit 2
[ -f "$program" ] && [ ! -L "$program" ] || exit 2
actual=$(sha256sum "$program"); actual=${actual%% *}; [ "$actual" = "$expected_hash" ] || exit 2
[ -d /sys/module/loop ] && [ "$(cat /sys/module/loop/parameters/max_part)" = 0 ] || exit 2
[ ! -e "/sys/dev/block/7:$index" ] && [ ! -e "/dev/loop$index" ] || exit 2
# Verify the exact earlier module receipt in a read-only container.
observed=$(docker run --rm --pull never --network none --read-only --cap-drop ALL \
 --mount "type=bind,source=$ledger,destination=/ledger,readonly" --entrypoint /usr/bin/sha256sum "$image" /ledger/module-load.receipt)
[ "$observed" = '5a78ade1345a020ce7ddd9baa14fe23851ce5b2744376b9bc0565bcfea17518c  /ledger/module-load.receipt' ] || exit 2
stage=$(mktemp -d /tmp/ipse-index-stage.XXXXXXXX)
chmod 0755 "$stage"
cp -- "$program" "$stage/loop-index-create"
chmod 0700 "$stage/loop-index-create"
stage_identity=$(stat -c '%d:%i' "$stage")
program_identity=$(stat -c '%d:%i' "$stage/loop-index-create")
uid=$(id -u)
host_ns=$(stat -Lc '%i' /proc/self/ns/mnt)
{
 printf 'nonce=%s kernel=%s index=%s host_mount_ns=%s\n' "$nonce" "$(uname -r)" "$index" "$host_ns"
 printf 'ledger=%s ledger_id=%s stage=%s stage_id=%s program_id=%s:0:700 program_sha256=%s original_uid=%s\n' "$ledger" '29:13347407' "$stage" "$stage_identity" "$program_identity" "$expected_hash" "$uid"
 stat -c 'control=%n type=%F major=%t minor=%T uid=%u gid=%g mode=%a dev=%d inode=%i' /dev/loop-control
 printf 'index_before=absent max_part=%s\n' "$(cat /sys/module/loop/parameters/max_part)"
} > "$parent/index-before.txt"
sync -f "$parent/index-before.txt"
sync -f "$parent"
docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN \
 --mount "type=bind,source=$stage,destination=/stage" --entrypoint /usr/bin/sh "$image" -c 'set -eu; chown -R 0:0 /stage; chmod 0700 /stage'
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = "$stage_identity:0:700" ] || exit 3
# Record before handing a device-control path to the daemon.
printf 'index_container_create=pending\n' > "$parent/index-container-create.pending"
sync -f "$parent/index-container-create.pending"
sync -f "$parent"
container=$(docker create --pull never --network none --read-only --cap-drop ALL --cap-add SYS_ADMIN \
 --cgroupns host --pids-limit 8 --memory 64m --cpus 0.5 \
 --device /dev/loop-control:/dev/loop-control:rw \
 --mount "type=bind,source=$stage,destination=/work/tools,readonly" \
 --mount "type=bind,source=$ledger,destination=/work/fixture-ledger" \
 --entrypoint /work/tools/loop-index-create "$image" "$nonce" "$index" "$host_ns")
printf 'CONTAINER_ID=%s\n' "$container"
case "$container" in *[!0-9a-f]*|'') exit 4;; esac
[ "${#container}" -eq 64 ] || exit 4
[ "$(docker inspect --format '{{.Id}} {{.Image}} {{.HostConfig.Privileged}} {{.HostConfig.NetworkMode}}' "$container")" = "$container $image false none" ] || exit 4
printf 'container=%s\nindex_add=pending\n' "$container" > "$parent/index-container.txt"
sync -f "$parent/index-container.txt"
sync -f "$parent"
set +e
timeout 30s docker start -a "$container" > "$parent/index-container.stdout" 2> "$parent/index-container.stderr"
status=$?
set -e
{
 printf 'docker_start_exit=%s\n' "$status"
 if [ -e "/sys/dev/block/7:$index" ]; then printf 'index_after=present\n';stat -Lc 'sysfs_dev=%d sysfs_inode=%i' "/sys/dev/block/7:$index"; else printf 'index_after=absent_or_unavailable\n'; fi
} > "$parent/index-after.txt"
sync -f "$parent/index-container.stdout"
sync -f "$parent/index-container.stderr"
sync -f "$parent/index-after.txt"
sync -f "$parent"
[ "$status" -eq 0 ] || { printf '%s\n' 'UNKNOWN: preserve exact container, stage, index and ledger'; exit 5; }
[ "$(docker inspect --format '{{.Id}} {{.State.Running}} {{.State.ExitCode}}' "$container")" = "$container false 0" ] || { printf '%s\n' 'UNKNOWN: preserve exact container, stage, index and ledger'; exit 5; }
printf '%s\n' 'INDEX_ADD_OBSERVED: retain exact container, stage, index and receipt for review'
