# Planning MCP declaration foundation

**Superseded source location:** a later continuation moved the declaration out
of the selected MCP file and into operator-only configuration. See
[the operator-authority follow-up](planning-mcp-operator-followup.md). The
original measurements below remain historical and do not describe current code.

2026-10-27. This is an uncommitted, inactive foundation for P31I planning MCP
reads. It is not a tool grant or a completed planning workflow. The existing
Session still denies every MCP call during a draft; ordinary approval and
journaling are unchanged.

The selected MCP configuration can carry per-tool `planning_reads` entries with
the allowlisted tool name, descriptor SHA-256 and the reviewed endpoint SHA-256.
The endpoint digest is calculated from the v2 public server fingerprint without
the declarations, avoiding a circular hash. The full session fingerprint does
include nonempty declarations. `MCP.planning_read?/1` checks the selected v2
server, exact tool identity and both hashes; legacy v1 cannot grant a match.
This helper assumes a trusted host-supplied discovered descriptor and does not
authenticate an operator, obtain approval or perform a call.

An intermediate test exposed a carry-forward error: after a configured HTTP
endpoint changed, a declaration that named only the tool and descriptor still
matched. That test failed before the endpoint digest was added. Controls now
cover reloaded changed HTTP endpoints and local commands, descriptor and identity
changes, malformed and duplicate declarations, undeclared tools, resources and
legacy fingerprints. A synthetic real Session with a matching declaration still
denied the draft call and recorded no tool start or file effect. This negative
control does not demonstrate an authorized planning read.

Configuration, HTTP and catalog suites passed 42 tests in the working tree
(seed 20270502); the new Session control passed separately (seed 20270504).
The same suites and Session control passed 43 tests, with 17 unrelated tests
excluded, in an isolated source graph based on `668e6a3` (seed 20270505).
Its tree is `36dad0d9404c917351ff45e07a34d8b5a8e33f17`; tracked bytes matched
the private index afterward. The copied production helper SHA-256 was
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`.
TLS certificate failures in the suite are expected negative fixtures. Working
tree strict compilation and changed-file formatting passed.

Current source SHA-256 values are `lib/ipse/mcp.ex`
`9faf63a78109803fea88e7f512a6c5d1c11f1a8bfe1665fbe9b8f32ab0b3726e`;
`lib/ipse/mcp/config.ex` `813b83ced271fe311d3fb1e8c95baea8ebccb6dd8363c631886851f022959669`;
config test `170d7399d94e3b6012add8fcae633afd07f7cf043c39c99768154ebc9a0c39e0`;
Session test `8a3df1179b6c793261f68b8c05a0c281697e05c6b7ae2ef78e6cbcd5a9dad952`.

Before enabling a call, establish operator-owned declaration selection and
review, the exact current Session catalog and endpoint at execution, ordinary
approval and egress/cost controls, durable intent/result and interruption
semantics, replay and resume validation, and draft evidence propagation. Test
revocation, tampering, changed configuration, concurrent dispatch and unknown
effects. Neither a server annotation nor a search-like name grants this policy.
Perform the full editorial review and applicable checks before a focused commit
and push; this foundation alone does not complete P31I.
