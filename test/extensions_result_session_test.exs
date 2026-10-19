defmodule Ipse.Extensions.ResultSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session}

  alias Ipse.Extensions.{
    Conformance,
    Config,
    Invocation,
    Manifest,
    Registry,
    ResultReader,
    ResultSource,
    Store
  }

  defmodule Model do
    def complete(config, messages, tools, _emit) do
      send(config.test_pid, {:result_session_model, messages, tools})
      tool_messages = Enum.filter(messages, &(&1["role"] == "tool"))
      published = Enum.find(tool_messages, &(&1["tool_call_id"] == "publish"))
      read = Enum.find(tool_messages, &(&1["tool_call_id"] == "read"))

      cond do
        config[:reader_only] == true and tool_messages == [] ->
          request = messages |> Enum.filter(&(&1["role"] == "user")) |> List.last()
          call("read", "saved_result_read", Jason.decode!(request["content"]))

        published && published["ipse_extension_result"] && is_nil(read) ->
          delivery = Jason.decode!(published["content"])

          call("read", "saved_result_read", %{
            "output_id" => delivery["output_id"],
            "path" => ["items", 0],
            "offset" => 0
          })

        tool_messages != [] ->
          {:ok, %{"role" => "assistant", "content" => "Synthetic fixture complete"}, %{}}

        true ->
          call("publish", "ext__output__publish", config[:tool_args] || %{})
      end
    end

    defp call(id, name, arguments) do
      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => id,
             "type" => "function",
             "function" => %{"name" => name, "arguments" => Jason.encode!(arguments)}
           }
         ]
       }, %{}}
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-result-session-#{Ipse.Usage.id()}")
    source = Path.join(root, "source")
    File.mkdir_p!(Path.join(source, "ebin"))
    on_exit(fn -> File.rm_rf!(root) end)
    marker = Path.join(root, "loads")
    called = Path.join(root, "callbacks")
    module = "ResultSession.Fixture#{System.unique_integer([:positive])}"

    capabilities =
      ~w(invoke.tool invoke.command invoke.result.pages host.actions host.state.write)

    descriptor = %{
      "id" => "publish",
      "description" => "Publish synthetic complete result",
      "arguments_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "near_cap" => %{"type" => "boolean"},
          "wrong" => %{"type" => "boolean"},
          "wait" => %{"type" => "boolean"},
          "inline" => %{"type" => "boolean"},
          "late_write" => %{"type" => "boolean"}
        }
      },
      "result_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["items", "pad"],
        "properties" => %{
          "items" => %{"type" => "array", "items" => %{"type" => "string"}},
          "pad" => %{"type" => "string"}
        }
      }
    }

    exports = %{
      "version" => 1,
      "tools" => [descriptor],
      "commands" => [descriptor],
      "services" => []
    }

    fixture = Path.join(root, "fixture.ex")

    File.write!(fixture, """
    defmodule #{module} do
      @behaviour Ipse.Extension
      @on_load :loaded
      def loaded, do: (File.write!(#{inspect(marker)}, "loaded\\n", [:append]); :ok)
      def describe, do: %{"sdk" => 2, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports, limit: :infinity)}}
      def init(options), do: {:ok, options}
      def handle(_, %{"arguments" => %{"late_write" => true}}, state) do
        request = %{"op" => "state.put", "scope" => "project", "key" => "late-effect",
          "expected_revision" => 0, "value" => %{"late" => true}}
        {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}
      end
      def handle(stage, payload, state) do
        File.write!(#{inspect(called)}, stage <> " " <> payload["invocation_id"] <> "\\n", [:append])
        arguments = payload["arguments"]
        if arguments["wait"], do: Process.sleep(:infinity)
        value = if arguments["near_cap"] do
          initial = %{"items" => List.duplicate(String.duplicate("x", 8192), 511), "pad" => ""}
          Map.put(initial, "pad", String.duplicate("y", 4 * 1024 * 1024 - byte_size(Jason.encode!(initial))))
        else
          %{"items" => List.duplicate(String.duplicate("雪", 2730), 3), "pad" => ""}
        end
        value = if arguments["wrong"], do: Map.put(Map.delete(value, "items"), "wrong", value["items"]), else: value
        value = if arguments["inline"], do: %{"items" => ["small"], "pad" => ""}, else: value
        {:ok, delivery} = Ipse.Extension.ResultPublication.prepare(value)
        {:ok, delivery, state}
      end
    end
    """)

    {output, status} =
      System.cmd(
        System.find_executable("elixirc"),
        [
          "-pa",
          Application.app_dir(:ipse, "ebin"),
          "-pa",
          Application.app_dir(:jason, "ebin"),
          "-o",
          Path.join(source, "ebin"),
          fixture
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.write!(Path.join(source, "LICENSE"), "MIT synthetic fixture")

    manifest = %{
      "format" => 1,
      "id" => "fixture/result-session",
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
        for path <- ["LICENSE", "ebin/Elixir.#{module}.beam"] do
          bytes = File.read!(Path.join(source, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Manifest.sha256(bytes)}
        end
    }

    File.write!(Path.join(source, "extension.json"), Jason.encode!(manifest))
    home = Path.join(root, "home")
    assert {:ok, artifact} = Store.import(source, Path.join(home, "extensions/artifacts"))
    refute File.exists?(marker)

    %{
      artifact_root: root,
      home: home,
      digest: artifact.digest,
      capabilities: capabilities,
      marker: marker,
      called: called,
      module: module
    }
  end

  setup c do
    File.rm(c.marker)
    File.rm(c.called)
    File.rm_rf!(Path.join(c.home, "extension-state-v1"))
    root = Path.join(c.artifact_root, "session-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)

    source = %{
      scope: "operator",
      path: Path.join(root, "operator.json"),
      data: %{
        "extensions" => [
          %{
            "instance" => "output",
            "artifact" => c.digest,
            "enabled" => true,
            "options" => %{},
            "order" => 0,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => c.digest,
            "capabilities" => c.capabilities,
            "allow_project" => false,
            "allow_children" => false
          }
        ]
      }
    }

    assert {:ok, catalog} = Config.resolve([source], [])
    assert {:ok, entries} = Registry.prepare(catalog, c.home)

    config = %{
      provider: :ollama,
      model: "synthetic",
      provider_module: Model,
      test_pid: self(),
      home: c.home,
      approval: :ask,
      extensions: entries
    }

    %{root: root, dir: Path.join(root, "state"), config: config, catalog: catalog}
  end

  defp start(c, id \\ nil) do
    assert {:ok, session} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: c.config, cwd: c.root, state_dir: c.dir, subscriber: self(), id: id}
             )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)
    session
  end

  defp command(session, arguments \\ %{}) do
    assert :ok = Session.invoke_export(session, :command, "ext__output__publish", arguments)
    assert_receive {:ipse, ^session, {:extension_result, display}}, 30_000
    assert_receive {:ipse, ^session, {:done, :ok}}, 3_000
    assert display["stage"] == "invoke.command"
    assert display["delivery"]["kind"] == "saved.result"
    display["delivery"]
  end

  defp events(c, session) do
    assert {:ok, events} = Journal.load(c.dir, Session.info(session).id)
    events
  end

  defp read_request(delivery), do: %{"output_id" => delivery["output_id"], "path" => ["items", 0]}

  test "command publication materializes exactly and resumes without executing its artifact", c do
    session = start(c)
    delivery = command(session)
    assert {:ok, result} = Session.materialize_result(session, delivery)
    assert result.provenance == "historical_receipt"

    assert result.value == %{
             "items" => List.duplicate(String.duplicate("雪", 2730), 3),
             "pad" => ""
           }

    assert byte_size(result.bytes) == delivery["byte_count"]
    assert Manifest.sha256(result.bytes) == delivery["sha256"]
    assert {:ok, view} = Session.read_saved_result(session, read_request(delivery))
    assert view["historical_receipt"] == true
    assert view["complete"] == false
    assert Ipse.Extension.validate(view) == :ok
    assert :ok = Invocation.validate_events(events(c, session))
    assert_raise ArgumentError, fn -> String.to_existing_atom("Elixir." <> c.module) end
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    before = File.read!(Path.join(c.dir, id <> ".jsonl"))
    loads = File.read!(c.marker)
    calls = File.read!(c.called)
    assert {:ok, ^result} = ResultReader.saved(c.dir, id, delivery["output_id"])

    captured =
      ExUnit.CaptureIO.capture_io(fn ->
        assert Ipse.CLI.run([
                 "result",
                 delivery["output_id"],
                 "--resume",
                 id,
                 "--state-dir",
                 c.dir
               ]) == 0
      end)

    assert {:ok, value} = Jason.decode(captured)
    assert value == result.value
    resumed = start(c, id)
    assert Session.info(resumed).extension_result["delivery"] == delivery
    assert {:ok, ^result} = Session.materialize_result(resumed, delivery)
    assert {:ok, ^view} = Session.read_saved_result(resumed, read_request(delivery))
    assert File.read!(c.marker) == loads
    assert File.read!(c.called) == calls
    assert File.read!(Path.join(c.dir, id <> ".jsonl")) == before
    refute_receive {:result_session_model, _, _}, 0
    foreign = start(c)
    assert {:error, _} = Session.materialize_result(foreign, delivery)
    assert {:error, _} = Session.read_saved_result(foreign, read_request(delivery))
  end

  test "model tool publication exposes bounded reads only after successful delivery", c do
    session = start(c)

    assert :ok =
             Session.prompt(session, "Publish the synthetic result, then inspect its first item")

    assert_receive {:ipse, ^session, {:approval, ref, "ext__output__publish", %{}}}, 3_000
    refute File.exists?(c.marker)
    assert :ok = Session.approve(session, ref, true)
    assert_receive {:ipse, ^session, {:done, :ok}}, 30_000
    events = events(c, session)
    result = Enum.find(events, &(&1["type"] == "extension_invocation_result"))
    assert result["version"] == 2
    assert :ok = Invocation.validate_events(events)
    assert {:ok, messages} = Session.restore_context(events)
    read = Enum.find(messages, &(&1["role"] == "tool" and &1["tool_call_id"] == "read"))
    assert is_map(read)
    assert {:ok, view} = Jason.decode(read["content"])
    assert view["historical_receipt"] == true
    assert view["output_id"] == result["delivery"]["output_id"]
    assert byte_size(view["text"]) <= 1024
    assert {:ok, _} = Session.materialize_result(session, result["delivery"])
    assert_receive {:result_session_model, _, before_tools}
    refute Enum.any?(before_tools, &(get_in(&1, ["function", "name"]) == "saved_result_read"))
    assert_receive {:result_session_model, _, after_tools}
    assert Enum.any?(after_tools, &(get_in(&1, ["function", "name"]) == "saved_result_read"))
  end

  test "a command output ID known to the model grants no model read access", c do
    c = %{c | config: Map.put(c.config, :reader_only, true)}
    session = start(c)
    delivery = command(session)
    assert :ok = Session.prompt(session, Jason.encode!(read_request(delivery)))
    assert_receive {:ipse, ^session, {:done, :ok}}, 10_000
    assert_receive {:result_session_model, _, tools}
    refute Enum.any?(tools, &(get_in(&1, ["function", "name"]) == "saved_result_read"))
    assert {:ok, messages} = Session.restore_context(events(c, session))
    read = Enum.find(messages, &(&1["role"] == "tool" and &1["tool_call_id"] == "read"))
    assert is_map(read)
    refute read["content"] =~ "historical_receipt"
    assert {:error, _} = Jason.decode(read["content"])
    assert {:ok, _} = Session.materialize_result(session, delivery)
  end

  test "denied tool execution creates neither worker load nor output source", c do
    session = start(c)
    assert :ok = Session.prompt(session, "Publish synthetic result")
    assert_receive {:ipse, ^session, {:approval, ref, "ext__output__publish", %{}}}, 3_000
    assert :ok = Session.approve(session, ref, false)
    assert_receive {:ipse, ^session, {:done, :ok}}, 10_000
    refute File.exists?(c.marker)
    refute File.exists?(c.called)

    refute Enum.any?(
             events(c, session),
             &(&1["type"] in (Invocation.types() ++ ResultSource.types()))
           )
  end

  test "invalid logical schema leaves an unreadable diagnostic prefix that resumes inertly", c do
    session = start(c)

    assert :ok =
             Session.invoke_export(session, :command, "ext__output__publish", %{"wrong" => true})

    assert_receive {:ipse, ^session, {:done, :error}}, 30_000
    events = events(c, session)
    begin = Enum.find(events, &(&1["type"] == "extension_output_begin"))
    assert is_map(begin)
    assert Enum.any?(events, &(&1["type"] == "extension_output_chunk"))

    refute Enum.any?(
             events,
             &(&1["type"] in ~w(extension_output_seal extension_invocation_result))
           )

    assert {:ok, _} = ResultSource.restore(events)
    assert :ok = Invocation.validate_events(events)

    delivery = %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => begin["output_id"],
      "byte_count" => begin["byte_count"],
      "sha256" => begin["sha256"],
      "historical_receipt" => true
    }

    assert {:error, _} = Session.materialize_result(session, delivery)
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    calls = File.read!(c.called)
    loads = File.read!(c.marker)
    resumed = start(c, id)
    assert Session.info(resumed).phase == :idle
    assert {:error, _} = Session.materialize_result(resumed, delivery)
    assert {:error, _} = Session.read_saved_result(resumed, read_request(delivery))
    assert File.read!(c.called) == calls
    assert File.read!(c.marker) == loads
  end

  test "native Session publication retains exactly four MiB through 1024 pages", c do
    session = start(c)
    delivery = command(session, %{"near_cap" => true})
    assert delivery["byte_count"] == 4 * 1024 * 1024
    events = events(c, session)
    chunks = Enum.filter(events, &(&1["type"] == "extension_output_chunk"))
    assert length(chunks) == 1024
    assert Enum.all?(chunks, &(&1["byte_count"] == 4096))
    assert List.last(chunks)["next"] == delivery["byte_count"]
    assert Enum.count(events, &(&1["type"] == "extension_output_seal")) == 1
    assert Enum.count(events, &(&1["type"] == "extension_invocation_result")) == 1
    assert :ok = Invocation.validate_events(events)
    assert {:ok, result} = Session.materialize_result(session, delivery)
    assert byte_size(result.bytes) == 4 * 1024 * 1024
    assert Manifest.sha256(result.bytes) == delivery["sha256"]
    assert result.value["items"] == List.duplicate(String.duplicate("x", 8192), 511)
    assert File.read!(c.marker) == "loaded\n"
    assert length(String.split(File.read!(c.called), "\n", trim: true)) == 1
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    loads = File.read!(c.marker)
    calls = File.read!(c.called)
    path = Path.join(c.dir, id <> ".jsonl")
    journal_hash = Manifest.sha256(File.read!(path))
    resumed = start(c, id)
    assert Session.info(resumed).extension_result["delivery"] == delivery
    assert {:ok, ^result} = Session.materialize_result(resumed, delivery)
    assert File.read!(c.marker) == loads
    assert File.read!(c.called) == calls
    assert Manifest.sha256(File.read!(path)) == journal_hash
    assert :ok = Session.close_confirmed(resumed)
  end

  test "cancel and the existing aggregate deadline stop a waiting producer without replay", c do
    for action <- [:cancel, :deadline] do
      File.rm(c.called)
      session = start(c)
      id = Session.info(session).id

      assert :ok =
               Session.invoke_export(session, :command, "ext__output__publish", %{"wait" => true})

      wait_callback(c.called, System.monotonic_time(:millisecond) + 3_000)

      if action == :cancel do
        assert :ok = Session.cancel(session)
        assert_receive {:ipse, ^session, {:done, :cancelled}}, 3_000
      else
        state =
          :sys.replace_state(session, fn state ->
            clock = %{
              state.extension_output_clock
              | started_ms: System.monotonic_time(:millisecond) - 120_001
            }

            %{state | extension_output_clock: clock}
          end)

        send(session, {:extension_output_deadline, state.job_ref})
        assert_receive {:ipse, ^session, {:done, :error}}, 3_000
      end

      assert Session.info(session).phase == :idle
      events = events(c, session)
      assert Enum.count(events, &(&1["type"] == "extension_invocation_intent")) == 1

      refute Enum.any?(
               events,
               &(&1["type"] in (ResultSource.types() ++ ["extension_invocation_result"]))
             )

      assert :ok = Session.close_confirmed(session)
      calls = File.read!(c.called)
      resumed = start(c, id)
      assert Session.info(resumed).phase == :idle
      assert File.read!(c.called) == calls
      assert :ok = Session.close_confirmed(resumed)
    end
  end

  test "insufficient journal capacity refuses before source begin and releases reservations", c do
    c = %{c | config: Map.put(c.config, :journal, %{"max_bytes" => 32_768})}
    session = start(c)
    assert :ok = Session.invoke_export(session, :command, "ext__output__publish", %{})
    assert_receive {:ipse, ^session, {:done, :error}}, 30_000

    refute Enum.any?(
             events(c, session),
             &(&1["type"] in (ResultSource.types() ++ ["extension_invocation_result"]))
           )

    state = :sys.get_state(session)
    assert state.extension_output == nil
    writer = :sys.get_state(state.journal_writer)
    assert writer.reserved_bytes == 0
    assert writer.reserved_events == 0
    assert writer.reservations == %{}
  end

  test "malformed sealed source is rejected before repairing a torn journal tail", c do
    session = start(c)
    _delivery = command(session)
    id = Session.info(session).id
    original = events(c, session)
    assert :ok = Session.close_confirmed(session)

    tampered =
      Enum.map(original, fn event ->
        if event["type"] == "extension_output_seal",
          do: Map.put(event, "sha256", String.duplicate("0", 64)),
          else: event
      end)

    bytes = Enum.map_join(tampered, "\n", &Jason.encode!/1) <> "\n{\"torn\":"
    path = Path.join(c.dir, id <> ".jsonl")
    File.write!(path, bytes)
    loads = File.read!(c.marker)
    calls = File.read!(c.called)

    assert {:error, _} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: c.config, cwd: c.root, state_dir: c.dir, subscriber: self(), id: id}
             )

    assert File.read!(path) == bytes
    assert File.read!(c.marker) == loads
    assert File.read!(c.called) == calls
  end

  test "conformance validates saved results and never substitutes an earlier inline value", c do
    counts = %{
      "extension_output_begin" => 1,
      "extension_output_chunk" => 7,
      "extension_output_seal" => 1,
      "extension_invocation_result" => 1
    }

    fixture = %{
      "version" => 1,
      "cases" => [
        %{
          "id" => "saved-command",
          "kind" => "command",
          "name" => "ext__output__publish",
          "arguments" => %{},
          "expect" => %{
            "status" => "ok",
            "requests" => 0,
            "records" => counts,
            "cleanup" => true
          }
        }
      ]
    }

    assert {:ok, report} = Conformance.run(c.catalog, c.home, fixture)
    assert report["passed"]
    assert hd(report["cases"])["journal_valid"]
    earlier = %{"items" => ["small"], "pad" => ""}
    counts = Map.put(counts, "extension_invocation_result", 2)

    fixture = %{
      "version" => 1,
      "cases" => [
        %{
          "id" => "latest-saved",
          "kind" => "prompt",
          "text" => "Synthetic inline then saved result",
          "script" => [
            %{"tool" => %{"name" => "ext__output__publish", "arguments" => %{"inline" => true}}},
            %{"tool" => %{"name" => "ext__output__publish", "arguments" => %{}}},
            %{"assistant" => "done"}
          ],
          "expect" => %{
            "status" => "ok",
            "records" => counts,
            "value" => earlier,
            "final" => "done"
          }
        }
      ]
    }

    assert {:ok, report} = Conformance.run(c.catalog, c.home, fixture, yes: true)
    refute report["passed"]
    [result] = report["cases"]
    refute result["checks"]["value"]
    assert Enum.all?(Map.delete(result["checks"], "value"), fn {_, passed} -> passed end)
  end

  test "an approved action continues into one complete saved result", c do
    session = start(c)

    assert :ok =
             Session.invoke_export(session, :command, "ext__output__publish", %{
               "late_write" => true
             })

    assert_receive {:ipse, ^session, {:approval, ref, "extension:state.put", _}}, 5_000
    assert :ok = Session.approve(session, ref, true)
    assert_receive {:ipse, ^session, {:extension_result, display}}, 10_000
    assert_receive {:ipse, ^session, {:done, :ok}}, 3_000
    records = events(c, session)
    [action] = Enum.filter(records, &(&1["type"] == "extension_action_result"))
    assert action["outcome"]["status"] == "ok"
    assert action["outcome"]["value"]["record"]["value"] == %{"late" => true}
    [result] = Enum.filter(records, &(&1["type"] == "extension_invocation_result"))
    assert result["version"] == 2
    assert result["action_count"] == 1
    assert result["actions_sha256"] == Ipse.Compaction.digest([action])
    assert {:ok, %{value: value}} = Session.materialize_result(session, display["delivery"])
    assert value["items"] == List.duplicate(String.duplicate("雪", 2730), 3)
    assert :ok = Invocation.validate_events(records)
    assert :ok = Session.close_confirmed(session)
  end

  test "an approval after the aggregate deadline cannot admit a state write", c do
    session = start(c)

    assert :ok =
             Session.invoke_export(session, :command, "ext__output__publish", %{
               "late_write" => true
             })

    assert_receive {:ipse, ^session, {:approval, ref, "extension:state.put", _}}, 5_000

    :sys.replace_state(session, fn s ->
      clock = %{
        s.extension_output_clock
        | started_ms: System.monotonic_time(:millisecond) - 120_001
      }

      %{s | extension_output_clock: clock}
    end)

    assert :ok = Session.approve(session, ref, true)
    assert_receive {:ipse, ^session, {:done, :error}}, 10_000
    records = events(c, session)

    refute Enum.any?(
             records,
             &(&1["type"] in ~w(extension_action_intent extension_action_result extension_output_begin extension_invocation_result))
           )

    assert Path.wildcard(Path.join(c.home, "extension-state-v1/**/*.json")) == []
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    resumed = start(c, id)
    assert Session.info(resumed).phase == :idle
    assert Path.wildcard(Path.join(c.home, "extension-state-v1/**/*.json")) == []
  end

  defp wait_callback(path, deadline) do
    if File.exists?(path) do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline

      receive do
      after
        10 -> wait_callback(path, deadline)
      end
    end
  end
end
