#!/bin/sh
# REVIEW ONLY: this can bind a backing file and create a device mapper, Btrfs
# filesystem and temporary mount. Do not run before independent review.
# On every outcome all exact container, stage, ledger, index and mapper state
# is retained. Container exit and kernel AUTOCLEAR may still change resources.
set -eu
set -C
image='sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af'
parent='/home/lexlapax/projects/lexlapax/ipse/.serenity-seventh-receipt.62mbAQNi'
ledger="$parent/ledger"
nonce='23456b0d98b24adcb65d36e11a87fb83'
loop_minor=4089
dm_major=252
dm_minor=4089
candidate='/tmp/ipse-live-candidate.Uol5d2U5'
manifest_hash='25dab5b0a4a849eab998f76be5e4c12bcccbc6af89acda90e63f7dd31018f669'
[ "$(stat -c '%d:%i:%u:%a' "$ledger")" = '29:13366395:0:700' ] || exit 2
[ "$(uname -r)" = "7.2.11-arch1-1" ] || exit 2
space_kib=$(df -Pk /tmp | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)
case "$space_kib" in *[!0-9]*|'') exit 2;; esac
[ "$space_kib" -ge 1048576 ] || exit 2
[ "$(stat -Lc '%d:%i' /sys/dev/block/7:4089)" = '25:820008' ] || exit 2
[ -d /sys/module/loop ] && [ -d /sys/module/dm_mod ] && [ "$(cat /sys/module/loop/parameters/max_part)" = 0 ] || exit 2
[ ! -e /sys/dev/block/252:4089 ] || exit 2
# Udev created this host node for the retained index. Inspect it only; the
# diagnostic never opens or removes it and creates a private node instead.
[ "$(stat -c '%F:%t:%T:%d:%i' /dev/loop4089)" = "block special file:7:ff9:7:1641" ] || exit 2
[ "$(stat -c '%F:%t:%T:%d:%i' /dev/mapper/control)" = "character special file:a:ec:7:775" ] || exit 2
dm_seen=no
while read -r number name; do if [ "$number" = 252 ] && [ "$name" = device-mapper ]; then dm_seen=yes; fi; done < /proc/devices
[ "$dm_seen" = yes ] || exit 2
[ "$(stat -Lc '%d:%i' /dev)" = '7:1' ] || exit 2
[ "$(stat -Lc '%i' /proc/self/ns/mnt)" = '4026531832' ] || exit 2
actual=$(sha256sum "$candidate/SHA256SUMS"); actual=${actual%% *}; [ "$actual" = "$manifest_hash" ] || exit 2
(cd "$candidate" && sha256sum -c --status SHA256SUMS) || exit 2
# Check both persistent evidence files and ensure no earlier diagnostic exists.
observed=$(docker run --rm --pull never --network none --read-only --cap-drop ALL \
 --mount "type=bind,source=$ledger,destination=/ledger,readonly" --entrypoint /usr/bin/sh "$image" -c '
set -eu
[ "$(sha256sum /ledger/index-add.receipt)" = "a46a66a1ef17faf56d5d975248f96c18e259dee72a370cc8842eca02ce78365a  /ledger/index-add.receipt" ]
[ "$(ls -A /ledger | sort)" = "index-add.receipt" ]
printf OK
')
[ "$observed" = OK ] || exit 2
name="ipse-fault-$nonce"
existing=$(docker ps -a --filter "name=^/$name$" --format '{{.Names}}')
[ -z "$existing" ] || exit 2
stage=$(mktemp -d /tmp/ipse-fault-stage.XXXXXXXX)
chmod 0755 "$stage"
cp -a "$candidate/tools" "$candidate/runtime" "$candidate/project" "$stage/"
cp "$candidate/SHA256SUMS" "$stage/SHA256SUMS"
mkdir -m 0755 "$stage/fixture" "$stage/mount" "$stage/control"
identity=$(stat -c '%d:%i' "$stage")
uid=$(id -u)
{
 printf 'nonce=%s kernel=%s loop=7:%s dm=%s:%s host_mount_ns=4026531832 host_dev=7:1\n' "$nonce" "$(uname -r)" "$loop_minor" "$dm_major" "$dm_minor"
 printf 'index_host_sysfs=25:820008 ledger=%s ledger_id=29:13366395 stage=%s stage_id=%s original_uid=%s bundle_sha256=%s\n' "$ledger" "$stage" "$identity" "$uid" "$manifest_hash"
 stat -c 'control=%n type=%F major=%t minor=%T uid=%u gid=%g mode=%a dev=%d inode=%i' /dev/mapper/control
 stat -c 'host_loop_node=%n type=%F major=%t minor=%T uid=%u gid=%g mode=%a dev=%d inode=%i' /dev/loop4089
} > "$parent/fault-before.txt"
sync -f "$parent/fault-before.txt"
sync -f "$parent"
# Root takes ownership of this exact private stage. No host device is mapped.
docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN \
 --mount "type=bind,source=$stage,destination=/stage" --entrypoint /usr/bin/sh "$image" -c '
set -eu
chown -Rh 0:0 /stage
chmod 0700 /stage /stage/fixture /stage/mount /stage/control
cd /stage
[ "$(sha256sum SHA256SUMS)" = "25dab5b0a4a849eab998f76be5e4c12bcccbc6af89acda90e63f7dd31018f669  SHA256SUMS" ]
sha256sum -c --status SHA256SUMS
[ "$(find tools runtime project -type f | wc -l)" -eq 656 ]
[ -z "$(find tools runtime project -type f -links +1 -print -quit)" ]
[ "$(find tools runtime project -type l | sort)" = "$(printf "runtime/lib/ipse/priv\nruntime/lib/telemetry/src")" ]
[ "$(readlink runtime/lib/ipse/priv)" = ../../priv ]
[ "$(readlink runtime/lib/telemetry/src)" = ../../../project/deps/telemetry/src ]
'
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = "$identity:0:700" ] || exit 3
printf 'stage_root_owned=confirmed\ncontainer_create=pending\ncontainer_name=%s\ncontainer_label=ipse.diagnostic.run:%s\n' "$name" "$nonce" > "$parent/fault-create.pending"
sync -f "$parent/fault-create.pending"
sync -f "$parent"
container=$(docker create --name "$name" --label "ipse.diagnostic.run=$nonce" --pull never --network none --read-only --cap-drop ALL --cap-add SYS_ADMIN --cap-add MKNOD \
 --security-opt no-new-privileges=true --cgroupns host --pids-limit 128 --memory 1g --cpus 2 \
 --device /dev/mapper/control:/dev/mapper/control:rw \
 --device-cgroup-rule 'b 7:4089 rwm' --device-cgroup-rule 'b 252:4089 rwm' \
 --mount "type=bind,source=$stage/tools,destination=/work/tools,readonly" \
 --mount "type=bind,source=$stage/runtime,destination=/work/runtime,readonly" \
 --mount "type=bind,source=$stage/fixture,destination=/work/fixture,bind-propagation=rprivate" \
 --mount "type=bind,source=$stage/mount,destination=/work/mount,bind-propagation=rprivate" \
 --mount "type=bind,source=$stage/control,destination=/work/control,bind-propagation=rprivate" \
 --mount "type=bind,source=$ledger,destination=/work/fixture-ledger,bind-propagation=rprivate" \
 --mount type=bind,source=/usr/lib/erlang,destination=/usr/lib/erlang,readonly \
 --mount type=bind,source=/usr/lib/elixir,destination=/usr/lib/elixir,readonly \
 --mount type=bind,source=/usr/lib/libsctp.so.1.0.21,destination=/usr/lib/libsctp.so.1,readonly \
 --entrypoint /usr/bin/sh "$image" -c 'set -u; line=$(cat /proc/self/cgroup); id=${line#0::/system.slice/docker-}; id=${id%.scope}; /work/tools/bin/ipse-diagnostic "$1" "$2" "$3" "$4" "$5" "$id" "$6" "$7"; status=$?; sleep 5; exit "$status"' sh "$nonce" "$loop_minor" "$dm_major" "$dm_minor" 4026531832 7 1)
