# Run from the source checkout: mix run scripts/verify-owned-listener-regressions.exs
# Requires Linux user/network/PID/mount namespaces; unavailable coverage exits 2.
unless match?({:unix, :linux}, :os.type()),
  do: raise("owned listener causal regressions require Linux")

[] = System.argv()
Code.require_file("../dev/platform/listener_regression/instrument.exs", __DIR__)
Code.require_file("../dev/platform/listener_regression/namespace.exs", __DIR__)
Code.require_file("../dev/platform/listener_regression/pid_namespace.exs", __DIR__)
{:ok, _} = Application.ensure_all_started(:ipse)
repository = Path.expand("..", __DIR__)

root =
  Path.join(
    System.tmp_dir!(),
    "ipse-listener-regressions-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  )

File.mkdir!(root)
File.chmod!(root, 0o700)

compile = fn source, output ->
  {log, code} =
    System.cmd("rustc", ["--edition=2021", "-D", "warnings", source, "-o", output],
      stderr_to_stdout: true
    )

  File.write!(output <> ".compile.log", log, [:exclusive])
  if code != 0, do: raise("diagnostic fixture compile failed; evidence retained")
end

fixture = Path.join(root, "fixture")
compile.(Path.join(repository, "dev/platform/owned_listener_probe.rs"), fixture)
loss_probe = Path.join(root, "output-loss-probe")
compile.(Path.join(repository, "dev/platform/listener_regression/output_loss.rs"), loss_probe)
pid_probe = Path.join(root, "pid-namespace-probe")
compile.(Path.join(repository, "dev/platform/listener_regression/pid_namespace.rs"), pid_probe)
current_helper = Path.join(root, "current-helper")
compile.(Path.join(repository, "native/ipse-runner.rs"), current_helper)

{helpers, originals} =
  for kind <- [:namespace, :output_loss], reverted <- [false, true], reduce: {%{}, nil} do
    {helpers, original} ->
      name = "#{kind}-#{if reverted, do: "reverted", else: "current"}"

      {helper, hashes} =
        Ipse.Development.Platform.ListenerRegression.Instrument.prepare!(
          repository,
          Path.join(root, name),
          kind,
          reverted
        )

      if original != nil and original != hashes,
        do: raise("production source changed during diagnostic preparation")

      {Map.put(helpers, {kind, reverted}, helper), hashes}
  end

previous = Process.flag(:trap_exit, true)

summary =
  try do
    namespace =
      Ipse.Development.Platform.ListenerRegression.Namespace.verify(
        helpers[{:namespace, false}],
        helpers[{:namespace, true}],
        fixture,
        Path.join(root, "namespace-evidence")
      )

    pid_namespace =
      Ipse.Development.Platform.ListenerRegression.PidNamespace.Controls.verify(
        pid_probe,
        current_helper,
        fixture,
        Path.join(root, "pid-namespace-evidence")
      )

    output_loss =
      for {reverted, expected} <- [{false, "retained"}, {true, "reaped"}], into: %{} do
        directory = Path.join(root, "output-evidence-#{expected}")

        {bytes, 0} =
          System.cmd(
            loss_probe,
            [helpers[{:output_loss, reverted}], fixture, directory, expected],
            stderr_to_stdout: true
          )

        value = JSON.decode!(bytes)

        true =
          value["pending_inspection"] and value["output_delivery_failed"] and
            value["helper_exited"] and value["diagnostic_cleanup_confirmed"]

        true = value["child_retained_unreaped"] == (expected == "retained")
        {expected, value}
      end

    for {name, hash} <- originals do
      true =
        Ipse.Development.Platform.ListenerRegression.Instrument.sha(
          File.read!(Path.join([repository, "native", name]))
        ) ==
          hash
    end

    %{
      "status" =>
        if(namespace["status"] == "passed" and pid_namespace["status"] == "passed",
          do: "passed",
          else: "incomplete"
        ),
      "namespace" => namespace,
      "pid_namespace" => pid_namespace,
      "output_loss" => output_loss,
      "inference_requests" => 0,
      "source_hashes" => originals,
      "fixture_sha256" =>
        Ipse.Development.Platform.ListenerRegression.Instrument.sha(File.read!(fixture)),
      "output_probe_sha256" =>
        Ipse.Development.Platform.ListenerRegression.Instrument.sha(File.read!(loss_probe)),
      "evidence" => root
    }
  after
    Process.flag(:trap_exit, previous)
  end

File.write!(Path.join(root, "summary.json"), JSON.encode!(summary) <> "\n", [:exclusive, :sync])
File.chmod!(Path.join(root, "summary.json"), 0o600)
IO.puts(JSON.encode!(summary))
if summary["status"] != "passed", do: System.halt(2)
