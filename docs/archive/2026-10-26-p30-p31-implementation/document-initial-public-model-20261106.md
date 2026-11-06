# Initial document public-controller model — 2026-11-06

Historical synthetic evidence. The [plan](../../plan.md) owns current status;
[storage training](../../developer/knowledge-storage.md) describes the current
implementation and verification boundaries.

An author-run model used the public Corpus controllers and production result
codecs from runtime `e0c2492f`, with modeled Native storage and embedding replies.
It returned a selected initial generation for 1,000 sources, 10,000 chunks,
20,000 facts and 5,000 entities. The terminal owner reported exit zero; source,
runtime, launcher inputs and origin post-checks passed. Its owned process group
was empty. The run did not check global Input ownership.

An independent audit streamed all 11,532 invocation rows and found contiguous
sequence numbers and no recorded unknown modeled requests. The trace reconciles
25,398 modeled effects and 809,948 reads to 1,670,692 action events, including
20,398 modeled mutation IDs and 5,000 modeled embedding calls. The model reports
3,594,044,700 minimum action-journal bytes, before Session headers, outputs and
other overhead. The final modeled store had 5,287 records, no active stages and
a 108,515,328-byte allocation lower bound at a 4,096-byte unit. The summary and
trace SHA-256 values are respectively
`411e23b0574d689b6aeba63fde83ef4036e1f384f6d9f6aa10c676f097d0ca55` and
`1bbc46ab777ce77a2895ab940bcac6ff253625d7cf58c321dc275d9cc62bc64b`.

The model explicitly reports `full_recipe_implemented: false` and `capacity_fit:
null`. It made zero actual native operations and measured no real Session journal
or physical storage peak. The lower bound is not a capacity measurement; the
journal estimate makes bounded Session handoffs and their real overhead material
to the next implementation. Actual producer progression, replacement/history,
cleanup, migration, physical peaks and complete document qualification remain
open. This run did not access the existing 2,000-note notebook or a model service.
