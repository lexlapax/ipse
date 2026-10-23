defmodule Ipse.CLISessionsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-cli-sessions-#{System.unique_integer([:positive])}")
    home = Path.join(root, "home")
    File.mkdir_p!(home)
    previous = System.get_env("IPSE_HOME")
    System.put_env("IPSE_HOME", home)

    on_exit(fn ->
      if previous, do: System.put_env("IPSE_HOME", previous), else: System.delete_env("IPSE_HOME")
      File.rm_rf!(root)
    end)

    %{root: root, home: home, dir: Path.join(home, "sessions")}
  end

  test "resume discovers only a header before applying each lowered operator journal bound", c do
    alias Ipse.Journal
    Code.ensure_loaded!(Journal)
    :erlang.trace_pattern({Journal, :read_path, 3}, true, [:local])

    try do
      for policy <- [
            %{"max_bytes" => 1_024},
            %{"max_events" => 2},
            %{"max_record_bytes" => 512}
          ] do
        {:ok, id} =
          Ipse.Journal.create(c.dir, %{
            "provider" => "demo",
            "model" => "fixture",
            "cwd" => c.root
          })

        path = Path.join(c.dir, id <> ".jsonl")

        File.write!(
          path,
          String.duplicate(Jason.encode!(%{"padding" => String.duplicate("x", 700)}) <> "\n", 3),
          [:append]
        )

        before = File.read!(path)
        operator = Path.join(c.home, "config.json")
        File.write!(operator, Jason.encode!(%{"version" => 1, "journal" => policy}))

        task =
          Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
            receive do: (:go -> :ok)

            capture_io(:stderr, fn ->
              assert 1 == Ipse.CLI.run(["chat", "--resume", id, "--state-dir", c.dir])
            end)
          end)

        :erlang.trace(task.pid, true, [:call, {:tracer, self()}])
        send(task.pid, :go)
        output = Task.await(task, 5_000)
        assert output =~ "Journal resource limit reached"
        pid = task.pid
        assert_receive {:trace, ^pid, :call, {Journal, :read_path, [^path, nil, :header]}}
        refute_receive {:trace, ^pid, :call, {Journal, :read_path, [_, nil, :load]}}, 0
        assert File.read!(path) == before
      end
    after
      :erlang.trace_pattern({Journal, :read_path, 3}, false, [:local])
    end
  end

  test "JSON is one sorted array with only public listing fields", c do
    first = String.duplicate("1", 32)
    last = String.duplicate("f", 32)
    cwd = "/synthetic/quoted \"workspace\"/雪\nnext\e[8m\u202E\u{E0001}"

    put_journal(c.dir, last, %{"provider" => "demo", "model" => "last", "cwd" => "/last"})

    put_journal(c.dir, first, %{
      "provider" => "demo",
      "model" => "first",
      "cwd" => cwd,
      "private_marker" => "synthetic-private-metadata",
      "configuration" => %{"token" => "synthetic-private-token"},
      "id" => "metadata-cannot-replace-id"
    })

    :ok =
      Ipse.Journal.append(c.dir, first, %{
        "type" => "message",
        "message" => %{"role" => "user", "content" => "synthetic-private-message"}
      })

    before = snapshot(c.dir)
    output = listing(["--json"])

    assert Jason.decode!(output) == [
             %{"id" => first, "provider" => "demo", "model" => "first", "cwd" => cwd},
             %{"id" => last, "provider" => "demo", "model" => "last", "cwd" => "/last"}
           ]

    assert length(String.split(output, "\n", trim: true)) == 1
    refute output =~ "\e"
    refute output =~ "\u202E"
    refute output =~ "\u{E0001}"
    refute output =~ "synthetic-private"
    refute output =~ "metadata-cannot-replace-id"
    assert snapshot(c.dir) == before
  end

  test "absent metadata fields and explicit nil values become JSON null", c do
    first = String.duplicate("2", 32)
    last = String.duplicate("3", 32)
    put_journal(c.dir, first, %{})
    put_journal(c.dir, last, %{"provider" => "demo", "model" => nil})

    assert Jason.decode!(listing(["--json"])) == [
             %{"id" => first, "provider" => nil, "model" => nil, "cwd" => nil},
             %{"id" => last, "provider" => "demo", "model" => nil, "cwd" => nil}
           ]
  end

  test "default text output and explicit no-json preserve the existing format", c do
    first = String.duplicate("4", 32)
    last = String.duplicate("5", 32)
    put_journal(c.dir, last, %{})

    put_journal(c.dir, first, %{"provider" => "demo", "model" => "fixture", "cwd" => "/space dir"})

    expected = "#{first}  demo/fixture  /space dir\n#{last}  /  \n"

    assert listing([]) == expected
    assert listing(["--no-json"]) == expected
  end

  test "missing stores emit an empty JSON array without creating directories", c do
    assert listing(["--json"]) == "[]\n"
    assert listing([]) == ""
    refute File.exists?(c.dir)
    assert File.ls!(c.home) == []
  end

  test "empty stores emit an empty JSON array and no text", c do
    File.mkdir_p!(c.dir)
    assert listing(["--json"]) == "[]\n"
    assert listing([]) == ""
    assert File.ls!(c.dir) == []
  end

  test "listing skips invalid journals and tolerates a truncated tail without repair", c do
    valid = String.duplicate("6", 32)
    corrupt = String.duplicate("7", 32)
    non_session = String.duplicate("8", 32)
    empty = String.duplicate("9", 32)
    put_journal(c.dir, valid, %{"provider" => "demo", "model" => "tail", "cwd" => "/fixture"})
    File.write!(Path.join(c.dir, valid <> ".jsonl"), "{\"type\":", [:append])
    File.write!(Path.join(c.dir, corrupt <> ".jsonl"), "not-json\n")
    File.write!(Path.join(c.dir, non_session <> ".jsonl"), "{\"type\":\"message\"}\n")
    File.write!(Path.join(c.dir, empty <> ".jsonl"), "")
    put_journal(c.dir, "invalid-id", %{"provider" => "synthetic-private-invalid"})
    File.write!(Path.join(c.dir, "unrelated.txt"), "synthetic-private-unrelated")
    before = snapshot(c.dir)

    assert Jason.decode!(listing(["--json"])) == [
             %{"id" => valid, "provider" => "demo", "model" => "tail", "cwd" => "/fixture"}
           ]

    assert listing([]) == "#{valid}  demo/tail  /fixture\n"
    assert snapshot(c.dir) == before
  end

  test "explicit state-dir uses only that store without auth or session creation", c do
    other = Path.join(c.root, "selected")
    id = String.duplicate("a", 32)
    put_journal(other, id, %{"provider" => "demo", "model" => "selected", "cwd" => "/selected"})
    put_journal(c.dir, String.duplicate("b", 32), %{"model" => "synthetic-private-other-store"})
    before = snapshot(other)
    home_before = snapshot(c.dir)
    sessions_before = DynamicSupervisor.which_children(Ipse.Sessions)

    assert Jason.decode!(listing(["--json", "--state-dir", other])) == [
             %{"id" => id, "provider" => "demo", "model" => "selected", "cwd" => "/selected"}
           ]

    assert snapshot(other) == before
    assert snapshot(c.dir) == home_before
    assert File.ls!(c.home) == ["sessions"]
    assert DynamicSupervisor.which_children(Ipse.Sessions) == sessions_before
  end

  test "help advertises the sessions JSON option" do
    output = capture_io(fn -> assert Ipse.CLI.run(["--help"]) == 0 end)
    assert output =~ "ipse sessions [--json]"
    assert output =~ "--json"
    assert output =~ "id/provider/model/cwd"
  end

  defp listing(options) do
    capture_io(fn ->
      assert capture_io(:stderr, fn -> assert Ipse.CLI.run(["sessions" | options]) == 0 end) == ""
    end)
  end

  defp put_journal(dir, id, metadata) do
    File.mkdir_p!(dir)

    File.write!(
      Path.join(dir, id <> ".jsonl"),
      Jason.encode!(%{"type" => "session", "metadata" => metadata}) <> "\n"
    )
  end

  defp snapshot(dir) do
    Map.new(File.ls!(dir), fn name -> {name, File.read!(Path.join(dir, name))} end)
  end
end
