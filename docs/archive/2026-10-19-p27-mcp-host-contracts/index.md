# P27 MCP host-contract verification, 2026-10-19

Historical verification record only. This records the first generic P27 host
increment, not completion of P27 or retrieval/model quality. Current procedures
are in the [operator MCP manual](../../operator/mcp.md) and
[extension MCP training](../../developer/extension-mcp-actions.md).
The [plan](../../plan.md#p27-optional-research-graph-and-rag) owns milestone status.

The implementation starts from `6096075aa5c91733d911548abb4f87fd3bd2b4d6`.
It adds operator-bound approved MCP calls, complete private result sources,
same-invocation UTF-8 windows and an explicit mixed read/action allowance.
These are generic host gaps: the existing file-tool contract does not route MCP,
and complete MCP text can exceed the unchanged worker SDK string bound. Domain
research/retrieval behavior remains outside Session.
The source commit containing this record owns the implementation and reproducible
checks. No package, private transcript or credential is preserved here.
The [decision trail](decisions.tsv) preserves the working decisions through this
increment, including the explicit correction of its initial placeholder
timestamp. Its temporary-path references identify local working evidence;
the committed verifier/examples supply the rerunnable proof.

## Causal failures and corrections

The initial integration run passed 80 of 85 cases. It exposed fixture defects
in an Erlang launcher expression, linked fixture-supervisor cleanup and expected
cancellation status. It also reproduced a real HTTP cleanup defect.

A separate minimal regression killed the HTTP transport's SDK owner. Before
repair, the transport exited `killed` without a cleanup receipt. Trapping exits
alone still yielded an unconfirmed receipt because OTP handles a linked parent
exit as system termination, interrupting asynchronous closure. The repair starts
the transport without that link and retains its owner monitor and task-scope
registration. Owner loss can then finish bounded Finch-pool cleanup. The strict
owner-death and post-dispatch timeout assertions were retained.

The mixed-action consumer audit found two v1-only assumptions in history snapshot
anchors and lifecycle metadata. Both had controlled failing regressions. Narrow
v2 action support fixed them; metadata still omits private binding/request/result
contents and refuses v2 records outside the action vocabulary. Exact 512-read,
16-other-call and 528-total counter boundaries also have direct checks.

A speculative redaction exception was removed during independent review.
Existing configuration loading already refuses a public argument containing a
different server's secret. Admitted redacted stdio arguments reproduce the
original fingerprint. Pure recovery now recomputes every public server
fingerprint, with negative redacted-field tamper and cross-server privacy cases.

The second run passed 98 of 102 cases. Its remaining defects were the HTTP owner
path above and two fixture assumptions. Raw Erlang stdio needed binary IO to
preserve UTF-8 bytes; ordinary Session close intentionally cancels a question,
so question recovery uses monitored owner loss. Assertions for exact bytes,
source-bound recovery and confirmed cleanup were preserved.

The first extracted-artifact proof reached HTTP successfully but refused the
stdio fixture at startup. The packaged clean boot references `$RELEASE_LIB`;
the fixture had omitted that boot variable. Supplying the same explicit release
library root as the existing production worker fixed the launcher. The corrected
fixture passed all fifteen Session scenarios and the extracted proof without
changing the packaged host or relaxing assertions.

The final audit also required direct extension coverage for resources and prompts,
beyond unit binding checks and existing client catalog tests. Four additional
isolated-worker cases passed across stdio and HTTP, including exact approval,
single selected dispatch, complete saved text and reconstructed windows. The
Session file then passed all nineteen cases. Both twelve-check artifact proofs
were rerun successfully with that expanded fixture. Runtime source was unchanged
after the 970-case baseline; the additional cases extend its fixture coverage.

## Verification receipts

| Check | Result |
| --- | --- |
| Pre-change selected extension/MCP/accounting/budget baseline | 105 passed |
| Corrected MCP, effect-result and HTTP owner cases | 87 passed |
| Corrected real-worker MCP Session cases | 15 passed |
| Expanded tool/resource/prompt and interruption Session cases | 19 passed |
| Mixed compatibility, metadata privacy, history and actual MCP workflows | 34 passed after two controlled compatibility failures |
| Independently compiled SDK artifact, source host | 12 checks passed; 18,900 synthetic source bytes, zero model calls |
| Source build and warnings-as-errors compile | Passed |
| Rust macOS policy unit cases | 4 passed; existing unused `run_anchor` warning |
| Full source baseline before the compatibility delta | 952 passed, 32 platform exclusions |
| Final source baseline including actual macOS native/filesystem cases | 970 passed, 17 Linux-only exclusions |
| Signed macOS file/network enforcement probe | Passed; outside credential/symlink read, write/chmod and network denied; workspace/private-temp operations and inherited policy checked |
| Extracted independent-artifact proof | 12 checks passed; archive/host unchanged, system development tools hidden |
| Standard extracted-package baseline | Passed under the bounded native process-group supervisor; help/demo, workspace paths, helpers/locks, MCP/delegation/extensions, text and explicit-memory fixtures |
| Hosted Linux/macOS checks | Pending |

The local independent-artifact proof used archive SHA-256
`60fd07f2d92eec695af910bb82901a7461e65ee4f9e7a21262da3b41e00f5417`.
This is a local verification archive, not a published release. The macOS probe
emitted its existing optional-process-module warning; stronger detached-process
containment was not claimed. The full suite kept its existing expected negative
fixture logs, and newer Mix reported support-file discovery warnings.

The source artifact proof checks exact approval, stdio/HTTP dispatch, private
source persistence before the public descriptor, UTF-8 reconstruction, inert
idle resume, twenty reads before an approved effect, denied dispatch,
pre-discovery alias refusal, descriptor drift, source corruption and refusal of
the seventeenth external effect. Its verifier and package wrapper are under
[`examples/mcp-actions/`](../../../examples/mcp-actions/README.md).

The module and Session cases additionally exercise child/ungranted/unconfigured
denial, invalid schemas, cross-invocation readers, malformed sources/windows,
pre-repair corruption refusal, pending-question continuation, timeout,
cancellation, owner loss and unchanged legacy step limits. These are protocol
and ownership fixtures. No semantic retrieval, support, citation-quality,
embedding, live-service interoperability or model-selection gate is established.
