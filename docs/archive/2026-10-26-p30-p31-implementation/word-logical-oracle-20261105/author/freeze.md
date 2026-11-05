# Manual author freeze

Frozen before any candidate extraction, old per-input extraction result,
question/answer gold or other-agent oracle exposure:

| File | SHA-256 |
| --- | --- |
| author_oracle.exs | 3f5f217db9db20556bc2dcaba098c29d1c402ba7e9590b31eadf2a202601e9ee |
| raw_package_reader.exs | 46e9c0b9256653b91ff92d9b7a43e67ff89c35bc17c2b48b291eccd1a73641c1 |
| authoring-plan.md | cb444a759157e845efaabebdd166e8d2135787c5290b7f9d1669e51cbfd8a921 |

The literal expected text and raw-node assignments are frozen. Later mechanical
execution should produce expected-oracle.json with complete source hashes,
part hashes, 144 visible blocks and 204 text-node dispositions. Execution has
not yet run. See the plan for exact incidental permitted-plan exposure and the
preserved failed raw-read attempt. This remains an exposed remediation cohort;
the independent author's lack of parser/gold exposure does not make it held out.
