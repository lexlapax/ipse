# Frozen Linux package checkpoint, 2026-11-06

Historical build and generic installed-verifier evidence for
`9b0acfdd3ec54d3e5beaf81d7fe5ff0f3bc5afd4`. The
[testing guide](../../developer/testing.md) owns current procedures and the
[plan](../../plan.md) owns acceptance. This is a private candidate build, not a
release publication, whole-source pass or complete P30/P31 qualification.

## Build and provenance

A separate clean checkout of that exact commit used the canonical
`dev/package.sh`, including the optional PDF build, locked cached dependencies,
strict production compilation and bundled artifact generation. Dependency
operations were offline. Existing versioned runtime notices were copied only
after checking every recorded file hash and their exact Elixir 1.20.4 / OTP
29.1.1 versions. No dependency, TLS or native policy was changed.

The build completed with exit zero under a 900-second coordination bound plus
ten-second termination grace. All tracked files and symbolic-link targets
remained unchanged. Launcher checks passed; the process group and an independent
actual-host compiler/process check were empty. The generated documentation check
reported 52 documents and no missing local targets.

Two preparation errors preceded any builder/compiler execution: a file-only
inventory encountered a tracked historical directory symlink, then a relative
launcher path became invalid after changing directory. Their partial inventories
and launcher preimages remain preserved. The final guard inventories regular
files and link targets separately and uses absolute launcher paths.

The archive is `ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`, SHA256
`65b2201c349f161520d7084ec13633179216ffb9d6e1ff2bdbe595400bdaff95`.
Its checksum sidecar was verified and has SHA256
`df9bb91eb44f126baf3194920c6afdf894ba30a27fce78a450c05f353362d903`.
The build status digest is
`a7d3c1c6efe532e2f572cfc8e94886adbaecd3173393fbd602020f263b4a87f3`.

## Installed verification

The first generic installed attempt stopped at the offline doctor assertion.
Its temporary workspace was under `/run`, a protected shell-sandbox system
directory; the doctor correctly reported native policy unavailable there.
The fixture was corrected to use its documented shell-eligible `/tmp` location.
No refusal predicate or expected policy status was weakened. The first failure
remains separate from the later pass.

The second attempt passed the existing generic installed verifier under a fresh
isolated home and a 600-second bound plus ten-second grace. It covered:

- archive/application/build identity, toolchain-free launch, offline doctor,
  setup preview/save, inference inspection and missing OAuth-registration refusal;
- ordinary edit/command grants, revocation, compatible extension-free resume,
  explicit extension mismatch refusal and relative-launcher behavior;
- terminal escaping, uncertainty/recovery, historical results, sandbox ceilings
  and the large Unicode text channel;
- bundled explicit memory with 100 records and 100 queries across six Sessions
  and two projects, including exact spans and no inference.

Input/source/archive/launcher checks passed. The owned process group was empty;
an independent actual-host check found the exact process and group absent and
the shared operator listener free. This verifier did not run an Input actor.
Its output and status digests are respectively
`410152def82dd1c1106308d13a9514e2aaf5a4c6c68ca640b4f381c875f3563d`
and `9f58d365e2ad3846684c0fb03d243def7f72d1780fcb1ced6a2ed4fce4c17e62`.

Private logs and inventories remain under `candidate-9b0a-package-20261106-01`.
No transcript, environment dump, credential or signed review code is exported.
This explicit-memory fixture is not the declined retained-notebook recall test.
The build alone does not qualify PDF extraction, Arch installation, macOS,
browser sign-in, real inference, model quality or the full capacity workload.
Independent extension and paired-lifecycle proofs have separate records.
