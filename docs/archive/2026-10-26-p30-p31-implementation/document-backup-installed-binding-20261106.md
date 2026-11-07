# Installed backup source-binding domain probe — 2026-11-06

A synthetic domain probe checked the repaired completed-backup source binding
using installed Collection code from package archive SHA-256
`f808631741a05660ba2a6c093248b24b67189fed16df38843a0c5503bbf0002e`.
The package was built from base commit `8304dd4c` plus a working patch whose
SHA-256 is `4b458b4ec0161fb51c64710a39c63676043730127edf987ebc3581fc4dcec9cc`;
it is not a clean build of that commit. The first full preexisting-file checksum
check failed because the build changed Telemetry's generated Rebar `source.dag`
cache. An independent comparison reported no other preexisting content changes;
the original failed check remains in the package verification directory.

`_build/verification/collection-backup-source-binding-20261106/generate-fixtures.exs`
(SHA-256 `a51169295f731c8c1acd3cf34a30f7df1e057492c5b6917dc21f193f41e07794`)
ran from the focused source checkout using test SDK/dependency BEAMs and that
checkout's built Collection bundle. Its manifest and Projection BEAM SHA-256s
were `421163ca248563e4447f39c7226c2da7f0e1657c35911a8c36b9c1bca121f97a`
and `7bddd355292608edf0a05ea4eae9a46f50503d84dabcd9464f8923946880d7b0`.
The retained synthetic `backup-binding-fixture.json` SHA-256 is
`99e313029d180c627635dde53759abd6421f75e88de9dd3492650f29423a759f`;
the generator log SHA-256 is
`e38151d97895e2e85fc4dd42844601beb84f39ac6458a0320191709ecf2e846a`.
Both are under `_build/verification/p31-focused-run-20261106-04/`.

`_build/verification/collection-backup-source-binding-20261106/installed-probe.exs`
(SHA-256 `e9cda04591300f789a4c2cb22864b58739feade9dfe1c02d2fae14486b5c2b89`)
ran via the extracted package's `installed/bin/ipse eval`, loading the installed
`corpus-collection-documents` artifact explicitly. The installed manifest and
Projection BEAM SHA-256s were
`e820e15b57ea85c4bdcab90080b70bb36551b55630ff62153481085cdd24c466` and
`9a00417695313516d8425ef8d1a84fa60b5fcb86736df78bb20ea212452c2627`.
The probe required the valid synthetic completed backup to pass and the
mismatched source binding to fail. Its retained `backup-binding-installed.log`
has SHA-256 `eac77a1d25a01e4732ee0395bb27f9256d3d391d0fec7c77ae22fe0c4a619844`.
The operator observed exit 0 for both commands; separate exit files were not
created. This direct domain probe does not establish a Session, actual restore,
native provenance, or full backup lifecycle qualification.
