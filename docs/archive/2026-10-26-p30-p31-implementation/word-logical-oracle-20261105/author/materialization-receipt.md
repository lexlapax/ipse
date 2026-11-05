# Frozen oracle materialization

After the literal/manual-source freeze, Root reviewed the full script and
released one pure OTP runtime slot. `sh author/materialize_oracle.sh` ran from
the repository root and exited 0 in 0.17 s. The runtime lane was then released.

Terminal output:

```text
Authored 12 sources; 144 blocks; 168 included text nodes; 36 excluded text nodes; complete 204-node accounting
```

| Frozen artifact | SHA-256 |
| --- | --- |
| expected-oracle.json | 890fc96281f60bb73eee4d6a71d044edc2250bf5a30b147e8d585b2eb5f858ed |
| raw-package-index.json | bc86e870b7f8de6151ae66936f0a6839e493b842518896517c97bb2a371d56ee |
| author_oracle.exs (unchanged) | 3f5f217db9db20556bc2dcaba098c29d1c402ba7e9590b31eadf2a202601e9ee |

All 12 original input paths, exact original byte lengths and SHA-256 hashes are
included in the expected oracle and raw index. Each original's six raw XML parts
also have exact byte lengths and hashes. The expected oracle provides separate
block, story and document UTF-8 spans and raw text-node dispositions. The
materializer validated equality between all 204 fixed literal/node assignments
and the complete raw text-node inventory. No expected text was taken from the
raw tree by algorithm; raw-tree text was used only for this equality check.

The author has not read candidate code/output, gold/questions or another oracle.
No product locator crosswalk or answer-quality conclusion is claimed here. The
historical 12-document/62-question denominator remains intact for the checker.
This is independent author evidence for exposed remediation, not a new held-out
cohort or page-layout fidelity result. No main-worktree/Git edit or commit was
made; all author artifacts stay under the authorized ignored build directory.
