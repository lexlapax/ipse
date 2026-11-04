# Populated storage-only comparison — 2026-11-04

One authorized fresh comparison completed successfully using the immutable
c8245f87 complete SDK and a private copy of **only** the retained Collection
namespace. The copy preserved its 2,197 entries and 7,523,976 regular-file bytes,
including immutable object/manifest history. All copied payloads matched the
originals; copied regular files had new inodes and link count one. No original
native lock, original journal, Identity/Consent secret, Session, provider or
native input was used. Only the storage algorithms were exercised.

The Ipse application was loaded for exact App/module/helper closure but was not
started. The script started its private Registry, Resources scope and telemetry
dependency. Native Collection owners operated exclusively on the fresh copy.
It used unchanged public Collection APIs, not the unpromoted paired function.

For each selected real note key, the script reproduced the five-operation
13-unit pattern: note/format/override get; live-page neighbors/get; anchor-page
neighbors/get. It compared a single ReadView with successive two-literal held
notes callbacks. Both complete outputs were exactly equal at 8 and 32 literals.
It did not authenticate signed eligibility or establish current-use authority.

| Literals | ReadView elapsed | Held pairs elapsed | Quota inventories, view / pairs | Full index loads, view / pairs |
| --- | --- | --- | --- | --- |
| 8 | 1.134198 s | 0.631510 s | 41 / 4 | 1 / 4 |
| 32 | 4.137636 s | 2.498113 s | 161 / 16 | 1 / 16 |

At 32 literals, measured quota-call elapsed time fell from 1.192354 s to
0.093757 s. ReadView borrowing accounted for 0.382183 s and installation
0.040531 s. The paired route performed no ReadView installation/borrow, but
immutable native file reads increased from 170 to 800 and full index loads
from one to sixteen. Their measured native-read call elapsed time increased
from 0.031410 s to 0.159737 s. Full index loading was counted, not separately
timed; remaining elapsed time must not be assigned conclusively to decoding.

The paired route was about 40% faster in the 32-literal comparison, rather than
the roughly tenfold reduction in quota calls. Repeated complete index loading
offsets a substantial portion of that structural saving. This supports the
bounded paired optimization but does not establish adequate sustained turn
cost for 14,600 turns. One complete populated read/day remains necessary to
measure actual Session, source reconstruction, accounting, worker and model
costs. No deadline, cache size, read budget or storage quota was increased.

These are single instrumented component measurements on one fresh copy, in
view-then-pairs order with S1/A1. Arity-only calls plus transient return timing
were collected by an isolated OTP trace session; no raw returned values were
persisted or printed. Return tracing adds message delivery/copying overhead,
especially to the paired route's more numerous immutable file reads. These
elapsed times therefore describe this instrumented component, not an untraced
runtime estimate. No p95, cold-cache distribution, reference-hardware,
annual-workload, retrieval quality or installed-user claim follows from them.

## Preservation and provenance

- Original Collection full pathset, hashes, inode/device, mode, uid/gid, size,
  mtime and ctime matched before and after. Original locks were never acquired.
- Private Collection payload pathset/bytes/modes matched its exact pre-read copy.
- The complete frozen SDK byte manifest, runtime/dependency pathset and symlink
  targets remained exact before and after. Input script pins also passed.
- All actual private native owners closed successfully; Resources finish
  returned `:ok` and its process stopped. No other effects or Input were started.
- Result: `execution-02/result.json`, SHA256
  `d40df8ff105e1e0acdf3b350a828f4ac5388712331a652c186a8d7555242ebac`.
- SDK manifest SHA256:
  `598fc7ce9b24eebbf06d7d10445afdbe0b04394adf07c73af528c31faf32693d`.
- Benchmark source SHA256:
  `3c85f87a619821c23cae63350fe29bcf43f944f6b4e7e25f153543a454a7cd39`.
- Launcher SHA256:
  `2b54e9153d9c8c93a44ca594762dd8b5a8e48968edeef6cc926a9de3cd635d62`.

The original setup attempt remains failed. Its local pathset constructor omitted
dependency-source leaves: 790 observed paths versus the correct 1,507, with
717 missing dependency leaves and zero added paths. All actual SDK bytes and
App/module paths passed independent inspection. This first attempt stopped
before original inventory/copy/quota or any native call. The fresh corrected
attempt added the dependency leaves and retained the full exact guard; it did
not loosen a guard, reuse a failed fixture or replay an unknown consumer.

All raw outputs and original/private inventories remain private outside Git.
