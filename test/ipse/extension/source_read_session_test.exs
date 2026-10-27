defmodule Ipse.Extension.SourceReadSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extension.{Artifact, Catalog, Config, Registry}

  defmodule Model do
    def complete(_, _, _, _),
      do: {:ok, %{"role" => "assistant", "content" => "Visible SDK fixture answer."}, %{}}
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-source-sdk-artifact-" <> Ipse.Usage.id())
    File.mkdir_p!(Path.join(root, "ebin"))
    on_exit(fn -> File.rm_rf!(root) end)
    name = "Independent.Sources#{System.unique_integer([:positive])}"
    capabilities = ~w(invoke.command host.actions host.sources)

    exports =
      Catalog.empty()
      |> Map.put("commands", [
        %{
          "id" => "inspect",
          "description" => "Read synthetic source evidence",
          "arguments_schema" => %{"type" => "object", "additionalProperties" => false},
          "result_schema" => %{"type" => "object"}
        }
      ])

    source = """
    defmodule #{name} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle("invoke.command", _, state), do: call(%{"op" => "source.list", "limit" => 32}, state)
      def handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => %{"sources" => rows} = value}}, state) do
        File.write!(state["trace"], Jason.encode!(value) <> "\\n", [:append])
        if state["hold"], do: Process.sleep(:infinity)
        row = Enum.find(rows, &(&1["kind"] == "input.original"))
        call(%{"op" => "source.read", "handle" => row["read_handle"]}, state)
      end
      def handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => %{"text" => _} = value}}, state) do
        File.write!(state["trace"], Jason.encode!(value) <> "\\n", [:append])
        call(%{"op" => "source.quote", "handle" => value["handle"], "quote" => "SDK café"}, state)
      end
      def handle("host.actions", %{"outcome" => outcome}, state) do
        File.write!(state["trace"], Jason.encode!(outcome) <> "\\n", [:append])
        {:ok, %{"api_version" => 1, "kind" => "result", "value" => outcome}, state}
      end
      defp call(request, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}
    end
    """

    file = Path.join(root, "fixture.ex")
    File.write!(file, source)

    assert {"", 0} =
             System.cmd(
               System.find_executable("elixirc"),
               [
                 "--erl",
                 "+S 2:2",
                 "-pa",
                 Application.app_dir(:ipse, "ebin"),
                 "-pa",
                 Application.app_dir(:jason, "ebin"),
                 "-o",
                 Path.join(root, "ebin"),
                 file
               ],
               stderr_to_stdout: true
             )

    File.write!(Path.join(root, "LICENSE"), "MIT synthetic fixture")

    files =
      for path <- ["LICENSE", "ebin/Elixir.#{name}.beam"] do
        bytes = File.read!(Path.join(root, path))
        %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
      end

    manifest = %{
      "format" => 1,
      "id" => "fixture/sources",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => name,
      "license_file" => "LICENSE",
      "files" => files,
      "capabilities" => capabilities,
      "exports" => exports,
      "options_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ~w(trace hold),
        "properties" => %{"trace" => %{"type" => "string"}, "hold" => %{"type" => "boolean"}}
      },
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      }
    }

    File.write!(Path.join(root, "extension.json"), Jason.encode!(manifest))
    File.rm!(file)
    %{artifact: root}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-source-sdk-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      home: Path.join(root, "home"),
      dir: Path.join(root, "state"),
      trace: Path.join(root, "trace")
    }
  end

  defp start(c, hold \\ false, id \\ nil) do
    {:ok, artifact} = Artifact.import(c.artifact, Path.join(c.home, "extensions/artifacts"))

    data = %{
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false
        }
      ],
      "extensions" => [
        %{
          "instance" => "sources",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => %{"trace" => c.trace, "hold" => hold},
          "order" => 0,
          "lifetime" => "session"
        }
      ]
    }

    {:ok, catalog} =
      Config.resolve([%{scope: "operator", path: "/fixture/sources.json", data: data}], [])

    {:ok, entries} = Registry.prepare(catalog, c.home)

    config = %{
      provider: :demo,
      model: "synthetic",
      provider_module: Model,
      home: c.home,
      approval: :deny,
      extensions: entries
    }

    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.root, state_dir: c.dir, subscriber: self(), id: id}
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)
    session
  end

  test "an independent SDK worker reads only the current Session through journaled source actions",
       c do
    session = start(c)
    assert :ok = Session.prompt(session, "SDK café original 雪")
    assert_receive {:ipse, ^session, {:done, :ok}}, 2000
    assert :ok = Session.invoke_export(session, :command, "ext__sources__inspect", %{})
    assert_receive {:ipse, ^session, {:done, :ok}}, 10_000
    rows = File.read!(c.trace) |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    assert length(rows) == 3
    assert Enum.at(rows, 1)["text"] == "SDK café original 雪"
    assert Enum.at(rows, 2)["status"] == "ok"
    assert get_in(Enum.at(rows, 2), ["value", "start_byte"]) == 0
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    assert {:ok, events} = Journal.load(c.dir, id)
    results = Enum.filter(events, &(&1["type"] == "extension_action_result"))
    assert Enum.map(results, & &1["request"]["op"]) == ~w(source.list source.read source.quote)

    assert Enum.all?(
             results,
             &(&1["approval"] == "not_required" and &1["outcome"]["status"] == "ok")
           )

    assert {:ok, _} = Session.Saved.restore(events, id)
    before = File.read!(c.trace)
    resumed = start(c, false, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(c.trace) == before
  end

  test "cancelling an actual source reader never resumes its old worker or publishes another page",
       c do
    session = start(c, true)
    assert :ok = Session.prompt(session, "SDK café cancellation")
    assert_receive {:ipse, ^session, {:done, :ok}}, 2000
    assert :ok = Session.invoke_export(session, :command, "ext__sources__inspect", %{})
    wait_trace(c.trace, 200)
    assert :ok = Session.cancel(session)
    assert_receive {:ipse, ^session, {:done, :cancelled}}, 2000
    before = File.read!(c.trace)
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    resumed = start(c, true, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(c.trace) == before
    assert length(String.split(before, "\n", trim: true)) == 1
  end

  defp wait_trace(_, 0), do: flunk("source worker did not receive its committed list page")

  defp wait_trace(path, left) do
    if File.exists?(path),
      do: :ok,
      else:
        (
          Process.sleep(10)
          wait_trace(path, left - 1)
        )
  end
end
