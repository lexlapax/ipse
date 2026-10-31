# Post-release receipt contract

Dated 2026-10-29. This is a pure host-side contract under development, not a
published receipt, a change to ordinary close behavior, or P30/P31 acceptance.
The [current plan](../../plan.md) remains authoritative. The prior
[framed-close follow-up](session-header-native.md#framed-close-and-transfer-deadline-follow-up)
still records a conservative unconfirmed lifecycle closure.

For each prospective owner, the contract defines a unique journaled owner-start
marker. The [independent review](release-receipt-independent-review.md) reproduced
an old-owner adoption gap in the historical-intent query. The revised contract
separates historical inspection from current-owner selection. For each prospective
close, `Ipse.Session.ReleaseReceipt.prepare/7` makes a fresh Ed25519 key pair
and a closed intent containing the session, owner and unique operation IDs,
optional epoch and exact closure digest, original source-origin
digest, lock device/inode, pinned-helper digest and public key. The private key
is returned in an owner-bound, inspection-redacted host term and is not included
in the intent or receipt. Same-VM code is trusted and can inspect that term's
fields; this is not a process-memory security boundary. A receipt signature is
domain-separated and binds the entire intent,
the exact closed receipt body and the asserted native `U/unlocked` and zero-exit
outcome. The format rejects duplicate JSON keys, extra fields, noncanonical
Base64url, incorrect keys or signatures, and receipts over 2 KiB. Public keys
and signatures must have exactly 43 and 86 encoded bytes respectively before
decoding. Equivalent JSON whitespace, key order and escapes are accepted; JSON
bytes themselves are not required to be canonical.

This is a **signed claim**, not independent observation of a native helper or
proof that a sidecar was durably published. The contract cannot prevent trusted
host code from signing before release. An eventual caller must journal the
intent under the original lock before stopping its Writer, retain the private
key only in that owner, and sign only after that exact non-exportable helper's
framed release and all other cleanup succeed. A missing or invalid receipt is
unknown. A lost publishing response leaves the close outcome unconfirmed even
if separately inspecting a valid signed claim later establishes what its trusted
signer asserted. The signature does not contain hostile BEAM code or arbitrary
same-user access to process memory, and does not authenticate a coherently
rewritten journal and sidecar by itself.

The pure journal scanner validates the existing lifecycle sequence and recorded
source-origin shape, requires each intent to match the latest unique owner marker,
that origin and its prior exact unconfirmed closure when an epoch exists, and
rejects duplicate owner or operation IDs, duplicate owner or epoch intents,
old-owner or old-epoch claims, and mismatched or premature closures. `intents/2`
retains historical entries, and `verify/2` only verifies the particular intent
provided: neither is a current-cleanup decision. `current_intent/2` selects only
the latest observed owner and current epoch, while `classify_current/3` combines
that selection with signature verification. A later owner marker or epoch start
invalidates the previous current selection. If lifecycle recording stops at its
limit, including within an active epoch, the scanner preserves historical intents
but refuses subsequent intents and returns no current selection: it does not
pretend that the active epoch ended or that recording was never enabled. Sessions
with no intent remain compatible. This relies on future integration durably
recording a fresh owner marker before every owner can act; the pure scanner
cannot detect an unrecorded reopen. Selection reflects only the supplied snapshot;
future adoption must fence concurrent reopen while validating and acting on it.
A caller must
still establish actual source/lock/helper identity under the original owner and
compare those facts to the intent; recorded origin shape alone is not that check.
The scanner and signature verifier are not yet connected to `Saved`, Session
close, diagnostics or a sidecar publisher.

The [eight focused contract tests](evidence/release-receipt-contract/test-v6.log)
passed using real Ed25519 signatures, including wrong private keys, a different
valid intent, duplicate JSON keys, delayed old-owner receipts, recording exhaustion,
exact Base64url field bounds and refusal to sign from a different process. They
exercise synthetic data and perform no lock release or publication. The
[source snapshot](evidence/release-receipt-contract/source-v6.tar),
[runtime inventory](evidence/release-receipt-contract/runtime-v6.sha256) and
[manifest](evidence/release-receipt-contract/manifest-v6.sha256) identify the
separate copied graph. Earlier v1–v5 logs and v4–v5 sources remain. Commands:

```sh
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-release-contract-v6-sol-20261029/lib elixir -e 'Code.compiler_options(ignore_module_conflict: true); case Kernel.ParallelCompiler.compile_to_path(["lib/ipse/session/release_receipt.ex"], "_build/session-release-contract-v6-sol-20261029/lib/ipse/ebin", return_diagnostics: true) do {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("RELEASE_RECEIPT_CONTRACT_COMPILE_OK"); result -> IO.inspect(result); System.halt(1) end'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-release-contract-v6-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/release_receipt_test.exs")'
```

The retained graph is local evidence, not a fresh-checkout build recipe. A
complete integration still needs durable intent and sidecar publication,
exact original helper outcome binding, crash and concurrent-reopen controls,
explicit inspection semantics and a decision for legacy resumed Sessions whose
generic unlock does not provide the same framed confirmation. The candidate
Session and managed-output paths remain closed.