printf 'CONTAINER_ID=%s\nSTAGE=%s\nLEDGER=%s\n' "$container" "$stage" "$ledger"
case "$container" in *[!0-9a-f]*|'') exit 4;; esac
[ "${#container}" -eq 64 ] || exit 4
[ "$(docker inspect --format '{{.Id}} {{.Image}} {{.HostConfig.Privileged}} {{.HostConfig.NetworkMode}} {{.HostConfig.ReadonlyRootfs}} {{.HostConfig.CgroupnsMode}} {{.Name}} {{index .Config.Labels "ipse.diagnostic.run"}}' "$container")" = "$container $image false none true host /$name $nonce" ] || exit 4
docker inspect --format 'caps={{json .HostConfig.CapAdd}} drop={{json .HostConfig.CapDrop}} devices={{json .HostConfig.Devices}} rules={{json .HostConfig.DeviceCgroupRules}} security={{json .HostConfig.SecurityOpt}}' "$container" > "$parent/fault-inspect.txt"
sync -f "$parent/fault-inspect.txt"
printf 'container=%s\ndevice_diagnostic=pending\n' "$container" > "$parent/fault-container.txt"
sync -f "$parent/fault-container.txt"
sync -f "$parent"
# Bound captured output; timeout does not prove container or descendants exited.
ulimit -f 16384
set +e
timeout 180s docker start -a "$container" > "$parent/fault-container.stdout" 2> "$parent/fault-container.stderr"
status=$?
set -e
{
 printf 'docker_start_exit=%s\n' "$status"
 if [ -e /sys/dev/block/7:4089 ]; then stat -Lc 'loop_sysfs_dev=%d loop_sysfs_inode=%i' /sys/dev/block/7:4089; else printf 'loop_sysfs=unavailable\n'; fi
 if [ -e /sys/dev/block/252:4089 ]; then stat -Lc 'mapper_sysfs_dev=%d mapper_sysfs_inode=%i' /sys/dev/block/252:4089; else printf 'mapper_sysfs=absent_or_unavailable\n'; fi
} > "$parent/fault-after.txt"
sync -f "$parent/fault-container.stdout"
sync -f "$parent/fault-container.stderr"
sync -f "$parent/fault-after.txt"
sync -f "$parent"
printf '%s\n' 'UNKNOWN UNTIL REVIEW: retain exact container, stage, index, mapper state and ledger; do not infer cleanup'
