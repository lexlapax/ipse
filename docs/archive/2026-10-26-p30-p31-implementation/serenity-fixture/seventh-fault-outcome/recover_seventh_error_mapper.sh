#!/bin/sh
# REVIEW ONLY: optional removal of exactly one retained synthetic mapper.
# Never remove or truncate its backing file, loop index, stage or ledger.
# A timeout/failure is unknown and is never retried automatically.
set -eu
set -C
image='sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af'
parent='/home/lexlapax/projects/lexlapax/ipse/.serenity-seventh-receipt.62mbAQNi'
ledger="$parent/ledger"
stage='/tmp/ipse-fault-stage.sFqNh39m'
nonce='23456b0d98b24adcb65d36e11a87fb83'
uuid="IPSE-Q-$nonce"
name="ipse-q-$nonce"
old='75438077d924e39164f225b769d02aa9ec37dd01dc011515db131dc40ed89a57'
recovery_name="ipse-recovery-$nonce"
[ "$(stat -c '%d:%i:%u:%a' "$ledger")" = '29:13366395:0:700' ] || exit 2
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = '53:332686:0:700' ] || exit 2
[ "$(docker inspect --format '{{.Id}} {{.Name}} {{.Image}} {{.State.Running}} {{.State.ExitCode}}' "$old")" = "$old /ipse-fault-$nonce $image false 3" ] || exit 2
existing=$(docker ps -a --filter "name=^/$recovery_name$" --format '{{.Names}}')
[ -z "$existing" ] || exit 2
[ "$(stat -Lc '%d:%i' /sys/dev/block/7:4089)" = '25:820008' ] || exit 2
[ "$(stat -Lc '%d:%i' /sys/dev/block/252:4089)" = '25:821994' ] || exit 2
[ "$(cat /sys/dev/block/252:4089/dm/name)" = "$name" ] || exit 2
[ "$(cat /sys/dev/block/252:4089/dm/uuid)" = "$uuid" ] || exit 2
[ -z "$(ls -A /sys/dev/block/7:4089/holders)" ] || exit 2
[ -z "$(ls -A /sys/dev/block/252:4089/slaves)" ] || exit 2
[ -z "$(ls -A /sys/dev/block/252:4089/holders)" ] || exit 2
# Inspect the exact stage and confirm the tool bundle and backing without writes.
docker run --rm --pull never --network none --read-only --cap-drop ALL \
 --mount "type=bind,source=$stage,destination=/stage,readonly" --entrypoint /usr/bin/sh "$image" -c '
