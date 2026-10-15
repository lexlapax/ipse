> Historical snapshot, archived 2026-10-14 from commit `27fbf6d`. Original path: `THIRD_PARTY_NOTICES.md`.
> Superseded guidance; use the [current documentation map](../../index.md).

# Third-party notices

Ipse's own source is MIT licensed. No Loopex or rs-llmspell source was copied
into this prototype. Those projects informed the design.

The source build fetches [Jason](https://github.com/michalmuskala/jason), Copyright
(c) 2017-2024 Michał Muskała, under MIT. Its license is in `deps/jason/LICENSE`.
The Rust helper uses only the Rust standard library (MIT OR Apache-2.0); it has
no third-party Cargo dependencies.

Bundled releases include [Elixir](https://github.com/elixir-lang/elixir)
(Copyright 2012 Plataformatec; copyright holders as listed upstream) and
[Erlang/OTP](https://github.com/erlang/otp) (Copyright Ericsson AB and contributors)
under Apache-2.0, with component-specific notices retained by their distributions.
The Apache-2.0 text is included in `licenses/`. Linux builds made from Debian
packages also include the Erlang package copyright file listing component terms.

Native runtimes rely on the target OS's system libraries, including its C library
and OpenSSL. These remain under their respective licenses. Platform-specific
packagers must preserve upstream notices for the runtimes they distribute.
