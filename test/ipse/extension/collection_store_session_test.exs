defmodule Ipse.Extension.CollectionStoreSessionTest do
  use ExUnit.Case, async: false
  import Ipse.Test.ResumeAssertions
  @moduletag :document_store_boundary
  alias Ipse.{Session, Journal, JSON, Usage}

  alias Ipse.Extension.{
    Artifact,
    Catalog,
    Config,
    Registry,
    ProjectIdentity,
    CollectionStore,
    Actions
  }

  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.Profile

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("storage fixture attempted inference")
  end

  setup_all do
    source = Path.join(System.tmp_dir!(), "ipse-document-store-artifact-" <> Usage.id())
    File.mkdir_p!(Path.join(source, "ebin"))
    on_exit(fn -> File.rm_rf!(source) end)
    name = "Independent.DocumentStore#{System.unique_integer([:positive])}"
    caps = ~w(invoke.command host.actions host.actions.mixed host.collection.store)

    exports =
      Map.put(Catalog.empty(), "commands", [
        %{
          "id" => "exercise",
          "description" => "Exercise bounded document storage",
          "arguments_schema" => %{"type" => "object"},
          "result_schema" => %{"type" => "object"}
        }
      ])

    code = """
    defmodule #{name} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(caps)}, "exports" => #{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle("invoke.command", %{"arguments" => %{"mode" => "stage_request", "request" => request}}, _state) do
        call(%{"op" => "snapshot"}, %{"step" => "stage_request", "request" => request})
      end
      def handle("invoke.command", %{"arguments" => %{"mode" => "layout"} = args}, _state) do
        call(%{"op" => "snapshot"}, %{"step" => "layout_boot", "args" => args})
      end
      def handle("invoke.command", %{"arguments" => %{"mode" => "inventory"} = args}, _state) do
        call(%{"op" => "snapshot"}, %{"step" => "inventory_boot", "keys" => [], "args" => args})
      end
      def handle("invoke.command", payload, state) do
        bytes = Jason.encode!(%{"paragraphs" => for(n <- 1..9, do: Integer.to_string(n) <> ":" <> String.duplicate("x",4096))})
        epoch = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
        state = Map.merge(state, %{"bytes" => bytes, "sha256" => hash(bytes), "epoch" => epoch,
          "step" => "open", "offset" => 0, "result" => "", "mode" => payload["arguments"]["mode"]})
        call(%{"op" => "snapshot"}, state)
      end
      def handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => wrapped}}, state) do
        result = wrapped["result"]
        next(state["step"], result, Map.put(state,"generation",result["generation"]))
      end
      def handle("host.actions", %{"outcome" => outcome}, state), do: {:ok,%{"api_version" => 1,"kind" => "result", "value" => outcome},state}
      defp next("inventory_boot", result, s) do
        request = %{"op" => "value.index", "generation" => result["generation"] + (s["args"]["generation_delta"] || 0),
          "after" => s["args"]["after"], "limit" => 16}
        call(request, Map.put(s,"step","inventory_page"))
      end
      defp next("stage_request", result, s) do
        call(Map.put(s["request"], "generation", result["generation"]), Map.put(s,"step","layout_result"))
      end
      defp next("layout_boot", result, s) do
        call(%{"op" => "value.layout", "generation" => result["generation"] + (s["args"]["generation_delta"] || 0),
          "key" => s["args"]["key"] || "layout.fixture"}, Map.put(s,"step","layout_result"))
      end
      defp next("layout_result", result, s), do: {:ok,%{"api_version" => 1,"kind" => "result", "value" => result},s}
      defp next("inventory_page", result, s) do
        keys = s["keys"] ++ Enum.map(result["records"], & &1["key"])
        if result["next"] do
          call(%{"op" => "value.index", "generation" => result["generation"], "after" => result["next"], "limit" => 16}, Map.put(s,"keys",keys))
        else
          {:ok,%{"api_version" => 1,"kind" => "result", "value" => %{"keys" => keys, "count" => result["count"], "coverage" => result["coverage"]}},s}
        end
      end
      defp next("open", _, s) do
        call(%{"op" => "value.open", "slot" => 0, "epoch" => s["epoch"], "key" => "packed.fixture",
          "expected_revision" => 0, "byte_count" => byte_size(s["bytes"]), "sha256" => s["sha256"],
          "generation" => s["generation"]}, Map.put(s,"step","append"))
      end
      defp next("append", _, s) do
        offset = s["offset"]
        if offset < byte_size(s["bytes"]) do
          n = min(6144,byte_size(s["bytes"])-offset)
          call(%{"op" => "value.append", "slot" => 0, "epoch" => s["epoch"], "offset" => offset,
            "data" => binary_part(s["bytes"],offset,n), "generation" => s["generation"]}, Map.put(s,"offset",offset+n))
        else
          call(%{"op" => "value.seal", "slot" => 0, "epoch" => s["epoch"], "generation" => s["generation"]},Map.put(s,"step","commit"))
        end
      end
      defp next("commit", _, s) do
        call(%{"op" => "commit", "stages" => [%{"slot" => 0, "epoch" => s["epoch"]}],
          "generation" => s["generation"]},Map.put(s,"step","read"))
      end
      defp next("read", _, s), do: page(s,0)
      defp next("page", result, s) do
        s = Map.put(s,"result",s["result"]<>result["data"])
        if result["next"] do
          page(s,result["next"])
        else
          {:ok,%{"api_version" => 1,"kind" => "result", "value" => %{"equal" => s["result"]===s["bytes"],
            "sha256" => hash(s["result"]), "byte_count" => byte_size(s["result"])}},s}
        end
      end
      defp page(s,offset), do: call(%{"op" => "value.read", "key" => "packed.fixture", "offset" => offset,
        "generation" => s["generation"]},Map.put(s,"step","page"))
      defp call(inner,state), do: {:ok,%{"api_version" => 1,"kind" => "host_call",
        "request" => %{"op" => "collection.store","scope" => "project","request" => inner}},state}
      defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256,bytes),case: :lower)
    end
    """

    path = Path.join(source, "fixture.ex")
    File.write!(path, code)

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
                 Path.join(source, "ebin"),
                 path
               ],
               stderr_to_stdout: true
             )

    File.rm!(path)
    File.write!(Path.join(source, "LICENSE"), "MIT synthetic fixture")

    files =
      for path <- ["LICENSE", "ebin/Elixir.#{name}.beam"] do
        bytes = File.read!(Path.join(source, path))
        %{"path" => path, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
      end

    File.write!(
      Path.join(source, "extension.json"),
      Jason.encode!(%{
        "format" => 1,
        "id" => "fixture/document-store",
        "version" => "0.1.0",
        "sdk" => 1,
        "protocol" => 1,
        "backend" => "elixir_worker",
        "entrypoint" => name,
        "license_file" => "LICENSE",
        "files" => files,
        "capabilities" => caps,
        "exports" => exports,
        "options_schema" => %{"type" => "object"},
        "runtime" => %{
          "elixir" => ">= 1.18.0",
          "otp" => [String.to_integer(System.otp_release())],
          "platforms" => [to_string(:erlang.system_info(:system_architecture))]
        }
      })
    )

    %{source: source}
  end

  defp open(c, options \\ []) do
    dir = Path.join(System.tmp_dir!(), "ipse-document-store-session-" <> Usage.id())
    home = Path.join(dir, "home")
    cwd = Path.join(dir, "workspace")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, artifact} = Artifact.import(c.source, Path.join(home, "extensions/artifacts"))

    trust = %{
      "artifact" => artifact.digest,
      "capabilities" => artifact.manifest["capabilities"],
      "allow_project" => false,
      "allow_children" => false,
      "collection_bindings" => [
        %{
          "instance" => "documents",
          "version" => 1,
          "id" => "documents",
          "scope" => "project",
          "profile" => Profile.documents()
        }
      ]
    }

    data = %{
      "extensions" => [
        %{
          "instance" => "documents",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => %{},
          "order" => 0,
          "lifetime" => "session"
        }
      ],
      "extension_trust" => [trust]
    }

    {:ok, selected} =
      Config.resolve([%{scope: "operator", path: "/fixture/config.json", data: data}], [])

    {:ok, entries} = Registry.prepare(selected, home)

    binding =
      if Keyword.get(options, :admit, true),
        do: elem(ProjectIdentity.admit(home, cwd, :folder), 1)

    config = %{
      provider: :demo,
      provider_module: NoModel,
      model: "synthetic",
      home: home,
      extensions: entries,
      approval: Keyword.get(options, :approval, :ask),
      approval_origin: :interactive,
      headless: false,
      compact: false
    }

    opts = [config: config, cwd: cwd, state_dir: Path.join(home, "sessions"), subscriber: self()]
    assert {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)

    %{
      pid: pid,
      id: Session.info(pid).id,
      opts: opts,
      dir: opts[:state_dir],
      home: home,
      binding: binding,
      data: data
    }
  end

  defp wait(run, approvals \\ 0, allow_refusal \\ false) do
    receive do
      {:ipse, pid, {:approval, ref, "extension:collection.store", proposed}}
      when pid == run.pid ->
        assert CollectionStore.validate(proposed["request"]) == :ok
        assert proposed["effect_binding"]["project"] === run.binding
        assert proposed["effect_binding"]["profile"] == Profile.documents()
        assert :ok = Session.approve(pid, ref, true)
        wait(run, approvals + 1, allow_refusal)

      {:ipse, pid, {:done, :ok}} when pid == run.pid ->
        {Session.info(pid).extension_result, approvals}

      {:ipse, pid, {:error, error}} when pid == run.pid ->
        {:ok, events} = Journal.load(run.dir, run.id)

        trace =
          for event <- events,
              event["type"] in ~w(extension_action_intent extension_action_result extension_invocation_result),
              do:
                {event["type"], get_in(event, ["request", "request", "op"]),
                 get_in(event, ["outcome", "status"]), get_in(event, ["outcome", "value"])}

        if allow_refusal,
          do: {nil, approvals},
          else:
            flunk(
              "document store error: #{inspect({error, trace}, limit: :infinity, printable_limit: 2000)}"
            )

      {:ipse, pid, _} when pid == run.pid ->
        wait(run, approvals, allow_refusal)
    after
      20_000 -> flunk("document store timed out")
    end
  end

  @tag :document_decision_session
  test "actual Session transports every bounded part, asks full mutation arguments and reconstructs exact large value",
       c do
    run = open(c)
    assert :ok = Session.invoke_export(run.pid, :command, "ext__documents__exercise", %{})
    {result, approvals} = wait(run)
    assert result["value"]["equal"] == true, inspect(result)
    assert result["value"]["byte_count"] > 32_768
    assert approvals == 10
    id = Session.info(run.pid).id
    {:ok, events} = Journal.load(run.dir, id)
    actions = Enum.filter(events, &(&1["type"] == "extension_action_result"))
    assert length(actions) > 16
    assert Enum.all?(actions, &Actions.valid_result?/1)
    assert Enum.all?(actions, &(Ipse.Extension.validate(Actions.resume(&1)) == :ok))
    assert Enum.count(actions, &(get_in(&1, ["request", "request", "op"]) == "value.append")) == 7
    assert Enum.all?(actions, &(&1["approval"] != "saved_consent"))
    namespace = CollectionStore.namespace(run.binding["project_id"])

    assert {:ok, %{"record" => nil}} =
             Collection.execute_profile(
               CollectionStore.root(run.home),
               namespace,
               %{"op" => "get", "key" => "host.stage.0.header"},
               Usage.id(),
               Profile.documents()
             )

    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  @tag :document_maintenance_session
  test "actual SDK keeps old stages fenced after close while fresh approved publication succeeds",
       c do
    run = open(c)
    root = CollectionStore.root(run.home)
    namespace = CollectionStore.namespace(run.binding["project_id"])
    epoch = Usage.id()
    bytes = Jason.encode!(%{"text" => "original staged document"})

    request = %{
      "op" => "value.prepare_inline",
      "slot" => 0,
      "epoch" => epoch,
      "key" => "old.staged",
      "expected_revision" => 0,
      "byte_count" => byte_size(bytes),
      "sha256" => JSON.sha256(bytes),
      "data" => bytes
    }

    assert :ok =
             Session.invoke_export(run.pid, :command, "ext__documents__exercise", %{
               "mode" => "stage_request",
               "request" => request
             })

    {prepared, 1} = wait(run)
    assert prepared["value"]["stage"]["state"] === "sealed"

    assert {:ok, %{"record" => header}} =
             Collection.execute_profile(
               root,
               namespace,
               %{"op" => "get", "key" => "host.stage.0.header"},
               Usage.id(),
               Profile.documents()
             )

    owner = header["value"]["owner"]
    assert owner["session_id"] === run.id
    assert {:ok, before} = Collection.document_snapshot(root, namespace)
    close_id = Usage.id()

    opening = %{
      "op" => "maintenance.open",
      "expected_generation" => before["generation"],
      "expected_epoch" => 0,
      "maintenance_id" => Usage.id(),
      "purpose" => "checkpoint_inspection",
      "close_operation_id" => close_id
    }

    # The internal transition is trusted fixture setup, not a public maintenance grant.
    assert {:ok, opened} =
             Collection.document_maintenance(root, namespace, opening, Usage.id(), owner)

    assert {:ok, _} =
             Collection.document_maintenance(
               root,
               namespace,
               %{
                 "op" => "maintenance.close",
                 "expected_generation" => opened["generation"],
                 "expected_epoch" => 1,
                 "maintenance_id" => opening["maintenance_id"]
               },
               close_id,
               owner
             )

    old_commit = %{"op" => "commit", "stages" => [%{"slot" => 0, "epoch" => epoch}]}

    assert :ok =
             Session.invoke_export(run.pid, :command, "ext__documents__exercise", %{
               "mode" => "stage_request",
               "request" => old_commit
             })

    {_refused, 1} = wait(run, 0, true)
    assert {:ok, events} = Journal.load(run.dir, run.id)

    [failed] =
      Enum.filter(
        events,
        &(&1["type"] === "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) === "commit")
      )

    assert failed["outcome"] === %{
             "status" => "failed",
             "value" => %{"code" => "document_store_refused"}
           }

    assert Actions.valid_result?(failed)

    fresh = %{
      "op" => "value.put_inline",
      "maintenance_epoch" => 1,
      "key" => "fresh.document",
      "expected_revision" => 0,
      "byte_count" => byte_size(bytes),
      "sha256" => JSON.sha256(bytes),
      "data" => bytes
    }

    assert :ok =
             Session.invoke_export(run.pid, :command, "ext__documents__exercise", %{
               "mode" => "stage_request",
               "request" => fresh
             })

    {published, 1} = wait(run)
    assert published["value"]["key"] === "fresh.document"
    assert {:ok, after_state} = Collection.document_snapshot(root, namespace)

    assert after_state["document_maintenance"] === %{
             "version" => 1,
             "epoch" => 1,
             "status" => "idle"
           }

    assert {:ok, %{"record" => nil}} =
             Collection.execute_profile(
               root,
               namespace,
               %{"op" => "get", "key" => "old.staged"},
               Usage.id(),
               Profile.documents()
             )

    assert :ok = Session.close_confirmed(run.pid)
    assert {:ok, final} = Journal.load(run.dir, run.id)
    assert {:ok, _} = Session.Saved.restore(final, run.id)

    assert Enum.all?(
             Enum.filter(final, &(&1["type"] === "extension_action_result")),
             &Actions.valid_result?/1
           )
  end

  @tag :document_inventory_session
  test "actual public read inventory binds the admitted project and replays bounded metadata receipts",
       c do
    run = open(c)
    namespace = CollectionStore.namespace(run.binding["project_id"])
    keys = for n <- 0..39, do: "data." <> String.pad_leading(Integer.to_string(n), 91, "a")
    private = ~w(host.stage.0.header host.stage.0.ready host.stage.0.part.0 host.other)
    body = "{\"text\":\"INVENTORY_BODY_NEVER_RETURNED\"}"

    packed = %{
      "version" => 1,
      "kind" => "document_value",
      "sha256" => JSON.sha256(body),
      "byte_count" => byte_size(body),
      "parts" => [body]
    }

    seed = fn ns, names ->
      assert {:ok, _} =
               Collection.execute_profile(
                 CollectionStore.root(run.home),
                 ns,
                 %{
                   "op" => "commit",
                   "expected_generation" => 0,
                   "advance_floor" => false,
                   "changes" =>
                     Enum.map(names, &%{"key" => &1, "expected_revision" => 0, "value" => packed})
                 },
                 Usage.id(),
                 Profile.documents()
               )
    end

    seed.(namespace, keys ++ private)
    seed.(CollectionStore.namespace(JSON.sha256("foreign project")), ["FOREIGN_PROJECT_RECORD"])
    root_path = Path.join([CollectionStore.root(run.home), namespace, "root.json"])
    before = File.read!(root_path)

    assert :ok =
             Session.invoke_export(run.pid, :command, "ext__documents__exercise", %{
               "mode" => "inventory"
             })

    {result, approvals} = wait(run)
    assert approvals == 0
    assert result["value"]["keys"] == Enum.sort(keys)
    assert result["value"]["count"] == 40
    assert result["value"]["coverage"] == "public_document_records"
    assert File.read!(root_path) == before
    {:ok, events} = Journal.load(run.dir, run.id)
    actions = Enum.filter(events, &(&1["type"] == "extension_action_result"))
    assert Enum.count(actions, &(get_in(&1, ["request", "request", "op"]) == "value.index")) >= 3
    assert Enum.all?(actions, &Actions.valid_result?/1)
    assert Enum.all?(actions, &(Ipse.Extension.validate(Actions.resume(&1)) == :ok))

    for event <- actions, get_in(event, ["request", "request", "op"]) == "value.index" do
      page = get_in(event, ["outcome", "value", "result"])
      assert byte_size(Jason.encode!(page)) <= 4096
      refute Jason.encode!(page) =~ "INVENTORY_BODY_NEVER_RETURNED"
      assert event["effect_binding"]["namespace"] == namespace
    end

    assert {:ok, _} = Session.Saved.restore(events, run.id)

    IO.inspect(
      %{
        public_records: length(keys),
        inventory_pages:
          Enum.count(actions, &(get_in(&1, ["request", "request", "op"]) == "value.index")),
        maximum_resume_frame_bytes:
          Enum.max(Enum.map(actions, &byte_size(Jason.encode!(Actions.resume(&1))))),
        maximum_worker_request_bytes:
          actions
          |> Enum.with_index(3)
          |> Enum.map(fn {event, id} ->
            frame = %{
              "protocol" => 1,
              "id" => id,
              "stage" => "host.actions",
              "payload" => Actions.resume(event)
            }

            assert byte_size(Jason.encode!(frame)) <= 16_384
            byte_size(Jason.encode!(frame))
          end)
          |> Enum.max(),
        approvals: approvals,
        model_calls: 0
      },
      label: "DOCUMENT_INVENTORY_SESSION"
    )

    [trust] = run.data["extension_trust"]

    for invalid <- [
          Map.delete(trust, "collection_bindings"),
          put_in(trust, ["collection_bindings", Access.at(0), "instance"], "foreign")
        ] do
      assert {:ok, selected} =
               Config.resolve(
                 [
                   %{
                     scope: "operator",
                     path: "/fixture/config.json",
                     data: Map.put(run.data, "extension_trust", [invalid])
                   }
                 ],
                 []
               )

      assert {:error, _} = Registry.prepare(selected, run.home)
    end

    [entry] = run.opts[:config][:extensions]

    request = %{
      "op" => "collection.store",
      "scope" => "project",
      "request" => %{"op" => "value.index", "generation" => 1, "after" => nil, "limit" => 16}
    }

    assert {:ok, binding} =
             CollectionStore.prepare(run.home, run.opts[:cwd], entry.identity, request, run.id)

    refute CollectionStore.valid_binding?(
             %{binding | "namespace" => JSON.sha256("foreign")},
             request,
             entry.identity
           )

    assert {:error, :document_store_refused} =
             CollectionStore.prepare(
               run.home,
               run.opts[:cwd],
               Map.delete(entry.identity, "collection_binding"),
               request,
               run.id
             )
  end

  @tag :document_layout_session
  test "actual SDK layout read has no mutation approval and remains bound to its project", c do
    run = open(c, approval: :deny)
    namespace = CollectionStore.namespace(run.binding["project_id"])
    body = Jason.encode!(%{"text" => "LAYOUT_BODY_IS_NOT_METADATA 🌌"})
    {first, second} = String.split_at(body, 13)

    value = %{
      "version" => 1,
      "kind" => "document_value",
      "byte_count" => byte_size(body),
      "sha256" => JSON.sha256(body),
      "parts" => [first, second]
    }

    seed = fn ns, key ->
      assert {:ok, _} =
               Collection.execute_profile(
                 CollectionStore.root(run.home),
                 ns,
                 %{
                   "op" => "commit",
                   "expected_generation" => 0,
                   "advance_floor" => false,
                   "changes" => [%{"key" => key, "expected_revision" => 0, "value" => value}]
                 },
                 Usage.id(),
                 Profile.documents()
               )
    end

    seed.(namespace, "layout.fixture")
    seed.(CollectionStore.namespace(JSON.sha256("foreign layout project")), "foreign.only")
    pointer = Path.join([CollectionStore.root(run.home), namespace, "root.json"])
    before = File.read!(pointer)

    assert :ok =
             Session.invoke_export(run.pid, :command, "ext__documents__exercise", %{
               "mode" => "layout"
             })

    {display, approvals} = wait(run)
    assert approvals == 0
    layout = display["value"]["layout"]
    assert layout["sha256"] == JSON.sha256(body)
    physical = Ipse.Extension.Collection.Migration.encode(value)
    assert layout["record_sha256"] == JSON.sha256(physical)
    assert layout["record_bytes"] == byte_size(physical) and length(layout["parts"]) == 2
    refute Jason.encode!(display) =~ "LAYOUT_BODY_IS_NOT_METADATA"

    assert :ok =
             Session.invoke_export(run.pid, :command, "ext__documents__exercise", %{
               "mode" => "layout",
               "key" => "foreign.only"
             })

    {absent, 0} = wait(run)
    assert absent["value"]["layout"] == nil

    for args <- [
          %{"mode" => "layout", "generation_delta" => -1},
          %{"mode" => "layout", "key" => "host.stage.0.ready"}
        ] do
      assert :ok = Session.invoke_export(run.pid, :command, "ext__documents__exercise", args)
      {_refused, 0} = wait(run, 0, true)
    end

    assert File.read!(pointer) == before
    {:ok, events} = Journal.load(run.dir, run.id)
    actions = Enum.filter(events, &(&1["type"] == "extension_action_result"))
    layouts = Enum.filter(actions, &(get_in(&1, ["request", "request", "op"]) == "value.layout"))
    assert length(layouts) == 3
    assert Enum.all?(actions, &Actions.valid_result?/1)
    assert Enum.all?(actions, &(&1["approval"] == "not_required"))

    for event <- layouts do
      assert event["effect_binding"]["namespace"] == namespace
      assert :ok = Ipse.Extension.validate(Actions.resume(event))
    end

    assert get_in(List.last(layouts), ["outcome", "status"]) == "failed"
    assert {:ok, _} = Session.Saved.restore(events, run.id)
    [entry] = run.opts[:config][:extensions]

    request = %{
      "op" => "collection.store",
      "scope" => "project",
      "request" => %{"op" => "value.layout", "key" => "layout.fixture", "generation" => 1}
    }

    assert {:ok, binding} =
             CollectionStore.prepare(run.home, run.opts[:cwd], entry.identity, request, run.id)

    refute CollectionStore.valid_binding?(
             %{binding | "namespace" => JSON.sha256("foreign")},
             request,
             entry.identity
           )

    assert {:error, :document_store_refused} =
             CollectionStore.prepare(
               run.home,
               run.opts[:cwd],
               Map.delete(entry.identity, "collection_binding"),
               request,
               run.id
             )

    missing = open(c, admit: false)

    assert :ok =
             Session.invoke_export(missing.pid, :command, "ext__documents__exercise", %{
               "mode" => "layout"
             })

    assert {nil, 0} = wait(missing, 0, true)
    refute File.exists?(CollectionStore.root(missing.home))

    IO.puts(
      "DOCUMENT_LAYOUT_SESSION " <>
        Jason.encode!(%{
          approvals: approvals,
          receipts: length(layouts),
          max_worker_request_bytes:
            Enum.max(
              Enum.map(actions, fn e ->
                byte_size(
                  Jason.encode!(%{
                    "protocol" => 1,
                    "id" => 99,
                    "stage" => "host.actions",
                    "payload" => Actions.resume(e)
                  })
                )
              end)
            ),
          model_calls: 0
        })
    )
  end

  @tag :document_inventory_session
  test "public inventory refuses stale generations and private cursors without mutation", c do
    for args <- [
          %{"mode" => "inventory", "generation_delta" => -1},
          %{"mode" => "inventory", "after" => "host.stage.0.header"}
        ] do
      run = open(c)
      namespace = CollectionStore.namespace(run.binding["project_id"])

      assert {:ok, _} =
               Collection.execute_profile(
                 CollectionStore.root(run.home),
                 namespace,
                 %{
                   "op" => "commit",
                   "expected_generation" => 0,
                   "advance_floor" => false,
                   "changes" => [
                     %{
                       "key" => "data.retained",
                       "expected_revision" => 0,
                       "value" => %{"text" => "RETAINED"}
                     }
                   ]
                 },
                 Usage.id(),
                 Profile.documents()
               )

      pointer = Path.join([CollectionStore.root(run.home), namespace, "root.json"])
      before = File.read!(pointer)
      assert :ok = Session.invoke_export(run.pid, :command, "ext__documents__exercise", args)
      {result, approvals} = wait(run, 0, true)
      assert approvals == 0
      refute get_in(result || %{}, ["value", "coverage"])
      assert File.read!(pointer) == before
      assert {:ok, events} = Journal.load(run.dir, run.id)

      indexes =
        Enum.filter(
          events,
          &(&1["type"] == "extension_action_result" and
              get_in(&1, ["request", "request", "op"]) == "value.index")
        )

      if args["generation_delta"] do
        assert [event] = indexes
        assert get_in(event, ["request", "request", "generation"]) == 0
        assert get_in(event, ["outcome", "status"]) == "failed"
        assert get_in(event, ["outcome", "value", "code"]) == "document_store_refused"
        assert Actions.valid_result?(event)
      else
        assert indexes == []
      end
    end
  end

  test "ordinary denial never initializes document storage and no identity is silently admitted",
       c do
    for opts <- [[approval: :deny], [admit: false]] do
      run = open(c, opts)
      assert :ok = Session.invoke_export(run.pid, :command, "ext__documents__exercise", %{})
      {result, approvals} = wait(run, 0, true)
      assert approvals == 0
      refute get_in(result || %{}, ["value", "equal"])
      assert Path.wildcard(Path.join(CollectionStore.root(run.home), "*/root.json")) == []

      if opts[:admit] == false,
        do: assert({:ok, nil} = ProjectIdentity.existing(run.home, run.opts[:cwd]))
    end
  end

  test "store capability requires its separate operator grant and read namespace binding", c do
    run = open(c)
    [trust] = run.data["extension_trust"]
    data = Map.put(run.data, "extension_trust", [Map.delete(trust, "collection_bindings")])

    assert {:ok, selected} =
             Config.resolve([%{scope: "operator", path: "/fixture/config.json", data: data}], [])

    assert {:error, _} = Registry.prepare(selected, run.home)

    invalid =
      put_in(
        run.data,
        ["extension_trust", Access.at(0), "collection_bindings", Access.at(0), "profile"],
        "notes-v1"
      )

    assert {:error, _} =
             Config.resolve(
               [%{scope: "operator", path: "/fixture/config.json", data: invalid}],
               []
             )

    request = %{
      "op" => "collection.store",
      "scope" => "project",
      "request" => %{"op" => "snapshot"}
    }

    [entry] = run.opts[:config][:extensions]

    assert {:ok, binding} =
             CollectionStore.prepare(run.home, run.opts[:cwd], entry.identity, request, run.id)

    event = %{
      "request" => request,
      "effect_binding" => binding,
      "outcome" => %{
        "status" => "ok",
        "value" => %{"result" => %{"project" => binding["namespace"]}}
      }
    }

    assert CollectionStore.bound_outcome?(event)

    refute CollectionStore.bound_outcome?(
             put_in(event, ["outcome", "value", "result", "project"], JSON.sha256("other"))
           )

    assert {:error, :document_store_refused} =
             CollectionStore.prepare(
               run.home,
               run.opts[:cwd],
               Map.delete(entry.identity, "collection_binding"),
               request,
               run.id
             )
  end

  test "native publication uncertainty reaches the actual journal as unknown and resume does not replay",
       c do
    run = open(c)
    id = Session.info(run.pid).id
    handler = "document-store-unknown-" <> Usage.id()
    owner = self()

    assert :ok =
             :telemetry.attach(
               handler,
               [:ipse, :extension, :collection, :staged],
               fn _, _, metadata, _ ->
                 if metadata.generation == 2 do
                   cap = Process.get({Collection, :lock_held})
                   Port.close(cap.port)
                   send(owner, :document_native_lost)
                 end
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert :ok = Session.invoke_export(run.pid, :command, "ext__documents__exercise", %{})
    {_, _} = wait(run, 0, true)
    assert_receive :document_native_lost
    :telemetry.detach(handler)
    {:ok, before} = Journal.load(run.dir, id)
    results = Enum.filter(before, &(&1["type"] == "extension_action_result"))
    assert get_in(List.last(results), ["outcome", "status"]) == "unknown"
    assert get_in(List.last(results), ["request", "request", "op"]) == "value.append"
    refute Enum.any?(results, &(get_in(&1, ["request", "request", "op"]) == "value.seal"))
    if Process.alive?(run.pid), do: assert(:ok = Session.close_confirmed(run.pid))
    path = Path.join(run.dir, id <> ".jsonl")
    before_resume = File.read!(path)

    files = fn ->
      Path.wildcard(Path.join(CollectionStore.root(run.home), "**/*"), match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Map.new(&{&1, JSON.sha256(File.read!(&1))})
    end

    retained = files.()

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(run.opts, :id, id)}
             )

    assert_idle_resume_journal(path, before_resume, id)
    assert {:ok, resumed_events} = Journal.load(run.dir, id)
    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, closed_events} = Journal.load(run.dir, id)
    assert Enum.take(closed_events, length(resumed_events)) == resumed_events

    assert [
             %{
               "type" => "session_release_intent",
               "session_id" => ^id,
               "epoch_id" => nil,
               "closure_sha256" => nil
             }
           ] =
             Enum.drop(closed_events, length(resumed_events))

    assert {:ok, %{"release_claim" => "signed_release_claim"}} =
             Session.Saved.inspect_saved(run.dir, id)

    assert files.() == retained
  end
end
