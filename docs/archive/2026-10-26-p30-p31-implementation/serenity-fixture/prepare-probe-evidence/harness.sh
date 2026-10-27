#!/bin/sh
# Read-only node/namespace checks; no block-node mapping, device open or ioctl.
set -eu
set -C
image=sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af
nonce=8baf34eff3b8498eaff2007c6f8a4c12
name=ipse-prepare-$nonce
probe=/tmp/ipse-prepare-probe/probe
hash=96a262197ba3f3b2056446003be2fcefae1a64d1e090fd5f0d6175ef876fdab9
[ "$(stat -Lc %i /proc/self/ns/mnt)" = 4026531832 ] || exit 2
[ "$(sha256sum "$probe" | cut -d ' ' -f1)" = "$hash" ] || exit 2
[ -z "$(docker ps -a --filter "name=^/$name$" --format '{{.Names}}')" ] || exit 2
stage=$(mktemp -d /tmp/ipse-prepare-stage.XXXXXXXX)
chmod 0755 "$stage"
cp "$probe" "$stage/probe"
chmod 0700 "$stage/probe"
stageid=$(stat -c '%d:%i' "$stage")
probeid=$(stat -c '%d:%i' "$stage/probe")
uid=$(id -u)
printf 'stage=%s stageid=%s probeid=%s uid=%s nonce=%s\n' "$stage" "$stageid" "$probeid" "$uid" "$nonce"
docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN --mount "type=bind,source=$stage,destination=/stage" --entrypoint /usr/bin/sh "$image" -c 'set -eu; chown -Rh 0:0 /stage; chmod 0700 /stage'
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = "$stageid:0:700" ] || exit 3
docker run --rm --pull never --network none --read-only --cap-drop ALL --mount "type=bind,source=$stage,destination=/stage,readonly" --entrypoint /usr/bin/sh "$image" -c '
set -eu
[ "$(stat -c "%d:%i:%u:%a" /stage/probe)" = "$1:0:700" ]
[ "$(sha256sum /stage/probe | cut -d " " -f1)" = "$2" ]
[ "$(ls -A /stage)" = probe ]
' sh "$probeid" "$hash" || exit 3
printf 'container_create=pending name=%s nonce=%s\n' "$name" "$nonce"
container=$(docker create --name "$name" --label "ipse.prepare.run=$nonce" --pull never --network none --read-only --cap-drop ALL --cap-add SYS_ADMIN --cap-add MKNOD --security-opt no-new-privileges=true --cgroupns host --pids-limit 128 --memory 1g --cpus 2 --device /dev/mapper/control:/dev/mapper/control:rw --device-cgroup-rule 'b 7:4092 rwm' --device-cgroup-rule 'b 252:4092 rwm' --mount "type=bind,source=$stage,destination=/work/tools,readonly" --entrypoint /work/tools/probe "$image")
printf 'container=%s\n' "$container"
case "$container" in *[!0-9a-f]*|'') exit 4;; esac
[ "${#container}" -eq 64 ] || exit 4
[ "$(docker inspect --format '{{.Id}} {{.Image}} {{.Name}} {{.HostConfig.Privileged}} {{.HostConfig.NetworkMode}} {{index .Config.Labels "ipse.prepare.run"}}' "$container")" = "$container $image /$name false none $nonce" ] || exit 4
set +e
timeout 15s docker start -a "$container"
status=$?
set -e
printf 'docker_start_exit=%s\n' "$status"
[ "$status" -eq 0 ] || { printf '%s\n' 'UNKNOWN: retain exact container and stage'; exit 5; }
[ "$(docker inspect --format '{{.Id}} {{.State.Running}} {{.State.ExitCode}}' "$container")" = "$container false 0" ] || exit 5
printf '%s\n' 'RETAIN: inspect exact stopped container and stage'
