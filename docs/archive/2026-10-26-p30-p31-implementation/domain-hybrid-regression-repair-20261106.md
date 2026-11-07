# Hybrid query fixture repair during full regression — 2026-11-06

The in-progress full default suite on commit
`0cdc36faeee16bb5134e9933baaa996bd954e3d8` reported one outer failure in
`Ipse.KnowledgeDomainRegressionsTest`: its isolated child reported 8 of 9 tests
passing. The synthetic hybrid fixture expected an immediate result, but the
Corpus now issues a State namespace-generation probe before returning it. The
original full-suite log remains at
`_build/verification/p31-final-regression-0cdc36fa-20261106-01/run-01/raw-private.log`;
it was still being written when this note was prepared. A retained extract of
its failure, `_build/verification/domain-hybrid-focused-0cdc36fa-20261106-01/full-suite-failure-excerpt.log`,
has SHA-256 `4f57870a4b512e9cb8308fe75f0f981a7253a3c88138a41a682ddf444049fa6d`.

The test-only repair supplies the captured generation and historical time
context, asserts the exact probe request, feeds the real callback a valid
missing-record response, and checks that a changed generation conflicts with no
evidence or claims. It then feeds a matching generation and retains all prior
hybrid score, citation, eligible graph seed and opposing claim-basis assertions.
The test used for that focused run had SHA-256
`659e0181c8a59d9897af05e4c7023262be9c804e51a91775a55afad2a87635d3`.
Independent static review found the State response and time context consistent
with the implementation; it did not run the test.

Subsequent review found that the outer wrapper did not require the child to
execute exactly nine cases. The strengthened test now requires nine total,
zero failures, skips and exclusions; its SHA-256 is
`f16ca8d9b78459a3f234eecdff69f305e461642b7d6a81198433643d6c6ca399`.
That additional assertion was not part of the first passing run below.

A separate isolated checkout of the same commit plus only the repaired test,
with a copied matching OTP 29 SDK and dependency BEAMs, ran the outer wrapper
once. It exited 0 and reports one outer test passed; the child must have exited
successfully for that wrapper to pass. The retained `fixture.log` SHA-256 is
`91c155f04bda3927e06663d5acc8cd1b21829d49db810d82e26dfdee61d2cb77`,
and `status.txt` SHA-256 is
`db8bf9a67ac9e30c546f9712fa799918b86c4289093efc096c42d74fb07642b0`.
Both source and SDK post-checks reported zero. The run started with 2,770,324 KiB
available under a calibrated 2.5-GiB scheduling floor; this is an operational
resource gate, not a change to any product limit or deadline. The complete
fixture and inventories remain under
`_build/verification/domain-hybrid-focused-0cdc36fa-20261106-01/`.

The strengthened fixture then passed in a separate isolated packet,
`_build/verification/domain-hybrid-focused-0cdc36fa-20261106-02/`: one outer
wrapper passed and its child required exactly nine cases, with no failures,
skips or exclusions. The `fixture.log` SHA-256 is
`ff953eeda704993e59ae297a826a9998e2bb2fa366438db13ee7177bf0d75890`;
`status.txt` reports exit 0, source post-check 0 and SDK post-check 0, and has
SHA-256 `db8bf9a67ac9e30c546f9712fa799918b86c4289093efc096c42d74fb07642b0`.
The run began with 2,719,448 KiB available under the same calibrated 2.5-GiB
scheduling floor.

The original full suite was still live at this checkpoint. Its final aggregate
was not yet known; the isolated pass does not replace the original failure or
establish a passing full suite.
