# Split metadata staging for group append — 2026-10-29

Historical implementation evidence following the [packed-shape diagnosis](shared-producer-v4-packed-shape.md);
the [plan](../../plan.md) owns acceptance. This changes private group append;
public begin and finalization retain their prior flow.

An append now returns a known continuation after each prepared metadata stage.
Before preparing a stage it verifies the immutable group prerequisites; once
all stages exist, the final continuation inspects them, verifies the prerequisites
at the same native generation and performs the existing atomic Job/catalog switch.
This avoids performing two full prerequisite passes in one invocation. The
reservation accounts for one pass, bounded control reads and the actual escaped
read-page counts of the catalog, root and Job anchors. Stages remain owned by the
original Session and retain their original expiry: an active-stage token is not a
fresh-Session handoff or permission to replay an unknown effect. Worst-case
reservation and owner-loss behavior still need independent review and native
qualification.

The full synthetic escaped case now completes: eight near-full segmented
sources, 256 vectors and 256 short-citation facts with wide quote/backslash-heavy
fields produced 32 vector pages and advanced the private group Job over 44
invocations. Hydration used 410 reads and the maximum append invocation used
463 of the unchanged 512 reads. Test execution took 272.0 seconds. These are
model counts, not actual Session journal, callback-deadline, semantic fact
extraction, native peak or full-profile capacity evidence.

Focused model controls preserve guard1, current two-page behavior, terminal
slot reuse, unknown-effect refusal and escaped page round trips. A changed
catalog between metadata stages refuses before another effect and retains the
original stage. Edited tokens cannot bypass missing immutable prerequisites;
the final check refuses missing/altered prerequisites before the pinned commit.
The existing non-append finalization model retains its prior canonical result.

One direct native DocumentStage control stored a source, built a small supplied
group, observed one and then two retained metadata stages, and completed the
Job/catalog switch with the old selected root unchanged. Its first run reached
the switch but asserted `groups` instead of the correct final `manifests` status;
that store remains at `/tmp/ipse-split-append-ae1cc2e6aeb4d57fcc883390d0cfd13a`.
The corrected independent fixture passed and is retained at
`/tmp/ipse-split-append-0c23217707d39c166bee15b04154dead`. Neither is an actual
Session owner-loss control. A separate fresh native Session passed the public
two-page synthetic-loopback path on artifact
`6dee1907b46aa2bc83c73044a927231f8f6bc4828e8cd90b73879f42545da18d`.

The [manifest](shared-producer-v4-split-append/manifest.json), SHA-256
`0eb3fc521ed9f05ae43e5d0befbc6a98e83fb9733550a0c40aa44ea7f8f30c50`,
pins 91 source, artifact, test, log and synthetic evidence files. Earlier
failed controls remain intact. Full native wide append, interrupted stage/owner
loss, Session handoffs, independent review, fact inference and release gates remain.
