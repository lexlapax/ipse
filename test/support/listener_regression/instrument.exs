defmodule ListenerRegressionInstrument do
  @moduledoc false
  def replace_once!(source, anchor, replacement) do
    case String.split(source, anchor) do
      [before, after_part] -> before <> replacement <> after_part
      _ -> raise("diagnostic anchor missing or nonunique")
    end
  end

  def prepare!(repository, root, kind, reverted) do
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    native = Path.join(root, "native")
    File.mkdir!(native)

    original =
      Path.wildcard(Path.join(repository, "native/*.rs"))
      |> Map.new(fn source ->
        bytes = File.read!(source)
        File.write!(Path.join(native, Path.basename(source)), bytes, [:exclusive])
        {Path.basename(source), sha(bytes)}
      end)

    listener = Path.join(native, "ipse-listener.rs")
    source = File.read!(listener)
    anchor = "    fn inspect(pid: u32, port: u16) -> Result<Option<u64>, String> {\n"

    injection = """
        #[cfg(ipse_probe_listener_barrier)]
        {
            let path = std::env::var("IPSE_LISTENER_PROBE_BARRIER").map_err(|_| "diagnostic barrier absent")?;
            let deadline = Instant::now() + Duration::from_secs(2);
            while !std::path::Path::new(&path).is_file() {
                if Instant::now() >= deadline { return Err("diagnostic readiness barrier timed out".into()); }
                std::thread::sleep(Duration::from_millis(1));
            }
        }
    """

    source = replace_once!(source, anchor, anchor <> injection)

    source =
      if kind == :namespace and reverted do
        source
        |> replace_once!("fn table(port: u16)", "fn table(pid: u32, port: u16)")
        |> replace_once!(
          "File::open(\"/proc/self/net/tcp\")",
          "File::open(format!(\"/proc/{pid}/net/tcp\"))"
        )
        |> replace_once!("let Some(inode) = table(port)?", "let Some(inode) = table(pid, port)?")
        |> replace_once!("if table(port)? != Some(inode)", "if table(pid, port)? != Some(inode)")
      else
        source
      end

    File.write!(listener, source)

    if kind == :output_loss do
      stdio = Path.join(native, "ipse-stdio.rs")
      source = File.read!(stdio)

      source =
        if reverted do
          replace_once!(
            source,
            "                    if !listener.as_ref().is_some_and(listener::Listener::inspection_pending) {\n" <>
              "                        let _ = child.wait();\n                    }\n",
            "                    let _ = child.wait();\n"
          )
        else
          source
        end

      anchor =
        "                    return Ok(());\n                }\n                if kind == b'E' {"

      injected =
        "                    #[cfg(ipse_probe_output_loss)] listener::diagnostic_after_output_loss(child.id(), listener.as_ref().is_some_and(listener::Listener::inspection_pending));\n"

      File.write!(stdio, replace_once!(source, anchor, injected <> anchor))

      File.write!(
        listener,
        """

        #[cfg(ipse_probe_output_loss)]
        pub fn diagnostic_after_output_loss(pid: u32, pending: bool) {
            let root = std::path::PathBuf::from(std::env::var("IPSE_LISTENER_PROBE_OUTPUT").unwrap());
            std::fs::write(root.join("pending"), pending.to_string()).unwrap();
            std::fs::write(root.join("child-pid.tmp"), pid.to_string()).unwrap();
            std::fs::rename(root.join("child-pid.tmp"), root.join("child-pid")).unwrap();
            let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
            while !root.join("release").is_file() && std::time::Instant::now() < deadline {
                std::thread::sleep(std::time::Duration::from_millis(1));
            }
        }
        """,
        [:append]
      )
    end

    generated =
      Path.wildcard(Path.join(native, "*.rs"))
      |> Map.new(&{Path.basename(&1), sha(File.read!(&1))})

    helper = Path.join(root, "helper")
    flags = if kind == :output_loss, do: ["--cfg", "ipse_probe_output_loss"], else: []

    {log, code} =
      System.cmd(
        "rustc",
        ["--edition=2021", "-D", "warnings", "--cfg", "ipse_probe_listener_barrier"] ++
          flags ++ [Path.join(native, "ipse-runner.rs"), "-o", helper],
        stderr_to_stdout: true
      )

    File.write!(Path.join(root, "compile.log"), log, [:exclusive])
    if code != 0, do: raise("diagnostic native compilation failed; retained compile.log")

    identity = %{
      "kind" => Atom.to_string(kind),
      "reverted" => reverted,
      "original_source" => original,
      "generated_diagnostic_source" => generated,
      "helper_sha256" => sha(File.read!(helper))
    }

    File.write!(Path.join(root, "identity.json"), JSON.encode!(identity) <> "\n", [
      :exclusive,
      :sync
    ])

    {helper, original}
  end

  def sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
