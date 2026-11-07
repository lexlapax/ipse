# Installed operator planning-decision control, 2026-11-07

This is a historical synthetic package check. See the [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance) for current acceptance.

A clean checkout at `2a6ed213d6d693a58988f5a74172dfa899099556` built a
PDF-free Linux x86-64 package with `IPSE_BUILD_PDF=0 ./dev/package.sh`.
The archive and sidecar matched SHA-256
`626208667e6833cdcea9d96df0d3fdf9b11ad9c474971b61b2ab4053345ae615`.
The package reported that exact commit. The verifier used the matching
Elixir/OTP and copied ExUnit, and checked that Ipse modules and its native runner
came from the extracted package, with no host Elixir or compiler on the child
path. The unchanged test fixture raises on any model completion.

Fresh synthetic PTY scenarios `plan_save` and `plan_revoked` both passed. The
fixture checks that no note is published before leaving planning and explicitly
requesting a save. The first scenario saves one reviewed statement with its
original assertion receipt; the second revokes consent and observes refusal
before publication. Both reconstruct Saved state and reopen the same Session.
An independent inspection of each final resume tail found only owner-start and
release-intent events, with no replay. The verifier's release, source, ExUnit,
fixture, driver, archive and sidecar integrity checks all passed. Host checks
found no selected test process, input-lock holder or test-port listener.

A first setup attempt ran out of temporary-filesystem quota during extraction,
before creating the PTY or starting either scenario. Its incomplete extraction
was retained. The passing run used a new private runtime-filesystem directory;
no effect was replayed. The verifier was formatted after the run; formatting
the retained tested copy produced identical bytes to the committed source.
This evidence covers only the two operator-authored synthetic scenarios on the
specified PDF-free package. Assistant-authored decisions, other platforms,
independent-human use and default PDF-enabled packaging remain unqualified.
