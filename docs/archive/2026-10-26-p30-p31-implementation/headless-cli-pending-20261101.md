# Headless CLI pending capture with saved native consent

Dated **2026-11-01**, based on `580d11a` plus the focused test/manual changes
recorded here. This is source integration evidence with a synthetic registered
provider, not live-model quality, installed acceptance or full P31 completion.
Current procedures belong to [notes permission](../../operator/knowledge-permissions.md)
and [testing](../../developer/testing.md#require-positive-controls-and-inspect-uncertainty);
remaining acceptance belongs to the [plan](../../plan.md).

## Replace a vacuous diagnostic with successful-save requirements

The [2026-10-29 argv/stdin diagnostics](headless-cli-untrusted.md) retained real
CLI errors and empty stores. Their old assertion accepted any page whose records
were all pending, including an empty page. It established no successful capture.
Those historical sources, logs and receipts remain unchanged.

The current `headless_cli_untrusted_process.exs` was first run unchanged against
the current test graph with a freshly compiled native PTY driver and private
working directory. Its separate argv CLI exited zero and stored one pending
proposal with the original task's `unattended_input` source. Its retained root is
`/tmp/ipse-current-headless-cli-e72a0a4128932d639f6b916b23d8c8ef`, with launcher
and child output in `/tmp/ipse-current-headless-cli-{launch-,}20261101.log`.
Read-only inspection found a successful publication and completed turn, not
merely the old diagnostic's pass marker.

Two ordinary regressions now run this helper through `knowledge_test.exs`:
one supplies task text in argv, the other redirects an actual regular file to
the child CLI's OS stdin. The parent performs genuine native project/permission
review first; the child uses the saved operator configuration, current bundled
artifact, explicit registered loopback Ollama service and normal CLI dispatch.
There is no `--yes`, injected grant, manufactured source or old runtime overlay.
The shared test launcher uses absolute code/source paths and a private cwd.

Each case requires:

- Five real adapter requests completed/final, CLI exit zero and a successful turn.
- One successful saved-consent V3 publication, `never_current` eligibility and
  one exact visible pending record at generation one.
- Stored proposal text matching the task, assigned preference remaining pending,
  exact original unattended-input proof and original Session ID.
- A settled consent operation, strict Saved reconstruction without unavailable
  lineage, no unknown Worker input, and a verified signed Session release claim.
- A real read while ordinary write and shell tools never start and their target
  files remain absent. The knowledge grant supplies no ordinary mutation authority.

The synthetic response deliberately asks to save the unattended task rather
than treating a prose file read as a trusted typed factual outcome. The assigned
category is not operator endorsement. Successful pending capture does not
promote the proposal into current-note recall or accept its premises.

## Verification and remaining limits

The first strict pair passed **2 tests, 8 excluded, 12.8s**, terminal exit zero,
in `/tmp/ipse-headless-cli-pending-first-20261101.log`. The complete CLI suite
passed **10 tests in 27.2s**, terminal exit zero, seed 978075, in
`/tmp/ipse-headless-cli-pending-final-20261101.log`. This includes every existing
permission, configuration-drift and refusal case using the private-cwd launcher.
The selected complete command was:

```sh
mix test test/ipse/cli/knowledge_test.exs --max-cases 1
```

Format and strict compilation passed in
`/tmp/ipse-headless-cli-pending-{format,compile}-20261101.log`.
The notes permission, general usage and developer testing chapters were reviewed
as whole documents. Existing task instructions and scope limits were reconciled;
the repository handoff now describes the implemented narrow saved-consent path
without relaxing ordinary headless mutation rules. Documentation checks passed
**1007 Markdown files, 8370 local links, zero errors** in
`/tmp/ipse-headless-cli-pending-docs-20261101.log`. Pre-existing inaccessible
private-ledger directory warnings remain distinct from documentation errors.

| Exact input/result | SHA-256 |
| --- | --- |
| `test/ipse/cli/knowledge_test.exs` | `2b806fd64e5a823179592ec51fceae4896e382f4dfcb25c6ffba1bf214e20a9c` |
| `test/support/headless_cli_untrusted_process.exs` | `e29ae4d9a418d9a6c988edbb14c33adef1519f62ae90ba73dcea84913947c242` |
| Unchanged child CLI launcher | `8475ec275835511fcd40f62f4119263af84743dc34312e6aa3d81a5758ef8cb5` |
| Unchanged ProviderFixture | `0092d34f9e3adeed2bf184e3ab48feabd79eeacd2b5f0e5c1b5c654ceba2dcc1` |
| Matched native helper | `5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a` |
| First strict-pair log | `cd12b2c8b2d7c9c01ca57a64ab15d4892e7f81862c32cb7f01483b479f79f8f2` |
| Complete CLI-suite log | `58e984d1ae5bed836dfa04b64b69bea0b5760620b2ae9aebe2860405790a9511` |

Ordinary regression homes are removed on test cleanup. The separate original
current-source diagnostic root above remains retained; it is evidence, not an
operation to replay. The same-runtime credential-free demo and CI policy passed
in the immediately preceding [registered-capture increment](repeated-v3-capture-20261101.md).
No runtime source changed between those controls and this CLI qualification.

No production module, dependency, native helper, live account or downloaded model
changed. The fixture proves current-source argv/stdin capture and its scoped
authority boundaries. It does not establish that a real model chooses capture
correctly, installed behavior, other provider protocols, every source category,
repeated headless CLI conversations, endurance or full capture/recall acceptance.
The final source/package qualification, quality work, adversarial audit and
reviewer handoff remain open.
