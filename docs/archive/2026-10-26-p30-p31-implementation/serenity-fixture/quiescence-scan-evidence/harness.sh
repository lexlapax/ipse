#!/bin/sh
# Bounded read-only host PID snapshot. Retain stage/container on all outcomes.
set -eu
set -C
image=sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af
nonce=2cef84595b244091a077cc2e94e43381
name=ipse-quiescence-$nonce
probe=/tmp/ipse-quiescence-scan/scan
hash=484d5c1f5a5c0800e5b4ef5d9c0fb06feabe75dcc1d5a165b057a94c64465f03
[ "$(sha256sum "$probe" | cut -d ' ' -f1)" = "$hash" ] || exit 2
[ -z "$(docker ps -a --filter "name=^/$name$" --format '{{.Names}}')" ] || exit 2
stage=$(mktemp -d /tmp/ipse-quiescence-stage.XXXXXXXX)
chmod 0755 "$stage"
cp "$probe" "$stage/scan"
chmod 0700 "$stage/scan"
stageid=$(stat -c '%d:%i' "$stage"); probeid=$(stat -c '%d:%i' "$stage/scan"); uid=$(id -u)
printf 'stage=%s stageid=%s probeid=%s uid=%s nonce=%s\n' "$stage" "$stageid" "$probeid" "$uid" "$nonce"
docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN --mount "type=bind,source=$stage,destination=/stage" --entrypoint /usr/bin/sh "$image" -c 'set -eu; chown -Rh 0:0 /stage; chmod 0700 /stage'
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = "$stageid:0:700" ] || exit 3
docker run --rm --pull never --network none --read-only --cap-drop ALL --mount "type=bind,source=$stage,destination=/stage,readonly" --entrypoint /usr/bin/sh "$image" -c '
set -eu
[ "$(stat -c "%d:%i:%u:%a" /stage/scan)" = "$1:0:700" ]
[ "$(sha256sum /stage/scan | cut -d " " -f1)" = "$2" ]
[ "$(ls -A /stage)" = scan ]
' sh "$probeid" "$hash" || exit 3
printf 'container_create=pending name=%s nonce=%s\n' "$name" "$nonce"
container=$(docker create --name "$name" --label "ipse.quiescence.run=$nonce" --pull never --network none --read-only --pid host --cap-drop ALL --cap-add SYS_PTRACE --cap-add DAC_READ_SEARCH --security-opt no-new-privileges=true --pids-limit 8 --memory 128m --cpus 1 --mount "type=bind,source=$stage,destination=/work/tools,readonly" --entrypoint /work/tools/scan "$image")
printf 'container=%s\n' "$container"
case "$container" in *[!0-9a-f]*|'') exit 4;; esac
[ "${#container}" -eq 64 ] || exit 4
[ "$(docker inspect --format '{{.Id}} {{.Image}} {{.Name}} {{.HostConfig.Privileged}} {{.HostConfig.NetworkMode}} {{.HostConfig.PidMode}} {{index .Config.Labels "ipse.quiescence.run"}}' "$container")" = "$container $image /$name false none host $nonce" ] || exit 4
set +e
timeout 30s docker start -a "$container"
status=$?
set -e
printf 'docker_start_exit=%s\n' "$status"
[ "$status" -eq 0 ] || { printf '%s\n' 'UNKNOWN: retain exact container and stage'; exit 5; }
[ "$(docker inspect --format '{{.Id}} {{.State.Running}} {{.State.ExitCode}}' "$container")" = "$container false 0" ] || exit 5
printf '%s\n' 'RETAIN: snapshot is not proof of quiescence; inspect exact container and stage'