set -eu
[ "$(stat -c "%d:%i:%u:%a" /stage)" = "53:332686:0:700" ]
[ "$(stat -c "%d:%i:%u:%a:%h:%s" /stage/fixture/backing.img)" = "53:333411:0:600:1:536870912" ]
cd /stage
[ "$(sha256sum SHA256SUMS)" = "25dab5b0a4a849eab998f76be5e4c12bcccbc6af89acda90e63f7dd31018f669  SHA256SUMS" ]
sha256sum -c --status SHA256SUMS
'
# Read-only DM status and table commands, each with the exact UUID selector.
query() {
 docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add SYS_ADMIN \
  --device /dev/mapper/control:/dev/mapper/control:rw \
  --mount "type=bind,source=$stage/tools,destination=/work/tools,readonly" \
  --env LD_LIBRARY_PATH=/work/tools/lib --entrypoint /work/tools/bin/dmsetup "$image" "$@"
}
info=$(query --columns --noheadings --separator '|' -o name,uuid,major,minor,open info --uuid "$uuid")
[ "$info" = "$name|$uuid|252|4089|0" ] || exit 2
active=$(query table --uuid "$uuid")
set -- $active
[ "$#" -eq 3 ] && [ "$1" = 0 ] && [ "$2" = 1048576 ] && [ "$3" = error ] || exit 2
inactive=$(query --inactive table --uuid "$uuid")
[ -z "$inactive" ] || exit 2
# Recheck the two kernel objects and identity immediately before journaling.
[ "$(stat -Lc '%d:%i' /sys/dev/block/7:4089)" = '25:820008' ] || exit 2
[ "$(stat -Lc '%d:%i' /sys/dev/block/252:4089)" = '25:821994' ] || exit 2
[ "$(cat /sys/dev/block/252:4089/dm/uuid)" = "$uuid" ] || exit 2
{
 printf 'recovery=pending operation=nondeferred-remove uuid=%s name=%s mapper=252:4089 sysfs=25:821994\n' "$uuid" "$name"
 printf 'loop=7:4089 sysfs=25:820008 backing=53:333411 size=536870912 release=unknown\n'
 printf 'active=%s\ncontainer_name=%s\ncontainer_label=ipse.recovery.run:%s\n' "$active" "$recovery_name" "$nonce"
 printf 'backing_and_loop_index=preserve\n'
} > "$parent/recovery-remove.pending"
sync -f "$parent/recovery-remove.pending"
sync -f "$parent"
# Exact UUID, nondeferred and no --force/--retry. If Docker create succeeds but
# the CLI loses its response, the recorded name/label support inspection only.
container=$(docker create --name "$recovery_name" --label "ipse.recovery.run=$nonce" \
 --pull never --network none --read-only --cap-drop ALL --cap-add SYS_ADMIN \
 --pids-limit 8 --memory 64m --cpus 0.5 --device /dev/mapper/control:/dev/mapper/control:rw \
 --mount "type=bind,source=$stage/tools,destination=/work/tools,readonly" \
 --env LD_LIBRARY_PATH=/work/tools/lib --entrypoint /work/tools/bin/dmsetup "$image" remove --uuid "$uuid")
printf 'RECOVERY_CONTAINER_ID=%s\n' "$container"
case "$container" in *[!0-9a-f]*|'') exit 3;; esac
[ "${#container}" -eq 64 ] || exit 3
[ "$(docker inspect --format '{{.Id}} {{.Image}} {{.Name}} {{.HostConfig.Privileged}} {{.HostConfig.NetworkMode}} {{index .Config.Labels "ipse.recovery.run"}}' "$container")" = "$container $image /$recovery_name false none $nonce" ] || exit 3
printf 'container=%s\nremove_attempt=pending\n' "$container" > "$parent/recovery-container.txt"
sync -f "$parent/recovery-container.txt"
sync -f "$parent"
set +e
timeout 30s docker start -a "$container" > "$parent/recovery-container.stdout" 2> "$parent/recovery-container.stderr"
status=$?
set -e
{
 printf 'docker_start_exit=%s\n' "$status"
 if [ -e /sys/dev/block/252:4089 ]; then stat -Lc 'mapper_sysfs_dev=%d mapper_sysfs_inode=%i' /sys/dev/block/252:4089; else printf 'mapper_sysfs=absent_or_unavailable\n'; fi
 if [ -e /sys/dev/block/7:4089 ]; then stat -Lc 'loop_sysfs_dev=%d loop_sysfs_inode=%i' /sys/dev/block/7:4089; else printf 'loop_sysfs=absent_or_unavailable\n'; fi
} > "$parent/recovery-after.txt"
sync -f "$parent/recovery-container.stdout"
sync -f "$parent/recovery-container.stderr"
sync -f "$parent/recovery-after.txt"
sync -f "$parent"
if [ "$status" -eq 0 ] && [ "$(docker inspect --format '{{.Id}} {{.State.Running}} {{.State.ExitCode}}' "$container")" = "$container false 0" ] && [ ! -e /sys/dev/block/252:4089 ]; then
 printf 'remove_command=exit0 mapper_sysfs=not_observed backing_release=unknown loop_index=retain\n' > "$parent/recovery-remove.observed"
 sync -f "$parent/recovery-remove.observed"
 sync -f "$parent"
fi
printf '%s\n' 'RECOVERY_OUTCOME_UNKNOWN: retain exact container, backing, index, stage and ledger for independent inspection'
