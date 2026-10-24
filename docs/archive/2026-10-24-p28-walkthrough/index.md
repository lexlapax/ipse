# P28 fresh-operator walkthrough record

Prepared and updated 2026-10-24. **Fresh-account Linux run completed and accepted
by the developer; excessive approval prompts are an open usability finding.** This dated record summarizes
the operator's terminal evidence and follow-up confirmation, not a scripted
acceptance result. The [current installation manual](../../operator/install.md)
and [user manual](../../operator/index.md) own the instructions. The
[implementation record](../2026-10-23-p28-p29-implementation/index.md) owns build,
fixture and release receipts; those do not replace this walkthrough.

## Candidate and prerequisites

The RC1 rehearsal is `v0.1.0-rc.1`, source
`e944fcf6223127f5db0bc290437f7989a9db3069`, with an
[unpublished draft](https://github.com/lexlapax/ipse/releases/tag/untagged-4e6186a5e3de63bc4040).
Both platform matrices and the final re-download inspection pass. The archives,
sidecars, GitHub digests and 13 runtime notices per archive were independently
verified ([receipt](../2026-10-23-p28-p29-implementation/rc-assets.json)). Record
the actual downloaded asset, checksum and compiled build identity before testing;
do not substitute a local archive while describing it as a draft-release download.

| Available RC archive | Verified SHA256 |
| --- | --- |
| `ipse-0.1.0-linux-x86_64-glibc-2.39.tar.gz` | `902bfc03d618322990bef59643ac0186be17805c55006783d350e16a7a652836` |
| `ipse-0.1.0-darwin-arm64.tar.gz` | `d08a357887202d0ba3284b3fcf730c0dd4c2aecc0ba4b9802eaedc6c418419ab` |

These bundles report version 0.1.0 and RC1's source identity. The later runtime
candidate `9c5eb6a` refines refusal messages and has separate passing source and
platform evidence. The developer supplied both attempts recorded below.
A separate scripted isolated-home smoke check of the downloaded Linux bundle
passed; it does not establish a fresh-OS-account human walkthrough.

Use a fresh OS user account on Linux, and macOS where available. Record the host
and account freshness evidence without credentials or personal account details.
Provision the selected provider's key privately before the attempt. Key presence
does not establish tier, model access or free use. The required real task uses an
explicitly selected provider and can incur charges.

The operator follows the manual without implementation-author hints. An observer
may record what happened. If assistance is needed, record it and the exact point
of confusion; repair the manual/message and repeat that step. Do not label an
assisted or scripted run unassisted. Private temporary application state alone is
not evidence of a fresh OS account.

## Attempt 1: existing account

| Field | Observation |
| --- | --- |
| Operator / observer identifiers | Developer/operator A; terminal excerpt and follow-up supplied in this implementation conversation |
| OS, architecture and available toolchain | Linux x86_64; bundled Elixir 1.18.5/OTP 27; distribution and separate development toolchain not reported |
| Fresh OS account evidence | Operator explicitly confirmed an existing account and existing state; doctor reported 58 readable saved-session headers |
| RC asset name and SHA256 | Linux archive named above; operator's `sha256sum -c` reported `OK`; expected digest is retained in the inspected asset receipt |
| `ipse version --json` build identity | Version 0.1.0, commit `e944fcf6223127f5db0bc290437f7989a9db3069`, Linux x86_64, Elixir 1.18.5, OTP 27 |
| Manual revision used | Installation procedure linked from the RC handoff; exact manual revision not supplied; pasted commands match that procedure |
| Provider/model/billing choice | Setup explicitly selected ChatGPT, saved `gpt-6.1-sol`, subscription billing, shell policy off |
| Credential source type, without value | Explicit browser sign-in offer accepted; subsequent doctor reported protected, unexpired subscription credentials |
| Assistance or deviations | No confusion or assistance reported; existing account/state used; human upgrade exercise skipped because only one release was available |

| Manual task | Status | Actual result, confusion or sanitized error |
| --- | --- | --- |
| Download intended archive and verify checksum | Pass, terminal evidence | Intended Linux archive; sidecar check reported `OK` |
| Extract and link the launcher; check version/build | Pass, terminal evidence | Extraction, launcher link and both version commands succeeded with expected RC1 identity |
| Fresh scratch workspace; reviewed setup | Pass, terminal evidence | Temporary workspace created; explicit ChatGPT choice, optional sign-in and exact configuration preview followed by typed `write` |
| Offline doctor and credential-free demo | Pass, terminal evidence | Doctor findings were `ok` or explained reachability `skip`; scripted demo wrote/read its fixture and completed its shell command with exit 0 |
| Explicit real-provider setup and diagnosis | Pass, terminal evidence | ChatGPT subscription selected explicitly; browser flow returned to setup; protected unexpired credentials reported without refresh |
| First real task, full proposed arguments and individual approvals | Pass, operator confirmation | Operator confirmed completing the manual's real task with individual approvals successfully; raw task transcript not retained |
| Inspect the actual file and shell outputs | Pass, operator confirmation | Operator confirmed output inspection succeeded; demo's expected file/read/shell outcomes are also visible in the excerpt |
| List and resume saved work while idle | Pass, operator confirmation | Operator confirmed listing and resuming the saved session successfully |
| Follow recovery for any refusal | Not exercised | No product refusal or recovery incident reported |
| Exercise upgrade | Skipped by operator | Only one release available; separate automated changed-build/resume/recovery proof remains the upgrade evidence |
| Remove installed release and launcher | Commands reported successful | Removal commands returned without a reported error; filesystem removal and retained-state contents were not independently inspected |

### Initial findings and disposition

No product failure or confusion was reported. The terminal evidence supports
installation, explicit setup/sign-in, offline diagnosis and scripted demo; the
follow-up supports the real task, approvals, inspection and resume as operator
attestations. The paste contained a browser authorization URL and private account
paths; neither those details nor session IDs/transcripts are copied into this
record. No credentials or authorization data are retained here.

This first attempt used an existing account and did not establish freshness.
Skipping the human upgrade exercise is recorded rather than relabelled as a pass;
the separate automated upgrade proof remains valid. The subsequent attempt below
retains this earlier evidence rather than replacing it.

## Attempt 2: fresh Linux account

The developer supplied a terminal attachment on 2026-10-24, then stated that the
run was satisfactory and declined another exhaustive walkthrough. The attachment
was inspected through a summary that withholds URLs, private content, approval
codes and session IDs. The raw attachment is not copied into the repository.

| Item | Evidence and outcome |
| --- | --- |
| Fresh OS account | Terminal output identifies the newly created `ipse-walkthrough` account and its new home; the explicit pre-install check prints `Fresh Ipse state` |
| Candidate | Version output reports RC1 commit `e944fcf6223127f5db0bc290437f7989a9db3069`; the supplied Linux archive matches the previously inspected candidate |
| Local setup and demo | Demo configuration and completed scripted-demo output appear in the run; a later doctor reports one readable session header rather than the old account's 58 |
| Explicit real provider | Configuration and live conversation banners select Ollama, model `qwen3.5:9b`; billing is local and no provider credential is required |
| Effects and approvals | The run contains seven distinct proposal confirmation codes: four writes and three shell calls; printed shell exit codes are zero and successful writes are reported |
| Confirmation friction | Five confirmation-mismatch messages are printed; counts describe the supplied run, not a controlled per-task benchmark |
| Operator disposition | Developer reports completing a substantial set of actions and being satisfied; requests follow-up because individual `allow CODE` prompts are too frequent for an operator |
| Resume evidence | The first attempt's successful list/resume attestation remains available; this attachment alone is not treated as independent proof of every resume step |
| Preparation and assistance | Account-provisioning instructions were supplied on request; incorrect chat-local heading links were replaced with file/line links, and `ipse setup --replace` was explained after initial Demo configuration |
| Cleanup | Developer reports deleting the new OS account after the run |
| Other platforms and upgrade | No macOS human run reported; human upgrade remains skipped with the independent automated proof retained |

## Current disposition and follow-up

The developer accepts the completed fresh-account run. Do not ask for another
full walkthrough on the basis that the first attempt used existing state. Record
the product-navigation assistance above; this is not an entirely unassisted
manual-only trial. The accepted brief's unassisted criterion therefore has this
explicit qualification rather than an invented pristine pass.

The material finding is approval fatigue. The existing runtime asks separately
for file writes/edits and shell calls unless the session was explicitly started
with `--yes`. Wrong confirmation input leaves the pending proposal intact and
prints another instruction. The [approval UX proposal](../2026-10-24-p28-approval-ux/index.md)
records a concrete follow-up; no approval authority has been changed by recording
the finding. Existing full argument display, fresh confirmation binding,
journaling and cancellation behavior remain the reviewed baseline.

Stable tag/publication, independent completeness review and any approval-policy
implementation remain separate decisions. The automated installed upgrade and
platform receipts are not relabelled as human walkthrough results.
