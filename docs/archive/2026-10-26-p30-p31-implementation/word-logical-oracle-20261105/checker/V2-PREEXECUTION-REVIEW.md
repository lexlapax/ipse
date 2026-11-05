# V2 checker derivative: source review before execution

2026-11-05. V1 source review and its receipt remain unchanged. Root reports the
reviewed v1 checker passed on the actual host (exit 0, 0.35 seconds, 30-second CPU
and 35-second wall bounds). Its retained receipt hash is
`59d06c3c6154e6aafe0a9fcca97ba69679635b984e2faaa1d980ef11fad445fc`;
it records all twelve sources, 144 blocks, 168 included and 36 excluded text nodes,
plus 36 absent-style string diagnostics. This record does not replace that run.

Independently reviewed the complete v1/v2 author source diff: only two fresh
output-path substitutions and `nil` to `:null` in absent `heading_style` metadata.
Root's v2 materializer pass is retained separately; no candidate result was read.

Prepared and read the complete `check_frozen_oracle_v2.exs` derivative. It is
**not executed yet**. Fresh receipt destination: `pure-check-receipt-v2.json`,
exclusive creation. V1 source/oracle/receipt remain untouched.

| Preexecution pin | SHA-256 |
| --- | --- |
| V2 checker source | 0c0f932090dd3753f28d79c8f4bd4949acf94a45a263dbd9dc8110715d4d4d65 |
| V2 expected oracle | e2af13b29bacd36da26490053f1f2b86b6ab37f0c418d43f553537ceb7851a47 |
| V2 author literal/materializer source | 37061b96da1ba15bb262a759928c1aa28bcfb937574eba2a358ad7f6add30cf8 |
| Exact 72 raw-node preimages | 0f1e25c54ac15b84c24d759128145da06d39732a1d970b355bdc4746d10f2d29 |

The derivative repeats the complete twelve-source original ZIP/raw-part/text/
block/story/document-span and raw-node coordinate checks. It additionally pins
every raw nodefile before decoding and returns each actual path/digest read in
its receipt. Exactly 72 actual reads must equal the preexecution digest map;
undeclared/missing/changed nodes refuse rather than escaping the closed input set.

It proves strict v1/v2 identity after changing only the existing 36 absent-style
strings to JSON-null values at direct body paragraphs 1/3/4. Changed strings,
text, offsets, keys, source rows, order, locators or other metadata refuse. Each
source must have three explicit nulls, no string `nil` and exactly one raw
Heading1 reference at body paragraph 2. No style-rendering claim is added.

Root may schedule one pure slot with the same bounded host invocation used for
v1, changing only the script pathname. No VM was launched by this derivative
task. After its actual successful receipt is frozen, the checker can issue the
independent v2 oracle verdict. Only **then** prepare/read candidate extraction
comparison inputs and actual installed join outputs. Historical gold conventions,
62 full locators, revision-kind/ID product representation and installed/answer
quality remain separate; the derivative changes no denominator or threshold.
