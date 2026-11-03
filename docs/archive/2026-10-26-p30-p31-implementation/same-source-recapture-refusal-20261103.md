# Synthetic same-source recapture attempt — 2026-11-03

Isolated git archive of HEAD `184dac3bd8e77d1fe860be5af596ea55df26c289`, with only the following formatted fixture overlays:

- `test/extensions/knowledge/knowledge_session_test.exs`: SHA-256 `70d3832bf82f3a6dfe97296f4bc0e80d03dfc6f2e7e5edfe811e6265608ce7e2`.
- `test/support/pending_rejection_cli.exs`: SHA-256 `4e0eb11484792dad44ddd6955f83e75110106668138563e7271cc4f40f0f8eb9`.

An initial sandboxed build failed because Mix could not acquire its local TCP lock; the same source built successfully with local TCP access. `build.log` SHA-256 `a3f29c3c7177e68cf06c8a8fc3064fd879e53229313fb2bac225ba095747263e`; `build-escalated.log` SHA-256 `16f569d69bc32a03ce9cecd0eb79bedbd0e83abc3137f5d8cdec036aee1099d5`.

One opted-in run of `mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_rejection_recapture --seed 0` failed (0/1, 11.7 seconds). The bundled worker captured two synthetic proposals through actual Session turns; the native reviewed rejection of the first completed with its original source retained, and the fixture did not revoke the grant. A distinct third turn in the reopened original Session failed at managed preflight before inference dispatch, so there was no worker recapture attempt or managed commit. The required exact same-source and rejection-suppression assertions were never reached. No automatic retry was made. Test log SHA-256 `eeb4e7def5bd6963a294cfa6dd2bd4ceff61ae9f056d60b1c23abb8b557a57cc`.

The journal includes an earlier successful root transition covering generations 1 and 2. A separate native management rejection settled before the next preflight refusal. This is consistent with the existing same-Session root-rebase boundary: root transition validation requires a successful Session-recorded new capture and an exact current-root receipt. The refusal contains no internal verdict or failure category, and multiple conditions share that event; the exact failed predicate and causal attribution are not established.

The temporary snapshot is `/tmp/ipse-rejected-recapture-184.hi4kM3Kz/`, and its preserved synthetic root is `tmp/ipse-native-knowledge-session-540ad84298db7af2f79b6a0987e05d1f` under that directory. The Session journal SHA-256 is `c30be6bae1aa65fd63059ee4c2871ee2c9119111e3f6ca8f9566ec34817c5280`; the native management journal SHA-256 is `62ef3083ad8d5a9a7f5e6e12c6d66d88557d6f98c9ba4af0c6bb293e6b29a7ea`. These synthetic findings do not establish legacy public override availability or same-source recapture suppression.
