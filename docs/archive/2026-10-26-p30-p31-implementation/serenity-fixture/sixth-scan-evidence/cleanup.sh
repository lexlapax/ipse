#!/bin/sh
# Exact disposable scanner cleanup only; stop on any mismatch.
set -eu
image=sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af
nonce=7155ed5255d14270bb6d2e210744c195
container=71970a4570a818a290c9ba71c5d66521670ab2008fa2420974b471c2811e3733
stage=/tmp/ipse-quiescence-stage.9pDdkFhN
hash=00fd35baaafc7bc25d4b32f04cc1a62b2c173cd899f0960767e0d580d52c3528
[ "$(docker inspect --format '{{.Id}} {{.Name}} {{.Image}} {{.State.Running}} {{.State.ExitCode}} {{index .Config.Labels "ipse.quiescence.run"}}' "$container")" = "$container /ipse-quiescence-$nonce $image false 0 $nonce" ] || exit 2
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = '53:328992:0:700' ] || exit 2
check='set -eu
[ "$(stat -c "%d:%i:%u:%a" /stage)" = "53:328992:0:700" ]
[ "$(stat -c "%d:%i:%u:%a:%F" /stage/scan)" = "53:328993:0:700:regular file" ]
[ "$(sha256sum /stage/scan | cut -d " " -f1)" = "$1" ]
[ "$(ls -A /stage)" = scan ]'
docker run --rm --pull never --network none --read-only --cap-drop ALL --mount "type=bind,source=$stage,destination=/stage,readonly" --entrypoint /usr/bin/sh "$image" -c "$check" sh "$hash"
[ "$(docker inspect --format '{{.Id}} {{.State.Running}} {{.State.ExitCode}}' "$container")" = "$container false 0" ] || exit 2
docker rm "$container"
docker run --rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN --mount "type=bind,source=$stage,destination=/stage" --entrypoint /usr/bin/sh "$image" -c "$check
rm /stage/scan
[ -z \"\$(ls -A /stage)\" ]
chown 1000:1000 /stage" sh "$hash"
[ "$(stat -c '%d:%i:%u:%a' "$stage")" = '53:328992:1000:700' ] || exit 2
[ -z "$(ls -A "$stage")" ] || exit 2
rmdir "$stage"
printf '%s\n' 'EXACT_SCANNER_STAGE_AND_CONTAINER_REMOVED'
