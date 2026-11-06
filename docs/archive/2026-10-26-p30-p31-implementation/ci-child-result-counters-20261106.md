# Child-result counter repairs, 2026-11-06

Historical test-verification record. Use
[the current testing guide](../../developer/testing.md#isolate-subprocess-inputs-and-shared-resources)
for contributor instructions and [the plan](../../plan.md) for current acceptance.
These repairs change test presentation assertions, not production behavior,
profile limits, test deadlines, selected controls or default exclusions.

Hosted run `42192551584` exposed assertions tied to rendered ExUnit summaries:
the supported Elixir versions can report the same successful child result with
different prose. The repaired wrappers inspect the exact `ExUnit.run/0` counters
`total`, `failures`, `excluded` and `skipped`. Only the expected completed scope
emits its fixed control-specific marker. The parent still requires child exit
zero and exactly one complete marker line. A broad pass-message match cannot
substitute for a missing, failed or skipped control.

The existing child entrypoints disable automatic exit-time running and finish
with one explicit run. The document-source entry disables autorun before loading
`test_helper.exs`. No common parser framework or dependency was added.

## Six repaired wrapper owners

| Wrapper owner | Counter contract |
| --- | --- |
| `producer_progress_test.exs` | 23 total; selected one; zero failures/skips; 22 excluded |
| `shared_producer_test.exs` | 22 total; existing selection determines one, two, three, four or all 22; remaining cases excluded |
| `collection_split_append_native_test.exs` | 11 total; selected one; zero failures/skips; ten excluded |
| `collection_document_source_use_test.exs` | 19 total; 15 selected; four existing native-sandbox exclusions |
| `query_completeness_test.exs` | Three total; all selected; zero failures/exclusions/skips |
| `test/dev/evaluation/plan_test.exs` | 11 total; selected one; zero failures/skips; ten excluded |

The shared-producer fixture and document-source entry are the two existing
support owners changed with their callers. Expected selection counts remain
explicit beside the corresponding selection.

## Separate representative executions

The earlier producer-progress representative passed one outer wrapper and one
selected nested control, with 22 excluded at each level, in 11.0 seconds including
its private artifact build. This current Elixir 1.20 wrapper result is separate
from the hosted Elixir 1.18 child result that first exposed the prose mismatch.
It does not qualify all 23 controls anew.

A later bounded execution ran five separate normal-start Mix processes against
the unchanged private Host03 runtime, with no compilation or dependency fetch,
one scheduler/async thread, maximum one case, seed 481639 and fresh private
HOME/operator/tmpfs paths. The process-group bound was 600 seconds plus ten
seconds kill grace; test and product deadlines were unchanged.

| Separate scope | Outer result | Nested result | Outer elapsed |
| --- | --- | --- | --- |
| Shared-producer selection | One passed | Four passed; 18 excluded | 11.3 s |
| Native projection-commit branch | One passed; ten excluded | One passed; ten excluded | 14.6 s |
| Document-source default controls | One passed; four excluded | 15 passed; four excluded | 4.4 s |
| Query completeness | One passed | Three passed | 38.2 s |
| Offline Research plan branch | One passed; ten excluded | One passed; ten excluded | 18.2 s |

All five processes completed with exit zero. Outer wrappers and their nested
controls are not added as independent behavioral tests. Unselected native or
population controls were not rerun. The source-use model's 1,000-source geometry
is not populated native-capacity evidence.

Complete Host03 build, dependencies, `priv`, Hex archive, source and harness-input
posts passed. Only the exact existing Mix failure-cache bookkeeping path was
exempted from byte equality. Independent actual-host scoped cleanup exited zero
and found the owned processes, groups and helpers absent. The query fixture used
an ephemeral loopback listener; there was no Input/TTY acquisition, fixed port
39657, real provider, paid model or original notebook access. No global Input or
fixed-listener neutrality is claimed alongside the independent full regression.

## Evidence commitments

Private evidence remains in the dated `ci-failures-20261106-01` and
`inference-budget-fixture-20261106-01` verification directories. No journal or
private request/answer is exported.

| Evidence | SHA-256 |
| --- | --- |
| Eight source-file commitments for these six owners and two support files | `149c377ba7c4489427ec087cac59baad10954c4d29b45f4ea1dc9ea55fbc61b3` |
| Earlier producer-progress result summary | `ffe6d58598c0648739bb17cc8816e986bdf8f1d6041cf6e6034ab3aca45b14a9` |
| Earlier producer-progress output | `6ee68bf67783ecba4d2eadb85d8b4cef2547a9d9504d5f7730ca007ca10bb7ad` |
| Five-owner result summary | `7a1a42320a1981476f524b20771eecf2115ff65b0b699ff44af029fb2e53dce7` |
| Five-owner receipt manifest | `afe5eabe755161e5e317526ff08c42b96c3a612736de20ea5aa80fd27c4510ef` |
| Five-owner terminal status | `058727baf510d33871ece9748de45fb2a7fc8bf08d9080084d43d46fcd5c022c` |
| Scoped-neutral status | `26b9cc6af5b8d9b72cac7c071205863cad7d1b53d15091e742f3205018b3db42` |

## Independent ten-file scope

A separate implementation repaired the same presentation boundary in ten files:
knowledge capture, recall and Session wrappers; Research transfer and fetch
transfer; pinned-native, Job-progress and producer-configuration wrappers;
the evaluation runner; and the opt-in Normalizer integration wrapper. Its
existing Research support scripts were unchanged: their callers installed a
local `ExUnit.after_suite` callback before loading them. No shared reporter was
introduced.

Its separate representative execution passed six of nine registered outer
cases, with three unrelated Research cases excluded, in 48.3 seconds. Those six
covered capture, recall, Job progress, Research transfer, fetch transfer and
producer configuration. Each child passed its exact counter gate and marker.
The run used direct Elixir, a fresh private copy of Host05's complete
16-application runtime, one scheduler and a 180-second bound plus ten seconds
grace. Source/runtime/link posts passed; scoped and independent actual-host
process/group checks found no owned processes. It used no Input, fixed listener,
TTY, model, provider or original notebook.

Pinned-native, Knowledge Session, the opt-in bound-host Normalizer and heavy
evaluation-runner branches were source-reviewed only in that scope. They are
not qualified by the six pure representatives. These results are separate from
the preceding five-owner execution and earlier producer-progress control.

| Independent-scope evidence | SHA-256 |
| --- | --- |
| Ten-file source manifest | `6e5ef058072f65846f16796b32375ae8303c9f82ebdd8eac6b4a82a3cefac733` |
| Source/results handoff | `941350e70f7834bb95644b0d706f1ded11f5e49accad8b1d7ec161e9d8873828` |
| Complete copied runtime inventory | `9ae87c04ec210ed639fda66349d5032fc7e9b5c5bd60d6a63f74465ea10e7dd6` |
| Representative output | `04a3140aad51e1fef8ba3e906498bfc9f7e8e27219d0e6f2b88fa6779b4e472d` |
| Representative status | `2b164cde03bf14f6e410ce64d44582516a61dc9d1ea63b653c2e1b30ccadb6fe` |
| Independent scoped-neutral receipt | `f700f85f92659bca1f4569d44fcf4f3ca297906bc73e724d8327d0ede154491e` |

That scope's private evidence remains under
`ci-output-fixtures-session-20261106-01`.

At this record's closing source check, nine of those ten files still matched
the tested manifest. The Job-progress wrapper had subsequently changed from
three expected child controls to four; its current SHA-256 was
`7c6dc63e71a81202a6ed71b2042db12ee26f2a45f1fd8b6835e93cd71b0a11a6`.
The six-outer result above belongs to the earlier pinned checkpoint and does
not independently qualify that additional control.

## Remaining hosted scope

All eight source partitions in the fetched hosted run remain failed. Presentation
repairs do not establish platform support. Many positive native fixtures returned
`collection_filesystem_unsupported` or `project_identity_filesystem_unsupported`.
The native profile admits specific Linux kernel/filesystem combinations; placing
files in `/dev/shm` alone does not establish that contract. The examined hosted
log did not retain the complete actual Ubuntu kernel/mount fingerprint, so the
specific failed admission predicate remains unknown. macOS allocation support,
separate PTY timeouts and the installed-memory failure also remain unresolved.
No blanket skip, profile widening or weakened assertion follows from these
focused results. The [MCP source repair](ci-mcp-resume-verifier-20261106.md) is a
separate scope; neither record qualifies an installed package or full regression.

The whole current Testing chapter was reviewed. Stable counter assertions are
integrated into its existing subprocess-isolation teaching; acceptance history
remains in this record rather than the manual.
