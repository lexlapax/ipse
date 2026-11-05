# V2 metadata correction materialized

Root reviewed and accepted the complete three-line v1→v2 source delta, then
released one short pure OTP slot. The v2 wrapper exited 0 in 0.20 s:

```text
Authored 12 sources; 144 blocks; 168 included text nodes; 36 excluded text nodes; complete 204-node accounting
```

Before and after execution, `sha256sum -c v2-input-preimages.sha256` passed all
15 checks: the 12 original public DOCX inputs, v1 author source, v1 expected
output and raw-package index. The v2 author source hash also remains unchanged.
The runtime lane was released immediately after these checks.

| Artifact | SHA-256 |
| --- | --- |
| expected-oracle-v2.json | e2af13b29bacd36da26490053f1f2b86b6ab37f0c418d43f553537ceb7851a47 |
| author_oracle_v2.exs | 37061b96da1ba15bb262a759928c1aa28bcfb937574eba2a358ad7f6add30cf8 |

A read-only shell comparison replaced only the exact serialized substring
`"heading_style":"nil"` with `"heading_style":null` in v1 and compared that
stream to v2 using `cmp`; it exited 0. Thus all text, byte spans, locators, raw
identities, hashes, policies and other serialized metadata are byte-for-byte
unchanged. All v1 files and freeze receipts remain preserved.

The source-checker's first v1 run and its 36 diagnostic disposition are owned by
Root/checker; the author has received only that metadata finding and aggregate
execution status. Candidate/gold/other-oracle isolation remains intact. This
author makes no candidate mapping, question-score or fidelity qualification claim.
