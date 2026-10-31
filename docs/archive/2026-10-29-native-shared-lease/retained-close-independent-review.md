# Independent retained-close infrastructure review — 2026-10-29

This additive review covers the frozen [first retained-close section](retained-close-infrastructure.md)
and [exporter-loss follow-up](retained-close-exporter-loss.md), against the
[accepted terminal direction](guarded-terminal-integration-independent-review.md).
The manifests have exact digests
`d7ce31a5eafa7e562564f1bad0a2009718f006cb359143bc307de89f5171ec85`
and
`7a8ab790c6524db89fce2687662a9bb6a306b84e0a8c1d2e207b95a51ce274a0`.
The [verifier](evidence/retained-close-review/review-manifests.exs) checked all
12 first-section files and four follow-up files, including exact source tars,
helpers, fixtures and retained logs. The [result](evidence/retained-close-review/review-manifests.log)
is retained. Inspection used extracted frozen tar sources, not changing working
native files. No implementation, gate or runtime control changed or ran here.

**Disposition: accept this as bounded inert native transport infrastructure.**
No concrete integrity defect was found in its scoped retained-export/close path.
The Session header/Writer barrier section may build on it, preserving the
integration conditions below. This accepts neither a public BEAM API nor terminal
activation, management mutation, forked-writer closure or managed delivery.

## Exact transport and close argument

Transaction `Y` requires the current sequence/depth, a retained stack index,
nonzero operation ID and the bounded existing peer/device/inode/secret request.
Its first export starts one finite five-second setup window; later slots cannot
renew it. The same operation may export other distinct held slots while all
conflicting ordinary operations and releases stay frozen. Already exported slots,
changed operation, closing-state export and remembered replay refuse with unknown
termination. Original open descriptions stay owned; no release/reacquire or
`LOCK_UN` is introduced.

The retained handoff pins recipient process identity with a pidfd and executable
inode, checks actual connection credentials and secret, and retains the exact
native peer socket. The collector independently checks exporter pidfd/executable,
credential and the received FD's exact dev/inode, regular-file/owner/link/mode/
length and close-on-exec properties. It rejects extra/truncated/malformed ancillary
FDs, duplicate identities/names/secrets and duplicate same-exporter slot pairs.
Same exporter PID is permitted for distinct slots. Framing is fixed and bounded:
one to four entries, a nonzero 16-byte operation, slots zero through two and a
finite overall duration no greater than 120,000 ms.

For this single-process recipient, the lease `Vec` is the only owner of the
received lock copies; it neither forks nor forwards them. It drops the entire
vector before sending **any** operation/slot-bound `C`. Exporter `K` consumes
only its stored matching peer and operation/slot, rechecks original lock and
recipient identities, receives `C`, sends `F`, and requires the matching `G`.
Returning from settlement drops that peer endpoint. The collector waits for the
exporter's actual socket EOF before dropping its peer, and aggregates completion
only after all peers finish. This keeps an ACK queued with HUP from masquerading
as a successful settlement. The original owners retain their flock descriptions
through thaw; final ordinary releases remain separate.

Possible send, missing ACK, malformed receipt, owner/control loss, wrong operation,
recipient loss or timed-out settlement never becomes known closure or evidence
that a descriptor was not received. The original helper terminates with `U` on
failed retained settlement. Recipient copies can therefore keep contenders
blocked after the original helper exits, exactly as the forged-settlement control
requires. Conversely, a recipient that has structurally dropped all copies can
settle without releasing the original owner's lock.

## Follow-up and retained controls

The v4 native change only replaces the post-collection close-request wait with
a bounded read that polls **all** retained exporter pidfds together with its
owner input, including partial close-frame reads. Exporter loss now exits the
inert collector promptly and drops its copies. It does not manufacture a
successful operation or a guardian/reader all-copy receipt. Once all lease copies
have already been dropped, later close handshakes retain their existing exact
peer checks and finite waits.

The passing controls were inspected rather than rerun. Four distinct real flock
locks include three slots in one Transaction process and one independent
Transaction stand-in. Contenders remain blocked through collection and recipient
close until the original owners release. Wrong operation, forged slot settlement
and recipient loss produce unknown; the forged-settlement case retains recipient
locks until actual recipient exit. Two distinct operations thaw the same original
owner, then replay of its earlier ID refuses. Five repeated affected handshake
controls pass. The v4 normal control still settles; killing the three-slot
exporter releases its three locks only after the collector exits, while the
surviving independent exporter still holds its fourth lock. Earlier sandbox
socket failures and the real pre-fix ACK/HUP failure remain historical failures.

## Conditions before actual-owner integration

- Preserve settlement ordering explicitly. The collector processes `F/G/EOF` in
  manifest entry order, and one native Transaction serially processes `K`.
  Settling a later slot first can wait for a `G` the collector cannot yet send.
  The trusted adapter must issue settlements in compatible manifest order,
  before ordinary reverse-stack guard unwind, or explicitly multiplex the small
  bounded peer set. A timeout here is unknown, never a reason to thaw.
- The 256 remembered-operation limit is a real owner-lifetime bound, not evidence
  for arbitrary repeated user review. Keep it fail-closed and resolve its declared
  lifetime behavior before exposing a long-lived Session export API. Do not reset
  replay memory while old capabilities remain usable.
- Executable inode, pidfd and credentials do not prove recipient mode or prevent
  exec after a check. A future production tty recipient needs its own exact
  operation-bound native-instance/role authorization and trusted fresh secrets.
  This inert mode's structural drop proof cannot be imported as proof for forked
  operator readers or copied writer FDs.
- The actual Session header/resume holder must export its original startup lock;
  Writer drain/proof snapshot, nonblocking Session barrier, sticky exact-owner
  controls, all-copy native closure/thaw and responsive quarantine remain to be
  implemented and tested. No legacy holder may be closed to open an export mode.
  The fixed safe redraw and actual tty write boundary remain mandatory.

The four-flock stand-ins establish neither real Session/Host Port ownership nor
Identity/Consent/Collection facts, native Review, a human terminal or worker pipe.
The separate 131-lease collector and the gated generic 132-distinct-description
combination are not qualified by this management-sized mode. No model, network
service, aggregate suite, repeated passing workload or gate activation ran for
this review. The parent and Lifecycle own the next source section, proposal
reconciliation, documentation checks and coherent commit.
