# Account for retained history and expiry before a native year

Dated **2026-11-02**, based on `d1863c7` plus the source inventory in the
[structured receipt](native-annual-calendar-20261102.json). This is a pure
action calendar for the next native driver, not a completed driver, actual
turnover or storage qualification. The [plan](../../plan.md) owns acceptance;
[storage training](../../developer/knowledge-storage.md#budget-native-effects-before-an-endurance-run)
owns commands and interpretation. The developer's
[10,000-total clarification](workload-change-count-20261102.md) remains unchanged.

## Preserve the workload and native lifecycle shapes

`NativeNotesWorkload.calendar/1` starts from the existing native initial plan's
2,000 captures and 100 pins, including its actual capture-day distribution. The
365 annual process dates follow the 21 seed dates. Every day declares 40 main
turns and the initial ordinary-intake floor; day 90 doubles ordinary additions,
corrections, forgets and temporal supersessions.

The additional 10,000 changes are spread evenly across all 365 days. The working
fixture cycles through temporal update, ordinary correction and ordinary forget:
3,334/3,333/3,333. This is an implementation choice for the working calendar,
**not a developer-specified ratio or ratified pilot mix**. Expected aliases do
not mint source handles, signed metadata or native review authority.

Ordinary correction retains the old deadline and creates a distinct replacement;
temporal replacement retains prior support for 365 days after the update. One
initial current slot is first updated on day 100. All 100 pins, 50 preferences
and 50 current slots remain. Forget/reclamation remove their exact public record
once while retaining admission anchors. The calendar never renews a deadline
through reading or by reusing a removed identity.

Cleanup waits until after the entire possible admission day plus 90 days and
uses only daily operation capacity left after required changes. A live caller
must still authenticate the actual deadline before native expiry. OTP `:gb_sets`
indexes eligible targets/deadlines without repeatedly scanning the complete
retained alias history. The CLI has the existing 16-million-word development
heap bound. No new dependency, native helper or runtime limit is introduced.

| Publication class | Working calendar count |
| --- | ---: |
| Initial captures and pin reviews | 2,100 |
| Ordinary additions | 7,320 |
| Ordinary corrections | 1,464 |
| Ordinary explicit forgets | 732 |
| Normal daily temporal supersessions | 1,464 |
| Additional mixed changes | 10,000 |
| Scheduled elapsed reclamations | 6,859 |
| Initial plus scheduled year | 29,939 |

All required days fit the existing 100-operation ceiling at intake 20, with
cleanup backlog explicitly reported. The day-90 burst at intake 40 instead
requires 127 publications: it reports 27 excess and keeps all required actions.
The input/output-byte vectors and unplanned journeys still need their own
accounting; an operation-count pass cannot establish their fit.

## Observe the record-count contradiction

Every admitted lineage retains an anchor row, including forgotten/reclaimed
identities. Every present literal/history also requires a live row and there is
one format record. Actual `ManagedPages.profile/1` requires at least 37 charged
bytes per anchor row and 170 per live row, within page capacities 4,544 and
4,542. Together with the 128-row syntax cap, no page can contain more than
**122 anchor rows or 26 live rows**. These optimistic maxima require no invented
tags or packing success.

For each action, the calendar tracks the lower bound:

```text
present public records + ceil(retained lineages / 122)
                       + ceil(present public records / 26) + 1
```

The working schedule has 18,915 retained lineages and reaches 8,012 public
records. Its minimum peak Collection count is **8,478**, at least **286 above**
the unchanged 8,192-record bound, before less-than-perfect packing or other
metadata. Hence this working calendar is ruled out under the current layout.
An operation-only preflight below 32,768 IDs had not established that it fit.

If every public value at that peak occupied the profile's 6,144-byte ceiling,
those public values alone would need **49,225,728 bytes**, exceeding the current
25,165,824-byte logical-record bound. This is a conditional ceiling-size scenario;
no actual maximum-payload source or signed native record was produced here.

The remedy needs an explicitly reviewed storage design and the final qualified
intake/mix. This record does not raise limits, discard anchors/history, change
the total-change requirement, or freeze the balanced ratio as developer policy.
It does not justify launching an annual native run already ruled out by its
working calendar.

## Checks and remaining work

The first pure run passed five of six tests; its intake-40 test incorrectly
expected 28 extra changes on day 90. The deterministic even distribution gives
27 that day. Only those expected totals changed. The original failed log remains.
The corrected combined selection passes **11 tests**, including existing seed
and lower-bound regressions, native alias uniqueness, single removal, persistent
slots, exact retention, first post-day-90 update and the unchanged quota excess.
Strict isolated compilation and source formatting pass; the plain-VM CLI reports
zero native operations/turns and false qualification. The receipt binds exact
source, summary and check bytes.

The whole storage training chapter and related operator statement, correction,
forgetting and expiry guidance were reviewed against the actual native shapes.
The contributor procedure integrates the calendar with the earlier operation
floor and historical receipt geometry. Manual/link validation checks 1,053
Markdown files and 8,710 local links with zero errors; retained private-ledger
permission warnings remain visible. Runtime build, full suite and native annual
execution were not run for this pure development increment.

The calendar does not yet execute its declared 14,600 main turns or effects.
Offline week, concurrent owners, imports, compaction, consent renewal, proposal
burst, maximum-payload production, resource peaks and independent quality remain
unplanned. Ordinary intake and category/change mix remain unratified. The
separate initial native population process remains on its frozen publisher;
this calculation changes none of its files or operations.
