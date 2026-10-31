replace_section = fn text, start, finish, body ->
  [before, rest] = String.split(text, start, parts: 2)
  [_old, after_text] = String.split(rest, finish, parts: 2)
  before <> body <> "\n" <> finish <> after_text
end
path = "docs/operator/knowledge-permissions.md"
text = File.read!(path)
text = String.replace(text, "tool becomes available in the **next new session**.", """
tool becomes available in the **next new session**.

Protected note publication is temporarily unavailable. The native clock check
cannot prevent scheduling from delaying rename past Consent expiry. `/remember`
and protected capture refuse; `--yes` cannot bypass the gate. New pin, automatic
and duration retention choices also refuse. Existing-note reads, permission
inspection/revocation, forgetting and elapsed-policy reclamation remain separate.
A ready saved grant does not mean that publication is available.
""")
text = replace_section.(text, "## Save your own reviewed statement", "## Correct or supersede a native note", """
## Save your own reviewed statement

`/remember CATEGORY TEXT` currently refuses before statement review because
protected publication has no enforceable final deadline fence. Do not expect a
saved note or retry with `--yes`. Protected capture selected by a model also
refuses before collection publication. Ordinary chat remains available.

Older confirmed statements and uncertain capture attempts remain in their private
journals. Preserve them and inspect actual storage before another attempt. This
gate does not roll back previous effects or replay interrupted commands. The
separate [Memory](memory.md) workflow keeps its own authority and limits.

Existing literal reads still require their signed record and original Session
source. Keep the original sessions directory and retained lock files. A copy
cannot substitute for an unavailable original. Historical endorsement establishes
recorded input, not independent truth or new publication permission.
""")
text = replace_section.(text, "## Change a selected native note's retention", "## Reclaim an expired native note", """
## Change a selected native note's retention

`pin`, `automatic` and `duration` currently refuse before review with the temporary
deadline-gate diagnostic. They do not renew a stored policy. Existing signed
choices remain readable; an older dependency cannot borrow a different revision's
deadline. Keep management journals and inspect an uncertain earlier choice with
`knowledge operation JOURNAL_ID` rather than repeating it.

The session-only choice remains available through the forgetting/suppression path:

```sh
ipse knowledge retention note.COPY_THE_64_CHARACTER_LINEAGE --policy session --cwd /path/to/project
```

Replace the complete placeholder with the actual key. Review the full target and
enter its fresh `forget CODE`; anything else cancels. This removes the stored
derivative while preserving original journals and shared evidence. It does not
insert a temporary note into a running conversation. Normal execution ceilings,
native review and explicit effect denial still apply. `--yes`, `--json`, provider
overrides and piped confirmations cannot bypass them.
""")
text = String.replace(text, "After saving notes, close the source conversation", "For notes already stored, close the source conversation")
text = String.replace(text, "The saved permission covers both chat and headless `run`. Covered collection\neffects do not ask for repeat approval, while workspace writes, shell commands,", "The saved permission records scope for chat and headless `run`; it cannot bypass\nthe publication gate. Workspace writes, shell commands,")
text = String.replace(text, "Use the retention command below to change an existing literal's\neffective policy.", "The session-only retention choice below uses this same suppression path.")
File.write!(path, text)

path = "docs/operator/usage.md"
text = File.read!(path) |> String.replace("covers only its declared collection effects and can also apply to `run`.", "records only its declared collection scope for `run`. Protected collection\npublication currently refuses because its native deadline fence is unavailable;\n`--yes` cannot restore it. Existing read/inspection routes remain separate.")
File.write!(path, text)

path = "docs/operator/corpus.md"
text = File.read!(path)
text = replace_section.(text, "## Query a document Collection", "## Read a complete retrieval result", """
## Query a document Collection

The experimental `collection-documents` preset can read existing admitted project
Collections. New deadline-bearing publication is temporarily unavailable: the
native clock check cannot fence scheduling before rename. Existing selected
sources and indexes are preserved. Reads still require current bindings, complete
values and matching index/source generations.

Do not start the previous multi-stage document/import/index workflow expecting a
successful publication. Stage expiry is a strict deadline even without inherited
managed input; fused multipart, prepare/seal and other deadline-bearing calls
refuse. A small ordinary `value.put_inline` without a stage or trusted deadline
can remain available under its normal full-argument approval, but it does not
make a complete large-source or index workflow usable. Managed-derived arguments
have additional refusal gates. No fallback to State, MCP or another namespace is
selected automatically.

For an already configured Collection with an existing selected index, use its
ordinary `query` command and inspect citations, `status`, `coverage.complete`,
`namespace_complete` and gaps. A stale index cannot answer a namespace query;
if rebuilding requires a gated write, retain the original data and wait for an
enforceable publication design. Do not replay a pending stage, delete protected
files or weaken approval/expiry checks. Follow
[protected recovery](recovery.md#inspect-unconfirmed-protected-knowledge).

State-backed and explicitly selected remote stores have separate authority and
limits described elsewhere in this chapter. Their existence is not a permission
to move protected Collection data or bypass its gate.
""")
text = String.replace(text, "A stage whose write approval waits beyond that\ndeadline refuses, including a final root write; it does not renew the draft.", "A stage whose write approval waits beyond that\ndeadline refuses at its time checks; those checks do not provide a kernel-atomic\nclock-and-rename guarantee. Collection-backed strict-deadline stages are gated\nas described below. A check does not renew the draft.")
File.write!(path, text)

