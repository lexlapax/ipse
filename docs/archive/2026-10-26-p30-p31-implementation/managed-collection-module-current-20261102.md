# Complete source-dependent capture regression

Dated **2026-11-02 UTC** (**2026-11-01 US/Pacific**), author-run synthetic Linux
verification of clean `2f628a936ba8fa969c33bbd3fed5063fcbf9e56d`. The
[receipt](managed-collection-module-current-20261102.json) records every parent
failure. This supersedes the [earlier complete module](managed-collection-module-v3-20261101.md)
as the latest complete-module aggregate. The [plan](../../plan.md) owns acceptance;
the failed [whole-source baseline](full-suite-20261101.md) remains separate.

## Terminal result and frozen checkout

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --max-cases 1 --seed 791731
```

Result: **170 passed, 5 failed, 15 skipped, zero excluded**, 1,802.1 seconds,
exit 2. All **190** declared parent cases are accounted for; **175** ran. Child
results are not added. The receipt retains 45 native approval parent roots and
six separately named inherited-literal parent roots. Skips prove no execution.

The independent checkout, `/tmp/ipse-current-capture-module-20261102`, was cloned
without hardlinks. Only dependency sources were copied from the main checkout;
the helper, inert artifacts and development/test runtime were rebuilt. Both
builds and warnings-as-errors test compilation exit zero. No untracked private
fixture directory was copied or opened.

Prelaunch captured **7,870 tracked source files**, **633 test-build BEAM/app
files**, helper bytes, clean tracked status and HEAD. Verification after terminal
exit reproduced the exact source/build path sets and bytes, helper, status and
HEAD. The checkout was not edited during the run. Native/Mix/PTY cohorts ran
serially. Separate compile-only checks of pending tests in the main checkout
started no Ipse application or tests and wrote no BEAM files into this checkout.

The inventory includes followed build bytes and source symlink targets. It
excludes system Elixir/ERTS, environment, generated child artifacts, in-memory
test code and permission/inode inventories. This is not a complete loaded-runtime
or machine-isolation attestation, nor a performance benchmark.

| Artifact | SHA256 |
| --- | --- |
| `/tmp/ipse-current-capture-module-20261102.log` | `5f833c6dc3e36c65e1837170d75c6c65287a1dd93b64a24ae9b25dab586a833f` |
| `/tmp/ipse-current-capture-module-prelaunch-20261102.json` | `e47527b8ec00298963911b7349902b2daf534d2db5e2e2b7dca3eacf1dddbe8e` |
| `/tmp/ipse-current-capture-module-postcheck-20261102.json` | `ff4c9725e9d2bafd4fec7a3af0abbc6cfde135f74d104ef7cc1067cbb54ad2ac` |
| `/tmp/ipse-current-capture-module-inputs-20261102.exs` | `05fcacb5ca2d1c0d5bfc9e80028182f936ab21877a86d53190c3fbddba216318` |
| `/tmp/ipse-current-capture-module-report-20261102.exs` | `6a985c7f4a335dd316f515b7dd67751512bf4ef5ca5b5f759b15f2f5e32f52c5` |
| Selected helper | `5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a` |

## Every parent failure

The parser selects the final top-level summary, checks all 190 cases and exit
status, then requires consecutive parent headings matching the failed count.
Locations refer to the frozen checkout.

| # | Test | Frozen line |
| --- | --- | --- |
| 1 | interrupted legacy extension question withholds arguments after revoke | 1759 |
| 2 | competing legacy saved-consent Sessions cannot both publish at 63 pending records | 4058 |
| 3 | V2 outer Identity loss after checked deferred publication retains full liability across inert resume | 9076 |
| 4 | upgraded literal v4 A cannot be discarded while candidate cites independent current B | 2247 |
| 5 | legacy saved-consent publication refuses a full pending queue | 4012 |

Failure 1 records an unknown extension outcome before the expected question.
Failures 2, 3 and 5 request unsupported legacy publication before reaching their
intended capacity/late-loss boundaries. Failure 4 lacks `IPSE_LITERAL_AB_ROOT`,
the distinct historical seed; fresh current literals are not substituted for it.
The new source-dependent capture and its four controls are in this cohort. This
does not qualify the shipped automatic recall/capture journey, all source
combinations, model quality or complete C0.

## Focused legacy-question synchronization

The subsequent test-only correction preserves both revocation and expiry cases.
Their held VM callback marker can appear before native input and Writer scopes
finish. Changing modeled historical tracking then races the pending frame's
immutable dependency commitment. This explanation is inferred from that ordering
and the observed failures; no production question permission is enabled.

The fixture now requires the exact committed read's `host.actions` frame to have
a durable delivered result, no pending Worker input and no Session share. Only
then does it inspect Session metadata and model missing legacy tracking. Its
actual question checkpoint, owner death, replay, withheld arguments, policy and
idle-resume assertions remain intact.

| Seed | Selection | Result | Seconds | Exit |
| --- | --- | --- | --- | --- |
| 791733 | First synchronization placement | 1 passed, 1 failed, 188 excluded | 23.1 | 2 |
| 791734 | Metadata query after input/Writer settlement | 2 passed, 188 excluded | 17.5 | 0 |

The first focused failure was `Session.info/1` returning
`{:error, :session_share_frozen}` at the VM marker. Moving that query behind the
same settlement predicate repairs the ordering without changing authority. The
focused pass does not alter the five-failure complete aggregate.

Selected post-run hashes, not another frozen inventory:

| Artifact | SHA256 |
| --- | --- |
| `/tmp/ipse-legacy-question-input-settlement-20261102.log` | `a8af514c6c0e709c7f446f22173b90bb5ee4b032480505ee313e66b9615c5db0` |
| `/tmp/ipse-legacy-question-input-settlement-paired-20261102.log` | `f3a43f858ff15fdb7d417645d3db1fcbc4dc67ca25002367212f321c42fc25d8` |
| Updated Session test module | `99fe71f958f466339d4ca7f30e58f28f57d7c53ce5477134d4bfc994b2b588b0` |

The current developer Source/Collection workflows distinguish VM computation from
settled native input and retain the full union. Operator permission and recovery
manuals preserve uncertain outcomes and nonreplaying resume. Their whole-workflow
review in the preceding capture increment remains applicable: this fixture
correction changes no command, permission or runtime behavior. Installed/platform
qualification, independent quality, final adversarial acceptance and full P30/P31
remain open.
