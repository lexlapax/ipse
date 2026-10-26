# Optional PDF parser dependency closure

Reviewed 2026-10-26. This inventory covers the exact locked Cargo closure of
`ipse-pdf`, including target and build dependencies. The host OS helper remains
Rust 1.85; building this optional parser requires Rust 1.88. Installed users run
the bundled executable and do not need Cargo or a parser toolchain.

The direct parser is lopdf 0.46.0, MIT, with default features disabled. No
renderer, OCR engine, external executable, C compression library, network client,
JavaScript runtime or Python runtime is selected. `flate2` uses Rust backends
`miniz_oxide` and `zlib-rs`; `libc` binds the existing platform C library.
The locked UEFI-only `r-efi` branch is not built for Linux or macOS.

Where upstream offers a choice, select Apache-2.0, or MIT when Apache-2.0 is
absent. Retain additional BSD-3-Clause/Unicode-3.0 terms for encoding/Unicode
data, BSD-3-Clause for the Brotli family and Zlib for `zlib-rs`. Older manifest
slash expressions (`MIT/Apache-2.0`, `BSD-3-Clause/MIT`) are preserved below;
Brotli’s supplied LICENSE is BSD-3-Clause. `r-efi` offers Apache-2.0 as an
alternative to LGPL; LGPL is not selected. Build-time packaging copies each
crate’s license, copyright, notice and author files plus this inventory.
`alloc-stdlib` 0.2.4 omits its repository-root license from its crate archive;
the retained [notice](notices/alloc-stdlib-LICENSE) comes from the crate’s
recorded [source commit](https://github.com/dropbox/rust-alloc-no-stdlib/blob/ae42d22078b98549e987d2f03d12df7b984fde47/LICENSE).

`Cargo.lock` supplies registry checksums. `dependency-inventory.json` freezes the
reviewed version/license list; the build refuses metadata drift. No dependency
is added to the host application by enabling ordinary text/DOCX extraction.

| Crate/source | Version | Purpose | Upstream license expression | Declared Rust floor |
| --- | --- | --- | --- | --- |
| [`adler2`](https://crates.io/crates/adler2/2.0.1) | 2.0.1 | Deflate checksum implementation | `0BSD OR MIT OR Apache-2.0` | not declared |
| [`aes`](https://crates.io/crates/aes/0.9.2) | 0.9.2 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`alloc-no-stdlib`](https://crates.io/crates/alloc-no-stdlib/2.0.4) | 2.0.4 | Bounded Rust stream decompression | `BSD-3-Clause` | not declared |
| [`alloc-stdlib`](https://crates.io/crates/alloc-stdlib/0.2.4) | 0.2.4 | Bounded Rust stream decompression | `BSD-3-Clause` | not declared |
| [`bitflags`](https://crates.io/crates/bitflags/2.13.2) | 2.13.2 | Rust parser support | `MIT OR Apache-2.0` | 1.56.0 |
| [`block-buffer`](https://crates.io/crates/block-buffer/0.12.1) | 0.12.1 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`block-padding`](https://crates.io/crates/block-padding/0.4.2) | 0.4.2 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`brotli-decompressor`](https://crates.io/crates/brotli-decompressor/5.0.3) | 5.0.3 | Bounded Rust stream decompression | `BSD-3-Clause/MIT` | not declared |
| [`cbc`](https://crates.io/crates/cbc/0.2.1) | 0.2.1 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`cfg-if`](https://crates.io/crates/cfg-if/1.0.5) | 1.0.5 | Rust parser support | `MIT OR Apache-2.0` | 1.32 |
| [`chacha20`](https://crates.io/crates/chacha20/0.10.2) | 0.10.2 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`cipher`](https://crates.io/crates/cipher/0.5.2) | 0.5.2 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`const-oid`](https://crates.io/crates/const-oid/0.10.2) | 0.10.2 | Parser cryptographic primitives; encrypted files are refused | `Apache-2.0 OR MIT` | 1.85 |
| [`core_detect`](https://crates.io/crates/core_detect/1.0.0) | 1.0.0 | Rust CPU feature detection and dispatch | `MIT/Apache-2.0` | not declared |
| [`cpubits`](https://crates.io/crates/cpubits/0.1.1) | 0.1.1 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`cpufeatures`](https://crates.io/crates/cpufeatures/0.3.1) | 0.3.1 | Rust CPU feature detection and dispatch | `MIT OR Apache-2.0` | 1.85 |
| [`crc32fast`](https://crates.io/crates/crc32fast/1.5.3) | 1.5.3 | Deflate checksum implementation | `MIT OR Apache-2.0` | 1.63 |
| [`crypto-common`](https://crates.io/crates/crypto-common/0.2.2) | 0.2.2 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`digest`](https://crates.io/crates/digest/0.11.3) | 0.11.3 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`ecb`](https://crates.io/crates/ecb/0.2.1) | 0.2.1 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`encoding_rs`](https://crates.io/crates/encoding_rs/0.8.42) | 0.8.42 | PDF text encodings and password normalization | `(Apache-2.0 OR MIT) AND BSD-3-Clause` | 1.88 |
| [`equivalent`](https://crates.io/crates/equivalent/1.0.3) | 1.0.3 | Parser collection storage | `Apache-2.0 OR MIT` | 1.6 |
| [`flate2`](https://crates.io/crates/flate2/1.1.10) | 1.1.10 | Bounded Rust stream decompression | `MIT OR Apache-2.0` | 1.67.0 |
| [`getrandom`](https://crates.io/crates/getrandom/0.4.3) | 0.4.3 | Parser random-source closure; r-efi is an unbuilt UEFI target branch | `MIT OR Apache-2.0` | 1.85 |
| [`hashbrown`](https://crates.io/crates/hashbrown/0.17.1) | 0.17.1 | Parser collection storage | `MIT OR Apache-2.0` | 1.85.0 |
| [`hybrid-array`](https://crates.io/crates/hybrid-array/0.4.15) | 0.4.15 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`indexmap`](https://crates.io/crates/indexmap/2.14.2) | 2.14.2 | Parser collection storage | `Apache-2.0 OR MIT` | 1.85 |
| [`inout`](https://crates.io/crates/inout/0.2.5) | 0.2.5 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`itoa`](https://crates.io/crates/itoa/1.0.18) | 1.0.18 | Rust parser support | `MIT OR Apache-2.0` | 1.68 |
| [`libc`](https://crates.io/crates/libc/0.2.191) | 0.2.191 | Rust bindings to the existing platform C library | `MIT OR Apache-2.0` | 1.65 |
| [`log`](https://crates.io/crates/log/0.4.34) | 0.4.34 | Rust parser support | `MIT OR Apache-2.0` | 1.71.0 |
| [`lopdf`](https://crates.io/crates/lopdf/0.46.0) | 0.46.0 | PDF objects, streams, font decoding and text extraction | `MIT` | 1.88 |
| [`md-5`](https://crates.io/crates/md-5/0.11.0) | 0.11.0 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.85 |
| [`memchr`](https://crates.io/crates/memchr/2.8.3) | 2.8.3 | Bounded-input Rust token and byte parsing | `Unlicense OR MIT` | 1.61 |
| [`miniz_oxide`](https://crates.io/crates/miniz_oxide/0.9.1) | 0.9.1 | Bounded Rust stream decompression | `MIT OR Zlib OR Apache-2.0` | not declared |
| [`multiversion_no_op`](https://crates.io/crates/multiversion_no_op/1.0.0) | 1.0.0 | Rust CPU feature detection and dispatch | `Apache-2.0 OR MIT` | 1.56 |
| [`nom`](https://crates.io/crates/nom/8.0.0) | 8.0.0 | Bounded-input Rust token and byte parsing | `MIT` | 1.65.0 |
| [`proc-macro2`](https://crates.io/crates/proc-macro2/1.0.107) | 1.0.107 | Rust compile-time macros and typed parser errors | `MIT OR Apache-2.0` | 1.71 |
| [`quote`](https://crates.io/crates/quote/1.0.47) | 1.0.47 | Rust compile-time macros and typed parser errors | `MIT OR Apache-2.0` | 1.71 |
| [`r-efi`](https://crates.io/crates/r-efi/6.0.0) | 6.0.0 | Parser random-source closure; r-efi is an unbuilt UEFI target branch | `MIT OR Apache-2.0 OR LGPL-2.1-or-later` | 1.68 |
| [`rand`](https://crates.io/crates/rand/0.10.3) | 0.10.3 | Parser random-source closure; r-efi is an unbuilt UEFI target branch | `MIT OR Apache-2.0` | 1.85 |
| [`rand_core`](https://crates.io/crates/rand_core/0.10.1) | 0.10.1 | Parser random-source closure; r-efi is an unbuilt UEFI target branch | `MIT OR Apache-2.0` | 1.85 |
| [`rangemap`](https://crates.io/crates/rangemap/1.8.0) | 1.8.0 | Parser collection storage | `MIT/Apache-2.0` | 1.81.0 |
| [`rustversion`](https://crates.io/crates/rustversion/1.0.23) | 1.0.23 | Rust compile-time macros and typed parser errors | `MIT OR Apache-2.0` | 1.31 |
| [`scopeguard`](https://crates.io/crates/scopeguard/1.2.0) | 1.2.0 | Rust parser support | `MIT OR Apache-2.0` | not declared |
| [`sha2`](https://crates.io/crates/sha2/0.11.1) | 0.11.1 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.88 |
| [`simd-adler32`](https://crates.io/crates/simd-adler32/0.3.10) | 0.3.10 | Deflate checksum implementation | `MIT` | not declared |
| [`simdutf8`](https://crates.io/crates/simdutf8/0.1.5) | 0.1.5 | Bounded-input Rust token and byte parsing | `MIT OR Apache-2.0` | not declared |
| [`stringprep`](https://crates.io/crates/stringprep/0.1.5) | 0.1.5 | PDF text encodings and password normalization | `MIT/Apache-2.0` | not declared |
| [`syn`](https://crates.io/crates/syn/3.0.9) | 3.0.9 | Rust compile-time macros and typed parser errors | `MIT OR Apache-2.0` | 1.71 |
| [`thiserror`](https://crates.io/crates/thiserror/2.0.21) | 2.0.21 | Rust compile-time macros and typed parser errors | `MIT OR Apache-2.0` | 1.77 |
| [`thiserror-impl`](https://crates.io/crates/thiserror-impl/2.0.21) | 2.0.21 | Rust compile-time macros and typed parser errors | `MIT OR Apache-2.0` | 1.77 |
| [`tinyvec`](https://crates.io/crates/tinyvec/1.13.3) | 1.13.3 | Parser collection storage | `Zlib OR Apache-2.0 OR MIT` | not declared |
| [`typenum`](https://crates.io/crates/typenum/1.20.1) | 1.20.1 | Parser cryptographic primitives; encrypted files are refused | `MIT OR Apache-2.0` | 1.41.0 |
| [`unicode-bidi`](https://crates.io/crates/unicode-bidi/0.3.18) | 0.3.18 | PDF text encodings and password normalization | `MIT OR Apache-2.0` | 1.47.0 |
| [`unicode-ident`](https://crates.io/crates/unicode-ident/1.0.27) | 1.0.27 | Rust compile-time macros and typed parser errors | `(MIT OR Apache-2.0) AND Unicode-3.0` | 1.71 |
| [`unicode-normalization`](https://crates.io/crates/unicode-normalization/0.1.26) | 0.1.26 | PDF text encodings and password normalization | `(MIT OR Apache-2.0) AND Unicode-3.0` | 1.36 |
| [`unicode-properties`](https://crates.io/crates/unicode-properties/0.1.4) | 0.1.4 | PDF text encodings and password normalization | `MIT/Apache-2.0` | not declared |
| [`weezl`](https://crates.io/crates/weezl/0.2.1) | 0.2.1 | Bounded Rust stream decompression | `MIT OR Apache-2.0` | 1.88.0 |
| [`zlib-rs`](https://crates.io/crates/zlib-rs/0.6.8) | 0.6.8 | Bounded Rust stream decompression | `Zlib` | 1.75 |
