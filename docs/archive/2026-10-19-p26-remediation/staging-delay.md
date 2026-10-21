# Forced temporary-staging delay, 2026-10-19

Historical synthetic verification at candidate
`25f1d8e115fe809857a8359c5420bc62126919c7`, after the whole-P26 source review.
The [remediation record](index.md) owns acceptance. Current behavior is taught in
[the State deadline contract](../../developer/extension-state.md#read-a-revision-and-propose-a-write)
and [the memory manual](../../operator/memory.md).

## What ran

The root used a detached exact-candidate worktree on Serenity at
`/tmp/ipse-p26-r2-staging-88jsQa/source`. The main checkout stayed clean at
`6a76950`; unrelated processes and worktrees were untouched. This was trusted
Linux execution with synthetic State, not a native-sandbox enforcement test.
No production source or test hook changed, and no dependency was installed.

A temporary Rust interposer delays only a named namespace's `.pending-*` file
while a separate arm file exists. It pauses once for 500 ms after the selected
file IO returns. The observed call was `close`, on the synchronous temporary-file
write, before State's final deadline check. Other namespace paths do not trigger
it. Each probe process has a 30-second outer bound.

The Elixir probe first performs ordinary and live-deadline control writes, saves
State bytes, arms the delay and attempts a replacement with a deadline 250 ms
away. It checks that the delay actually fired, the result is a validated known
failure with the prior summary, every stored byte is unchanged, and temporary
files are gone.

A separate scratch module removes only the final staging deadline check from
candidate State source. It retains the initial locked check and all other code.
This mutation is compiled in the probe VM, never written into the checkout or
loaded as `Ipse.Extensions.State`. Its expected failing probe demonstrates that
the final check, rather than the initial check, protects this case.

| Probe | Observed delay | Result | Stored bytes | Failed receipt | Temporary files |
| --- | --- | --- | --- | --- | --- |
| Scratch module without final check | 503 ms, `close` observed | Write succeeds after expiry; probe exits 1 as expected | Changed | None | Removed |
| Actual candidate State | 503 ms, `close` observed | `failed`; probe exits 0 | Unchanged | Exact prior summary and valid elapsed receipt | Removed |

The first injector intercepted only `fsync` and `fdatasync`; neither triggered on
this write. Both of those initial probes reported `fault_observed_after_sync:
false`, so they are not fault-injection evidence. The refined injector also
intercepts the pending file's close. The initial logs remain as
`mutation-sync-only.log` and `actual-sync-only.log`; the exercised results are
`mutation-close.log` and `actual-close.log` in the scratch root.

The close-interposer source SHA-256 is
`76b353cf03aea68f2ab2ed1d001d2d96998a8c53336c1969146d5d46326aa124`;
the Elixir probe source SHA-256 is
`fe5815b35f95b527a7ec4d9340d24bd595ad21c588304b481773b496fed76ef5`.
The compiled Linux shared object SHA-256 was
`7745088b5428bcf8e4e4a718f7cf30fd97403ecbb3c842de5e1236a83bc4de7a`.
Sources follow unchanged for reproduction. They use the existing Rust toolchain,
Elixir/OTP and Linux libc; they add no runtime feature.

## Rust delay interposer

Save as `stage-sync-close.rs` in a private scratch directory.

```rust
use std::ffi::{c_char, c_int, c_void};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
static FIRED: AtomicBool = AtomicBool::new(false);
#[link(name = "dl")]
extern "C" { fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void; }
fn target(fd: c_int) -> Option<String> {
    let prefix = std::env::var("IPSE_FAULT_NAMESPACE").ok()?;
    let armed = std::env::var("IPSE_FAULT_ARM").ok()?;
    let path = std::fs::read_link(format!("/proc/self/fd/{fd}")).ok()?;
    if path.to_string_lossy().starts_with(&(prefix + "/.pending-"))
        && std::path::Path::new(&armed).is_file() {
        std::env::var("IPSE_FAULT_OBSERVED").ok()
    } else { None }
}
unsafe fn after_io(fd: c_int, symbol: *const c_char, name: &str) -> c_int {
    let function = dlsym(-1isize as *mut c_void, symbol);
    if function.is_null() { std::process::abort(); }
    let real: unsafe extern "C" fn(c_int) -> c_int = std::mem::transmute(function);
    let observed = target(fd);
    let result = real(fd);
    if result == 0 {
        if let Some(path) = observed {
            if !FIRED.swap(true, Ordering::SeqCst) {
                std::fs::write(path, name).unwrap();
                std::thread::sleep(Duration::from_millis(500));
            }
        }
    }
    result
}
#[no_mangle]
pub unsafe extern "C" fn fsync(fd: c_int) -> c_int { after_io(fd, c"fsync".as_ptr(), "fsync") }
#[no_mangle]
pub unsafe extern "C" fn fdatasync(fd: c_int) -> c_int { after_io(fd, c"fdatasync".as_ptr(), "fdatasync") }
#[no_mangle]
pub unsafe extern "C" fn close(fd: c_int) -> c_int { after_io(fd, c"close".as_ptr(), "close") }
```

## Elixir State probe

Save as `stage-probe-close.exs` alongside it.

```elixir
{:ok, _} = Application.ensure_all_started(:ipse)
mutated = System.get_env("IPSE_PROBE_MUTATION") == "without-final-check"
store =
  if mutated do
    source = File.read!("lib/ipse/extensions/state.ex")
    check = "             :ok <- check_write_deadline(request),\n"
    [_, _] = String.split(source, check)
    source = source |> String.replace("defmodule Ipse.Extensions.State do", "defmodule P26StagingMutation do") |> String.replace(check, "")
    Code.compile_string(source, "synthetic-mutation.ex")
    P26StagingMutation
  else
    Ipse.Extensions.State
  end
root = System.fetch_env!("IPSE_PROBE_ROOT")
File.mkdir_p!(root)
File.chmod!(root, 0o700)
namespace = String.duplicate("a", 64)
put = fn revision, text -> %{"op" => "state.put", "scope" => "project", "key" => "note", "expected_revision" => revision, "value" => %{"text" => text}} end
{:ok, _} = store.execute(root, namespace, put.(0, "original"), Ipse.Usage.id())
{:ok, control} = store.execute(root, namespace, Map.put(put.(1, "live control"), "write_before_ms", System.system_time(:millisecond) + 5000), Ipse.Usage.id())
path = Path.join([root, namespace, "state.json"])
before_bytes = File.read!(path)
File.write!(System.fetch_env!("IPSE_FAULT_ARM"), "armed")
request = Map.put(put.(2, "must not replace"), "write_before_ms", System.system_time(:millisecond) + 250)
operation_id = Ipse.Usage.id()
started = System.monotonic_time(:millisecond)
result = store.execute(root, namespace, request, operation_id)
elapsed = System.monotonic_time(:millisecond) - started
observed_io = File.read(System.fetch_env!("IPSE_FAULT_OBSERVED"))
observed = observed_io in [{:ok, "fsync"}, {:ok, "fdatasync"}, {:ok, "close"}]
unchanged = File.read!(path) == before_bytes
pending = Path.wildcard(Path.join([root, namespace, ".pending-*"]))
valid_failure =
  case result do
    {:failed, failure} ->
      failure["code"] == "write_deadline_elapsed" and failure["checked_at_ms"] >= request["write_before_ms"] and
        failure["generation"] == control["generation"] and failure["record"] == Map.drop(control["record"], ["value"]) and
        store.valid_outcome?(request, "failed", failure, operation_id)
    _ -> false
  end
passed = observed and unchanged and pending == [] and valid_failure and elapsed >= 500
IO.puts(Jason.encode!(%{"passed" => passed, "mutation" => mutated, "fault_observed_after_sync" => observed, "elapsed_ms" => elapsed, "state_bytes_unchanged" => unchanged, "temporary_files_removed" => pending == [], "valid_failed_receipt" => valid_failure, "outcome" => elem(result, 0), "injection_syscall" => if(observed, do: elem(observed_io, 1))}))
if not passed, do: System.halt(1)
```

## Invocation

Run from a clean, isolated checkout of the candidate after `./scripts/build.sh`.
The actual probe used the following scratch location; a reproduction needs a new
private root and fresh State subdirectories. Build the shim with:

```sh
rustc --edition=2021 --crate-type cdylib ../stage-sync-close.rs -o ../stage-sync-close.so
```

The actual candidate invocation was:

```sh
probe_root=/tmp/ipse-p26-r2-staging-88jsQa
probe_namespace=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
env IPSE_HOME="$probe_root/private-home" \
  IPSE_PROBE_ROOT="$probe_root/actual-close" \
  IPSE_FAULT_NAMESPACE="$probe_root/actual-close/$probe_namespace" \
  IPSE_FAULT_ARM="$probe_root/actual-close-arm" \
  IPSE_FAULT_OBSERVED="$probe_root/actual-close-observed" \
  LD_PRELOAD="$probe_root/stage-sync-close.so" \
  timeout 30s mix run ../stage-probe-close.exs
```

The negative control uses distinct `mutated-close`, `mutation-close-arm` and
`mutation-close-observed` paths and additionally sets
`IPSE_PROBE_MUTATION=without-final-check`. Its exit status must be 1 with
`fault_observed_after_sync: true`, `outcome: "ok"` and changed State bytes.
A failure without the observed delay does not establish this counterfactual.
The actual case must exit 0 with all verification booleans true. Neither command
may be rerun over its old State directory as if it were a fresh probe.

This closes the earlier unexercised Linux staging-delay case. It does not prove
macOS fault injection, hard real-time rename completion, clock rollback defense,
crash durability or every filesystem failure. Existing public Session tests cover
the separate approval-expiry path and inert receipt recovery.
