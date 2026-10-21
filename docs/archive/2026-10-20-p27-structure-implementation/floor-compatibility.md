# Raw evaluator compatibility with the supported toolchain

Historical investigation, 2026-10-21, based on
`d35287afbfc0101938f0c86e70748a5e1c354c9f`. Current contributor procedures belong
to [testing](../../developer/testing.md); P27 acceptance belongs to
[the plan](../../plan.md#p27-optional-research-graph-and-rag).

[Hosted run 39587478392](https://github.com/lexlapax/ipse/actions/runs/39587478392)
failed on Ubuntu and macOS with Elixir 1.18.5 and OTP 27. Local Elixir 1.20/OTP 29
checks had passed. The hosted failures have two causes.

When the measured environment has no compiled policy, Elixir 1.18 infers a nil
return from the attribute-or-raise expression and warns about downstream map
access. Strict evaluator compilation rejects that diagnostic; source CLI output
also ceases to be JSON-only. A guarded private argument function now returns
only a captured map or raises. It neither reads runtime policy nor adds an
ambient fallback, and the unbound-evaluator refusal remains tested.

On the hosted macOS raw ERTS launch, Latin-1 standard output converts the Unicode
argument into a literal backslash-x escape, which JSON does not accept. An isolated
OTP-27 probe reproduces the output transformation by selecting Latin-1 explicitly.
The generic verification bootstrap and bound measured environment now explicitly
select Unicode standard output. No request, argv, source inventory, executable
binding or code-path validation is relaxed.

The existing frozen-role test forces Latin-1 before each child's verified
bootstrap. It still requires exact Unicode and quoted/injection-like argv,
unloaded host domains, and changed/missing precompiled-module refusal. This
exercises correction of the IO default rather than relying on the local locale.

An isolated candidate checkout passes formatting, strict compilation and all
40 tests in `verification_test.exs`, `knowledge_evaluation_declaration_cli_test.exs`
and `knowledge_evaluation_measured_test.exs` under Elixir 1.18.5/OTP 27. Current
Elixir 1.20 strict compilation and changed-file formatting also pass. Both bounded
independent source reviews report no finding. There were no actual-model calls
or private evaluation inputs.

Two earlier setup attempts did not reach tests: the isolated toolchain needed a
compatible Hex archive and the existing OTP-27-compatible rebar executable.
The missing-rebar prompt was stopped explicitly; its zero exit after SIGTERM is
not a passing check. Acceptance requires the completed 40-test summary without
interruption. The replacement uses an isolated Mix home and the existing rebar.

The d352 local full-suite and package receipts remain evidence for that earlier
source. They do not establish a passing hosted run for this repair, whole-manual
completion, held-out quality, an actual-model resource comparison or engine choice.