path = "docs/operator/recovery.md"
text = File.read!(path) |> String.replace("## Inspect unconfirmed protected knowledge\n", """
## Inspect unconfirmed protected knowledge

Protected capture, `/remember`, deadline-bearing document Collection writes and
new pin/automatic/duration retention choices currently refuse because the native
clock check cannot prevent a delayed rename after expiry. This is a temporary
safety gate, not a provider or storage-location error. `--yes`, renewing Consent,
changing the timeout or moving to tmpfs cannot bypass it. Existing read/inspection,
forgetting and elapsed-policy reclamation remain separate operations.

A new explicit gate refusal starts no protected publication. Earlier uncertain
attempts, including attempts made before this gate, still need inspection below.
The gate does not prove that an old operation left storage unchanged.
""")
File.write!(path, text)

path = "docs/developer/collection-sdk.md"
text = File.read!(path)
text = String.replace(text, "## Follow one capture across its owners\n", """
## Follow one capture across its owners

Protected publication is currently gated. `publication_deadline_admission/1`,
`with_publication_deadline/2` and `execute_profile_before/6` refuse without running
their publication callback. Session also refuses the protected action before its
intent; `/remember` refuses before statement review. Ordinary no-deadline internal
Collection operations remain separate and grant no semantic authority.

The flow below explains the retained contracts and historical records. It is not
a runnable protected capture recipe while the gate is active. Component tests
using direct Core normalization do not establish an operator publication route.
""")
old = """
The trusted normalization receipt also supplies the earlier old/new finite
deadline to the native root switch. That switch checks the actual wall clock
after staged-file sync and identity checks, immediately before rename. A deadline
crossing during IO therefore cannot publish an extended policy. An elapsed switch
does not remove earlier staged immutable objects; the operation remains unknown
for inspection, with no automatic retry or permit reuse.
"""
new = """
The normalization receipt retains the earlier old/new finite deadline. A native
wall check followed by rename is insufficient: the process can stop between them
and rename after expiry. `managed_mutation` therefore refuses deadline-bearing
retention/supersession before mutation staging, and the final pointer switch has
a backstop refusal for any inherited deadline. The CLI refuses new pin, ordinary
and duration choices before review; session-only suppression and elapsed-policy
reclamation have separate paths. Earlier staged objects and uncertain operations
remain inspectable and must not be retried automatically.
"""
unless String.contains?(text, old), do: raise "retention deadline paragraph changed"
text = String.replace(text, old, new)
text = String.replace(text, "For `knowledge retention NOTE_KEY`, the CLI translates", "In the retained retention contract, the CLI translates")
File.write!(path, text)

path = "docs/developer/knowledge-extensions.md"
text = File.read!(path) |> String.replace("## Follow protected capture from a Session source\n", """
## Follow protected capture from a Session source

The protected capture route is temporarily refused by the host deadline gate.
The retained schemas, source receipts and normalizers below describe stored data
and component contracts; they do not establish a currently executable capture
journey. New pin/automatic/duration retention and deadline-bearing Collection
document stages also refuse. Existing reads, ordinary unprotected operations,
forgetting and elapsed-policy reclamation retain their separate authority.
""")
text = String.replace(text, "Native State checks it\nunder its lock and immediately before rename, so approval delays cannot publish\nexpired work.", "Native State checks it\nunder its lock and before rename. This is not a kernel-atomic clock-and-rename\nguarantee. Strict-deadline Collection publication is refused rather than treating\nthat precheck as an enforceable fence.")
File.write!(path, text)

path = "docs/developer/session-sources.md"
text = File.read!(path)
text = replace_section.(text, "`/remember` uses the Session Input service", "## Bind a new terminal choice to revalidated facts", """
`/remember` currently refuses before statement review because protected note
publication lacks an enforceable final deadline fence. Existing
`operator_assertion` records still carry their original endorsed text/category and
project/artifact/policy scope. SourceIndex exposes category-specific
`input.assertion.ordinary`, `input.assertion.preference` and
`input.assertion.current` kinds when those historical records validate. Plain
input and question answers cannot acquire that origin by repeating their text.
These receipts prove recorded endorsement, not external truth or current effect
permission. Reading one never bypasses the publication gate.
""")
File.write!(path, text)
