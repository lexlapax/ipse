# Read admitted Session evidence

Use the source interface when a tool or extension needs exact, attributed bytes
already admitted in its own conversation. It provides bounded discovery, evidence
pages and host-computed quote offsets without placing every source in the prompt.
It does not authorize capture, note publication, service egress or any other effect.
Knowledge eligibility, consent, exclusions and managed retraction have separate
owners and must be checked by their eventual consumers.

Read [workspace context](workspace-context.md) first for frozen headers, native
tool groups and compaction. [Persistence](persistence.md) owns journal integrity,
locking and interrupted-effect recovery. This chapter owns source selection and
the read protocol.

## Follow the commit before the read

[`SourceIndex`](../../lib/ipse/session/source_index.ex) is the pure admission and
UTF-8 paging contract. It accepts specific host-validated receipts, never an
arbitrary text/origin map. [`SourceWindow`](../../lib/ipse/session/source_window.ex)
pairs those receipts chronologically. The existing Session-owned
[`Journal.Writer`](../../lib/ipse/journal/writer.ex) caches this projection and
advances it only after a successful durable append, including reserved appends.
A refused or failed append cannot create a source.

Session remains the conversation and permission owner. Only that owner can install
or query the writer cache. Native model reads additionally require the exact active
task PID, job reference, phase, selected source tool and original arguments. Public
`Session.sources/3` calls require the registered subscriber. An extension goes
through its current invocation, artifact capability, activation lease and ordinary
action chain. A valid cursor alone cannot cross any of these boundaries.

| Committed records | Available projection |
| --- | --- |
| `input_received` plus its matching committed effective user message | Immutable original bytes with verified terminal or unattended origin; orphan input remains unavailable |
| Native question checkpoint plus atomic `operator_answer` v2 | Assistant question and exact original answer payload, linked by host question/render/input hashes; parsed answer text alone supplies no origin |
| Admitted visible original assistant answer | Assistant proposal; presentation and hidden reasoning are excluded |
| Typed native tool intent/outcome plus the actual matching tool message | Separate host outcome facts and attributed `read`, `shell` or MCP text; `write`/`edit` publish outcome facts only |
| Successful MCP/embedding action plus its bound private source | Attributed MCP text or typed vector metadata; source-only/interrupted prefixes grant no read |
| Successful decision action, response and completed final metering | Separate operation facts and advisory content; durable response before settlement/result grants no read |

Legacy roles and unverified older answers are coverage gaps, not newly attested
operator input. Other event prose, presentations, arbitrary journal paths and
hidden reasoning never become sources. Tool stdout is an attributed reference;
the typed outcome attests only the host-observed status, approval and timing.
Neither establishes the truth of output prose. A terminal event also does not
establish that a human supplied the bytes: automated PTYs exercise the same channel.

## Read through a real synthetic Session

Run this fixture in `iex -S mix` from a built checkout. The provider override is a
development fixture, not a configurable service or fallback. It uses no account:

```elixir
defmodule SourceExample do
  def complete(_, _, _, _),
    do: {:ok, %{"role" => "assistant", "content" => "Synthetic visible answer."}, %{}}
end

root = Path.join(System.tmp_dir!(), "ipse-source-example-" <> Ipse.Usage.id())
File.mkdir_p!(root)
{:ok, session} = Ipse.Session.start_link(
  config: %{provider: :demo, model: "synthetic", provider_module: SourceExample,
            home: Path.join(root, "home"), approval: :deny},
  cwd: root, state_dir: Path.join(root, "state"), subscriber: self())
:ok = Ipse.Session.prompt(session, "Record café 雪 exactly.")
receive do
  {:ipse, ^session, {:done, :ok}} -> :ok
after
  5000 -> raise "synthetic Session did not complete"
end
{:ok, page} = Ipse.Session.sources(session, "source.list", %{"limit" => 32})
[original | _] = page["sources"]
{:ok, evidence} = Ipse.Session.sources(session, "source.read",
  %{"handle" => original["read_handle"]})
"Record café 雪 exactly." = evidence["text"]
{:ok, quote} = Ipse.Session.sources(session, "source.quote",
  %{"handle" => evidence["handle"], "quote" => "café"})
7 = quote["start_byte"]
12 = quote["end_byte"]
:ok = Ipse.Session.close_confirmed(session)
File.rm_rf!(root)
```

The original input is unattended because this fixture did not observe a native
terminal. A subscriber cannot choose a stronger origin. Repeat the read from a
different process and require refusal, even with the actual handle.

Fresh sessions pin `source_layout: "session_sources_v1"` and declare `source_list`,
`source_read` and `source_quote` from their first model request, including an empty
index. Existing sessions without this marker retain their admitted catalog. The
three tools use the same argument objects shown above, without the operation name.
Normal native tool intent/results, turn call limits, model steps and context bytes
apply. Source reads do not imply another model or embedding call.

## Grant an extension source access explicitly

Declare and trust both `host.actions` and `host.sources`. This grants current-Session
source access, including private admitted input; an effect-result or history grant
alone does not. It gives no parent/child transcript access and adds no child grant.
[`SourceRead`](../../lib/ipse/extension/source_read.ex) validates the closed requests.
An independent worker returns this ordinary continuation:

