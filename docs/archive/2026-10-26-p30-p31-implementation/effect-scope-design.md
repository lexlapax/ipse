# Proposed owned inference effect scope

Recorded 2026-10-27. This is a design for review, not an implemented API or a
claim that the experimental Mint transport is ready for Session use. The
[plan](../../plan.md) owns milestone status.

## Private prototype snapshot

A later private prototype is preserved as a [patch](child-scope-prototype.patch)
against `lib/ipse/session/resources.ex` SHA-256
`adc1a81af0f837daaeec1e675d9b090cd3ee67252e40ed3fe77bc566d86b1bb2`
at repository commit `f20475a7919474438f978cdffeac1879855e8d37`. The patched
file SHA-256 is
`226846d74ddcc03f9bbd2ce8c01220e5fd06aceb8375e132d4d00cd69d1d6ba0`;
the patch SHA-256 is
`06350bfa89148e0e14b52b50b55f0d0b523cdfe9e35011e433a93b6488947492`.
It includes a **private-only diagnostic hook** for the suspended lock-guard
race; it must not be applied to production as written. It has not been wired
to inference or accepted as a complete ownership contract.

**Known integration defect:** independent review found that the prototype
registers its child scope with the retained Session lock guard as a `:peer`.
The guard currently permits nested registrations only from a tracked `:scope`,
so child registration of a native controller can fail in a real Session. The
passing native cancellation tests below used a root scope without a retained
Session lock guard and did not detect this. The patch is preserved as defective
evidence, not a proposed production change; actual retained-guard integration
and a narrowly authorized delegated-scope contract remain open.

The [primary private tests](child-scope-diagnostic.exs) and
[close-path tests](child-scope-close-diagnostic.exs) reported **11 passed**
with seed 20270123; their [output](child-scope-diagnostic.log) is retained.
The existing Session resource and authority tests reported **10 passed** with
seed 20270124 in the same graph; see [output](child-scope-regression.log).
The test sources hash to
`c7893bddb8ab129bad32779c9df5e936405cdbaa8657b42df2d7f18d65bcc1f2` and
`840aecd033d0c7ab5e1484b14d01568a45a61f8e162a7b404ae0b6d83c9ee39f`;
the outputs hash to
`c4c754ad1d1a312373cedbd3255dd7c8a68502e30de3ca8a902d768bb43e0b43` and
`64e98e88df86cb1bdd23e2222c5803441e69e4db2d0b37cb565c09dee7fe3313`.
The private graph used Elixir 1.20.4/OTP 29, a strict compile, isolated
temporary files and a private helper SHA-256
`d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`.
The native tests exercised lock acquisition and cancellation only; they did
not run a protected quota stage or qualify 7.2.11. One fixture deliberately
stops and kills its own isolated native helper; inspect it before reproducing.

Independent review reproduced two startup races and exposed normal close and
cast-stop paths in which a peer could continue. The snapshot includes repairs
and focused controls for those observations, but review of registration,
receipts, resource loss and concurrent close/send remains incomplete. Do not
infer full safety from the test count.

`Resources.file_effect/2` registers a separate peer in the request-wide scope.
Its peer monitors the initiating worker before starting, but the callback may
continue after that worker dies. A [synthetic diagnostic](effect-owner-diagnostic.exs)
observed this behavior in an isolated graph: **1 passed**, seed 20270108; the
[output](effect-owner-diagnostic.log) is retained. Source and output SHA-256
are `4ddcbe48de1e6ac51912e03b37c1e97b01b9e2501c38e1fd22eabb18bfb3f170` and
`9402751e34cea23183d418033dda589139f9e67890c8d079ae752c00e968e11b`.
The diagnostic does not create a native lock or send inference data. Existing
native transaction tests separately show that the native controller monitors
the upstream owner and fences later native operations. That fact does not fence
network sends from a still-running peer.

Project Identity and Consent perform protected callbacks inside the file-effect
peer. The Mint continuation is exact-owner: it must run in the same process as
the connection. A new process introduced between the protected callback and
the continuation would refuse; transferring the continuation or accepting a
worker-supplied authority token is not a fix. The whole connection and final
protected callback need to execute inside one admitted effect peer.

## Candidate contract

The request-wide root scope would authenticate a child effect using its existing
tracked initiating task, an exact peer PID and a one-use host nonce. It would
register the peer as an authorized effect, then register a child scope as a
root-owned resource only for that peer and nonce. The child scope would inherit
the actual root Session lock guard through the authenticated registration, not
rediscover one from the peer PID. Native controllers and other resources opened
by the peer would register in this child scope. The root still recognizes the
peer for the Session's existing caller/job authorization.

The child scope would separately track the peer, its native controllers and
any nested children. A coordinator deadline first prevents further setup,
terminates the exact peer, and then waits for both peer termination and a
correlation-bound child-scope cleanup receipt. Root Session cancellation must
also cancel the child scope and await its resource receipts. A missing, late,
duplicate, wrong-owner or uncertain receipt must report cleanup unconfirmed;
process termination alone is not that receipt. Pending registration racing
timeout must be tombstoned atomically so a child cannot register after cleanup
was reported. Any potentially attempted send is unknown unless independently
settled; no outcome string or process DOWN establishes that a send did not
occur.

## Required proof before implementation is used

The design needs review of root/child authorization and lifecycle ownership,
registration-before-start, deadline and owner-loss races, nested effect reuse,
lock ordering, and bounded close behavior. It must not close sibling work or
block the Session GenServer on slow IO. Tests need actual controller and native
helper cancellation with a retained Identity/Consent lock, stopped or lost helper,
lost/malformed/late cleanup receipt, and root or peer death at every registration
and send boundary. A 7.2.11-only private test override may diagnose test logic,
but cannot qualify that kernel or turn a simulated run into a supported-host
pass. CompletionWitness additionally needs independently reviewed cleanup and
native-parser evidence; Mint's public close acknowledgment ignores the underlying
transport-close result and cannot alone provide that proof.

Until this protocol exists, a wrapper that merely kills a spawned Task, calls
request-wide `Resources.finish/1`, or trusts a child-provided completion result
would overstate ownership and cleanup. The experimental transport remains
unwired and the current Session egress paths do not gain a freshness guarantee.
