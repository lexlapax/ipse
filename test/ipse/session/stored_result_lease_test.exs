Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Session.StoredResultLeaseTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage
  alias Ipse.{JSON, Journal, Runner, Session, Usage}
  alias Ipse.Extension.{Artifact, Config, ProjectIdentity, Registry}
  alias Ipse.Session.StoredSources
  @moduletag :stored_result_lease
  @moduletag skip: :os.type() != {:unix, :linux}

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("result lease fixture must not call a model")
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-result-lease-artifact-" <> Usage.id())
    artifact = Path.join(root, "artifact")
    File.mkdir_p!(Path.join(artifact, "ebin"))
    on_exit(fn -> File.rm_rf!(root) end)
    for path <- [root, artifact, Path.join(artifact, "ebin")], do: File.chmod!(path, 0o700)
    module = "StoredResultLease.Fixture#{System.unique_integer([:positive])}"
    capabilities = ~w(invoke.command invoke.result.pages host.actions host.collection.read)

    exports = %{
      "version" => 1,
      "tools" => [],
      "services" => [],
      "commands" => [
        %{
          "id" => "publish",
          "description" => "Publish synthetic paged lease input",
          "arguments_schema" => %{
            "type" => "object",
            "additionalProperties" => false,
            "properties" => %{"managed" => %{"type" => "boolean"}}
          },
          "result_schema" => %{"type" => "object", "additionalProperties" => true}
        }
      ]
    }

    source = Path.join(root, "fixture.ex")

    File.write!(source, """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 2, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports, limit: :infinity)}}
      def init(options), do: {:ok, options}
      def handle("invoke.command", %{"arguments" => %{"managed" => true}}, state) do
        request = %{"op" => "collection.call", "request" => %{"op" => "snapshot"}}
        {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}
      end
      def handle("invoke.command", _, state), do: publication(state)
      def handle("host.actions", %{"outcome" => %{"status" => "ok"}}, state), do: publication(state)
      defp publication(state) do
        value = %{"items" => List.duplicate(String.duplicate("x", 8192), 3)}
        {:ok, publication} = Ipse.Extension.ResultPublication.prepare(value)
        {:ok, publication, state}
      end
    end
    """)

    {log, status} =
      System.cmd(
        System.find_executable("elixirc"),
        [
          "--warnings-as-errors",
          "-pa",
          Application.app_dir(:ipse, "ebin"),
          "-pa",
          Application.app_dir(:jason, "ebin"),
          "-o",
          Path.join(artifact, "ebin"),
          source
        ],
        stderr_to_stdout: true
      )

    assert status === 0, log
    File.cp!(Path.expand("../../../LICENSE", __DIR__), Path.join(artifact, "LICENSE"))
    paths = ["LICENSE", "ebin/Elixir.#{module}.beam"]
    for path <- paths, do: File.chmod!(Path.join(artifact, path), 0o600)

    manifest = %{
      "format" => 1,
      "id" => "fixture/stored-result-lease",
      "version" => "0.1.0",
      "sdk" => 2,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
      "license_file" => "LICENSE",
      "options_schema" => %{"type" => "object", "additionalProperties" => false},
      "capabilities" => capabilities,
      "exports" => exports,
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(paths, fn path ->
          bytes = File.read!(Path.join(artifact, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
        end)
    }

    File.write!(Path.join(artifact, "extension.json"), Jason.encode!(manifest))
    File.chmod!(Path.join(artifact, "extension.json"), 0o600)
    %{artifact: artifact, capabilities: capabilities}
  end

  setup c do
    root = Path.join(System.tmp_dir!(), "ipse-result-lease-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "project")
    directory = Path.join(root, "sessions")
    for path <- [root, home, cwd, directory], do: File.mkdir_p!(path)
    for path <- [root, home, cwd, directory], do: File.chmod!(path, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, binding} = ProjectIdentity.admit(home, cwd, :folder)
    assert {:ok, artifact} = Artifact.import(c.artifact, Path.join(home, "extensions/artifacts"))

    source = %{
      scope: "operator",
      path: Path.join(root, "operator.json"),
      data: %{
        "extensions" => [
          %{
            "instance" => "result",
            "artifact" => artifact.digest,
            "enabled" => true,
            "options" => %{},
            "order" => 0,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => artifact.digest,
            "capabilities" => c.capabilities,
            "allow_project" => false,
            "allow_children" => false
          }
        ]
      }
    }

    assert {:ok, catalog} = Config.resolve([source], [])
    assert {:ok, extensions} = Registry.prepare(catalog, home)

    config = %{
      home: home,
      provider: :demo,
      model: "demo",
      provider_module: NoModel,
      approval: :ask,
      extensions: extensions
    }

    original = start(config, cwd, directory)
    assert :ok = Session.invoke_export(original, :command, "ext__result__publish", %{})
    assert_receive {:ipse, ^original, {:extension_result, display}}, 30_000
    assert_receive {:ipse, ^original, {:done, :ok}}, 3_000
    assert display["delivery"]["kind"] === "saved.result"
    id = Session.info(original).id
    consumer = start(%{config | extensions: []}, cwd, directory)

    context = %{
      config: config,
      cwd: cwd,
      history_dir: directory,
      session_id: Session.info(consumer).id
    }

    %{
      root: root,
      original: original,
      consumer: consumer,
      context: context,
      binding: binding,
      selected: %{"version" => 1, "session_id" => id, "delivery" => display["delivery"]},
      journal: Path.join(directory, id <> ".jsonl"),
      lock: Path.join(directory, id <> ".lock")
    }
  end

  defp start(config, cwd, directory) do
    assert {:ok, pid} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: config, cwd: cwd, state_dir: directory, owner: self(), subscriber: self()}
             )

    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)
    pid
  end

  defp closed(c) do
    assert :ok = Session.close_confirmed(c.original)
    assert {:ok, events} = Journal.load(c.context.history_dir, c.selected["session_id"])
    assert {:ok, saved} = Session.Saved.restore(events, c.selected["session_id"])
    {events, saved}
  end

  defp unexpected_callback do
    recipient = self()

    fn _, _ ->
      send(recipient, :unexpected_result_callback)
      :unexpected
    end
  end

  defp checked_callback(recipient, fun) do
    fn value, guard ->
      try do
        fun.(value, guard)
      rescue
        error ->
          send(recipient, {:callback_assertion, error, __STACKTRACE__})
          :callback_assertion_failed
      end
    end
  end

  defp managed_read_config(c) do
    alias Ipse.Extension.{Catalog, Consent, SemanticAdmission, SemanticConsent}
    config = c.context.config
    [entry] = config.extensions
    assert {:ok, catalog} = Catalog.snapshot(config)
    [descriptor] = catalog["entries"]
    assert {:ok, namespace} = SemanticConsent.namespace(c.binding["project_id"], "result")
    settings = Ipse.Test.ManagedPolicy.policy()["settings"]

    selection = %{
      "version" => 2,
      "activation" => nil,
      "constraints" => settings["constraints"],
      "recipes" => settings["recipes"],
      "domain" => "knowledge",
      "namespace" => namespace,
      "scope" => %{"kind" => "project", "worktree_id" => nil},
      "sources" => %{"categories" => ["unattended_input"], "exclusions" => []},
      "storage" => %{"kind" => "local_collection", "collection" => "result"},
      "retention" => %{"automatic" => 90, "manual" => 3650},
      "routes" => [
        %{
          "operation" => "main",
          "provider" => "demo",
          "profile" => nil,
          "model" => "demo",
          "endpoint" => "demo://local",
          "service_id" => "demo",
          "billing_mode" => "none",
          "processing_region" => nil,
          "storage_region" => nil,
          "cache_retention" => nil,
          "account_controls" => nil
        }
      ],
      "effects" => [
        %{
          "operation" => "notes.recall",
          "class" => "collection.read",
          "outer_sha256" => JSON.digest([descriptor]),
          "inner_op" => "collection.call",
          "managed_read" => Enum.sort(Map.keys(settings["recipes"]))
        }
      ],
      "limits" =>
        Map.merge(Consent.zero(), %{
          "operations" => 4,
          "input_bytes" => 100_000,
          "output_bytes" => 100_000
        }),
      "period_ms" => 86_400_000,
      "expires_at_ms" => System.system_time(:millisecond) + 600_000,
      "headless" => true
    }

    assert {:ok, policy} = SemanticConsent.prepare(c.binding, entry.identity, selection)
    control = SemanticAdmission.control_root(config.home)
    assert {:ok, before} = Consent.snapshot(control, c.binding["project_id"])

    assert {:ok, _} =
             Consent.replace(
               control,
               c.binding["project_id"],
               before["epoch"],
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, selected} = Ipse.Config.Semantics.selection(policy)
    Map.put(config, :semantic_selections, selected)
  end

  test "a real closed result retains its original lock, exact bytes, intent and full output dependencies",
       c do
    {_, saved} = closed(c)
    second = start(managed_read_config(c), c.context.cwd, c.context.history_dir)

    assert :ok =
             Session.invoke_export(second, :command, "ext__result__publish", %{"managed" => true})

    assert_receive {:ipse, ^second, {:extension_result, second_display}}, 30_000
    assert_receive {:ipse, ^second, {:done, :ok}}, 3_000
    second_id = Session.info(second).id
    assert :ok = Session.close_confirmed(second)
    assert {:ok, second_events} = Journal.load(c.context.history_dir, second_id)
    assert {:ok, second_saved} = Session.Saved.restore(second_events, second_id)
    assert Enum.any?(Map.values(second_saved.extension_state.managed_outputs), &(&1 !== []))

    second_selected = %{
      "version" => 1,
      "session_id" => second_id,
      "delivery" => second_display["delivery"]
    }

    before = File.read!(c.journal)
    recipient = self()

    result =
      StoredSources.with_result(
        c.context,
        c.selected,
        checked_callback(recipient, fn value, guard ->
          assert :ok = guard.()
          task = Task.async(fn -> guard.() end)
          assert {:error, _} = Task.await(task)
          assert {:error, _} = Runner.lock_source(c.lock)
          assert value.project_binding === c.binding
          assert value.delivery === c.selected["delivery"]
          assert JSON.sha256(value.bytes) === value.delivery["sha256"]
          assert Jason.decode!(value.bytes) === value.value
          assert value.value === %{"items" => List.duplicate(String.duplicate("x", 8192), 3)}
          id = value.source_intent["invocation_id"]
          assert value.dependencies === Map.fetch!(saved.extension_state.managed_outputs, id)
          assert value.source_intent["payload"]["session_id"] === c.selected["session_id"]

          assert :ok =
                   ProjectIdentity.with_held_binding(
                     c.context.config.home,
                     c.context.cwd,
                     value.project_binding,
                     fn _ -> guard.() end
                   )

          nested = Map.put(c.context, :held_document_project, value.project_binding)

          assert :nested =
                   StoredSources.with_result(
                     nested,
                     second_selected,
                     checked_callback(recipient, fn page, page_guard ->
                       assert page.project_binding === value.project_binding
                       assert page.source_intent["payload"]["session_id"] === second_id
                       assert page.dependencies !== []

                       assert page.dependencies ===
                                Map.fetch!(
                                  second_saved.extension_state.managed_outputs,
                                  page.source_intent["invocation_id"]
                                )

                       expected_actions =
                         Enum.filter(second_events, fn event ->
                           event["type"] === "extension_action_result" and
                             event["parent_invocation_id"] ===
                               page.source_intent["invocation_id"]
                         end)

                       assert expected_actions !== []
                       assert page.action_results === expected_actions
                       assert :ok = page_guard.()
                       :nested
                     end)
                   )

          assert :ok = guard.()

          {:ok, guard}
        end)
      )

    receive do
      {:callback_assertion, error, stacktrace} -> reraise error, stacktrace
    after
      0 -> :ok
    end

    assert {:ok, guard} = result

    assert {:error, :collection_source_refused} = guard.()
    assert File.read!(c.journal) === before
    assert {:ok, lock} = Runner.lock_source(c.lock)
    assert :ok = Runner.unlock(lock)
  end

  test "active originals and a same-Session selection refuse without callback entry", c do
    callback = unexpected_callback()
    assert {:error, _} = StoredSources.with_result(c.context, c.selected, callback)
    closed(c)
    same = %{c.context | session_id: c.selected["session_id"]}
    assert {:error, _} = StoredSources.with_result(same, c.selected, callback)
    assert :ok = StoredSources.with_result(c.context, c.selected, fn _, guard -> guard.() end)
    refute_receive :unexpected_result_callback, 0
  end

  test "closed selection and descriptor fields cannot redirect the original or change its bytes",
       c do
    closed(c)

    for changed <- [
          Map.put(c.selected, "history_dir", c.root),
          Map.put(c.selected, "version", 1.0),
          Map.put(c.selected, "session_id", "../original"),
          put_in(c.selected, ["delivery", "sha256"], String.duplicate("a", 64)),
          put_in(c.selected, ["delivery", "byte_count"], c.selected["delivery"]["byte_count"] + 1)
        ] do
      assert {:error, _} = StoredSources.with_result(c.context, changed, unexpected_callback())
      refute_receive :unexpected_result_callback, 0
    end
  end

  test "equal absent semantic pins cannot authorize another or unadmitted project", c do
    closed(c)
    other = Path.join(c.root, "other")
    File.mkdir!(other)
    File.chmod!(other, 0o700)
    callback = unexpected_callback()
    forged = Map.put(c.context, :held_document_project, c.binding)
    assert {:error, _} = StoredSources.with_result(forged, c.selected, callback)

    assert {:error, _} =
             StoredSources.with_result(%{c.context | cwd: other}, c.selected, callback)

    assert {:ok, _} = ProjectIdentity.admit(c.context.config.home, other, :folder)

    assert {:error, _} =
             StoredSources.with_result(%{c.context | cwd: other}, c.selected, callback)

    wrong =
      put_in(c.context, [:config, :semantic_admission], %{
        "pin" => %{"project_id" => String.duplicate("a", 64)}
      })

    assert {:error, _} = StoredSources.with_result(wrong, c.selected, callback)
    refute_receive :unexpected_result_callback, 0
  end

  test "copied and hardlinked original journals refuse before exposing a value", c do
    closed(c)
    copied = Path.join(c.root, "copied")
    File.mkdir!(copied)
    File.chmod!(copied, 0o700)
    File.cp!(c.journal, Path.join(copied, Path.basename(c.journal)))
    File.cp!(c.lock, Path.join(copied, Path.basename(c.lock)))
    callback = unexpected_callback()

    assert {:error, _} =
             StoredSources.with_result(%{c.context | history_dir: copied}, c.selected, callback)

    linked = Path.join(c.root, "linked")
    File.ln!(c.journal, linked)
    assert {:error, _} = StoredSources.with_result(c.context, c.selected, callback)
    File.rm!(linked)
    refute_receive :unexpected_result_callback, 0
  end

  test "changed input invalidates the pre-CAS guard and the callback result", c do
    closed(c)
    before = File.read!(c.journal)
    marker = Path.join(c.root, "must-not-write")
    recipient = self()

    publish = fn value, guard ->
      with :ok <- guard.() do
        File.write!(marker, value.bytes)
        :written
      end
    end

    assert :written = StoredSources.with_result(c.context, c.selected, publish)
    assert JSON.sha256(File.read!(marker)) === c.selected["delivery"]["sha256"]
    File.rm!(marker)

    assert {:error, _} =
             StoredSources.with_result(c.context, c.selected, fn value, guard ->
               File.write!(c.journal, "\n", [:append])
               assert {:error, _} = publish.(value, guard)
               send(recipient, :withheld)
               :must_not_escape
             end)

    assert_receive :withheld
    refute File.exists?(marker)
    File.write!(c.journal, before)
  end

  test "a torn, legacy-origin or unfinalized selected result is not a readable input", c do
    {events, _} = closed(c)
    before = File.read!(c.journal)
    File.write!(c.journal, "{", [:append])
    callback = unexpected_callback()
    assert {:error, _} = StoredSources.with_result(c.context, c.selected, callback)
    [header | rest] = events

    legacy = [
      update_in(header, ["metadata"], &Map.drop(&1, ~w(source_origin source_origin_layout)))
      | rest
    ]

    File.write!(c.journal, Enum.map_join(legacy, "", &(Jason.encode!(&1) <> "\n")))
    assert {:error, _} = StoredSources.with_result(c.context, c.selected, callback)
    File.write!(c.journal, before)
    final = Enum.find_index(events, &(&1["type"] === "extension_invocation_result"))
    prefix = events |> Enum.take(final) |> Enum.map_join("", &(Jason.encode!(&1) <> "\n"))
    File.write!(c.journal, prefix)
    assert {:ok, index} = Ipse.Extension.ResultSource.restore(Enum.take(events, final))

    assert {:error, _} =
             Ipse.Extension.ResultSource.readable_source(index, c.selected["delivery"])

    assert {:error, _} = StoredSources.with_result(c.context, c.selected, callback)
    refute_receive :unexpected_result_callback, 0
  end

  test "native original-owner loss withholds the callback value and leaves original bytes unchanged",
       c do
    closed(c)
    before = File.read!(c.journal)
    ports = MapSet.new(Port.list())
    recipient = self()

    assert {:error, _} =
             StoredSources.with_result(c.context, c.selected, fn _, guard ->
               port =
                 Enum.find(Port.list(), fn port ->
                   with false <- MapSet.member?(ports, port),
                        {:connected, owner} when owner === self() <- Port.info(port, :connected),
                        {:os_pid, pid} <- Port.info(port, :os_pid),
                        {:ok, command} <- File.read("/proc/#{pid}/cmdline") do
                     c.lock in String.split(command, <<0>>)
                   else
                     _ -> false
                   end
                 end)

               assert is_port(port)
               monitor = Port.monitor(port)
               {:os_pid, pid} = Port.info(port, :os_pid)
               assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(pid)])
               assert_receive {:DOWN, ^monitor, :port, ^port, _}, 5_000
               assert {:error, _} = guard.()
               send(recipient, :original_owner_lost)
               :must_not_escape
             end)

    assert_receive :original_owner_lost
    assert File.read!(c.journal) === before
  end
end
