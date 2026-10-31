# Planning MCP configuration binding

2026-10-27. This uncommitted change extends the
[operator declaration](planning-mcp-operator-followup.md) and
[replay foundation](planning-mcp-replay-followup.md). It does not enable an MCP
call under a planning or draft ceiling.

Session startup now requires its runtime declaration map to equal the map in
its configuration manifest. Resume also compares the saved manifest's complete
declaration map with the current runtime map, independently of the existing
fingerprint comparison. Missing, null, malformed, ambiguous or changed maps
cannot stand in for a nonempty declaration. This closes the specific case where
the saved map is removed but the old fingerprint string is left intact. It is
not a cryptographic authentication of an arbitrary journal or operator file.

A synthetic Session with an operator-style declaration resumed with its original
header, then refused with `resume_configuration_mismatch` after that header's
declaration was removed without changing its fingerprint. Unit tests also check
empty legacy configuration and malformed or conflicting bindings. The focused
working-tree test passed nine cases, with 17 unrelated tests excluded (seed
20270518). A fixed graph based on `668e6a3` plus the selected operator, replay,
Session and inline-draft sources passed 42 tests, with 17 exclusions (seed
20270519), and forced strict compilation of 143 project files. Its tree was
`393dc4b9143f6ffe543d2adc8897694783cd3317`; tracked files matched its index.
The copied production helper SHA-256 was
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`.

Current SHA-256 values: `lib/ipse/mcp/planning.ex`
`ac1e1c9d7cf34914db8e53f57d9617a98eb805d1b172710531a217d51bb0ffc8`;
`lib/ipse/session.ex` `a71b1aea7ba2d448c440949bd15b07e65c392b29d7b8ca9734c485e3a118f58f`;
planning test `d9205821d22f3b3d32e34cd44dc1c1735a857d3e5736122d73eec4855f08c9ef`;
Session test `501cb7689dbed954ad89bc2f7f45aad1a24106892e0f3dedbe7bcf0052ab9138`.

Per-epoch execution mode and activation, stopped-lifecycle recovery, live
approval and descriptor revalidation, evidence propagation and interruption
behavior still need implementation and adversarial review before dispatch can
be enabled. This evidence does not qualify P31I or the full P30/P31 goal.
