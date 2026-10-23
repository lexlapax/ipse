unless match?({:unix, :linux}, :os.type()),
  do: raise("terminal ownership verification requires Linux")

Code.require_file("platform/memory_scope.exs", __DIR__)
alias Ipse.Development.Platform.MemoryScope, as: Verify
[helper] = System.argv()

root =
  Path.join(
    System.tmp_dir!(),
    "ipse-memory-terminal-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  )

File.mkdir!(root)
File.chmod!(root, 0o700)

baseline = Verify.start(Path.expand(helper), Path.join(root, "production"), ["/bin/true"])
Verify.finish(baseline) |> Verify.assert_closed(true)

guard = """
                    if reason == "completed" {
                        if let Some(outcome) = active_failure(bound.as_ref(), lease.anchor.as_mut().unwrap(), start, Duration::from_millis(timeout))? {
"""

barrier = """
                    if reason == "completed" {
                        if role == "root" {
                            private_file(&output.join("terminal-ready.json"), b"{}\\n")?;
                            let barrier_deadline = Instant::now() + Duration::from_secs(5);
                            while !output.join("terminal-release").exists() {
                                if Instant::now() >= barrier_deadline { return Err("diagnostic terminal barrier timed out".into()); }
                                std::thread::sleep(Duration::from_millis(1));
                            }
                        }
                        if let Some(outcome) = active_failure(bound.as_ref(), lease.anchor.as_mut().unwrap(), start, Duration::from_millis(timeout))? {
"""

helpers =
  for kind <- ["guarded", "reversed"], into: %{} do
    directory = Path.join(root, kind)
    File.mkdir!(directory)
    File.cp_r!(Path.expand("../native", __DIR__), Path.join(directory, "native"))
    source_file = Path.join(directory, "native/ipse-measure.rs")
    source = File.read!(source_file)
    [_before, _after] = String.split(source, guard)

    injected =
      if kind == "guarded",
        do: barrier,
        else:
          String.replace(
            barrier,
            "if let Some(outcome) = active_failure(bound.as_ref(), lease.anchor.as_mut().unwrap(), start, Duration::from_millis(timeout))? {",
            "if let Some(outcome) = None::<&str> {"
          )

    File.write!(source_file, String.replace(source, guard, injected))
    binary = Path.join(directory, "ipse-runner")

    {output, code} =
      System.cmd(
        "rustc",
        [
          "--edition=2021",
          "-D",
          "warnings",
          Path.join(directory, "native/ipse-runner.rs"),
          "-o",
          binary
        ],
        stderr_to_stdout: true
      )

    File.write!(Path.join(directory, "build.log"), output)
    unless code == 0, do: raise(output)
    {kind, binary}
  end

for kind <- ["guarded", "reversed"] do
  run = Verify.start(helpers[kind], Path.join(root, kind <> "-owner"), ["/bin/true"])
  Verify.wait_json(Path.join(run.output, "terminal-ready.json"))
  true = Port.command(run.port, "C")
  File.write!(Path.join(run.output, "terminal-release"), "go")
  value = Verify.finish(run) |> Verify.assert_closed(kind == "reversed")
  true = value["reason"] == if(kind == "guarded", do: "owner_closed", else: "completed")
end

run = Verify.start(helpers["guarded"], Path.join(root, "guarded-deadline"), ["/bin/true"], 1000)
Verify.wait_json(Path.join(run.output, "terminal-ready.json"))
Process.sleep(1100)
File.write!(Path.join(run.output, "terminal-release"), "go")
value = Verify.finish(run) |> Verify.assert_closed(false)
true = value["reason"] == "timeout"

IO.puts(
  JSON.encode!(%{
    checks: 4,
    production_success: true,
    terminal_owner_loss_refused: true,
    reversed_terminal_guard_accepts_cancel: true,
    terminal_original_deadline_refused: true,
    diagnostic_copies_only: true,
    inference_requests: 0,
    evidence: root
  })
)
