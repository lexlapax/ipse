#!/bin/sh
# Review only: one isolated tmpfs overmount; no block devices or host mounts.
# Retain exact container and staged files for inspection on all outcomes.
set -eu
set -C
image=sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af
nonce=8a618cba8c2347f8819287a3c90ad13b
name=ipse-overlay-$nonce
probe=/tmp/ipse-bind-overlay-probe-v2
hash=db60c39445840674302bb2575af538f6faa0d77e89c02aaf4f7e035f11582077
[ "$(stat -Lc %i /proc/self/ns/mnt)" = 4026531832 ] || exit 2
[ "$(sha256sum "$probe" | cut -d ' ' -f1)" = "$hash" ] || exit 2
[ -z "$(docker ps -a --filter "name=^/$name$" --format '{{.Names}}')" ] || exit 2
stage=$(mktemp -d /tmp/ipse-overlay-stage.XXXXXXXX)
chmod 0755 "$stage"
mkdir -m 0755 "$stage/bin" "$stage/mount"
cp "$probe" "$stage/bin/probe"
chmod 0700 "$stage/bin/probe"
stageid=$(stat -c '%d:%i' "$stage")
binid=$(stat -c '%d:%i' "$stage/bin")
probeid=$(stat -c '%d:%i' "$stage/bin/probe")
mountid=$(stat -c '%d:%i' "$stage/mount")
uid=$(id -u)
printf 'stage=%s stageid=%s binid=%s probeid=%s mountid=%s original_uid=%s nonce=%s\n' "$stage" "$stageid" "$binid" "$probeid" "$mountid" "$uid" "$nonce"
docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN --mount "type=bind,source=$stage,destination=/stage" --entrypoint /usr/bin/sh "$image" -c 'set -eu; chown -Rh 0:0 /stage; chmod 0700 /stage /stage/bin /stage/mount'
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = "$stageid:0:700" ] || exit 3
docker run --rm --pull never --network none --read-only --cap-drop ALL --mount "type=bind,source=$stage,destination=/stage,readonly" --entrypoint /usr/bin/sh "$image" -c '
set -eu
[ "$(stat -c "%d:%i:%u:%a" /stage/bin/probe)" = "$1:0:700" ]
[ "$(stat -c "%d:%i:%u:%a" /stage/mount)" = "$2:0:700" ]
[ "$(sha256sum /stage/bin/probe | cut -d " " -f1)" = "$3" ]
[ -z "$(ls -A /stage/mount)" ]
' sh "$probeid" "$mountid" "$hash" || exit 3
printf 'container_create=pending name=%s nonce=%s\n' "$name" "$nonce"
container=$(docker create --name "$name" --label "ipse.overlay.run=$nonce" --pull never --network none --read-only --cap-drop ALL --cap-add SYS_ADMIN --security-opt no-new-privileges=true --pids-limit 8 --memory 64m --cpus 0.5 --mount "type=bind,source=$stage/bin,destination=/work/bin,readonly" --mount "type=bind,source=$stage/mount,destination=/work/mount,bind-propagation=rprivate" --entrypoint /work/bin/probe "$image" 4026531832 "${mountid%:*}" "${mountid#*:}")
printf 'container=%s\n' "$container"
case "$container" in *[!0-9a-f]*|'') exit 4;; esac
[ "${#container}" -eq 64 ] || exit 4
[ "$(docker inspect --format '{{.Id}} {{.Image}} {{.Name}} {{.HostConfig.Privileged}} {{.HostConfig.NetworkMode}} {{index .Config.Labels "ipse.overlay.run"}}' "$container")" = "$container $image /$name false none $nonce" ] || exit 4
mounts=$(docker inspect --format '{{range .Mounts}}{{.Source}} {{.Destination}} {{.RW}} {{.Propagation}}{{println}}{{end}}' "$container" | LC_ALL=C sort)
expected_mounts=$(printf '%s\n%s\n' "$stage/bin /work/bin false rprivate" "$stage/mount /work/mount true rprivate" | LC_ALL=C sort)
[ "$mounts" = "$expected_mounts" ] || exit 4
[ "$(docker inspect --format '{{json .HostConfig.Devices}} {{json .HostConfig.DeviceCgroupRules}} {{json .HostConfig.CapAdd}} {{json .HostConfig.CapDrop}}' "$container")" = '[] null ["CAP_SYS_ADMIN"] ["ALL"]' ] || exit 4
set +e
timeout 15s docker start -a "$container"
status=$?
set -e
printf 'docker_start_exit=%s\n' "$status"
[ "$status" -eq 0 ] || { printf '%s\n' 'UNKNOWN: retain exact container and stage'; exit 5; }
[ "$(docker inspect --format '{{.Id}} {{.State.Running}} {{.State.ExitCode}}' "$container")" = "$container false 0" ] || exit 5
printf '%s\n' 'OBSERVED: retain exact stopped container and stage for independent inspection'
