# MCP resume-verifier correction, 2026-11-06

Historical verification record. Current guidance is in
[the verification laboratory](../../developer/testing.md#learn-a-complete-workflow-through-the-compatibility-lab),
[MCP configuration](../../operator/mcp.md) and
[extension MCP calls](../../developer/extension-effects.md#bind-and-call-an-external-mcp-item).
This record qualifies a synthetic source verifier, not an installed package,
hosted CI run or complete regression.

The fetched hosted run `42192551584` failed its independent MCP source proof at
an assertion that an idle reopen left the journal byte-identical. Current
release-layout Sessions append one owner-start marker. The verifier now requires
the exact original byte prefix followed by exactly one complete, same-Session
marker accepted by the existing `ReleaseReceipt` validator. Legacy journals
without that layout still require an empty suffix. Altered prefixes, duplicate
JSON keys, malformed or foreign markers, missing or additional rows and extra
fields refuse. Transport records remain separately byte-exact.

The helper lives in the existing independently compiled verifier owner and uses
runtime JSON and release-receipt APIs. It adds no dependency on test support to
the installed harness and changes no production behavior.

## Separate results and preserved failures

| Execution | Actual result | Scope |
| --- | --- | --- |
| Pure 06 | Setup failure | The test loaded the fixture-only harness and incorrectly assumed the verifier module was loaded |
| Pure 07 | One selected outer test passed; 35 excluded; 2.7 s | Existing independent runtime harness; two accepting and nine refusing synthetic suffix cases in the child |
| Source 01 | Exit 1 | Repaired idle boundary passed; a later descriptor-drift expectation was stale |
| Source 02 | Exit 0; all 12 checks true | Fresh artifact and evidence paths, existing Host05 SDK, ordinary source verification |

A copied source-packet guard initially named Host03 while its command selected
Host05. Review caught that preparation error before dispatch. Its preimage was
preserved; the executed guard covered the actual complete 16-application Host05
runtime and private `priv`, without a mutable-cache exemption.

Source 01 expected descriptor drift to finish successfully with a known refusal.
It actually finished with an error. Cleanup removed that synthetic journal, so
this record does not infer its missing action details or tool-wire count after
the fact. Its failed result remains unchanged.

The existing real-Session fixture establishes the conservative distinction:
admitted MCP discovery may make a later descriptor-change outcome unknown even
when the fixture receives no tool call. Source 02 therefore requires an error
terminal, an exact empty unknown outcome and no effect result source. It also
requires an unchanged tool-call count and one additional discovery measured
from the post-approval-discovery baseline. Confirmed close and same-ID idle
reopen must preserve the original journal prefix, append only the valid owner
marker, and create no further transport records. No effect is replayed.

Source 02 reported 18,900 source bytes and zero live model calls. It built only
the private MCP artifact against the existing SDK; no Core/runtime compilation,
TTY, Input lock, fixed port 39657, real provider or original notebook was used.
Runtime, source and harness-input posts all passed. Independent actual-host
scoped cleanup exited zero and found the owned PID, process group, BEAM and
helper processes absent. These checks make no global Input or fixed-listener
neutrality claim while the separate default regression owns those resources.

## Evidence commitments and remaining gates

Private evidence remains under `ci-mcp-idle-resume-20261106-01`; no journal,
private request or answer is exported here.

| Evidence | SHA-256 |
| --- | --- |
| Final `dev/verification/mcp.exs` | `86553e5c897721238e177612b89404165606546eb69f8337c7d95771557d8387` |
| Final `test/dev/verification_test.exs` | `b370dbb08e9948f828e6869d5efb580d500f8722c273f1d95b8a423999064969` |
| Source 02 packet manifest | `2c449576b5a982f39484b475a8a12fa586759d3fcf97bcdadb5c76047dcbb2bb` |
| Failed Source 01 output | `e0a649bd97e7c221f482cea17b3522b85b02d6f5aa20a5fbff764b3b68f7ae41` |
| Passing Source 02 output | `c15ea9d9afb98e61923562456466949a252483ac69e998e18228cf58a8c83ab4` |
| Source 02 status | `058727baf510d33871ece9748de45fb2a7fc8bf08d9080084d43d46fcd5c022c` |
| Scoped-neutral status | `26b9cc6af5b8d9b72cac7c071205863cad7d1b53d15091e742f3205018b3db42` |
| Private result summary | `cf5b21849503d1440e867d46b23206a7cd8e1cb4071fae7b20bc0fd52f6ff061` |
| Private receipt manifest | `f58ca97ef0b509f1dd0b5d5d5ffa5ab4f4b9b96b2445c5f23d08cd5df88e5124` |

The whole current Testing chapter was reviewed. Its existing MCP guidance
already distinguishes strict resume evidence from transport records; the
associated [child-counter correction](ci-child-result-counters-20261106.md)
adds stable child-test assertions. The fetched hosted run remains failed.
A fresh current package and separate installed MCP proof remain required;
older available archives do not qualify current source. Native filesystem
support and unrelated hosted failures are separate gates, not consequences of
this verifier repair.
