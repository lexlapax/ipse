# Local capture pilot refused before reservation — 2026-11-03

The one-shot local pilot was invoked once after the [committed synthetic gate](pilot-local-integrated-20261103.md).
The supervising shell reported exit **1**. This is the first outcome, not a
completed pilot; no automatic retry or alternate route was attempted. The
[plan](../../plan.md) owns the remaining P31A work.

The executed shell's SHA-256 was
`8cd571a3dbe08509089aa771c38db0da869eb4bd704569f0ef59dd074de76c57`.
Its prior loopback metadata inspection completed and passed the prepared checks
for the exact selected model, origin, runtime, manifest and metadata digest.
The inspection record reports zero inference calls and six metadata requests;
that count is the inspection's own report, not an independent wire capture.
The retained private inspection file hashes to
`7bb466cf9f43398eb7dfbcd83f7ce0dd32bd84e901edc14ea4285e684890f520`;
its contents are not reproduced here.

The launcher's private log contained exactly one line:

```text
Local pilot refused; inspect its private declaration and first outcome before any further run.
```

That 95-byte log hashes to
`28aac18f7cdb3429e85ec8b4e13da185d32641098d6cbbc982852648c4878a69`.
The launcher created a private audit declaration, SHA-256
`94147b974d6ef14bf28d8c9c7ebb3eb1486fc99a8ec212b44274f55828e6698b`.
Its attempts, progress and candidate files were each zero bytes, with SHA-256
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`;
no final `result.json` was present. The private output remains under its original
owner-only temporary directory. Its declaration and metadata contents are not
published.

After the refusal, the OS account resolved uniquely to `/home/lexlapax`, and
`/home/lexlapax/.ipse` was observed as a directory owned by UID 1000 with mode
**0755**. Its `p31a-pilot-authorizations` directory was absent. The tested
`PilotReservation.root/2` checks that `.ipse` is owned by the native UID and is
mode **0700** before creating the authorization directory; its inference
callback is reached only after the reservation is created and synced. If the
observed mode held when the check ran, it would cause refusal before directory
creation, reservation or inference. The generic log does not itself identify
which check failed, and the filesystem observation was made after the shell
exited; this attribution is an inference from the observed state and tested
code, not a classified error emitted by the launcher.

The [accounting record](live-call-accounting.md) therefore remains **4 of 1,000
local calls charged**, with 996 remaining; ChatGPT remains **238 of 300
conservatively charged**, with 62 remaining. The separate earlier uncertain
ChatGPT reservation is unchanged. This review changed no account permissions
and did not repeat the refused pilot. Recovery or another invocation requires
its own reviewed decision; preserve the first outcome and private files.