```json
{"api_version":1,"kind":"host_call","request":{"op":"source.list","limit":32}}
```

On an `ok` result, retain the actual returned `read_handle` and submit
`{"op":"source.read","handle":HANDLE}`. Continue with its actual `next` handle.
For a quote, submit `{"op":"source.quote","handle":HANDLE,"quote":"exact bytes"}`.
`HANDLE` is a string copied from that response, not a path or constructed ID.
No request accepts origin, session ID, byte offset, provider or journal location.
An unavailable/stale read returns `source_refused`; list again for the current
window rather than replaying old effects to recreate evidence.

Session syncs the action intent before preparing the read and compares the exact
prepared outcome before committing its result. Reads use at most 512 action steps
within the invocation's two-minute read deadline. They do not enlarge other call
families. Explicit `host.actions.mixed` permits 512 reads plus sixteen other calls
under their individual grants. Cancellation closes the worker; resume reconstructs
the receipt and never starts its old continuation automatically.

## Interpret bounds and incomplete coverage

List requests accept `limit` 1..32 and an optional opaque `cursor`. A page may
contain fewer rows to stay within **4096 rendered JSON bytes**. Evidence pages fit
**8192 rendered JSON bytes**, including escaping, metadata, coverage and tokens;
UTF-8 codepoints are never split. Follow the actual `next` until `complete: true`.
The complete SDK object remains bounded independently. Each row carries occurrence,
version and chunk IDs, kind, origin, coverage, reason and read handle.

`available` means the selected immutable view is readable. `partial` identifies an
attributed tool/external-text view with limited host meaning. `unavailable` supplies
no invented bytes. Visible answers retain the existing Lifecycle 8-KiB admission
bound: a larger answer has unavailable original text and a recorded size/hash,
even if other journal records still contain its provider response. Original input
retains its separate 1-MiB bound. A large Journal source wrapper does not truncate
or prevent reading that admitted original input.

The index retains at most **1024 occurrences**, **8 MiB** of text and **1 MiB** per
source. It refuses capacity without eviction. Pending receipt pairs separately
allow **128 entries/4 MiB**; the full journal is not cached. Coverage counters expose
indexed/observed projections, unavailable/legacy views, refused capacity and
pending-pair gaps. `complete` finishes pagination of the indexed window; it never
claims that missing journal views became available. New source/coverage changes
fence old tokens. A compact status summary uses the existing 16-KiB rendered
reference allowance after selected extension contributions reserve their bytes;
it is omitted whole when it does not fit. Readers still work with zero inline
source allocation. Ordinary context reduction retains the original source index.

Exact quotes must match globally and uniquely in the immutable UTF-8 source and
lie wholly within the referenced evidence page. Repeated or normalized text,
overlapping matches, stale versions, redactions and unavailable bytes refuse.
The host computes absolute byte offsets and quote/content hashes. This proves
source support, not entailment, current eligibility or truth.

## Reconstruct without giving old tokens authority

`Saved.restore/2` validates the complete owning prefix before building SourceWindow.
Actual source references validate before permitted torn-tail repair. Startup may
resolve bounded source pages; source list/read/quote operations themselves never
repair a journal or run an effect. Idle resume preserves journal bytes. The new
window and source-driven lifecycle epoch are admitted only when actual work starts.

Each live window uses a volatile secret and authenticated tokens bound to Session,
window, source generation, policy generation, kind, version and offset. Resume
creates a fresh window/secret, so previous tokens refuse while immutable occurrence
and version IDs remain stable. A durable `source_window_opened` record binds the
historical window before token-producing model/SDK work.

Saved read results are recomputed at their chronological source boundary. Replay
checks closed canonical historical token claims and the admitted historical window,
then compares exact source/result bytes after replacing only obsolete window/MAC
framing. This replay-only structural operation cannot authorize a live read.
Future occurrences/generations and mixed historical windows refuse. This is
consistency checking of a protected journal, not a cryptographically signed
transcript resistant to coherent rewriting by arbitrary same-user code.

## Verify a changed source boundary

```sh
mix test test/ipse/session/source_index_test.exs test/ipse/session/source_window_test.exs
mix test test/ipse/extension/source_read_test.exs test/ipse/extension/source_read_session_test.exs
mix test test/ipse/journal/source_window_test.exs
mix test test/ipse/cli/operator_input_test.exs test/ipse/session/question_eof_test.exs
```

The native CLI tests use serial synthetic PTYs and actual restoration receipts;
they establish no human attribution or untested-platform guarantee. Session/SDK
fixtures cover 64 typed receipts without inline source text, cancellation, exact
Unicode/repeated quotes, capacity, append refusal, caller leases and inert resume.
For an admission change, remove a successful publication record while retaining
its private source and require no readable content. For a reader change, alter
returned source bytes and superficial hashes; replay must still reject the page.
Run the existing reference wire/history/lifecycle suites alongside the source
owner's regressions. [Testing](testing.md) owns the complete handoff baseline.
