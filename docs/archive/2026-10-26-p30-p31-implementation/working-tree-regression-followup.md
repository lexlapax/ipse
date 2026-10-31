# Working-tree P30/P31 synthetic regression

2026-10-27. This is a focused, uncommitted working-tree check, not a full
repository regression, release candidate, native profile qualification or
adversarial audit. The [plan](../../plan.md) owns milestone status.

The sandboxed strict compile again failed because Mix could not acquire its TCP
filesystem lock (`:eperm`). With approved local TCP access,
`mix compile --warnings-as-errors` passed, and
`MIX_ENV=test mix compile --force --warnings-as-errors` rebuilt 152 project
files and passed. `mix format --check-formatted` passed for the repository.

The following selected suites ran together with local TCP access, seed 46330,
and `--max-cases 1`: Knowledge decision policy and document fidelity/document
tests; neutral decisions, decision provider, transport and profiles; Session
permissions, execution mode, draft acceptance and vertical integration; planning
MCP, MCP Session, CLI and developer verification. The result was **215 passed**
in 158.6 seconds. The configured native-sandbox, macOS-sandbox,
macOS-filesystem and memory-scope tags were excluded. The printed headless
question error is a fixture's expected CLI output, not a suite failure. The
tests use synthetic providers and local services; no paid account, external
model or protected storage capacity workload was exercised.

The following selected sources and tests had these SHA-256 values during the
run; this is not a complete source graph manifest:

| Path | SHA-256 |
| --- | --- |
| `lib/ipse/extension/mode.ex` | `e3c73f897abc167077df06e94402bcc5e05bf70a5de3bcd50dca72e3d642407d` |
| `lib/ipse/session/planning_mcp.ex` | `7736ac88bcc5f68e0ad832ad0d81f610850695a5e2a2b97cae6edfd4136dc68e` |
| `lib/ipse/session/permissions.ex` | `dbbc723bd824db1a492df420d0729154342a93ed20ed933605fc030a333bf6b5` |
| `lib/ipse/session/saved.ex` | `04dd2643440da585af86123ae1b5fa0ee013deacee8e591bd6a5b3318f328c4d` |
| `extensions/knowledge/src/knowledge/decision_policy.ex` | `e7cdc0e7971cd62b2df796fe4c844e44883d967b81173bd658e66e90414ee41e` |
| `extensions/knowledge/src/documents/docx.ex` | `d7b7492f194778c4640f42501ef94eb8c6bd0d0f96ef12338aa3232278ee5bc0` |
| `extensions/knowledge/src/documents.ex` | `59fe4119e3aaf17292679cb5970c1b5d0b850d789bc273df50106e39fe45c86d` |
| `test/extensions/knowledge/decision_policy_test.exs` | `91c3e326da34ed186c0759b2aeb92ceee3f99743af2446f89b4201beafa78c75` |
| `test/extensions/knowledge/documents_fidelity_test.exs` | `0b03cbc59fcc14239d5daa4dfd0bac41ecb11304e504652c301cdb44eedfdcd6` |
| `test/ipse/session/execution_mode_test.exs` | `69a7024a3d21380c6c95ded3d6b797eaef0eb0f0b9dfb2256ac88c8367dd9488` |
| `test/ipse/session/planning_mcp_test.exs` | `28212310c7e1f4da46824827b65b0e66628ecbe0a747cc9786e8e9179c5cf597` |
| `test/ipse/session/permissions_test.exs` | `406223b91487b0c110e20f53fa01bae02429be2e53adb9648874fd81645991e9` |
| `test/ipse/session/draft_vertical_test.exs` | `4976e4cea22da3534b25be46920d671752ade48d7cdff763c7b116148c65611e` |

The host reported `7.2.11-arch1-1`, which is outside the admitted protected
storage profile. The prior [full regression failure](corrected-full-regression-followup.md)
is not superseded by this selected run. Current authority and lineage, capacity,
actual planning transitions, acquisition, installed user journeys, live service
and platform checks remain open. The frozen independent document set was not
run. Do not extend the native profile or start the capacity workload on the
strength of these results.

## Knowledge authority and inference component selection

A second working-tree selection ran with approved local TCP access, seed 46340
and `--max-cases 1`. It covered managed-reference reconstruction, source index,
semantic consent and configuration, inference dispatch and budgets, the
unwired Mint transports and egress gate, and the synthetic managed-v3 capacity
controller. It reported **209 passed** in 39.5 seconds with the same configured
tag exclusions. The controller tests did not start a storage capacity workload.

The output explicitly reported unsupported filesystem refusal for semantic
admission and numerous selected positive registered-dispatch, queued revocation,
concurrent SDK and protected Session journeys. Those positive journeys did not
run and are not passes for their intended behavior. A TLS hostname mismatch
notice came from the loopback negative fixture. These results neither establish
live protected authority nor qualify the host. They do not replace the missing
supported-host regression, actual publication, current-root barrier or completed
P31 user journeys.
