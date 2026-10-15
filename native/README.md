# Shell supervisor

Build with `native/build.sh` (Rust standard library only; Linux/macOS). Runner
also builds it on demand in a source checkout when `rustc` is available. Package
`priv/ipse-runner` with releases/escripts, or set `IPSE_RUNNER_PATH`.

Arguments are `CWD TIMEOUT_MS COMMAND`. Stdout is a binary frame stream: one type
byte, a four-byte unsigned big-endian payload length, then that many payload
bytes. `O` carries stdout/stderr bytes (interleaving follows arrival order), `X`
carries JSON `{ "exit_code": integer, "timed_out": boolean }`, and `E` carries a
fatal supervisor error. Output can split UTF-8 characters between frames.

The caller keeps the helper's stdin pipe open. EOF kills the shell's process
group. The helper starts `/bin/sh -c COMMAND` in a fresh process group and kills
that group on timeout, parent-pipe EOF, failed output delivery, and shell exit.
The timeout includes the shell and its ordinary descendants. A deliberately
adversarial process can escape by creating a new session; this is **not a
sandbox**. Shell runs with the user's local filesystem and network access.
Provider credentials OPENAI_API_KEY, ANTHROPIC_API_KEY, and
IPSE_CHATGPT_ACCESS_TOKEN are removed from the shell environment. Other
inherited environment values remain available.

## Session locks

`ipse-runner --lock PATH` opens a persistent file with mode 0600 and takes a
nonblocking exclusive advisory `flock`. Linux and macOS reject symlink lock
files with `O_NOFOLLOW`. A successful lock emits an `L` frame. Sending any stdin
byte releases the lock and emits a `U` frame; stdin EOF also releases it.
Ownership follows the helper process, so an Elixir Port owner's death releases
the lock automatically. Lock files must **never be deleted**: preserving the
inode prevents concurrent owners from locking different files at the same path.
