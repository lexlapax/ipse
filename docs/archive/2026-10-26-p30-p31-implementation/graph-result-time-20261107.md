# Graph worker result-time boundary, 2026-11-07

This dated development observation does not qualify the Graph milestone. The
[plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance) owns current
scope; the [operator procedure](../../operator/graph.md) describes use.

After the existing State or MCP token and generation revalidation, Graph now
checks the selected-time boundary before **and after** preparing a worker
result. A crossed eligibility transition or sampled clock rollback returns
`query_time_changed` with no evidence or claims. This also discards an in-memory
paged result; it does not change source-token or identity revalidation. Explicit
historical queries keep their selected time. Always-historical sources, sources
whose expiry is no later than observation, and empty fact intervals never become
eligible and therefore do not create false transitions. Other unreturned
captured items remain in the conservative boundary calculation.

A direct isolated Elixir run against the `4f4c1255`-based Graph source and a
separately built SDK passed eight controls, with no failures, skips or exclusions.
They exercise source expiry, sampled rollback, future source and fact activation,
fact expiry, never-current and historical sources, empty fact intervals, explicit
historical query time, inline and >12 KiB paged results, and one fake-MCP
revalidation callback. The fixture uses an in-memory fake host; it makes no real
MCP, native, terminal, or model call. Its retained log is `pure-05.log` under
`_build/verification/p31g-graph-result-time-20261107-01`. The Graph source,
outer wrapper, inner fixture and log SHA-256 values are, respectively:

```text
2a3a89dd01a3dd7ec8ac57509fef9337c5a6433d5921d4062c8c1c41ec26e127
42ba1ba2e7837651c90dfd959afa01595d62a4f699f6fe79444e2cbbb85f2cc7
19b86b240fc5fb2a5ddae59de65920b34676ae6783e2d79071966c43f7dc702b
c0be36292dcc195a68c0df462e2317297b8bfa1b4c4564bb4635116bd4c9f736
```

Two earlier runs each passed three of four cases but failed while setting up the
paged case: eight separate long quotes crossed more than Graph's two-chunk
capture limit. The corrected in-memory fixture uses one uniquely occurring quote
for distinct relations; those failures remain in `pure-01.log` and `pure-02.log`.
An intermediate four-case run passed separately in `pure-03.log`. None made an
external effect or established an unknown outcome.

The unfiltered documentation checker passed in this isolated source checkout:
1,316 Markdown files and 10,568 local links checked, with zero errors. This
check validates documentation structure and links, not runtime behavior.

This samples only the captured worker view. It does not authenticate the original
workspace file or the Corpus-to-Graph association, fence actual dispatch or
delivery, prove a remote MCP service truthful, detect a rollback that recovers
between samples, or qualify installed artifacts and the full source baseline.

During later integration review, a new control exposed a sampled rollback that
remained above the original selected time: the initial integrated wrapper failed
because that result was not refused. The worker now compares the second sample
with the first, and the wrapper passes with that control and a first-sample-at-
expiry refusal. This checks observed rollback between these two samples; it does
not detect rollback and recovery between them or enforce a delivery lease. The
earlier eight-control run and its source hashes describe the prior candidate,
and the full regression at `5e87be95` predates this additional correction.
An independent scoped source review found no further concrete regression in
the revised sampling logic. A fresh `graph/state-explicit` artifact also built
without diagnostics against the existing candidate SDK; it was not exercised
in a native Session or installed package by this build check.
