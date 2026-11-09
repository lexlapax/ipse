defmodule Ipse.CLI.InferenceTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-inference-cli-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    cwd = Path.join(root, "workspace")
    File.mkdir!(cwd)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, home: Path.join(root, "unused-home"), cwd: cwd}
  end

  test "fresh status creates no operator home or conversation configuration", c do
    output =
      capture_io(fn ->
        assert Ipse.CLI.Inference.run(["status"], [json: true], c.home, c.root) == 0
      end)

    assert %{"services" => %{}, "queue" => [], "recent" => [], "revision" => 0} =
             Jason.decode!(output)

    refute File.exists?(c.home)
  end

  test "CLI status ignores malformed conversation config and refuses redirected service state",
       c do
    config = Path.join(c.root, "private-config.json")
    File.write!(config, "malformed synthetic configuration")
    previous = Map.new(~w(IPSE_HOME IPSE_CONFIG), &{&1, System.get_env(&1)})
    System.put_env("IPSE_HOME", c.home)
    System.put_env("IPSE_CONFIG", config)

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    output = capture_io(fn -> assert Ipse.CLI.run(["inference", "status", "--json"]) == 0 end)
    assert Jason.decode!(output)["services"] == %{}
    assert File.read!(config) == "malformed synthetic configuration"
    refute File.exists?(c.home)
    File.mkdir!(c.home)
    target = Path.join(c.root, "external")
    File.mkdir!(target)
    File.ln_s!(target, Path.join(c.home, "inference-services"))
    capture_io(:stderr, fn -> assert Ipse.CLI.run(["inference", "status"]) == 1 end)
    assert File.ls!(target) == []
  end

  test "unsupported flags and noncanonical selections refuse before protected state", c do
    for {command, opts} <- [
          {["status"], [yes: true]},
          {["reconcile", "local", String.duplicate("a", 32), "0"], [yes: true]},
          {["reconcile", "local", String.duplicate("a", 32), "00"], []},
          {["reconcile", "local", String.duplicate("a", 32), "0"], [json: true]},
          {["reconcile", "../escape", String.duplicate("a", 32), "0"], []},
          {["reconcile", "local", "invalid", "0"], []},
          {["reconcile", "local", String.duplicate("a", 32), "9007199254740992"], []}
        ] do
      capture_io(:stderr, fn ->
        assert Ipse.CLI.Inference.run(command, opts, c.home, c.root) == 1
      end)

      refute File.exists?(c.home)
    end
  end

  test "protected status preserves ledger bytes and reports unresolved service identity", c do
    alias Ipse.InferenceSlots.{Ledger, Store}
    File.mkdir!(c.home)
    File.chmod!(c.home, 0o700)

    case Store.context(c.home, c.cwd) do
      {:error, :service_filesystem_unsupported} ->
        capture_io(:stderr, fn ->
          assert Ipse.CLI.Inference.run(["status"], [], c.home, c.cwd) == 1
        end)

        IO.puts("Protected status positive NOT RUN: unsupported filesystem refusal verified")

      {:ok, context} ->
        id = Ipse.Usage.id()
        now = System.system_time(:millisecond)

        meta = %{
          "session_id" => Ipse.Usage.id(),
          "project_id" => Ipse.JSON.sha256("project"),
          "request_sha256" => Ipse.JSON.sha256("request"),
          "route_sha256" => Ipse.JSON.sha256("route"),
          "priority" => "foreground",
          "dispatch_timeout_ms" => 5000
        }

        {:ok, _} =
          Store.transaction(context, fn state ->
            {:ok, queued, _} =
              Ledger.enqueue(state, "local", ["http://127.0.0.1:11434"], id, meta, now, 5000)

            Ledger.admit(queued, id, now)
          end)

        path = Path.join(context.root, "control.json")
        before = File.read!(path)

        output =
          capture_io(fn ->
            assert Ipse.CLI.Inference.run(["status"], [json: true], c.home, c.cwd) == 0
          end)

        report = Jason.decode!(output)
        assert report["services"]["local"]["active"]["id"] == id
        assert report["services"]["local"]["origins"] == ["http://127.0.0.1:11434"]

        assert report["active_meaning"] ==
                 "unresolved_until_known_terminal_or_operator_reconciliation"

        assert File.read!(path) == before
    end
  end

  @tag :inference_tty
  @tag timeout: 120_000
  @tag :native_storage
  test "native exact reconciliation and cancellation, stale, pipe and concurrent-revision refusal",
       c do
    driver = Path.join(c.root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    for {scenario, mode} <- [
          {"confirm", "--review"},
          {"cancel", "--review-cancel"},
          {"stale", "--review-stale"},
          {"pipe", nil},
          {"race", "--review-guarded"}
        ] do
      root = Path.join(c.root, scenario)
      File.mkdir!(root)
      File.chmod!(root, 0o700)

      args =
        ["--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/inference_reconciliation.exs"), root, scenario]

      {command, args} =
        if mode,
          do: {driver, [mode, System.find_executable("elixir") | args]},
          else: {System.find_executable("elixir"), args}

      {output, status} = System.cmd(command, args, stderr_to_stdout: true)
      assert status == 0, output

      assert output =~
               if(scenario == "confirm",
                 do: "INFERENCE_RECONCILIATION_CONFIRMED",
                 else: "INFERENCE_RECONCILIATION_REFUSED"
               )
    end
  end
end
