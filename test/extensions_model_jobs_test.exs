defmodule Ipse.Extensions.ModelJobsTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal, Usage, Budget}
  alias Ipse.Extensions.{Catalog, Config, Registry, Store, ChildUsage}

  defmodule Main do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, {:main_request, config[:delegation_origin]})

      assistant =
        if config[:delegation_origin] == nil and not Enum.any?(messages, &(&1["role"] == "tool")) do
          %{
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [
              %{
                "id" => "parallel",
                "type" => "function",
                "function" => %{
                  "name" => "delegate_parallel",
                  "arguments" =>
                    Jason.encode!(%{
                      "tasks" => [
                        %{"task" => "First synthetic task", "context" => "Public fixture"},
                        %{"task" => "Second synthetic task", "context" => "Public fixture"}
                      ]
                    })
                }
              }
            ]
          }
        else
          %{"role" => "assistant", "content" => "finished"}
        end

      {:ok, assistant, %{"input_tokens" => 7, "output_tokens" => 3}}
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-model-jobs-#{Usage.id()}")
    directory = Path.join(root, "source")
    File.mkdir_p!(Path.join(directory, "ebin"))
    module = "Independent.ModelJobs#{System.unique_integer([:positive])}"
    capabilities = ~w(event.job host.actions host.model)

    job = %{
      "id" => "extract",
      "description" => "Synthetic accounted extraction",
      "arguments_schema" => %{
        "type" => "object",
        "required" => ["event"],
        "additionalProperties" => false,
        "properties" => %{"event" => %{"type" => "object"}}
      },
      "result_schema" => %{
        "type" => "object",
        "required" => ["status"],
        "additionalProperties" => false,
        "properties" => %{"status" => %{"type" => "string"}}
      }
    }

    exports = Map.put(Catalog.empty(), "jobs", [job])

    declaration = %{
      "id" => "extract",
      "handler" => "extract",
      "event" => "prompt.effective_committed",
      "event_version" => 1,
      "view" => "metadata",
      "mode" => "job",
      "schedule" => "before_request",
      "required" => true
    }

    code = """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}, "subscriptions" => [#{inspect(declaration)}]}
      def init(options), do: {:ok, options}
      def handle("event.job", _payload, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => state["request"]}, state}
      def handle("host.actions", payload, state), do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{"status" => payload["outcome"]["status"]}}, state}
    end
    """

    file = Path.join(root, "fixture.ex")
    File.write!(file, code)

    {output, status} =
      System.cmd(
        System.find_executable("elixirc"),
        ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(directory, "ebin"), file],
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.write!(Path.join(directory, "LICENSE"), "MIT synthetic fixture")

    manifest = %{
      "format" => 1,
      "id" => "fixture/model-jobs",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
      "license_file" => "LICENSE",
      "options_schema" => %{
        "type" => "object",
        "required" => ["request"],
        "additionalProperties" => false,
        "properties" => %{"request" => %{"type" => "object"}}
      },
      "capabilities" => capabilities,
      "exports" => exports,
      "subscriptions" => [declaration],
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(["LICENSE", "ebin/Elixir.#{module}.beam"], fn path ->
          bytes = File.read!(Path.join(directory, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end)
    }

    File.write!(Path.join(directory, "extension.json"), Jason.encode!(manifest))
    on_exit(fn -> File.rm_rf!(root) end)
    %{artifacts: root, directory: directory, capabilities: capabilities}
  end

  setup context do
    root = Path.join(context.artifacts, "run-#{Usage.id()}")
    File.mkdir_p!(root)
    home = Path.join(root, "home")
    {:ok, installed} = Store.import(context.directory, Path.join(home, "extensions/artifacts"))
    %{root: root, home: home, digest: installed.digest, dir: Path.join(root, "state")}
  end

  test "parallel child model jobs overlap with explicit approvals and one durable tree quota",
       context do
    {base, server} = http_fixture(self())

    request = %{
      "op" => "model.complete",
      "version" => 1,
      "profile" => "extract",
      "instruction" => "Extract only from the explicit input.",
      "input" => "Public synthetic input",
      "max_output_bytes" => 1024,
      "timeout_ms" => 10_000
    }

    source = %{
      scope: "operator",
      path: Path.join(context.root, "operator.json"),
      data: %{
        "extensions" => [
          %{
            "instance" => "extractor",
            "artifact" => context.digest,
            "enabled" => true,
            "options" => %{"request" => request},
            "order" => 1,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => context.digest,
            "capabilities" => context.capabilities,
            "allow_project" => false,
            "allow_children" => true
          }
        ]
      }
    }

    {:ok, catalog} = Config.resolve([source], [])
    {:ok, entries} = Registry.prepare(catalog, context.home)

    config = %{
      provider: :openai,
      model: "main-fixture",
      provider_module: Main,
      test_pid: self(),
      home: context.home,
      approval: :ask,
      extensions: entries,
      subagents: true,
      subagent_concurrency: 2,
      budget: %{"version" => 1, "max_requests" => 7},
      profiles: %{
        "extract" => %{"provider" => "ollama", "model" => "helper-fixture", "base_url" => base}
      }
    }

    pid = start(context, config)
    :ok = Session.prompt(pid, "This main prompt must not become the helper input.")

    assert_receive {:ipse, ^pid, {:approval, root_ref, "extension:model.complete", proposed}},
                   3000

    assert proposed["request"] == request
    :ok = Session.approve(pid, root_ref, true)
    assert_receive {:helper_http, root_http, payload}, 3000

    assert [helper_system, helper_context] = payload["messages"]
    assert helper_system["role"] == "system"
    refute helper_system["content"] =~ request["instruction"]
    assert helper_context["role"] == "user"
    [label, encoded] = String.split(helper_context["content"], "\n", parts: 2)
    assert label =~ "Untrusted extension task context"
    assert Jason.decode!(encoded) == Map.take(request, ~w(instruction input))

    send(root_http, :respond)
    assert_receive {:ipse, ^pid, {:approval, delegate_ref, "delegate_parallel", _}}, 3000
    :ok = Session.approve(pid, delegate_ref, true)

    children =
      for _ <- 1..2 do
        assert_receive {:ipse, ^pid, {:approval, child_ref, name, args}}, 3000

        assert String.starts_with?(name, "child ") and
                 String.ends_with?(name, "/extension:model.complete")

        assert args["request"] == request
        assert args["execution"]["provider"] == "ollama"
        :ok = Session.approve(pid, child_ref, true)
        assert_receive {:helper_http, http, child_payload}, 3000
        assert child_payload == payload
        http
      end

    assert length(Enum.uniq(children)) == 2
    assert Enum.all?(children, &Process.alive?/1)
    {:ok, pending} = Budget.saved(context.dir, Session.info(pid).id)
    assert pending["request_count"] == 4
    assert pending["unsettled_count"] == 2
    Enum.each(children, &send(&1, :respond))
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
    assert :ok = Task.await(server)
    id = Session.info(pid).id
    {:ok, final} = Budget.saved(context.dir, id)
    assert final["request_count"] == 7
    assert final["unsettled_count"] == 0
    assert final["refused_count"] == 0
    assert final["overdrawn"] == false
    {:ok, events} = Journal.load(context.dir, id)
    assert {:ok, _} = Session.restore_context(events)
    {:ok, child_state} = ChildUsage.restore(events)
    assert length(child_state.order) == 2

    for child <- Map.values(child_state.index) do
      assert child["cleanup_confirmed"]
      assert {:ok, ledger, _, _, _} = ChildUsage.read_for_budget(context.dir, id, child)
      assert length(ledger.order) == 2

      [helper] =
        ledger.requests |> Map.values() |> Enum.filter(&(&1.admission["kind"] == "extension"))

      assert helper.admission["parent_session_id"] == id
      assert helper.admission["selected_profile"] == "extract"
      assert helper.completion["usage"]["counts"]["total_tokens"] == 10
    end

    :ok = Session.close(pid)
    before = File.read!(Path.join(context.dir, id <> ".jsonl"))
    resumed = start(context, config, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(Path.join(context.dir, id <> ".jsonl")) == before
    refute_receive {:helper_http, _, _}, 20
  end

  defp start(context, config, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config, cwd: context.root, state_dir: context.dir, subscriber: self(), id: id}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  defp http_fixture(owner) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    server =
      Task.async(fn ->
        handlers =
          for _ <- 1..3 do
            {:ok, socket} = :gen_tcp.accept(listener, 10_000)

            Task.async(fn ->
              payload = read_request(socket, "")
              send(owner, {:helper_http, self(), payload})
              receive do: (:respond -> :ok)

              body =
                Jason.encode!(%{
                  "done" => true,
                  "message" => %{"content" => "entities"},
                  "prompt_eval_count" => 7,
                  "eval_count" => 3
                }) <> "\n"

              :ok =
                :gen_tcp.send(
                  socket,
                  "HTTP/1.1 200 OK\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                    body
                )

              :gen_tcp.close(socket)
            end)
          end

        Enum.each(handlers, &Task.await(&1, 10_000))
        :gen_tcp.close(listener)
        :ok
      end)

    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)
    {"http://127.0.0.1:#{port}", server}
  end

  defp read_request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
        read_body(socket, body, String.to_integer(size)) |> Jason.decode!()

      [_] ->
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
        read_request(socket, buffer <> bytes)
    end
  end

  defp read_body(_, body, size) when byte_size(body) >= size, do: body

  defp read_body(socket, body, size) do
    {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
    read_body(socket, body <> bytes, size)
  end
end
