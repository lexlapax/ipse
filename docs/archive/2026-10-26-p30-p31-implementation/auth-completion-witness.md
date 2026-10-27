# Authentication and registered inference completion

Recorded 2026-10-27. A credential refresh and the selected inference request use
the same bounded HTTP client. Before this repair, a registered text request's
completion witness was installed before `Provider.request_complete/4` obtained
its token. A refresh HTTP request was therefore observed as a wrong inference
target. The later native inference could succeed, but the witness remained
invalid and the registered service retained an unknown outcome.

`CompletionWitness.during_auth/1` now brackets only the host's ChatGPT or xAI
token acquisition. It restores the original owner-local witness after normal
return, exception or throw. While authentication runs, a sentinel prevents a
nested completion capture from replacing it. Once inference has started, or
the witness is already invalid, this bracket does not hide further HTTP
observations. The exact selected inference target, native response validation
and actual HTTP guardian cleanup remain required. This change does not provide
the still-needed final managed-content freshness/egress barrier.

## Reproduction and checks

An isolated pre-repair graph compiled the original provider sources from
`HEAD` and ran the new end-to-end control. A synthetic expired credential used
the existing test-only auth transport to issue an actual loopback HTTP refresh;
the subsequent main request used an actual loopback Ollama-format response.
The response succeeded, but completion was `false`, as retained in
[the original failure](auth-witness/before.log). This fixture exercises the
real `Auth.token/1` and `Provider.request_complete/4` path with synthetic
credentials; it makes no subscription request. The first attempt selected the
wrong test line and failed because the old module lacked the new helper;
[that diagnostic](auth-witness/wrong-line.log) is kept separately.

The repaired private graph compiled with warnings as errors. Its unchanged
provider/subscription/xAI suites plus new witness controls passed **15/15**,
seed 20261220, max-cases 1: [output](auth-witness/after.log). Controls include
actual loopback refresh then inference, failure restoration, nested-capture
refusal, a second HTTP start after inference, wrong target, wrong owner, wrong
cleanup reference, incomplete streams and malformed/error responses. The three
changed files also passed `mix format --check-formatted`. No external service,
model request or paid credential was used.

The broader provider and authentication suites then passed **259/259**, seed
20261221, max-cases 2; their [output](auth-witness/broad.log) includes expected
TLS hostname/CA rejection diagnostics from negative fixtures. This broad run
does not exercise the registered native service ledger.

| Input or output | SHA-256 |
| --- | --- |
| `lib/ipse/provider.ex` | `d6c8844a3854fddd3afa531bc7de20b176a796a21105376eb2161fb580dfdcc6` |
| `lib/ipse/provider/completion_witness.ex` | `8ab77f800a8e58872f37e19485ebecce262d32439503c12ddc98e2b008e6e068` |
| `test/ipse/provider/completion_witness_test.exs` | `d070b43abd7f40fdfa769415fecb2f1c1806009deb34d1c893cf590bc811c3c3` |
| Before reproduction | `1cfdca11a3b90d75abfa402d471a2f675dbcbeca8c403963f490cf265c46806f` |
| Wrong-line diagnostic | `a377cf33b38b459eed7f37fe9275935774cb91568a7687fb417ba51684583c44` |
| Final test output | `34c5fc2fc15fc05e3249c32025f99381fa58f66507f2919bdfcdcd94e2851511` |
| Broad provider/auth output | `1fae1684fe2f82eefab975cade7f636dfbe359460713c12e3822a4085fdbf1e7` |

These are owner-run component checks, not an independent audit or a live
ChatGPT/xAI qualification. The registered service ledger could not be exercised
on this host after its kernel changed; see [kernel recovery](kernel-profile-recovery.md).
The [plan](../../plan.md) retains the full integration and acceptance gates.
