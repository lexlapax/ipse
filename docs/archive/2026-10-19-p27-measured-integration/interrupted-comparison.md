# Superseded CPU comparison

Historical verification record, 2026-10-19 session. The final observation was
2026-10-20 06:16:59 UTC. Use the [evaluation chapter](../../developer/knowledge-evaluation.md)
for current procedures and the [plan](../../plan.md#p27-optional-research-graph-and-rag)
for outstanding acceptance. P27 remains incomplete.

Source `f2bfc8d7f8dd3fadedd2e18183faf4533ee63ac5` began a fresh CPU-only
comparison using the original selected model manifests and the already-used
frozen workload. Repeating that workload produces a repaired/reused-set result,
not untouched held-out evidence. The preparation read no quality labels or
prediction text to tune the implementation.

| Binding | SHA256 or identity |
| --- | --- |
| Execution | `9bf55ae29d21adf4d550ece2004e9dd1` |
| Freeze manifest | `3b7ffa9d3e79d9fafed4ac78135a36f57e6ae1214b98802e8b3f5f1cd741afa0` |
| Selection | `fc870ad9b2258e31127d8feb796a827641635464d7e6903f5280f08687d4f30a` |
| Original data manifest | `2759aebcd62f1d6368ce41dfd038ead0d4948f78ab5db4ba41ae92d7e9336063` |

Whole-P27 review then reproduced graph-depth completeness and durable embedding
selection omissions with separate synthetic probes. The comparison's candidate
was superseded. Only its owned root service was explicitly stopped to avoid more
inference against that candidate. The stop returned success; the unit was
inactive/dead with no remaining control group or matching private model daemon.

The last closed cell had 25 prediction rows, 25 canonical admissions and 25
finished requests, a retained domain result, model-service receipt and close
phase. The next cell had a service receipt and was performing explicit graph
extraction, with no model admissions, finished requests or prediction rows and
no completed domain result. These counts do not establish a complete experiment.

Later read-only inspection of the first cell's native receipt found
`complete: false`, `exit_code: 0` and `reason: "residual_descendants"`. Its domain
and service closure therefore did not establish a complete measured lifetime.
The collector observed a populated descendant scope after the leader exited and
forced cleanup. That receipt does not identify the residual or establish whether
it would have exited naturally. Its peak is not an accepted comparison result.
Fresh bounded diagnostics must resolve that cleanup issue before another real
comparison; the old receipt remains unchanged.

The native execution terminated with exit 1 and `failed/stage_protocol`.
Execution and resource completeness were false. There is no complete post-exit
audit, complete quality score or accepted full-comparison peak. Process absence
establishes cleanup, not successful completion. Private declarations, journals,
claims, partial results and failure receipts remain retained and immutable.
Never reuse this seal, replay its operations, renew its budget or resume it.
A corrected comparison needs a separate reviewed source, plan and fresh seal.
The earlier interrupted 280/350 run and its unknown request also remain untouched.
