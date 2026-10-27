#!/bin/sh
# REVIEW ONLY: no devices, networking, image pulls, or project mounts.
# Run only after independent review. Unknown results leave the stage for recovery.
set -eu
image='sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af'
probe='/tmp/ipse-runtime-boundary-preflight'
[ -f "$probe" ] && [ ! -L "$probe" ] || exit 2
stage=$(mktemp -d /tmp/ipse-boundary-check.XXXXXXXX)
printf 'STAGE=%s\n' "$stage"
# Traversable but not writable by other users until root takes ownership.
chmod 0755 "$stage"
mkdir -m 0755 "$stage/bin" "$stage/lib"
cp -- "$probe" "$stage/bin/probe"
chmod 0700 "$stage/bin/probe"
identity=$(stat -c '%d:%i' -- "$stage")
uid=$(id -u)
probe_identity=$(stat -c '%d:%i' -- "$stage/bin/probe")
probe_identity="$probe_identity:0:700"
probe_hash=$(sha256sum -- "$stage/bin/probe")
probe_hash=${probe_hash%% *}
printf 'STAGE_IDENTITY=%s ORIGINAL_UID=%s PROBE_IDENTITY=%s SHA256=%s\n' "$identity" "$uid" "$probe_identity" "$probe_hash"
# Root owns every staged object; the /tmp sticky bit then prevents ordinary
# same-user renaming of the root-owned stage entry after this chown.
docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN \
 --mount "type=bind,source=$stage,destination=/stage" --entrypoint /usr/bin/sh "$image" -c 'set -eu; chown -R 0:0 /stage; chmod 0700 /stage /stage/bin /stage/lib'
[ "$(stat -c '%d:%i:%u:%a' -- "$stage")" = "$identity:0:700" ] || exit 3
host_ns=$(stat -Lc '%i' /proc/self/ns/mnt)
printf 'HOST_MOUNT_NS=%s\n' "$host_ns"
# The fixed shell derives its own host-cgroupns scope name, forwards the ID to
# the probe, and prints it. The host independently compares it with Docker's ID.
container=$(docker create --pull never --network none --read-only --cap-drop ALL \
 --cgroupns host --pids-limit 8 --memory 64m --cpus 0.5 \
 --mount "type=bind,source=$stage,destination=/work/tools,readonly" \
 --mount type=bind,source=/usr/lib/erlang,destination=/usr/lib/erlang,readonly \
 --mount type=bind,source=/usr/lib/elixir,destination=/usr/lib/elixir,readonly \
 --mount type=bind,source=/usr/lib/libsctp.so.1.0.21,destination=/usr/lib/libsctp.so.1,readonly \
 --mount type=bind,source=/usr/lib/erlang,destination=/work/runtime,readonly \
 --entrypoint /usr/bin/sh "$image" -c 'set -eu; line=$(cat /proc/self/cgroup); id=${line#0::/system.slice/docker-}; id=${id%.scope}; printf "CGROUP_ID=%s\n" "$id"; exec /work/tools/bin/probe "$id" "$1"' sh "$host_ns")
printf 'CONTAINER_ID=%s\n' "$container"
case "$container" in *[!0-9a-f]*|'') exit 4;; esac
[ "${#container}" -eq 64 ] || exit 4
# Leave the exact stopped container intact if start/inspect/ID verification fails.
output=$(docker start -a "$container")
printf '%s\n' "$output"
[ "$output" = "$(printf 'CGROUP_ID=%s\nRUNTIME_PREFLIGHT_OK' "$container")" ] || exit 5
[ "$(docker inspect --format '{{.Id}} {{.State.Running}} {{.State.ExitCode}}' "$container")" = "$container false 0" ] || exit 5
docker rm "$container"
# The only permitted cleanup is of this exact stage, identity and expected files.
# If any check fails, preserve it; never recursively remove unknown entries.
docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN \
 --mount "type=bind,source=$stage,destination=/stage" --entrypoint /usr/bin/sh "$image" -c '
set -eu
[ "$(stat -c "%d:%i:%u:%a" /stage)" = "$1:0:700" ]
[ "$(ls -A /stage | sort)" = "$(printf "bin\nlib")" ]
[ "$(ls -A /stage/bin)" = probe ]
[ -z "$(ls -A /stage/lib)" ]
[ -f /stage/bin/probe ] && [ ! -L /stage/bin/probe ]
[ "$(stat -c "%d:%i:%u:%a" /stage/bin/probe)" = "$3" ]
set -- "$1" "$2" "$3" "$4"
actual=$(sha256sum /stage/bin/probe); actual=${actual%% *}; [ "$actual" = "$4" ]
rm -- /stage/bin/probe
rmdir -- /stage/bin /stage/lib
chown "$2" /stage
' sh "$identity" "$uid" "$probe_identity" "$probe_hash"
[ "$(stat -c '%d:%i:%u' -- "$stage")" = "$identity:$uid" ] || exit 6
rmdir -- "$stage"
printf '%s\n' 'STAGE_REMOVED'
