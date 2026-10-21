# Long-answer implementation review A

No findings in the reviewed implementation diff from fad2856.

Reviewed `lib/ipse/config.ex`, `lib/ipse/profiles.ex`, `lib/ipse/extensions/model_call.ex`, `examples/model-calls/proof.exs`, their changed focused tests, and the Session admission/resume and saved-source paths needed to assess the change.

- Project profiles cannot declare `model_call_timeout_ms`, including trusted project configuration. The field is validated as 1000..600000 and stays outside ordinary profile settings.
- Profiles without the override retain the exact previous snapshot expression. Existing metadata equality and saved source execution equality remain intact. The new proof rejects altered saved execution facts and checks inert resume.
- V1/v2 retain their 120000 request ceiling. V3 shares the structured schema, whole-request bound, provider restriction and response checks with v2. Root/profile/request narrowing remains enforced; delegated approvals now reject execution timeouts above the request.
- Runtime preparation still strips inherited credentials, provider injection and history. Accounting, reservation narrowing and ownership paths are unchanged. SDK-2 aggregate/read/publication limits are untouched, consistent with the approved SDK-1 answers-only scope.

Verification in this review was source inspection and `git diff --check`, which passed. I did not run application code, tests, model requests, services or access private workloads. The supplied focused-test results were not independently rerun. The new proof validates admission/wire/accounting/restore behavior with a fast synthetic response; it does not establish actual 480-second service performance.
