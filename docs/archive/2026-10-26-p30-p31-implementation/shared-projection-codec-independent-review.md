# Independent review of shared projection codec

2026-10-29. This read-only scoped audit covers the frozen
[shared projection codec](shared-projection-codec.md), not a published global
generation or completed capacity profile. The reviewer verified 15 source
snapshots, eight logs, 61 artifact files, 209 host BEAMs, the helper and strict
gate manifest. The recorded read-only Session result and dry 5,030/6,414 key
arithmetic agree with the implementation. No aggregate or native tests were rerun.

One bounded pure reproducer found a canonical round-trip defect: a fact with
numeric `version: 1.0` passes existing validation and shared packing, but
successful hydration regenerates integer `1`. The fact ID and citation identity
remain the same, but exact supplied/hydrated equality is false. The shared
boundary must refuse the noncanonical version or require exact regenerated
equality, with a focused negative control.

No concrete authority, source identity, vector-input, citation-span, warning or
page-order defect was found in the inspected frozen codec paths. This does not
authenticate actual model provenance beyond declared selectors. Trusted global
manifest/catalog/floor selection, public selected-query integration, atomic
publication, GC, migration, lifetime indices and full populated/rebuild peak
capacity remain unqualified. The strict publication gate remains closed.
