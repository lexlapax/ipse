# Approval UX research from the P28 operator walkthrough

Research and proposal, 2026-10-24, against runtime `9c5eb6a`; no policy change is
implemented by this research. The subsequent authorized
[implementation record](../2026-10-24-approval-implementation/index.md) tracks the
follow-up before audit. The [walkthrough](../2026-10-24-p28-walkthrough/index.md) supplies the
operator feedback. [Terminal usage](../../operator/usage.md) owns current behavior;
the [plan](../../plan.md#p28-operator-usability-and-release-readiness) owns status.

## Observed problem

The developer accepts the fresh Linux run but finds individual `allow CODE`
prompts too frequent. The supplied run has seven distinct proposals (four writes,
three shell calls) and five printed confirmation-mismatch messages. These counts
are not a controlled per-task benchmark. Current interactive sessions ask per
effect; `--yes` explicitly permits broad session execution. Headless effects are
otherwise denied. Existing fresh confirmation binding prevents stale input from
approving a different proposal.

## Primary-source comparison

These official pages were opened and read on 2026-10-24. This is documentation
research, not a hands-on test or security audit of those applications.

| Agent | Documented pattern | Source |
| --- | --- | --- |
| Codex | Routine work proceeds inside the workspace-write boundary; approvals govern escalation. Once/session scopes and optional automatic review reduce interruptions while the sandbox remains separate. | [Sandbox and approvals](https://learn.chatgpt.com/docs/sandboxing) |
| Claude Code | File-edit consent can last for the session; command approvals can become repository rules. Modes include accepting edits, planning, automatic review and broad bypass. Prompts show reusable scope. | [Permissions](https://code.claude.com/docs/en/permissions), [permission modes](https://code.claude.com/docs/en/permission-modes) |
| OpenCode V1 | Offers once, matching-pattern consent for the session, or reject. | [V1 permissions](https://opencode.ai/docs/permissions/) |
| OpenCode V2 | Allow/ask/deny rules; always saves project-scoped approvals and cannot override configured deny. Shell directory inference is best effort. | [V2 permissions](https://opencode.ai/v2/docs/permissions) |
| Gemini CLI | Tool/argument rules combine with default, auto-edit, plan and broad-auto modes. Reusable approvals are mode-aware; headless ask becomes denial. Its docs mark workspace policy files disabled. | [Policy engine](https://geminicli.com/docs/reference/policy-engine/) |

The common pattern is operating modes plus reusable, inspectable permissions.
OpenCode's differing always semantics demonstrate why duration must be stated.
Approval policy and actual OS isolation are distinct controls.

## Recommendation for Ipse

This is an Ipse design inference from that comparison, not existing behavior:

1. Offer **review each action**, **accept workspace file edits**, and the existing
   explicit broad session allowance. Display the selected mode and authority.
2. Command prompts offer **allow once**, **allow this exact command for this
   session**, and **deny**, displaying command, cwd and expiry. Session grants are
   inspectable and revocable. An explicitly saved operator rule can follow later.
3. Begin command reuse with complete-command matching. Prefix/glob approval needs
   validated handling of compound commands, substitutions, wrappers and redirects;
   a raw string-prefix check is insufficient.
4. Preserve full proposed arguments and fresh input binding. Improve selection
   interaction after proving stale/buffered input cannot approve a new proposal.
   Merely shortening the confirmation code does not remove repeated consent.
5. Keep explicit denials, private targets, external services and child/extension
   scopes authoritative. Repository instructions cannot grant themselves access.

Codex-style workspace autonomy is applicable only where Ipse enforces the stated
boundary. With native confinement off, shell runs with the user's OS authority;
a cwd does not confine it. Automatic classifier review can be evaluated later;
it is not a prerequisite or an implicit new provider/cost dependency.

## Implementation and verification boundary

Review the exact choices, eligible effects and matching inputs before changing
Session's approval API. Grants belong to Session and are not silently restored
from journals or inherited by children. Canonical path validation, intent before
effect, unknown outcomes, cancellation and inert resume remain mandatory.

Test repeated native edits, exact-command reuse, changed arguments/cwd, outside
and symlink targets, hard denials, revocation, child isolation, SDK effects where
supported, stale input and headless behavior. Compare prompt counts on a fixed
multi-action task. Run whole-manual review and the full source/native, installed
and hosted gates for the implemented change.

The accepted P28 brief excludes approval-semantics changes. This is the requested
follow-up discovered during acceptance. No new policy or dependency is introduced
by this research. The current public behavior remains the linked manual's.
