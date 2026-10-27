#!/bin/sh
# REVIEW ONLY: creates one new, retained host-global loop index; no backing
# binding, block I/O, mapper operation, mount, unload or index removal.
set -eu
set -C
image='sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af'
old_parent='/home/lexlapax/projects/lexlapax/ipse/.serenity-fifth-receipt.NisZ7idN'
old_ledger="$old_parent/ledger"
nonce='2f2367d678aa40c3b8b8dc4bc34ac165'
index=4090
program='/tmp/ipse-loop-index-build/loop-index-create'
expected='ff64c2a44ec7893363f51d93e7ee4eeeeed77d6f27ae7299fee52baa6993aa2d'
[ "$(stat -c '%d:%i:%u:%a' "$old_ledger")" = '29:13359764:0:700' ] || exit 2
[ "$(stat -Lc '%d:%i' /sys/dev/block/7:4091)" = '25:756344' ] || exit 2
[ -d /sys/module/loop ] && [ -d /sys/module/dm_mod ] && [ "$(cat /sys/module/loop/parameters/max_part)" = 0 ] || exit 2
[ "$(uname -r)" = '7.2.11-arch1-1' ] || exit 2
[ ! -e "/sys/dev/block/7:$index" ] && [ ! -e "/dev/loop$index" ] || exit 2
[ -f "$program" ] && [ ! -L "$program" ] || exit 2
actual=$(sha256sum "$program"); actual=${actual%% *}; [ "$actual" = "$expected" ] || exit 2
name="ipse-index-$nonce"
existing=$(docker ps -a --filter "name=^/$name$" --format '{{.Names}}')
[ -z "$existing" ] || exit 2
parent=$(mktemp -d /home/lexlapax/projects/lexlapax/ipse/.serenity-sixth-receipt.XXXXXXXX)
chmod 0700 "$parent"
mkdir -m 0755 "$parent/ledger"
stage=$(mktemp -d /tmp/ipse-retry-index-stage.XXXXXXXX)
chmod 0755 "$stage"
cp -- "$program" "$stage/loop-index-create"
chmod 0700 "$stage/loop-index-create"
stage_identity=$(stat -c '%d:%i' "$stage")
ledger_identity=$(stat -c '%d:%i' "$parent/ledger")
program_identity=$(stat -c '%d:%i' "$stage/loop-index-create")
uid=$(id -u)
host_ns=$(stat -Lc '%i' /proc/self/ns/mnt)
{
 printf 'nonce=%s kernel=%s index=%s host_mount_ns=%s\n' "$nonce" "$(uname -r)" "$index" "$host_ns"
 printf 'prior_ledger=%s prior_index=7:4091 prior_backing=53:317801 preserved=true\n' "$old_ledger"
 printf 'ledger=%s ledger_id=%s stage=%s stage_id=%s program_id=%s:0:700 program_sha256=%s original_uid=%s\n' "$parent/ledger" "$ledger_identity" "$stage" "$stage_identity" "$program_identity" "$expected" "$uid"
 stat -c 'control=%n type=%F major=%t minor=%T uid=%u gid=%g mode=%a dev=%d inode=%i' /dev/loop-control
 printf 'index_before=absent max_part=%s\n' "$(cat /sys/module/loop/parameters/max_part)"
} > "$parent/index-before.txt"
sync -f "$parent/index-before.txt"
sync -f "$parent"
for path in "$stage" "$parent/ledger"; do
 docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN \
  --mount "type=bind,source=$path,destination=/stage" --entrypoint /usr/bin/sh "$image" -c 'set -eu; chown -R 0:0 /stage; chmod 0700 /stage'
done
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = "$stage_identity:0:700" ] || exit 3
[ "$(stat -c '%d:%i:%u:%a' "$parent/ledger")" = "$ledger_identity:0:700" ] || exit 3
docker run --rm --pull never --network none --read-only --cap-drop ALL \
 --mount "type=bind,source=$stage,destination=/stage,readonly" --entrypoint /usr/bin/sh "$image" -c '
 set -eu
 [ "$(stat -c "%d:%i:%u:%a" /stage/loop-index-create)" = "$1:0:700" ]
 [ "$(sha256sum /stage/loop-index-create | cut -d " " -f 1)" = "$2" ]
 ' sh "$program_identity" "$expected" || exit 3
printf 'container_create=pending\nname=%s\nlabel=ipse.index.run:%s\n' "$name" "$nonce" > "$parent/index-create.pending"
sync -f "$parent/index-create.pending"
sync -f "$parent"
container=$(docker create --name "$name" --label "ipse.index.run=$nonce" --pull never --network none --read-only --cap-drop ALL --cap-add SYS_ADMIN \
 --cgroupns host --pids-limit 8 --memory 64m --cpus 0.5 --device /dev/loop-control:/dev/loop-control:rw \
 --mount "type=bind,source=$stage,destination=/work/tools,readonly" --mount "type=bind,source=$parent/ledger,destination=/work/fixture-ledger" \
 --entrypoint /work/tools/loop-index-create "$image" "$nonce" "$index" "$host_ns")
printf 'CONTAINER_ID=%s\nLEDGER_PARENT=%s\nLEDGER_IDENTITY=%s\nSTAGE=%s\nSTAGE_IDENTITY=%s\nPROGRAM_IDENTITY=%s\n' "$container" "$parent" "$ledger_identity" "$stage" "$stage_identity" "$program_identity"
case "$container" in *[!0-9a-f]*|'') exit 4;; esac
[ "${#container}" -eq 64 ] || exit 4
[ "$(docker inspect --format '{{.Id}} {{.Image}} {{.Name}} {{.HostConfig.Privileged}} {{.HostConfig.NetworkMode}} {{index .Config.Labels "ipse.index.run"}}' "$container")" = "$container $image /$name false none $nonce" ] || exit 4
printf 'container=%s\nindex_add=pending\n' "$container" > "$parent/index-container.txt"
sync -f "$parent/index-container.txt"
sync -f "$parent"
set +e
timeout 30s docker start -a "$container" > "$parent/index-container.stdout" 2> "$parent/index-container.stderr"
status=$?
set -e
{
 printf 'docker_start_exit=%s\n' "$status"
 if [ -e "/sys/dev/block/7:$index" ]; then stat -Lc 'sysfs_dev=%d sysfs_inode=%i' "/sys/dev/block/7:$index"; else printf 'index_after=absent_or_unavailable\n'; fi
} > "$parent/index-after.txt"
sync -f "$parent/index-container.stdout"
sync -f "$parent/index-container.stderr"
sync -f "$parent/index-after.txt"
sync -f "$parent"
[ "$status" -eq 0 ] || { printf '%s\n' 'UNKNOWN: retain exact container, stage, index and ledger'; exit 5; }
[ "$(docker inspect --format '{{.Id}} {{.State.Running}} {{.State.ExitCode}}' "$container")" = "$container false 0" ] || { printf '%s\n' 'UNKNOWN: retain exact container, stage, index and ledger'; exit 5; }
printf '%s\n' 'FRESH_INDEX_ADD_OBSERVED: retain exact container, stage, index and ledger for review'
