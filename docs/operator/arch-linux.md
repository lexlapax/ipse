# Install and run Ipse on Arch Linux

Use a [bundled release](install.md) that matches your machine, or build from source. The
credential-free demo lets you check the installation before signing in to a model
service. Ipse's own ChatGPT login is separate from other coding tools' logins.

## Build from source

Use a fully updated Arch system. The source build requires Elixir 1.18+, OTP 27+,
Rust 1.85+, Git, and a C linker. Arch does not support partial upgrades.

```sh
sudo pacman -Syu --needed elixir erlang rust base-devel git
elixir --version
rustc --version
git clone https://github.com/lexlapax/ipse.git
cd ipse
mix local.hex --force
mix local.rebar --force
./dev/build.sh
./bin/ipse demo
```

Hex/Rebar and the build retrieve the repository's approved dependencies. Check
[the inventory](../developer/dependencies.md) if you need their sources and
licenses. Do not run Mix or Ipse with `sudo`.

The demo should finish without authentication. From this checkout, substitute
`./bin/ipse` for the manual's `ipse`. Rolling toolchain updates can introduce
compatibility differences; a successful install alone does not verify every
integration.

If you intend to contribute, follow the [developer manual](../developer/index.md)
for formatting, compilation, behavior checks, and release verification.

## Start your first real session

For ChatGPT subscription use:

```sh
./bin/ipse login
./bin/ipse status
./bin/ipse chat --provider chatgpt --cwd /path/to/project
```

Complete the printed browser sign-in on a browser that reaches the same host's
loopback callback. The last command makes real subscription requests only after
you submit a task. API and local providers need their own explicit setup; see
[Using Ipse](usage.md#select-a-provider).

Start with a read-only orientation prompt or a disposable directory. Approve each
proposed effect using its printed `allow CODE`. Keep credentials and journals
outside your project.

## Decide whether to use native shell enforcement

Linux native mode requires Landlock ABI 6+ and permitted unprivileged user, mount,
network, and PID namespaces. A compatible kernel alone is insufficient if the
execution environment blocks those facilities.

```sh
./bin/ipse chat --provider chatgpt --cwd /path/to/project --sandbox native
```

This requests workspace/private-temp writes, selected system reads, and denied
external network access for shell calls. Approvals remain required. Setup fails
closed rather than retrying with broader permissions. Keep the running application
and helper outside the target workspace; use an installed bundle for Ipse
self-development. See [shell policy](usage.md#choose-shell-confinement) for toolchain visibility
and cleanup limits.

## Check protected-storage admission

Native knowledge permission and protected collection writes have a separate
storage-allocation profile. Passing shell sandbox setup does not admit storage,
and storage admission does not establish shell confinement.

| Kernel and architecture | Protected storage admitted by the source implementation |
| --- | --- |
| Linux 64-bit `7.2.10` or `7.2.10-*` | Previously reviewed Btrfs/tmpfs features; see the [native contract](../../native/README.md#admit-allocated-bytes-before-writing) |
| Exact `7.2.11-arch1-1`, x86_64 | tmpfs only: 4096-byte page/block units, selected global shmem policy `advise`, and the actual directory mount's `huge=advise` |
| Other combinations, including Btrfs on `7.2.11-arch1-1` | Protected writes refuse |

Check your intended locations before enabling knowledge:

```sh
uname -r
getconf PAGESIZE
findmnt -T /path/to/ipse-home -o FSTYPE,OPTIONS
cat /sys/kernel/mm/transparent_hugepage/shmem_enabled
```

These observations help diagnose refusal; the helper checks the actual retained
directory descriptor, mount identity, ownership and allocation features again.
All protected home/control/state/collection locations must meet the profile.
A default home on Btrfs remains unsupported on the newer kernel. Ipse does not
silently move it to another filesystem.

Tmpfs loses data at unmount or reboot. Selecting a qualified tmpfs location is
an explicit choice for volatile work, not a durable-storage migration procedure.
Do not assume `/run/user` or another mount has the same features, change global
huge-page settings to silence a refusal, or relocate existing protected state
without preserving its original identity. Existing releases retain their own
compiled helper; rebuild the checkout or use a separately verified package to
obtain a changed source profile.

## Recover from installation errors

For missing `mix` or `rustc`, check versions and `PATH`. For dependency-fetch
errors, check access to the sources in `mix.lock`. Mix locking and local HTTP
fixtures require loopback sockets, so an outer sandbox can block the build or
checks. Use the normal permission flow or a suitable terminal. Do not disable
TLS verification or weaken checks.

If an archive fails because of loader/libc incompatibility, use a matching build;
renaming an archive does not make it portable. Keep the sanitized error and host
versions for a bug report. Continue with [Troubleshooting](recovery.md).
