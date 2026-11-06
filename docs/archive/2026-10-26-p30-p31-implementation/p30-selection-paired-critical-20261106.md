# Paired critical selection observations — 2026-11-06

Historical development evidence. The [plan](../../plan.md) owns P30 status;
the [decision-engine training](../../developer/decisions.md) describes the
current measurement contract.

The earlier selection report compared only aggregate critical recall. If the
baseline recalled critical case A and missed B, while the candidate missed A and
recalled B, both totals were one and the aggregate comparison passed. The
separate paired-critical hard gate remained unverified; that aggregate result did
not qualify a strategy, but it failed to expose the observed loss of A.

The selection scorer now applies the existing paired comparison to frozen case
membership and reference sets and reports known loss IDs. A critical set is
recalled only when all its members are present. Missing, refused and other failed
rows remain unverified, as does an empty critical population. A calculated pass
does not validate labels, reviewer independence, workload matching or the
paired-critical hard gate; the experiment disposition remains unverified.

A one-scheduler pure run passed 28 tests with exit 0 and no warnings: the new
version-one and version-two score controls, existing selection-experiment tests
and existing decision-metrics tests. It covers offsetting gains and losses,
missing, unknown and refused rows, a passing matched set, no critical members,
and multi-member sets. No native Input, TCP, model call or real labels were used.
The retained log at `/tmp/ipse-p30-selection-pairs-20261106/pure-05.log` has
SHA-256 `fd3a69b29025fd954d5bd0d63effc7e1e96d0a5d2b49534b585c5956b3ffb2f8`.
The tested scorer and new test SHA-256 values were respectively
`ba3e3730d6c2a516579fd5346e2982874dcaa608b89aad87a9094d265d07d811` and
`2ad1b413f599ea9b2db43db5b0c4b12a820c39c438fc6042c666598aa2982877`.

An earlier extended run failed one test because its fixture called nonexistent
`Ipse.JSON.decode!/1`. That failed log remains at
`/tmp/ipse-p30-selection-pairs-20261106/pure-02.log`, SHA-256
`75e1ede577450f4e26dd80f54432d21d7e124d52ceddc90b0859d2c8941df2f1`.
The fixture was corrected to use Jason. This scoped source check does not
establish accepted matched-input scoring, independent review, model quality,
installed behavior or P30E completion.

An independent static reviewer found no semantic or scope blocker in the
version-one and version-two report paths or the focused controls. This review
does not validate the labels or make the membership observation a hard gate.
