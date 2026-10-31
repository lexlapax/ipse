# Retained native export and close: first management-sized section

Implementation checkpoint, 2026-10-29. This does **not** activate terminal
review, managed output, management mutation or any P30/P31 gate. It provides
the first private retained-channel transport needed by the
[reviewed terminal design](guarded-terminal-integration-design.md). The
[plan](../../plan.md) remains authoritative.

Linux Transaction helpers now support a versioned private retained export. `Y`
binds the original held slot and a fresh operation ID to the existing
credential/secret/device/inode-checked descriptor handoff. It retains the
native peer socket, freezes conflicting operations while any slot is shared,
allows other slots of the same Transaction to export, and uses one finite
five-second setup window for that operation. `K` accepts only the matching
operation and slot, and waits for the same native peer's close message before
thawing that slot. Missing/forged closure is unconfirmed; it is not an unlock
or proof that a sent descriptor was never received. The sender retains a
recipient pidfd and checks its executable inode and connection credentials.
An acknowledged transfer is not activation or a close receipt.

The new `--lease-collect-close-v2` is an **inert** four-lease collector for
this first management-sized transport. It has no terminal, destination or
payload-writing operation, and does not replace the existing 131-lease
collector. It checks ordered bounded entries, rejects duplicate identities,
names, secrets and same-exporter slots, retains all four received FDs, and
drops them before sending any operation/slot close message. The exporter then
returns `F`; the collector replies `G` and waits for the exporter's actual
socket EOF before closing its peer. Only after every peer completes does the
collector send its aggregate completion. This explicit handshake prevents an
ACK and concurrent HUP from being mistaken for a confirmed close. Each side
checks its own owner control and finite deadline, and a timeout stays unknown.

The trusted recipient must in future prove that **all** its forked writer
copies are closed before its `C`: this single-process inert collector never
forks or sends its FDs onward, and its result is not a guardian/reader proof.
The peer/executable checks do not alone prove helper mode or rule out exec
after a check; operation secrets must be generated and bound by a trusted host.
The private native `Y`/`K` API has no Elixir caller or authorization path yet.
The current helper caps remembered operation IDs at 256 per owner lifetime;
that explicit temporary bound requires review before any user path is enabled.
The actual Session header/resume owner, Writer barrier, real owner-control EOF,
tty admission, all-copy fork closure and its authenticated original-exporter
settlement remain unimplemented. The generic 132-distinct-lease combination
also remains gated. A stalled kernel operation can outlive a deadline; no
physical cleanup deadline or mixed-old-writer guarantee is claimed.

## Focused controls

The [source, binary and log manifest](evidence/retained-close/manifest.sha256)
retains an unignored source snapshot, the exact helper and fixture binaries,
and both successful and unsuccessful runs. Actual Unix-socket controls on the
available Linux host demonstrated four distinct retained flocks, including
three slots from one native Transaction owner and a fourth independent owner.
After the inert collector dropped every received FD, each exact native
close/settlement completed; contenders remained blocked until the original
owners released. Wrong operation close and lost collector produced unknown,
not a known settlement. A forged slot settlement stopped its original owner,
but independent contenders remained blocked until the recipient really exited.
Two successive distinct operations thawed on the same owner; replay of an old
operation ID was refused. Five repeated focused handshake controls passed.

The first sandboxed socket runs failed before transfer. They were followed by
the authorized isolated Unix-socket execution outside that restriction. A later
pre-fix run exposed the real ACK/HUP race; it is preserved rather than counted
as a success. The subsequent C/F/G/EOF handshake passed the affected controls.
The four test flocks are stand-ins: there was no actual Session journal holder,
operator tty, management facts, worker pipe or native Review in these tests.
No model or external service was used.

From the repository root, the matching artifacts were built with:

```sh
rustc --edition=2021 -D warnings native/ipse-runner.rs -o /tmp/ipse-retained-export-helper-v3
rustc --edition=2021 -D warnings dev/fixtures/transaction_lease_export.rs -o /tmp/ipse-retained-export-fixture-v4
```

For each `mode` in `normal`, `wrong`, `wrong-slot`, and `lost`, the fixture ran
`/tmp/ipse-retained-export-fixture-v4 --retained-close <new-private-directory> /tmp/ipse-retained-export-helper-v3 <mode>`.
The repeat/replay case used `--retained-repeat <new-private-directory>` with
the same helper. These are focused infrastructure checks; independent review
and the remaining actual-owner/tty controls are required before activation.
