#!/bin/sh
# Exact disposable listener probe cleanup only; stop on mismatch.
set -eu
image=sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af
nonce=4cc69510aa7c4885a753c0e1e3270e77
container=e94b32462e8df2747f0f1dabe59260b69e7ffd9cd682af843416d8d5cf7a1828
stage=/tmp/ipse-listener-stage.7CmHouXR
[ "$(docker inspect --format '{{.Id}} {{.Name}} {{.Image}} {{.State.Running}} {{.State.ExitCode}} {{index .Config.Labels "ipse.listener.run"}}' "$container")" = "$container /ipse-listener-$nonce $image false 0 $nonce" ] || exit 2
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = '53:318715:0:700' ] || exit 2
check='set -eu
[ "$(find /stage -printf "%p\n" | sort)" = "$(printf "%s\n" /stage /stage/control /stage/control/0700.stderr /stage/control/0700.stdout /stage/control/0755.stderr /stage/control/0755.stdout /stage/control/native-stage.sock /stage/mount /stage/mount/transaction /stage/runtime /stage/runtime/priv /stage/runtime/priv/ipse-runner /stage/tools /stage/tools/peer_listener | sort)" ]
for pair in "/stage:318715:700:directory" "/stage/tools:318716:755:directory" "/stage/runtime:318717:755:directory" "/stage/mount:318718:700:directory" "/stage/control:318719:700:directory" "/stage/runtime/priv:318720:755:directory" "/stage/mount/transaction:318721:700:directory" "/stage/tools/peer_listener:318722:700:regular file" "/stage/runtime/priv/ipse-runner:318723:700:regular file" "/stage/control/0755.stdout:318725:644:regular file" "/stage/control/0755.stderr:318726:644:regular file" "/stage/control/0700.stdout:318727:644:regular file" "/stage/control/0700.stderr:318728:644:regular file" "/stage/control/native-stage.sock:318729:755:socket"; do
 path=${pair%%:*}; rest=${pair#*:}; ino=${rest%%:*}; rest=${rest#*:}; mode=${rest%%:*}; type=${rest#*:}
 [ "$(stat -c "%d:%i:%u:%a:%F" "$path")" = "53:$ino:0:$mode:$type" ]
done
[ "$(sha256sum /stage/tools/peer_listener | cut -d " " -f1)" = 8b55476acb9174e7785ef453cf92daebffa3a1fe005676572d79823ad926f85f ]
[ "$(sha256sum /stage/runtime/priv/ipse-runner | cut -d " " -f1)" = 4def0d0a3e3bffbdd705d73beb91218154c8bbe9f8f708632a1b2065c245a596 ]
[ "$(sha256sum /stage/control/0700.stdout | cut -d " " -f1)" = fc3101f3dabfb924ac9b6e20e1c7613c43ee8279d9a77ecb7290b75b0834f2b4 ]
[ "$(sha256sum /stage/control/0755.stderr | cut -d " " -f1)" = 304f948b513379f09eeb0a3e8febd6d850ebf7669dde81841cbf0dbb9374571e ]
[ ! -s /stage/control/0755.stdout ] && [ ! -s /stage/control/0700.stderr ]'
docker run --rm --pull never --network none --read-only --cap-drop ALL --mount "type=bind,source=$stage,destination=/stage,readonly" --entrypoint /usr/bin/sh "$image" -c "$check"
[ "$(docker inspect --format '{{.Id}} {{.State.Running}} {{.State.ExitCode}}' "$container")" = "$container false 0" ] || exit 2
docker rm "$container"
docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN --mount "type=bind,source=$stage,destination=/stage" --entrypoint /usr/bin/sh "$image" -c "$check
rm /stage/control/0700.stderr /stage/control/0700.stdout /stage/control/0755.stderr /stage/control/0755.stdout /stage/control/native-stage.sock /stage/tools/peer_listener /stage/runtime/priv/ipse-runner
rmdir /stage/control /stage/mount/transaction /stage/mount /stage/runtime/priv /stage/runtime /stage/tools
[ -z \"\$(ls -A /stage)\" ]
chown 1000:1000 /stage"
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = '53:318715:1000:700' ] || exit 2
[ -z "$(ls -A "$stage")" ] || exit 2
rmdir "$stage"
printf '%s\n' 'EXACT_LISTENER_STAGE_AND_CONTAINER_REMOVED'
