# Independent pilot usage-privacy repair review — 2026-10-29

This additive review corrects the default-output disposition in the
[earlier pilot audit review](pilot-candidate-audit-independent-review.md).
That review checked candidate/category fields but treated provider usage as
ordinary metrics without checking its attribution payload. This was a review
gap. Raw provider usage passed unchanged to both public progress and returned
records and could contain content. The root's subsequent approved live pilot
exposed this issue; this reviewer did not open, print or copy its raw progress
or candidate files.

The repair replaces that raw field in the shared `perform/4` return path with
`Ipse.Usage.normalize(config.provider, usage)`. It applies to both initial and
continuation responses. The existing normalizer extracts only named numeric
counters and returns a closed record of counters, derived-field names, quality
and fixed issue labels. Arbitrary attribution fields are omitted; invalid
counters or non-map input produce a content-free invalid record rather than
echoing provider data. The source review covered both permitted pilot providers,
ChatGPT and Ollama, including their extractors and the normalized record validator.

The recorded focused suite passed **15 tests at seed 47008**. The reviewer
inspected that receipt and its new regression without rerunning the suite.
An independent [synthetic probe](pilot-candidate-audit-review/usage-probe.exs)
then exercised both initial and continuation progress for each provider with
valid counters plus nested attribution content, and with malformed content in
a counter field. All four cases passed: both callback and returned records
contained valid normalized usage and no synthetic content marker. Valid token
totals were preserved; malformed counts reported invalid quality. Each case
ended with a deliberate third mock-request failure, counted three attempts,
retained two response records and performed no retry. Only synthetic booleans,
provider names and counts were printed. There were no live provider calls.

No additional concrete defect was found in this narrow repair. It changes the
pilot's public `usage` representation to the existing normalized contract; the
[contributor manual](../../developer/capture-pilot.md) now explains that format
and its unknown/invalid counter limits. It does not alter model selection,
candidate audit consent, the private candidate schema, request ceiling or any
publication authority. It cannot retrospectively remove content from earlier
raw progress files; those require continued private handling.

The root reports that the partial live run has 96 proven responses and no final
result receipt; its cause and in-flight outcome remain unknown. Those facts do
not establish pilot completion or the exact final dispatch count. Charging its
full 120-request reservation conservatively, with no retry, avoids converting
missing evidence into additional allowance. This reviewer did not independently
recount private live records or qualify semantic candidate quality.

The reviewer changed no implementation and ran no aggregate validation. The
parent retains the seed 47008 receipt, accounts the private run and batches
documentation validation.
