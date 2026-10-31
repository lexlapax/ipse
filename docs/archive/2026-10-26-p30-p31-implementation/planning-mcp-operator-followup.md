# Operator-only planning MCP declarations

2026-10-27. This uncommitted foundation supersedes the selected-MCP-file
approach in the [previous record](planning-mcp-declaration-followup.md). The
selected MCP file can be anywhere and its contents alone do not establish the
operator-only policy required by the plan. No MCP dispatch has been enabled.

`planning_mcp_reads` now belongs to the existing operator configuration source.
Project sources cannot introduce or erase it, even when project configuration
is trusted. Each bounded entry binds one exact tool ID and server, the selected
v2 endpoint/command fingerprint, and the discovered descriptor SHA-256. The
effective configuration fingerprint includes nonempty declarations. The
`MCP.Planning.declared?/2` consistency check accepts host-discovered descriptors
only by convention and grants no call, permission or current-state proof; legacy
v1 fingerprints cannot match. A changed endpoint or descriptor does not match an
old declaration.

The operator-source test initially failed because the field was not supported.
Working-tree configuration and MCP suites then passed 48 synthetic tests with
17 unrelated tests excluded (seed 20270508), including a Session control showing
that a matching declaration still cannot dispatch in a draft. Expected TLS
failure fixtures remain negative checks. Real operator review, approval,
execution-time rediscovery, durable intent and result, cancellation, replay,
evidence propagation and actual planning-read behavior remain unimplemented.
No positive planning journey or P31I completion is implied.

The isolated graph based on `668e6a3` has tree
`69f87623151c66f508eefdebaba9b0c0f141fdbc`. Source SHA-256 values are
`lib/ipse/config.ex` `42a4d7378fdcaea5b15442c2b36bd8e9b2793bf1896581743ee6fed544f6ebda`;
`lib/ipse/mcp/planning.ex` `4390f8e31e3bcd5e3d7227ecff5f7cb79b4e7cd63de56babf99d5074280b41b2`;
semantic loading test `510a4ffbc6b2bf1bc22ed7b6c23fe65f64637fbaaf4b88df8a3291ce3a63ccd4`;
planning test `cf788ff818b052ff16a4d893ba226389419d50337b422f559c5aa69e059c19f2`;
Session test `3a99473a94728c6c43efc7bc78fdb1599e8cf1783d8d3454c22f722dadde39a6`.
The fixed graph passed the same 48 tests with 17 exclusions (seed 20270509),
then forced strict compilation of 142 project files. Tracked bytes matched the
private index, and the copied production helper SHA-256 was
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`.
These checks do not establish native qualification.
