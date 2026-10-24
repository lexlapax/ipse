# Install, upgrade and remove Ipse

Choose a release matching your OS, architecture and Linux libc. Bundles contain
Erlang, Elixir application code and the native helper; running one needs compatible
OS libraries and `/bin/sh`, without an Elixir or Rust installation. Windows,
signing and notarization are not supported. For source builds, use
[Arch Linux setup](arch-linux.md) or [developer prerequisites](../developer/index.md).

## Download and check a release

Open the repository's [Releases](https://github.com/lexlapax/ipse/releases), select
a published version and read its notes. Download the matching `.tar.gz` and its
`.tar.gz.sha256` into the same directory. Drafts are available only to repository
collaborators. If no version is published, there is no public release to install
yet. Renaming an archive does not make it compatible with a different platform.

Set the version and exact asset name; replace `RELEASE_ASSET_NAME` first:

```sh
IPSE_VERSION=0.1.0
IPSE_ARCHIVE=RELEASE_ASSET_NAME
cd "$HOME/Downloads"
sha256sum -c "$IPSE_ARCHIVE.sha256"
```

On macOS use `shasum -a 256 -c "$IPSE_ARCHIVE.sha256"`. Expect the archive name
followed by `OK`. Stop on a mismatch or missing file and download both again from
the intended repository. A checksum detects changed bytes; it is not a signature
or independent proof of the publisher's identity.

## Extract and put the launcher on PATH

Keep releases outside workspaces that Ipse will modify:

```sh
IPSE_DIR="$HOME/.local/opt/ipse-$IPSE_VERSION"
mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
mkdir "$IPSE_DIR"
tar -xzf "$IPSE_ARCHIVE" -C "$IPSE_DIR"
ln -s "$IPSE_DIR/ipse" "$HOME/.local/bin/ipse"
export PATH="$HOME/.local/bin:$PATH"
ipse --version
ipse version --json
```

An existing directory or launcher link stops this first-install procedure; use
the upgrade procedure below. Keep the release files together. Add the PATH
assignment to your shell startup file if needed. Expect the selected version
and build/runtime facts. On loader/libc errors, choose a compatible archive or
build from source.

macOS may quarantine an unsigned download. Only after deciding to trust it, remove
quarantine from this extracted release if required:

```sh
xattr -dr com.apple.quarantine "$IPSE_DIR"
```

This removes the OS download warning; it does not sign, notarize or verify code.
macOS native confinement remains experimental; see
[shell policy](usage.md#choose-shell-confinement).

## Complete first run

From a scratch directory:

```sh
IPSE_FIRST_WORKSPACE=$(mktemp -d)
cd "$IPSE_FIRST_WORKSPACE"
ipse setup
ipse doctor
ipse demo
```

Setup requires a provider choice, labels billing and credential sources, and
prints the exact private configuration for confirmation. To try without an
account, choose `demo` and model `scripted`. Doctor is offline by default; resolve
its failures before real work. Demo prints a temporary workspace/session ID,
writes/reads `ipse-demo.txt` and runs a shell probe. It proves local operation,
not provider access. Continue with [provider setup](configuration.md#choose-and-save-a-provider),
[a first real task](usage.md#approve-a-small-task) and
[diagnosis](recovery.md#diagnose-your-setup).

## Upgrade without losing recovery options

Finish active work before switching builds. Download, verify and extract the next
version into a different directory, keeping the old release. Set `IPSE_DIR` to
the new extracted directory and switch future launches explicitly:

```sh
ln -sfn "$IPSE_DIR/ipse" "$HOME/.local/bin/ipse"
ipse version --json
ipse doctor
```

Settings, credentials and journals remain in `IPSE_HOME` (normally `~/.ipse`).
Switching a link does not migrate a running conversation.

Selected extensions pin the host BEAM build. A different build refuses their
resume with configuration-mismatch and handoff guidance. Finish those sessions,
keep using the old release, or export an operator note with it:

```sh
umask 077
IPSE_HANDOFF_DIR=$(mktemp -d)
/path/to/old-release/ipse handoff --resume SESSION_ID --note 'Continue the remaining work from this reviewed note.' > "$IPSE_HANDOFF_DIR/handoff.json"
/path/to/old-release/ipse chat --resume SESSION_ID --cwd /path/to/original/workspace
```

Use the original configuration, state directory and workspace. Review the exported
`handoff.json`, then start a fresh conversation with
`ipse chat --handoff "$IPSE_HANDOFF_DIR/handoff.json" --cwd /path/to/workspace`. It contains
private text and grants no approvals. Extension-free sessions resume when their
configuration still matches. Changed configuration bytes can also refuse resume;
follow [recovery](recovery.md) rather than editing journals. To roll back, repoint
the launcher at the retained old release and check its version.

## Uninstall

Check `readlink "$HOME/.local/bin/ipse"`, then remove the intended link and release:

```sh
rm "$HOME/.local/bin/ipse"
rm -rf "$IPSE_DIR"
```

Keep `~/.ipse` to retain sign-in, settings and saved work. Deleting it is a separate
decision that removes credentials, journals, handoffs and extension state. Export
anything needed first. Before removing the last executable, revoke saved sign-ins
with `ipse logout` for ChatGPT and `ipse logout --provider xai_oauth` for Grok.
Review each command's remote-revocation result and the corresponding account-side
grants. A custom `IPSE_HOME` remains at its configured location.
