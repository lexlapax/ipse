# Local embedding transport smoke

2026-10-27. This is a single synthetic transport diagnostic, not a retrieval,
quality, offline, protected-admission or release qualification.

On the available `7.2.11-arch1-1` host, `ollama list` reported an existing
`qwen3-embedding:0.6b-q8_0` model with short ID `ac6da0dfba84`. The local
service reported no loaded models immediately before this check. No model was
downloaded and no service setting was changed. The shared Ollama service may
retain the loaded model according to its own policy.

The first inventory command in the default sandbox refused its loopback socket;
the inventory and the following diagnostic ran with approved local socket
access. The [source](local-embedding-smoke.exs), SHA-256
`c46043f6e9ecda382955a00a22a8f59eca4ff1423bc540c73bc3dd3a5f251ba3`, sent one
synthetic input through `Ipse.Provider.Embedding.embed/3` to the explicitly
selected `http://127.0.0.1:11434` endpoint with a 60-second deadline. It received
one valid 1,024-dimensional vector, reported model
`qwen3-embedding:0.6b-q8_0`, eight prompt-evaluation tokens, and 2,903 ms elapsed.
The provider response SHA-256 was
`c8851b829e3150ab94f2dced16a0dfd356ca85c9f324cd57d7563670eb41fd03`.
The vector itself is not retained here.

The diagnostic used the then-current uncommitted working-tree build; it was not
a fixed-source package or a replay of the frozen independent evaluation.

This direct low-level provider call did not exercise Session admission, saved
consent, a knowledge store, model-identity pinning, retrieval or answer quality.
It does not prove the loopback daemon makes no external requests. The kernel and
protected-storage profile remain unqualified; the frozen independent evaluation
was not run.
