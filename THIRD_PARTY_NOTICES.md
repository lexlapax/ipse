# Third-party notices

Ipse's own source is Apache-2.0 licensed, Copyright (c) 2026 Sandeep Puri.
No Loopex or rs-llmspell source was copied into this prototype. Those projects
informed the design.

The source build fetches [Jason](https://github.com/michalmuskala/jason), Copyright
(c) 2017-present Michał Muskała, under Apache-2.0. Its notice is in
`deps/jason/LICENSE`; the Apache-2.0 license text is also bundled.
The earlier MIT label for Jason was incorrect.

The MCP client reuses MCP Elixir SDK and JSONSchex (MIT), plus their locked
Elixir/BEAM dependencies. All versions, purposes, licenses, and required approvals
are listed in the [dependency inventory](docs/developer/dependencies.md).
Bundled releases copy every locked package's upstream LICENSE/COPYING/NOTICE
files into `licenses/`, preserving package-specific copyrights and notices.
For NimblePool 1.1.0, which ships that notice in README.md, the upstream README
is retained alongside the Apache-2.0 license text.
The OS helper uses only the Rust standard library (MIT OR Apache-2.0); it has
no third-party Cargo dependencies. Parser-enabled packages separately include
the optional MIT-licensed lopdf 0.46.0 parser and its locked Rust dependencies.
Their complete [inventory and selected license terms](native/ipse-pdf/DEPENDENCIES.md)
accompany all 60 upstream notice directories in the package. The optional parser
does not enable document acquisition by itself.

Bundled releases include [Elixir](https://github.com/elixir-lang/elixir)
(Copyright 2012 Plataformatec; copyright holders as listed upstream) and
[Erlang/OTP](https://github.com/erlang/otp) (Copyright Ericsson AB and contributors)
under Apache-2.0, with component-specific notices retained by their distributions.
The Apache-2.0 text is included in `licenses/`. Linux builds made from Debian
packages also include the Erlang package copyright file listing component terms.

Native runtimes rely on the target OS's system libraries, including its C library
and OpenSSL. These remain under their respective licenses. Platform-specific
packagers must preserve upstream notices for the runtimes they distribute.
