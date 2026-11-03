# Eight-owner Worker handoff attempt

2026-11-03. This synthetic diagnostic stopped before its traced Session and
does not explain the [retained-cohort failure](retained-probe-20261103.md).
The [plan](../../plan.md) owns current status.

An isolated snapshot of commit `d0dcaf03fa64da0eef3fe3eefa064a748e88d5a5`
excluded duplicate archived documents and used separate dependency, build and
home directories. It overlaid only the following disposable test files:

```text
3fe075fbfe63b0341904f530fe8db69734a75b0f037f0274644d145d8b1425d2  test/support/managed_literal_ab_seed.exs
637ecf5517edf414c1196716cbd3f811707d74d5655adaac48ca742d53ad1d74  test/support/managed_literal_pair_runner.exs
4c02625530d0209ec2e9e2cce10a137426e227281d8fe8aee22baa6f1cdca59e  test/support/worker_handoff_trace.exs
1bd6e076dbfb61cb8afdbc6bc7f8a1e27b5af549d4d25815743997bc4f6003fb  dev/verification/worker_handoff_trace.exs
```

The complete [source manifest](worker-handoff-eight-owner-20261103/ipse-eight-owner-d0.oSeft09F.source-sha256)
SHA-256 is `82e75962c6b700761da6e53994a33136d2e12704bc522e0d3a6f092d4d7a72f6`;
all listed source hashes matched after the attempt. The copied
[dependency manifest](worker-handoff-eight-owner-20261103/ipse-eight-owner-d0.oSeft09F.deps-sha256)
SHA-256 is `bc860d87c49dd1fdbac11c07f0a5f480aab3cad0876880b27fe0963b68181100`.
All dependency files outside generated `_build` directories matched afterward;
the copied telemetry Rebar `source.dag` build cache changed during compilation.

The offline test-environment [build](worker-handoff-eight-owner-20261103/ipse-eight-owner-d0.oSeft09F.build.log)
passed with the native helper and bundled artifacts. A single fresh native
fixture seed then passed: its private seed report contains eight note keys,
eight distinct original Session owners and Collection generation eight. Its
seed report SHA-256 is
`e66d7aa8ffad1d28d2eb7333ce610bf453d4df8f16f844c97013391df841edff`;
its private terminal log SHA-256 is
`9d7d4cef6b230173a959997e553bd3524b623bbc9210075b3bf2f8a09cbc9f41`.
These private fixture files remain under `/tmp/ipse-handoff-eight-d0-01` and
`/tmp/ipse-eight-owner-d0.oSeft09F.seed.log`; the seed's synthetic source text
is not copied here.

The one diagnostic launch exited **1** before tracing or starting the test
Session. The [error log](worker-handoff-eight-owner-20261103/ipse-eight-owner-d0.oSeft09F.trace.log)
reports a syntax error at `test/support/worker_handoff_trace.exs:114`: a `for`
expression used as a map value needs parentheses before the following key.
**Zero handoffs were measured.** The tracer and fixture were not modified or
rerun after this error. No claim follows about source-owner scaling, timeout,
cleanup or the cause of the retained-cohort failure.

The successful historical two-owner control used a different source revision;
it is not a controlled comparison to this attempt. The diagnostic used no
production deadline or source-lock changes and made no live model calls.
