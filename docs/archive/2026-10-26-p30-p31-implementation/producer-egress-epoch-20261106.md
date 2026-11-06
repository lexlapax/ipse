# Producer egress and maintenance epochs, 2026-11-06

Historical implementation and verification record. The current procedures are in
[Corpus](../../operator/corpus.md#produce-shared-vector-pages) and the
[Collection SDK guide](../../developer/collection-sdk.md). This record covers a
bounded P31C1b increment, not complete document storage or producer qualification.

The shared-generation Job already retained its opening maintenance epoch. A
producer claim could nevertheless remain in a live invocation across a later
maintenance fence. This increment freezes the current idle epoch for staged and
inline claim writes, authenticates the actual stored Job against the maintenance
state under the retained native reader, and joins that epoch to the confirmed
live claim at each final inference admission. The producer checks its Job and
continuation against the same epoch before continuing work. No saved claim is
adopted and an unknown effect is not replayed.

The normal offline test build compiled 199 host files with warnings treated as
errors and built the four normal inert bundles. The focused evidence is:

- A synthetic model control passed for both producer versions with an old Job
  at a later idle epoch, before writes or model requests. The matching live-state
  unit and source-authentication controls passed.
- A disposable native held-reader control passed at epoch zero, during active
  maintenance and after the epoch advanced. The original claim was accepted only
  in the first state. A broader host compatibility run passed 14 outer tests
  with four excluded, including the isolated source-use suite and existing
  inline-claim controls.
- Synthetic public Session controls passed for both staged v3 and inline v4
  claims fenced while embedding approval was pending. A fresh Job begun after
  the fence produced a v4 page with guarded batches. The sessions used ordinary
  programmatic approvals and a local fixture endpoint.
- Existing epoch-zero v3 and v4 positive Session journeys also passed; the v3
  case completed four guarded fixture batches with the selected root unchanged.
- Two bounded model geometry controls passed against the inert bundle. The
  128-chunk fixture used 258 hydration reads. The segmented 256-chunk,
  256-fact fixture used 410 hydration reads and at most 460 reads in each of
  39 append invocations. This does not measure populated native capacity.
- A separate in-flight control passed with one fixture wire request already
  sent when maintenance ran. The selected root remained unchanged and the
  claim remained pending. The journal recorded two attempts: one had a
  completed/final Usage outcome and one a failed/partial outcome; only the
  first reached the fixture wire. This does not cancel an already admitted
  request, establish an external provider charge or settle an unknown outcome.
- Two existing synthetic Session owner-loss controls also passed: killing the
  owner during a guarded in-flight request closed the socket, preserved the
  selected root in the applicable case and did not replay on Saved/idle resume.
  Their freshly built test artifact also included separate, unqualified abort
  changes; these controls did not invoke the abort action.

The first combined Session run passed three of four cases; its in-flight test
incorrectly assumed one journal dispatch intent and failed its assertion. The
corrected single-case rerun passed. An earlier pure unit run also found a test
fixture construction error, and the first combined pure-control run had an
incorrect malformed-request expectation; their corrected reruns passed. A
Mix-based pure attempt was refused by the sandbox's local TCP lock restriction;
the direct source-loaded controls and the later authorized offline Mix run are
separate results.

The first direct documentation check scanned unrelated untracked fixture
copies and failed on their incomplete links and examples. It is not a clean
repository documentation result; the staged, isolated check is a separate gate.

The subsequent indexed current-manual check passed across 1,245 Markdown files
and 10,193 local links with zero errors, excluding unrelated untracked copies.
An independent source review found no concrete bypass in the bounded epoch and
live-claim admission change. Its review digest is
`a476a41992a546dd187fc820ce503470436daec1ef934286b252769bde14cfc8`.

These are synthetic, current-host controls; they do not qualify live account or
provider behavior, installed upgrades, populated capacity, source/input budget
at full scale, general maintenance or garbage collection, cross-Session claim
adoption, or complete P31C1b production. Keep the original source and an
unknown in-flight result separate from these fixtures.
