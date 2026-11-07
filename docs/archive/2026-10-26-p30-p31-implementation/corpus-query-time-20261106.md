# Corpus full-snapshot time candidate — 2026-11-06

Historical synthetic development evidence. The [plan](../../plan.md) owns
acceptance; the [Corpus manual](../../operator/corpus.md) and
[extension training](../../developer/knowledge-extensions.md) describe current
behavior. The earlier [namespace-fence record](corpus-namespace-fence-20261106.md)
remains separate.

The candidate bounds time changes within an ordinary full State/MCP snapshot.
It checks captured source observation/expiry and fact-validity transitions for
null-as-of queries before proposing rerank, at final store revalidation, and
after a workspace-file check. Explicit historical timestamps retain selected-time
semantics. An unrelated captured transition can cause a refusal.

One author-run pure fixture completed 14 tests without failures or exclusions,
seed 1306, using one scheduler and no native Input, MCP transport or model call.
It exercised State source observation and expiry, Graph-captured fact validity
boundaries, explicit historical controls, malformed continuation context,
simulated clock rollback, a simulated workspace callback and the point before a
rerank model action is proposed. It also retained the earlier eight synthetic
namespace controls. The original test log remains in the private verification
workspace; its SHA-256 is
`e760b68e3018c99ef23346eb12197d0641eff332b76ed53ec170b5203539739d`.
The tested private Corpus source SHA-256 was
`c84af895c0855ed45b0af1674bb256a948707d4fa75fd35827887bbed6592dee`,
and its fixture SHA-256 was
`77c3f9b6bd6112066d27c4d20f70f19f9ad7c209c12afb30fd387a48c240097b`.
The integration owner subsequently reported one repository-wrapper pass: one
outer test, seed 324370, in 21.9 seconds, requiring all 14 inner controls and
their unique marker without warnings. The integrated Corpus source SHA-256 was
`7a723bd744986f65500799e69a4d4d714e6b1d972fe0324eda37d5d5df2cd827`;
the support fixture SHA-256 was
`430ddec9adf3b0ed58d2a78279bd8948eeec2e538716f33160c674047d7d89f7`.
The raw wrapper log was not retained, so this is the owner's reported observation,
not a separately inspectable transcript.

After formatting the support fixture with Elixir 1.18, a separate one-scheduler
source run passed all 14 controls, with source and fixture hashes matching before
and after. Its retained log SHA-256 is
`301174a58a226e4d67d54c01c48d495ce07720c89661f0f2f03ddac5d6587106`;
the formatted fixture SHA-256 is
`81af360928286bef2aadfea359c87ca594ea87834ad88f199d2603e202cb4090`.

Remote-selected and Collection queries can omit future-eligible items and do not
have this full-snapshot bound. A subsequent private remote-selected candidate
extends the sampled guard to hydrated selected sources only. Its one-scheduler
synthetic fixture passed 16 controls with exit 0, including current and explicit
historical queries, empty selection, a simulated final-boundary crossing and a
real source expiry before model proposal. The retained run log SHA-256 is
`a8ed46c1c10e68474c6e765cb33d6fb621e9341beff3e837e3114c0a9dcbb17d`;
the candidate source SHA-256 is
`837e279a4acb23fb013ce43a38971aa01936148c99d36fc5205b19331895803a`.
After integration and Elixir 1.18 formatting, the direct source fixture also
passed all 16 controls with exit 0; its retained log SHA-256 is
`9e9de58f1d9d86d4f813ea158ca567739e26c9488be6814dc919b8581ed74eed`.
The tested Corpus and support fixture SHA-256 values were respectively
`c064ba5b142aa5d6e776045bee2e0cf6f6974cc483c75bd644333ed232f64e42` and
`e5683d388abb9d7cd0480d78318592f8af4252da3ea7680555d4040d7521937a`.
These controls do not establish the current eligibility of omitted sources or
exercise real MCP transport.

A later Collection candidate uses all indexed source summaries for namespace
BM25, selected sources for selected BM25, and selected source/fact boundaries
for dense and hybrid queries. Six synthetic closed-host tests passed with exit 0
after Elixir 1.18 formatting, including an empty namespace, a controlled semantic
final continuation and a simulated workspace callback. The retained log SHA-256
is `0f7d1895566321715f6417d4da50ea2aeeacf1af9638c3c27d49d413d48476db`;
the private tested Corpus and Index sources were respectively
`a70d30effa964a1cb4807af3eb7c5ba5e47ae7092a5198d7a8954cfff6be3e84` and
`91c0fa97b26c8c1a484022039909cfebf673c2c6e90f3657dd33eadca7bdffaa`.
After integration, a direct source run using the existing helper BEAMs passed all
19 existing and new controls with exit 0 and no warnings. Its retained log
SHA-256 is `502697d795af62bcc100f12a3e80caf6aa48c9184e8b7b1d16650ca8a87c9bce`;
the integrated time-control fixture SHA-256 is
`d23a69c5a7cbf19ed9fe79ebfc7059be1f76907234bae4a7e16d999979ce94da`.
After the Collection integration, the separate State/remote fixture was rerun
against the integrated Corpus source and passed all 16 controls with exit 0.
The Corpus and fixture hashes matched the integrated hashes above and
`e5683d388abb9d7cd0480d78318592f8af4252da3ea7680555d4040d7521937a`;
the retained log SHA-256 is
`9e9de58f1d9d86d4f813ea158ca567739e26c9488be6814dc919b8581ed74eed`.
The isolated repository wrapper remains pending.
Semantic hydration and workspace bytes were simulated; no native Collection
Session or model dispatch was exercised. A source expiring at the Collection
recheck can return `snapshot_changed` before the sampled time guard.

The rerank and query-embedding checks are before host proposal; approval
can delay dispatch past the boundary. The sampled clock can roll back and recover
between observations, and the check is not a delivery lease. These controls do
not establish real MCP transport, real workspace-file handling, installed use,
model quality or complete P31 qualification.
