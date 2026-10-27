#!/bin/sh
# No-device synthetic listener root-mode test; retained exact stage/container.
set -eu
set -C
image=sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af
nonce=4cc69510aa7c4885a753c0e1e3270e77
name=ipse-listener-$nonce
listener=/tmp/ipse-listener-diagnostics/peer_listener
runner=/tmp/ipse-live-candidate.r2vcuE5y/runtime/priv/ipse-runner
lh=8b55476acb9174e7785ef453cf92daebffa3a1fe005676572d79823ad926f85f
rh=4def0d0a3e3bffbdd705d73beb91218154c8bbe9f8f708632a1b2065c245a596
[ "$(sha256sum "$listener" | cut -d ' ' -f1)" = "$lh" ] || exit 2
[ "$(sha256sum "$runner" | cut -d ' ' -f1)" = "$rh" ] || exit 2
[ -z "$(docker ps -a --filter "name=^/$name$" --format '{{.Names}}')" ] || exit 2
stage=$(mktemp -d /tmp/ipse-listener-stage.XXXXXXXX)
chmod 0755 "$stage"
mkdir -m 0755 "$stage/tools" "$stage/runtime" "$stage/mount" "$stage/control"
mkdir -m 0755 "$stage/runtime/priv" "$stage/mount/transaction"
cp "$listener" "$stage/tools/peer_listener"
cp "$runner" "$stage/runtime/priv/ipse-runner"
chmod 0700 "$stage/tools/peer_listener" "$stage/runtime/priv/ipse-runner"
stageid=$(stat -c '%d:%i' "$stage"); uid=$(id -u)
printf 'stage=%s stageid=%s uid=%s nonce=%s\n' "$stage" "$stageid" "$uid" "$nonce"
docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN --mount "type=bind,source=$stage,destination=/stage" --entrypoint /usr/bin/sh "$image" -c 'set -eu; chown -Rh 0:0 /stage; chmod 0700 /stage /stage/control /stage/mount/transaction'
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = "$stageid:0:700" ] || exit 3
docker run --rm --pull never --network none --read-only --cap-drop ALL --mount "type=bind,source=$stage,destination=/stage,readonly" --entrypoint /usr/bin/sh "$image" -c '
set -eu
[ "$(sha256sum /stage/tools/peer_listener | cut -d " " -f1)" = "$1" ]
[ "$(sha256sum /stage/runtime/priv/ipse-runner | cut -d " " -f1)" = "$2" ]
[ "$(stat -c %a /stage/mount)" = 755 ]
[ "$(stat -c %a /stage/mount/transaction)" = 700 ]
[ "$(stat -c %a /stage/control)" = 700 ]
' sh "$lh" "$rh" || exit 3
printf 'container_create=pending name=%s\n' "$name"
container=$(docker create --name "$name" --label "ipse.listener.run=$nonce" --pull never --network none --read-only --cap-drop ALL --security-opt no-new-privileges=true --pids-limit 8 --memory 64m --cpus 0.5 --mount "type=bind,source=$stage/tools,destination=/work/tools,readonly" --mount "type=bind,source=$stage/runtime,destination=/work/runtime,readonly" --mount "type=bind,source=$stage/mount,destination=/work/mount,bind-propagation=rprivate" --mount "type=bind,source=$stage/control,destination=/work/control,bind-propagation=rprivate" --entrypoint /usr/bin/sh "$image" -c '
set -eu
set +e
/work/tools/peer_listener /work/control/native-stage.sock /work/mount/transaction /work/runtime/priv/ipse-runner > /work/control/0755.stdout 2> /work/control/0755.stderr
s1=$?
set -e
[ "$s1" -ne 0 ] && grep -q "mount root rejected.*mode=755" /work/control/0755.stderr
[ ! -e /work/control/native-stage.sock ]
chmod 0700 /work/mount
set +e
timeout 2s /work/tools/peer_listener /work/control/native-stage.sock /work/mount/transaction /work/runtime/priv/ipse-runner > /work/control/0700.stdout 2> /work/control/0700.stderr
s2=$?
set -e
[ "$s2" -eq 124 ] && [ "$(cat /work/control/0700.stdout)" = LISTENING ]
printf "MODE_0755_REFUSED status=%s\nMODE_0700_LISTENING status=%s\n" "$s1" "$s2"
')
printf 'container=%s\n' "$container"
case "$container" in *[!0-9a-f]*|'') exit 4;; esac
[ "${#container}" -eq 64 ] || exit 4
[ "$(docker inspect --format '{{.Id}} {{.Image}} {{.Name}} {{.HostConfig.Privileged}} {{.HostConfig.NetworkMode}} {{index .Config.Labels "ipse.listener.run"}}' "$container")" = "$container $image /$name false none $nonce" ] || exit 4
set +e
timeout 15s docker start -a "$container"
status=$?
set -e
printf 'docker_start_exit=%s\n' "$status"
[ "$status" -eq 0 ] || { printf '%s\n' 'UNKNOWN: retain exact container and stage'; exit 5; }
[ "$(docker inspect --format '{{.Id}} {{.State.Running}} {{.State.ExitCode}}' "$container")" = "$container false 0" ] || exit 5
printf '%s\n' 'RETAIN: inspect exact stopped container and stage'
