defmodule Ipse.Extensions.UsageReadTest do
  use ExUnit.Case, async: false
  alias Ipse.{Usage, Journal, Session}
  alias Ipse.Extensions.{UsageRead, Config, Registry, Catalog, Store, Actions}

  defmodule Model do
    def complete(config, _, _, emit) do
      emit.({:reason, "Synthetic hidden reasoning must stay private"})
      emit.({:provider_usage, %{"input_tokens" => 100, "output_tokens" => 1}})
      emit.({:provider_usage, %{"input_tokens" => 100, "output_tokens" => 3}})

      if config[:fail_model] do
        {:error, "Synthetic refusal"}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => "Synthetic private answer",
           "provider_data" => %{
             "reported_model" => "fixture",
             "opaque" => "Synthetic native secret"
           }
         }, %{"input_tokens" => 100, "output_tokens" => 20}}
      end
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-usage-reader-artifact-#{Usage.id()}")
    File.mkdir_p!(Path.join(root, "ebin"))
    module = "Independent.UsageReader#{System.unique_integer([:positive])}"
    caps = ~w(invoke.command host.actions host.usage)

    exports =
      Catalog.empty()
      |> Map.put("commands", [
        %{
          "id" => "read",
          "description" => "Read synthetic accounting",
          "arguments_schema" => %{"type" => "object"},
          "result_schema" => %{"type" => "object"}
        }
      ])

    file = Path.join(root, "reader.ex")

    File.write!(file, """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(caps)}, "exports" => #{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle("invoke.command", payload, state) do
        args = payload["arguments"]
        state = Map.put(state, "hold", args["hold"] == true)
        {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => %{
          "op" => "usage.read", "cursor" => Map.get(args, "cursor", 0), "limit" => Map.get(args, "limit", 4), "snapshot" => args["snapshot"]}}, state}
      end
      def handle("host.actions", payload, state) do
        if state["hold"] do
          File.write!((state["pid"]) <> ".ready-" <> System.pid(), System.pid()); File.rename!((state["pid"]) <> ".ready-" <> System.pid(), state["pid"]); Process.sleep(:infinity)
        end
        {:ok, %{"api_version" => 1, "kind" => "result", "value" => payload["outcome"]}, state}
      end
    end
    """)

    {_, 0} =
      System.cmd(
        System.find_executable("elixirc"),
        ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(root, "ebin"), file],
        stderr_to_stdout: true
      )

    File.write!(Path.join(root, "LICENSE"), "Synthetic fixture license")

    files =
      for path <- ["LICENSE", "ebin/Elixir.#{module}.beam"],
          bytes = File.read!(Path.join(root, path)),
          do: %{
            "path" => path,
            "bytes" => byte_size(bytes),
            "sha256" => Ipse.Extensions.Manifest.sha256(bytes)
          }

    File.write!(
      Path.join(root, "extension.json"),
      Jason.encode!(%{
        "format" => 1,
        "id" => "test/usage-reader",
        "version" => "1.0.0",
        "sdk" => 1,
        "protocol" => 1,
        "backend" => "elixir_worker",
        "entrypoint" => module,
        "capabilities" => caps,
        "exports" => exports,
        "license_file" => "LICENSE",
        "files" => files,
        "options_schema" => %{
          "type" => "object",
          "properties" => %{"pid" => %{"type" => "string"}}
        },
        "runtime" => %{
          "elixir" => ">= 1.18.0",
          "otp" => [String.to_integer(System.otp_release())],
          "platforms" => [to_string(:erlang.system_info(:system_architecture))]
        }
      })
    )

    on_exit(fn -> File.rm_rf!(root) end)
    %{artifact: root}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-usage-read-#{Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      home: Path.join(root, "home"),
      dir: Path.join(root, "sessions"),
      pid_file: Path.join(root, "worker.pid")
    }
  end

  defp configured(c, extra \\ %{}) do
    {:ok, artifact} = Store.import(c.artifact, Path.join(c.home, "extensions/artifacts"))

    data = %{
      "extensions" =>
        Enum.map(~w(reader other), fn name ->
          %{
            "instance" => name,
            "artifact" => artifact.digest,
            "enabled" => true,
            "options" => %{"pid" => c.pid_file},
            "order" => 0,
            "lifetime" => "persistent"
          }
        end),
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false
        }
      ]
    }

    {:ok, catalog} =
      Config.resolve([%{scope: "operator", path: "/fixture/usage.json", data: data}], [])

    {:ok, entries} = Registry.prepare(catalog, c.home)

    Map.merge(
      %{
        provider: :openai,
        model: "fixture",
        provider_module: Model,
        approval: :deny,
        compact: false,
        home: c.home,
        extensions: entries
      },
      extra
    )
  end

  defp start(c, config, id \\ nil) do
    result =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config, cwd: c.root, state_dir: c.dir, id: id, subscriber: self(), owner: self()}
      )

    if match?({:ok, _}, result) do
      {:ok, pid} = result
      on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    end

    result
  end

  defp done(pid, status \\ :ok), do: assert_receive({:ipse, ^pid, {:done, ^status}}, 15_000)

  defp read(pid, args \\ %{}, instance \\ "reader") do
    :ok = Session.invoke_export(pid, :command, "ext__#{instance}__read", args)
    done(pid)
    Session.info(pid).extension_result["value"]
  end

  defp prompt(pid) do
    :ok = Session.prompt(pid, "Synthetic private prompt")
    done(pid)
  end

  defp rows(c, pid), do: elem(Journal.load(c.dir, Session.info(pid).id), 1)
  defp eventually(fun, n \\ 200)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, n),
    do:
      if(fun.(),
        do: :ok,
        else:
          (
            Process.sleep(10)
            eventually(fun, n - 1)
          )
      )

  test "usage authority is explicit and grants neither history nor write access", c do
    cfg = configured(c)
    entry = hd(cfg.extensions)
    request = %{"op" => "usage.read", "cursor" => 0, "limit" => 4, "snapshot" => nil}
    response = %{"api_version" => 1, "kind" => "host_call", "request" => request}
    assert {:ok, ^request} = Actions.proposal(response, entry.identity)

    for capability <- ~w(host.usage host.actions) do
      identity =
        put_in(
          entry.identity["capabilities"],
          List.delete(entry.identity["capabilities"], capability)
        )

      assert {:error, _} = Actions.proposal(response, identity)
    end

    assert {:error, _} =
             Actions.proposal(
               put_in(response["request"], %{
                 "op" => "state.get",
                 "scope" => "project",
                 "key" => "x"
               }),
               entry.identity
             )

    assert Catalog.validate(entry.exports, ~w(invoke.command host.usage)) != :ok
    assert UsageRead.validate(Map.put(request, "session_id", Usage.id())) != :ok
    assert UsageRead.validate(Map.put(request, "limit", 5)) != :ok
  end

  test "independent worker reads latest cumulative usage without private content or inference",
       c do
    {:ok, pid} =
      start(c, configured(c, %{base_url: "https://example.test/synthetic-endpoint-secret"}))

    prompt(pid)
    assert %{"status" => "ok", "value" => page} = read(pid)

    assert [
             %{
               "usage" => %{
                 "counts" => %{
                   "input_tokens" => 100,
                   "output_tokens" => 20,
                   "total_tokens" => 120
                 }
               },
               "finality" => "final"
             }
           ] = page["requests"]

    assert page["snapshot"]["request_count"] == 1
    assert Session.info(pid).accounting["request_count"] == 1
    encoded = Jason.encode!(page)

    for private <- [
          "Synthetic private",
          "Synthetic native",
          "Synthetic hidden",
          "synthetic-endpoint-secret"
        ],
        do: refute(encoded =~ private)

    assert byte_size(encoded) <= 12_288
    assert UsageRead.validate_sources(c.dir, Session.info(pid).id, rows(c, pid)) == :ok
    refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 30
  end

  test "request pages exceed the latest-sixteen display and freeze their admitted prefix", c do
    {:ok, pid} = start(c, configured(c))
    for _ <- 1..18, do: prompt(pid)
    assert %{"status" => "ok", "value" => first} = read(pid)
    assert length(first["requests"]) == 4
    assert first["next"] == 4
    prompt(pid)
    assert %{"value" => last} = read(pid, %{"cursor" => 16, "snapshot" => first["snapshot"]})
    assert length(last["requests"]) == 2
    assert last["next"] == nil
    assert last["snapshot"] == first["snapshot"]
    assert Session.info(pid).accounting["request_count"] == 19
    assert %{"value" => fresh} = read(pid, %{"cursor" => 16})
    assert length(fresh["requests"]) == 3
    assert %{"value" => same} = read(pid, %{"cursor" => 0, "snapshot" => first["snapshot"]})
    assert same == first

    assert %{"status" => "failed", "value" => %{"code" => "usage_cursor"}} =
             read(pid, %{"cursor" => 19, "snapshot" => first["snapshot"]})
  end

  test "snapshot admission rejects altered, other-instance and other-session references", c do
    cfg = configured(c)
    {:ok, pid} = start(c, cfg)
    prompt(pid)
    %{"value" => page} = read(pid)
    s = page["snapshot"]

    for snapshot <- [Map.put(s, "request_count", 2), Map.put(s, "operation_id", Usage.id())] do
      assert %{"status" => "failed", "value" => %{"code" => "usage_snapshot"}} =
               read(pid, %{"snapshot" => snapshot})
    end

    assert %{"status" => "failed"} = read(pid, %{"snapshot" => s}, "other")
    {:ok, other} = start(c, cfg)
    assert %{"status" => "failed"} = read(other, %{"snapshot" => s})
  end

  test "partial failed and historical unknown requests are not synthesized as successful zero",
       c do
    {:ok, pid} = start(c, configured(c, %{fail_model: true}))
    :ok = Session.prompt(pid, "Synthetic private prompt")
    done(pid, :error)
    assert %{"value" => %{"requests" => [r]}} = read(pid)
    assert r["outcome"] == "failed"
    assert r["finality"] == "partial"
    assert r["usage"]["counts"]["output_tokens"] in [nil, 1, 3]
    header = %{"type" => "session", "metadata" => %{}}
    a = Usage.admission(Usage.id(), %{provider: :openai, model: "fixture"}, "model", Usage.id())
    {:ok, ledger} = Usage.restore([header, a])
    assert ledger.legacy_unmetered
    record = Usage.request_record(ledger.requests[a["request_id"]])
    assert Usage.valid_request_record?(record)
    assert record["outcome"] == "unknown"
    assert record["usage"]["counts"]["output_tokens"] == nil
  end

  test "idle resume validates cached pages and restores their exact snapshot without replay", c do
    cfg = configured(c)
    {:ok, pid} = start(c, cfg)
    prompt(pid)
    %{"value" => page} = read(pid)
    id = Session.info(pid).id
    :ok = Session.close(pid)
    path = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(path)
    {:ok, resumed} = start(c, cfg, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(path) == before
    assert %{"value" => ^page} = read(resumed, %{"snapshot" => page["snapshot"]})
    :ok = Session.close(resumed)
    assert {:ok, _} = Ipse.Diagnostics.saved(c.dir, id)
  end

  test "a structurally coherent changed page fails saved accounting validation before tail repair",
       c do
    cfg = configured(c)
    {:ok, pid} = start(c, cfg)
    prompt(pid)
    read(pid)
    events = rows(c, pid)
    id = Session.info(pid).id
    :ok = Session.close(pid)

    first =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "usage.read")
      )

    [request] = first["outcome"]["value"]["requests"]

    changed =
      put_in(
        request["usage"],
        Ipse.Usage.Normalizer.normalize(:openai, %{"input_tokens" => 100, "output_tokens" => 21})
      )

    outcome = put_in(first["outcome"]["value"]["requests"], [changed])["outcome"]
    assert {:ok, forged} = Actions.result(Actions.result_intent(first), outcome)
    altered = Enum.map(events, &if(&1 == first, do: forged, else: &1))
    assert {:error, _} = UsageRead.restore(altered)
    path = Path.join(c.dir, id <> ".jsonl")
    bytes = Enum.map_join(altered, "\n", &Jason.encode!/1) <> "\n" <> "{torn"
    File.write!(path, bytes)
    assert {:error, _} = start(c, cfg, id)
    assert File.read!(path) == bytes
    assert {:error, _} = Ipse.Diagnostics.saved(c.dir, id)
  end

  test "cancel stops an independent post-read callback and does not replay its invocation", c do
    cfg = configured(c)
    {:ok, pid} = start(c, cfg)
    :ok = Session.invoke_export(pid, :command, "ext__reader__read", %{"hold" => true})
    eventually(fn -> File.exists?(c.pid_file) end)
    :ok = Session.cancel(pid)
    done(pid, :cancelled)
    id = Session.info(pid).id
    :ok = Session.close(pid)
    path = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(path)
    {:ok, resumed} = start(c, cfg, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(path) == before
    assert Session.info(resumed).accounting["request_count"] == 0
  end

  test "a self-consistent snapshot must resolve the actual initial read intent", c do
    {:ok, pid} = start(c, configured(c))
    prompt(pid)
    read(pid)
    events = rows(c, pid)
    id = Session.info(pid).id

    first =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "usage.read")
      )

    {:ok, source} = Ipse.Lifecycle.Source.build(id, 0, hd(events))
    {:ok, reference} = Ipse.Lifecycle.Source.metadata(source)
    value = put_in(first["outcome"]["value"]["snapshot"]["source"], reference)["outcome"]["value"]

    {:ok, forged} =
      Actions.result(Actions.result_intent(first), %{"status" => "ok", "value" => value})

    altered = Enum.map(events, &if(&1 == first, do: forged, else: &1))
    assert {:ok, _} = UsageRead.restore(altered)
    assert {:error, _} = UsageRead.validate_sources(c.dir, id, altered)
  end

  test "the snapshot ceiling refuses fresh ranges without invalidating admitted pages", c do
    {:ok, pid} = start(c, configured(c))
    prompt(pid)
    %{"value" => page} = read(pid)
    events = rows(c, pid)
    {:ok, ledger} = Usage.restore(events)

    intent =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_intent" and &1["request"]["op"] == "usage.read")
      )

    s = page["snapshot"]

    snapshots =
      Map.new(1..UsageRead.limit(), &{Integer.to_string(&1), s}) |> Map.put(s["operation_id"], s)

    assert {:failed, %{"code" => "usage_limit"}} =
             UsageRead.prepare(ledger, snapshots, intent, s["source"])

    reuse = put_in(intent["request"]["snapshot"], s)
    assert {:ok, ^page} = UsageRead.prepare(ledger, snapshots, reuse)
    refute Usage.valid_request_record?(Map.put(hd(page["requests"]), "native", "excluded"))
  end
end
