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

The bundle includes the current manuals. Links to source files, source-build
examples and historical records open the repository at the build's recorded
commit and need Internet access. Those procedures still require a source checkout
and its toolchain. When a build has no full Git commit identity, such links use
the application version's tag; `docs/bundle-links.json` records that fallback.

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
IPSE_LINK="$HOME/.local/bin/ipse"
export PATH="$HOME/.local/bin:$PATH"
(
  set -eu
  if [ -e "$IPSE_DIR" ] || [ -L "$IPSE_DIR" ] ||
     [ -e "$IPSE_LINK" ] || [ -L "$IPSE_LINK" ]; then
    printf '%s\n' 'Installation path already exists; inspect it and use the upgrade procedure.' >&2
    exit 1
  fi
  mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
  mkdir "$IPSE_DIR"
  tar -xzf "$IPSE_ARCHIVE" -C "$IPSE_DIR"
  ln -s "$IPSE_DIR/ipse" "$IPSE_LINK"
  ipse --version
  ipse version --json
)
```

The grouped commands stop at the first failure. An existing installation path,
including a dangling link or a directory at the launcher path, refuses before
extraction. Use the upgrade procedure below for an installed release. A failed
extraction can leave a partial new directory; inspect it before removing that
failed installation and retrying. Keep the release files together. Add the PATH
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
ipse demo
ipse setup
ipse doctor
```

Demo prints a temporary workspace/session ID,
writes/reads `ipse-demo.txt` and runs a shell probe. It proves local operation,
not provider access. Setup then requires an explicit provider choice, labels
billing and credential sources, and prints the exact private configuration for
confirmation. You can stop after the demo if you do not want to configure an
account yet. Doctor is offline by default; resolve its failures before
[your first real task](usage.md#approve-a-small-task). See
[provider setup](configuration.md#choose-and-save-a-provider) for account choices
and [diagnosis](recovery.md#diagnose-your-setup) for doctor findings.

## Upgrade without losing recovery options

Finish active work before switching builds. Record `readlink "$HOME/.local/bin/ipse"`
so you can return to the old release. Download the next version and its sidecar,
then verify them using the checksum procedure above. Keep the old directory.
From the download directory, replace both placeholders and extract separately:

```sh
IPSE_VERSION=NEXT_VERSION
IPSE_ARCHIVE=RELEASE_ASSET_NAME
IPSE_DIR="$HOME/.local/opt/ipse-$IPSE_VERSION"
(
  set -eu
  if [ -e "$IPSE_DIR" ] || [ -L "$IPSE_DIR" ]; then
    printf '%s\n' 'New release directory already exists; inspect it before extracting.' >&2
    exit 1
  fi
  mkdir -p "$HOME/.local/opt"
  mkdir "$IPSE_DIR"
  tar -xzf "$IPSE_ARCHIVE" -C "$IPSE_DIR"
  "$IPSE_DIR/ipse" version --json
)
```

Expect the next version and its build identity. Stop on extraction or loader
failure; the launcher still points to the old release. Inspect a partially
extracted new directory before removing or retrying it. Once the new executable
works, switch future launches explicitly:

```sh
IPSE_LINK="$HOME/.local/bin/ipse"
(
  set -eu
  test -x "$IPSE_DIR/ipse"
  if [ ! -L "$IPSE_LINK" ]; then
    printf '%s\n' 'Expected the existing launcher to be a symbolic link; inspect its path before switching.' >&2
    exit 1
  fi
  ln -sfn "$IPSE_DIR/ipse" "$IPSE_LINK"
  "$IPSE_LINK" version --json
  "$IPSE_LINK" doctor
)
```

Settings, credentials and journals remain in `IPSE_HOME` (normally `~/.ipse`).
Switching a link does not migrate a running conversation.
The procedure refuses a regular file or directory at the launcher path. If the
new doctor's checks fail, retain both releases and follow [diagnosis](recovery.md)
before new work. To roll back, set `IPSE_DIR` to the retained old release and
repeat the same guarded switch.

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

Export any saved work you need. Before removing the last executable, revoke saved
sign-ins with `ipse logout` for ChatGPT and `ipse logout --provider xai_oauth` for
Grok, if configured. Review each command's remote-revocation result and the
corresponding account-side grants.

Choose the version to remove and inspect the link first. For the standard layout:

```sh
IPSE_VERSION=0.1.0
IPSE_DIR="$HOME/.local/opt/ipse-$IPSE_VERSION"
IPSE_LINK="$HOME/.local/bin/ipse"
readlink "$IPSE_LINK"
```

After confirming the displayed target is that release, remove only the matching
link and directory:

```sh
(
  set -eu
  test -L "$IPSE_LINK"
  test "$(readlink "$IPSE_LINK")" = "$IPSE_DIR/ipse"
  rm "$IPSE_LINK"
  rm -rf "$IPSE_DIR"
)
```

A mismatch refuses before deletion. Review a custom installation's equivalent
paths separately rather than substituting a broad directory.

Keep `~/.ipse` to retain settings and saved work. Deleting it is a separate
decision that removes credentials, journals, handoffs and extension state. Export
anything needed first. A custom `IPSE_HOME` remains at its configured location.
