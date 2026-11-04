# Remaining P31G work after the stored-source increment

1. Review/promote this Graph-only tool and its tests; reconcile operator/developer
   Graph guidance and qualify the integrated current build. This is the only
   newly implemented increment in this packet.
2. Define and implement reversible alias/merge identities. Evidence currently
   stores string entity identifiers; name equality cannot establish identity.
   Keep distinct entities, mistaken merges and undo/correction inspectable.
3. Complete conversational capture's original-source admission/current-use path.
   Public `source.read`/`source.quote` plus `Extension.source_proof` provide
   historical evidence JSON, not permission to publish another store or a
   durable current-use capability. This tool consumes already stored sources.
4. Review the managed graph publication API gap. A real managed note/read adds
   dependencies; Session.Invocation correctly refuses State.put/delete and
   generic Collection.store in that context. Graph has State/MCP presets only.
   Do not bypass these guards or present an untrusted stored receipt as current
   source authority. A Collection-backed managed graph adapter needs explicit
   source/policy/owner/publication fencing before implementation/qualification.
5. Carry correction/forgetting/suppression across admitted notes, relationships,
   aliases and derived stores. Current component evidence covers ordinary State
   source replacement and forgetting, not full managed cross-store lifecycle.
6. Evaluate extraction separately from traversal using frozen unsupported
   relations, negation, false merges, conflicts and temporal updates. Scripted
   main-provider controls prove integration, not real extraction quality.
7. Complete C1b graph collection capacity and installed optional-package journeys.
   Existing State's 256-record envelope is not the planned 5,000-entity/
   20,000-relationship target. Retain graph experimental/off status and exact
   failures until the corresponding implementation and safety checks exist.
