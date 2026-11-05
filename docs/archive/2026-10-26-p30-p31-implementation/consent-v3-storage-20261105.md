# Lossless Consent storage representation v3

2026-11-05, US/Pacific. Historical engineering checkpoint. Current contracts
belong to the [Collection SDK](../../developer/collection-sdk.md#keep-approval-and-replay-facts-distinct),
[storage training](../../developer/knowledge-storage.md#budget-native-effects-before-an-endurance-run)
and [permission procedure](../../operator/knowledge-permissions.md#review-the-project-and-exact-permission).
The [plan](../../plan.md) owns remaining notes and endurance acceptance.

## Capacity failure and representation change

The provisional source calendar has 2,100 seed operations plus 28,952 scheduled
effects, including its additional 10,000 mixed changes: 31,052 retained IDs.
That count fits 32,768, but the old serialized representation does not. After
retaining 64 recent full receipts, its 30,988 compacted seven-tuples alone need
at least 6,713,291 bytes with 13-digit calendar times and even single-digit
resource counters. This exceeds the unchanged 6,225,920-byte reserved-write
budget before policy, recent operations and maintenance reserve.

The v3 disk row packs the request and receipt digests' exact 64 bytes into one
canonical 86-character unpadded URL-base64 value, with a strict terminal-status
enum. Logical/public rows retain their original hexadecimal hashes, status
strings and six-resource vectors. IDs, all unresolved liabilities and the
latest 64 full receipt bodies remain. Counts, read/write/allocation limits,
reservation budgets and permission checks do not change.

V1/v2 files remain readable without rewrite. Only a successful already-authorized
protected mutation writes v3; a rejected CAS leaves the original bytes intact.
The native migration case verifies the unchanged compacted facts, operation map
and sequence after ordinary revocation. An older host cannot read v3, so keep
the matching newer installation after that mutation. No original retained
cohort was read, migrated, granted or replayed in this checkpoint.

## Specified geometry and focused verification

The [pure geometry receipt](consent-v3-storage-20261105/geometry.json) uses the
actual six-resource order and native notes vector shape. Every input counter
is conservatively 131,072; output is 16,384 and model/download/cost are zero.
Future measured input counters are not claimed. It retains all 31,052 IDs,
including 64 full receipts of exactly 8,192 bytes each:

| Quantity | Bytes |
| --- | ---: |
| V2 compacted object with that vector | 6,992,183 |
| V3 compacted object | 5,349,819 |
| Complete V3 state | 5,926,170 |
| Existing reserved-maintenance formula | 5,958,949 |
| Unchanged write cap | 6,225,920 |
| Reserved headroom | 266,971 |

A legal worst-size vector case still refuses capacity without pruning. Pure
controls reject malformed/noncanonical packed digests, padding and low-bit
aliases, float/unknown tags, extra fields, foreign projects and duplicate JSON
keys; they check both terminal statuses and unchanged unknown operations.

The [focused native receipt](consent-v3-storage-20261105/focused-result.json)
records **22 passed in 183.3 seconds**: six storage, nine native compaction and
seven budget cases, run together with one scheduler, one async thread and one
ExUnit case at a time. The fresh protected fixture passed its 32-MiB fsync quota
probe. All three source pins stayed exact; no owned helper remained, and only
that disposable fixture was removed after success. Whole-owner compilation and
six earlier pure controls passed separately; they are not added to the 22.

The preserved private harness history includes a deprecated compiler-option
warning and two old-BEAM export-check failures before a corrected private ebin
produced zero diagnostics. Those were setup checks, not failed native effects.
The public packet contains only [source pins](consent-v3-storage-20261105/source-pins.json),
[source/test delta](consent-v3-storage-20261105/source-and-test.patch),
[manual delta](consent-v3-storage-20261105/manuals.patch) and sanitized numerical
receipts; no private journal, transcript, grant, endpoint or filesystem path is
copied. Their [manifest](consent-v3-storage-20261105/manifest.sha256) binds the files.

This establishes the specified representation's byte fit and focused accounting
compatibility. It does not ratify intake, repair an uncertain original operation,
qualify retained 2,000-note recall, execute a populated day, measure full-root
growth or authorize 30/90/365-day runs. Native allocation entries, signed metadata,
history, expiry/renewal, process-tree peaks, latency and semantic quality remain
separate gates.
