#!/bin/sh
# Review-only command renderer. It cannot start a container. Device mapping,
# staged binary/library attestation, namespace proof and cleanup remain open.
set -eu
if [ "$#" -ne 5 ]; then
  printf '%s\n' 'usage: container_harness.sh NONCE LOOP_MINOR DM_MAJOR DM_MINOR HOST_MOUNT_NS_INODE' >&2
  exit 2
fi
nonce=$1
loop_minor=$2
dm_major=$3
dm_minor=$4
host_ns=$5
case "$nonce" in *[!0-9a-f]*|'') exit 2;; esac
[ "${#nonce}" -eq 32 ] || exit 2
for value in "$loop_minor" "$dm_major" "$dm_minor" "$host_ns"; do
  case "$value" in *[!0-9]*|'') exit 2;; esac
  [ "${#value}" -le 18 ] || exit 2
done
[ "$loop_minor" -le 4095 ] && [ "$dm_major" -gt 0 ] && [ "$dm_major" -ne 7 ] &&
  [ "$dm_minor" -le 65535 ] && [ "$host_ns" -gt 0 ] || exit 2
fixture="/tmp/ipse-btrfs-fault-$nonce"
tools="/tmp/ipse-btrfs-fault-tools-$nonce"
image='sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af'
printf '%s\n' 'REVIEW ONLY: no command below is executed. The controller entry is disabled.'
printf '%s\n' 'The staged tool/library source must have a separately attested, protected immutable lifetime.'
printf '%s\n' 'The default seccomp profile and exact device rules have not been validated for this workload.'
printf '%s\n' \
  "docker run --name ipse-btrfs-$nonce --network none --read-only --cap-drop ALL --cap-add SYS_ADMIN --cap-add MKNOD" \
  "  --device /dev/loop-control --device /dev/mapper/control" \
  "  --device-cgroup-rule 'b 7:$loop_minor rwm' --device-cgroup-rule 'b $dm_major:$dm_minor rwm'" \
  '  --pids-limit 48 --memory 768m --cpus 1' \
  "  --mount 'type=bind,source=$fixture,destination=/work'" \
  "  --mount 'type=bind,source=$tools,destination=/work/tools,readonly'" \
  "  $image /work/tools/bin/ipse-fault-controller $nonce $loop_minor $dm_major $dm_minor $host_ns"
printf '%s\n' 'Do not copy this command as an approved procedure; creation, node ownership, tool pinning, cgroup cleanup and exact teardown remain open.'
