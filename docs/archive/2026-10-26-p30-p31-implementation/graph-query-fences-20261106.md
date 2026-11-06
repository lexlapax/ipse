# Graph query fences — 2026-11-06

Historical synthetic development evidence. The [plan](../../plan.md) owns
current acceptance status; the [Graph manual](../../operator/graph.md) and
[extension training](../../developer/knowledge-extensions.md) describe the
current contract and its limits.

On the candidate based on `a1a4e8ea`, Graph rechecks the captured snapshot's
source and fact time transitions before returning a current-time query. It also
compares the original snapshot generation with the final State or MCP
revalidation. An empty MCP snapshot uses a bounded read to obtain the latter.
This can conservatively refuse on an unrelated transition or same-scope write;
the MCP generation is reported by the selected service. Neither check supplies
a lease through delivery, proves a remote service truthful, detects clock
rollback and recovery between samples, or proves later use remains authorized.
Explicit historical queries retain their selected-time semantics, while the
generation fence still detects a concurrent store change.

The author-run State fixture passed 34 synthetic controls, and the MCP adapter
fixture passed five; a separate wrapper passed. They cover time and generation
changes, empty and populated snapshots, conservative conflicts, bounded probe
accounting, fragmented replies, and unknown, denied and malformed probe outcomes.
The non-State temporal callback is simulated. A separate synthetic real-clock
fixture passed 33 controls after a first attempt used an obsolete continuation
field and failed; that earlier failure remains distinct. Other private MCP
fixture attempts failed before revalidation or used incorrect request-count
assertions and were corrected; they are not passing evidence.

Freshly built `graph/state-explicit` and `graph/mcp-explicit` artifacts each ran
their corresponding fixtures against a minimal SDK: 34 State and five MCP
controls passed. The Graph source SHA-256 was
`5716c6f56ea2ecbb6694b08d684e64229bf98dd7d6a9e1017b23d245a05a0f42`.
These are fixture-host and built-module results, not actual MCP transport,
installed-package, whole-source or model-quality qualification.
The selector insertion case used a synthetic State row and did not qualify a
Research transfer. The full runtime baseline, independent platform checks and
integrated P31 acceptance remain open.

A separate fresh synthetic State journey built this Graph source with the
`546869c8` host SDK and passed through a real Session and worker. It exercised
capture, generation refusal, denial, an interrupted State result, saved recovery
and idle reopen without replay. The retained log SHA-256 is
`c460b81d54aa7374bddcb06c5dba93ab53b2716d2f8f653415394f252c80414b`;
its artifact manifest SHA-256 is
`037193dd054e38ce1d470bdf3abfdd39cbc8e1784cd2752fcf9c2aca8a8fe79c`.
An independent host inspection found no remaining BEAM, runner or timeout
process and the Input lock and TCP 39657 free. This journey did not inject the
new query races, use a real MCP transport, or test the later host revision.
