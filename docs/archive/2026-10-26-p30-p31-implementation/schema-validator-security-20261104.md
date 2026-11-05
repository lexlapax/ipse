# Maintained schema-validator update — 2026-11-04

Historical dependency-review checkpoint. The [dependency inventory](../../developer/dependencies.md)
owns current versions and adoption policy; the [plan](../../plan.md) owns final
integration acceptance.

The required build reported JSONSchex 0.10.0 retired for security. The official
[release notes](https://github.com/xinz/jsonschex/blob/main/CHANGELOG.md) and
[upstream fix](https://github.com/xinz/jsonschex/pull/19) describe regex engine
match-limit failures being treated as non-matches, permitting validation bypass
through regex-keyed properties or inverted/composed rules. Version 0.11.0 fixes
that behavior; 0.11.1 additionally fixes Elixir 1.20 compilation warnings.

The declaration now pins **JSONSchex 0.11.1**, with required **ex_json_pointer
0.9.0**. These are updates to existing Elixir dependencies, both MIT-licensed.
Their exact package licenses and Mix declarations were inspected. No other
lockfile entry changed, no new application was added, and optional Decimal/IDNA
remain disabled. The official release checksum for JSONSchex 0.11.1 is
`e4c0572d85d321bb36fc6afa2f38bd710082a9237055a175d7d0db52c73b36a6`;
the pointer package checksum is
`e0292f6476e903bedd77cec1585e24554760d66b3c2dd731abe31ca147a8d3f5`.

Ipse's existing schema gate already excludes regexes, `patternProperties`,
`propertyNames`, `not` and combinators before library compilation. This review
does not establish a reachable bypass through that gate. The update retains
the same keyword, byte, depth and loader restrictions; three additional
unsupported-schema vectors exercise those closed boundaries.

Checks on the working integration tree pass:

- All 21 JSON-adapter, decision and artifact tests.
- Normal native build, strict compilation of all 197 host sources and four
  bundled artifacts, with no retired-package warning.
- Repository formatting and the credential-free demo in an isolated home.

The current dependency chapter was reviewed as a whole and its existing
adoption/example/optional-service flow remains intact. Operator interfaces and
the admitted schema subset did not change. The complete stable-source suite,
extracted package/platform verification and final adversarial review remain
separate open gates; earlier runtimes and their recorded failures are unchanged.
