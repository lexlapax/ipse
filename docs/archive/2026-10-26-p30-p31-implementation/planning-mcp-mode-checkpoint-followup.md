# Planning MCP mode checkpoints

The later [ordinary MCP binding](planning-mcp-ordinary-binding-followup.md)
adds checkpoint-bound ordinary starts in sessions with declarations. The
remaining live restricted-dispatch and journal-trust limitations still apply.

2026-10-27. This uncommitted change extends the
[configuration binding](planning-mcp-config-binding-followup.md) and
[replay foundation](planning-mcp-replay-followup.md). It records effective
Session modes; it does not enable planning or draft MCP dispatch.

Sessions with nonempty operator planning declarations now mark their header with
protocol version 1 and append a declaration-bound mode checkpoint before other
startup records. Each resume appends a new checkpoint linked to the prior one.
Replay validates the declaration digest, unique epoch IDs, chain, startup kind,
and effective mode. A fresh checkpoint must match the header mode; a resumed
mode must satisfy the existing `Mode.inherit/2` rules. Planning-read intents
bind the current checkpoint. A new checkpoint also closes an interrupted
pre-start intent independently of optional lifecycle recording. A header-only
interruption can be resumed with a first `resume` checkpoint before later work.
Existing sessions without planning declarations have no new protocol record.

The synthetic Session test verified fresh and resumed checkpoints, a changed
approval on resume, refusal after removing the checkpoints or header protocol,
and continued draft denial. Another actual synthetic Session verified an
ordinary MCP call still requires approval: denial caused no call, while an
explicit approval executed the fixture and the journal reconstructed. Pure
controls reject broken chains, changed declaration digests, duplicated epochs,
broadened inherited ceilings and explicit-deny promotion.

The fixed graph based on `668e6a3` plus selected operator, replay, Session and
inline-draft sources passed 44 tests with 17 unrelated tests excluded (seed
20270525), and forced strict compilation of 143 project files. Its tree was
`97e31099c5c4968711541fb433fbcbdf61215430`; tracked files matched the index.
The copied production helper SHA-256 was
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`.
Source SHA-256 values: `lib/ipse/session.ex`
`ff45060ed23a1faaf1864694e048e575233c9c75214c1a5fe3d624348ae144b5`;
`lib/ipse/session/planning_mcp.ex`
`c290a603cf562ef67f15e6de3e4b0f3e0f0d40c8bc264de8f41088ba3441566d`;
checkpoint test `404dda0491cecd256e3ff5519f307252abfd4c9345eafd518fa3bf0cbc2e570b`;
Session test `e2fe9fd156fbdc798c6140137bcf3fbcee0a4026482fecb4cf3a554677b49e1e`.

The checkpoints are journal records under the host's existing journal trust
model, not independent authentication against arbitrary journal rewriting.
In particular, ordinary MCP starts do not currently carry a checkpoint-bound
intent; removal and substitution attacks across normal and restricted epochs
need a complete live-producer and replay design before planning dispatch can be
enabled. Operator review, exact approval, fresh descriptor revalidation, evidence,
unknown-effect recovery and installed journeys also remain open. Older sessions
that contain the uncommitted planning declaration but lack protocol version 1
refuse resume rather than infer activation. This is not P31I or P30/P31 acceptance.
