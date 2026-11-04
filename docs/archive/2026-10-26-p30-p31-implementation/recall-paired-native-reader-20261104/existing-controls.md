# Existing withdrawal controls and their exact scope

Source review only on 2026-11-04. This list records implemented controls; it is
not a fresh execution receipt or a claim that they interpose between the new
worker observation passes.

| Location and exact name | Actual boundary exercised |
| --- | --- |
| `test/ipse/extension/managed_collection_call_session_test.exs:3303`, generated `nested native result is withheld after root_change between committed effect and Worker input` (also MCP and revoke variants) | Holds the successful committed action reply, changes Collection root or revokes permission, then releases it. Requires the already-real effect to remain, Worker input to be unknown, no continuation payload in worker trace, strict Saved unavailable state and idle no-replay. This is a worker-delivery boundary, not a deterministic change between its two internal observations. |
| Same file:1744, `a changed current root refuses display preparation before entering its adapter` | Builds a real root dependency, advances the root before calling the adapter, and requires no adapter callback. This covers stale input before entry on the separate display path. |
| Same file:8106, `a root change during generation withholds buffered native output without retaining policy locks` | Waits for the actual provider body, changes the native root, releases the response, and requires no terminal text, no completed answer in the journal and no remaining result seal. This covers final inference-result release after egress. |
| Same file:9311, `loss of a literal source during decision inference withholds its response` | Holds a genuine literal-derived decision response, makes the original journal unavailable, and requires no successful decision result or worker advice, plus strict Saved reconstruction. It restores the source byte-identically afterward. This covers original-source withdrawal during inference, not root reuse in worker delivery. |
| `test/ipse/session/stored_sources_test.exs:1470`, `source owner loss before the native decision leaves the root unchanged` | Kills the actual source helper before native root switching under a real retained source lease. Requires switch unknown, source refusal and unchanged root. This is a native lease component boundary. |
| Same file:1518, `loss of either original session prevents a two-source root decision` | Repeats the native decision boundary for each original source in a two-source retained set; either helper loss must prevent the switch. |

The focused root-witness reuse case separately covers authentic mixed v3/v4
observations, independent pass counts, v3-only fallback and incompatible roots.
Root changes specifically between its passes, after its second observation but
before the final native owner, or across separate 32-record chunks remain
explicitly unexecuted interpositions. The unchanged source fences were read;
no production hook or timing-sensitive trace is proposed as a substitute.
