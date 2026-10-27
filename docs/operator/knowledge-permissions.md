# Enable and revoke native knowledge permission

Use the standalone knowledge commands to select the bundled native notes tool
for a project. Setup imports the shipped artifact and saves a protected permission;
it does not start a model or change your provider configuration. The selected
tool becomes available in the **next new session**.

First install or build Ipse and [save your provider choice](configuration.md#choose-and-save-a-provider).
Use a private Ipse home and an existing workspace. These commands use that saved
provider; provider/model overrides and `--yes` are refused during knowledge setup.
They require no separate embedding account or download.

Protected writes also require the current native
[allocation profile](../../native/README.md#publish-protected-state-through-its-lock-owner):
64-bit Linux kernel `7.2.10` or `7.2.10-*`, with supported Btrfs or explicitly
qualified tmpfs mount settings. Other kernels/filesystems and macOS currently
refuse write admission. Installation alone does not establish this prerequisite.

## Review the project and exact permission

Run from a terminal with matching native input and display:

```sh
ipse knowledge enable --cwd /path/to/project
```

For a new identity, choose the displayed `repository CODE` or `folder CODE`.
Repository scope shares with reciprocally verified Git worktrees. Folder scope
covers only that canonical folder. A linked worktree needs its primary repository
admitted first; once the repository has an active project grant, a new session
can verify and join a reciprocal worktree. A copied repository or forged `.git`
pointer does not establish membership.

Read the full review, then enter its fresh `enable CODE`. The review identifies
the artifact, project, selected main route, source categories, retention, expiry
and finite daily allowances. Bare `yes`, an old code, piped text and command-line
approval flags cannot save the grant. Anything else cancels the review. Import
and project admission can already have occurred, but cancellation saves no new
permission.

The native preset permits literal, source-bound notes and attributed pending
proposals. Ordinary notes have a 90-day host retention ceiling; pending proposals
have seven days and never become current merely because they quote a source.
Current facts and preferences can persist. The full review is authoritative for
the selected rules. It authorizes no secondary model calls or downloads. Main
conversation requests retain their ordinary route and resource accounting.
The reviewed native selection bounds each Main request to the smaller of your
configured timeout and 90 seconds. Requests on its registered route buffer
assistant text until the response passes completion checks, so text can appear
after upstream generation finishes. Review the displayed route and effective
timeout before enabling; setup does not enlarge a shorter configured timeout.

The saved permission covers both chat and headless `run`. Covered collection
effects do not ask for repeat approval, while workspace writes, shell commands,
MCP and delegation keep their separate approval requirements. The grant expires
after one year and has daily limits of 100 operations, 2 MiB of input and 4 MiB of
output. A refusal or uncertain attempt may consume conservative allowance.

After successful setup, start a new conversation:

```sh
ipse knowledge status --cwd /path/to/project
ipse chat --cwd /path/to/project
```

In chat, `/ext` lists the admitted tool/command schemas. The native capture tool
requires an exact quotation from an admitted Session source. Generated prose and
unattended input remain pending. The presence of the tool does not guarantee
automatic capture or current-note recall; those workflows and proposal management
are separate from permission setup. For the existing explicit note-management
workflow, follow [Memory](memory.md).

## Inspect readiness or the saved review

```sh
ipse knowledge status --cwd /path/to/project --json
ipse knowledge permissions --cwd /path/to/project
```

Status checks whether the saved selection is ready under the current installed
artifact, route and timeout. Its JSON reports `activation_ready_now`, whether this
worktree is admitted, the policy digest, epoch, expiry and headless selection.
It does not join a worktree, create a project or reclaim staged files. An
unadmitted folder can still join during new-session admission when a repository
grant permits it. Readiness is an observation; every later effect checks current
permission again.

`permissions` prints the complete saved policy without attempting activation.
Its `activation_ready_now` is null. Use it when status refuses after a changed
route or unavailable artifact. Neither command starts a worker or inference.
Keep saved output private because it describes your project and selected routes.

Changing provider configuration does not silently replace the route in an old
permission. Review `knowledge enable` again under the intended saved configuration,
then start a new session. An existing conversation retains its pinned catalog;
it cannot adopt the replacement selection in place.

## Revoke future effects

```sh
ipse knowledge disable --cwd /path/to/project
ipse knowledge status --cwd /path/to/project
```

Enter the fresh `disable CODE` after reviewing the project and epoch. Revocation
preserves stored records, operation receipts and unresolved liabilities. It stops
later knowledge effects; already admitted work may have started. New sessions
use the ordinary catalog. Existing sessions retain their saved artifact identity
and must pass the live permission check before another effect.

If setup reports a consent conflict, inspect permissions and perform a fresh
review. A concurrent permission change is never overwritten by the older review.
Changing the saved configuration during review also refuses the save, even when
the edited file would select equivalent settings. Inspect it and begin a fresh
review so the displayed selection matches the configuration being admitted.
If an outcome is unconfirmed, follow [protected knowledge recovery](recovery.md#inspect-unconfirmed-protected-knowledge) before retrying; a
missing confirmation is not proof that nothing changed. Unsafe private-directory
permissions, a missing retained `.lock` or `.writer.lock`, or malformed protected
data refuse rather than being repaired by status. Preserve the original state
for diagnosis.
