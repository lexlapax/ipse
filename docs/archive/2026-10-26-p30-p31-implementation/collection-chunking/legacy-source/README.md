# Frozen legacy consumer sources

Historical compatibility fixture only. These exact source bytes are copied from
the namespace-index and packed-adapter source freezes identified in
[manifest.json](manifest.json). They implement the prior Source 1/2 consumer and
must not be edited or reformatted. Current production code is under
`extensions/knowledge/src/`; current behavior is described in the operator and
developer manuals.

The compatibility test compiles these sources into an isolated `_build` fixture
artifact and grants it a separate explicit operator binding. This keeps old-reader
refusal of Source 3 portable without committing generated BEAMs or depending on
an untracked build directory. The manifest's old `_build` paths are provenance,
not runtime dependencies.
