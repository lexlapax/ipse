# Ordinary MCP checkpoint binding

2026-10-27. This uncommitted change extends the
[mode checkpoints](planning-mcp-mode-checkpoint-followup.md). Planning and
draft MCP dispatch remains denied; the new ordinary marker is not a grant.

When operator planning declarations are present, every ordinary MCP tool,
resource or prompt start now has a preceding intent bound to the current mode
checkpoint, recorded start and model request. Replay requires that marker even
in normal mode and checks the recorded catalog, capability identity, configured
server fingerprint, arguments and approval. This closes the specific removal
gap where a restricted start might otherwise be presented as an unmarked normal
MCP start after a checkpoint was removed. It does not authenticate arbitrary
wholesale journal rewriting. Sessions without declarations retain their prior
ordinary MCP record format. Previously created, uncommitted protocol-v1 sessions
with unmarked ordinary MCP starts refuse rather than infer this binding.

Synthetic Session tests confirmed explicit approval is still required, a denied
call has no fixture effect, an approved call executes and reconstructs, and
removing its marker or checkpoint or altering its start or epoch refuses replay.
A copied synthetic journal truncated before the start record resumed without
repeating the already-executed fixture call and reconstructed the missing result
as unknown. This is a controlled truncation, not an actual owner-death test.
Resource and prompt calls also received markers; their completed Session resumed
without repeating either call.

The affected configuration, MCP Session, catalog and draft suites passed 80
tests (seed 20270602) in a fixed graph based on `668e6a3`, tree
`73302f49e5436f8c6b3b04826c898d4df5a7c6f5`. After adding a test-only resource
and prompt resume assertion, tree `bb85b79985286cb9f4c763988a22fded835ce20e`
passed that focused test (seed 20270604; nine unrelated tests excluded) and
forced strict compilation of 143 project files. Tracked files matched the private
index; the production helper SHA-256 was
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`.

Current SHA-256 values: `lib/ipse/session.ex`
`54ee92dbeece0e00d89e8e92f2eb48955ed18cc33197425f9b613286e0df82b7`;
`lib/ipse/session/turn.ex` `37f3bf79bcc1ff5b88c8958490e6750f12209c17cd4ca37d969f26d62efacbba`;
`lib/ipse/session/planning_mcp.ex` `d982400e436bf85e1d1ff97eb2783f27fc28a4ff4d7b87a0fac9ccad85ae1ea8`;
MCP Session test `3c8df96d1bfd87d031f89817b9f2015ca9255fa5a617b964e4667bb9bed2a9d3`;
catalog Session test `9a4f7e3f5e7dc8cb66a6299b7ad1822f9330cdcd361b5b4d2e508c18e9328501`.

Before enabling restricted calls, the live producer must select the restricted
intent and enforce operator review, exact approval, current descriptor and
endpoint revalidation, cost/egress policy, evidence propagation and unknown
cleanup. Test real interruption and all covered modes and perform adversarial
review. These controls do not qualify P31I, the native host, or P30/P31.
