defmodule IpseEmbeddingExample.Proof do
  @moduledoc false
  alias Ipse.Session
  alias Ipse.Journal
  alias Ipse.Usage
  alias Ipse.Usage.Budget
  alias Ipse.Extension.{Config, Registry, Artifact}

  defmodule NoModel do
    def complete(_, _, _, _),
      do: raise("Explicit embedding command called the conversation model")
  end

  def run(artifact) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    false = :code.is_loaded(IpseEmbeddingExample.Embed) != false
    root = Path.join(System.tmp_dir!(), "ipse-embedding-proof-" <> Usage.id())
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    Process.put(:embedding_proof_sessions, [])
    fixture = fixture()
    previous_key = System.get_env("OPENAI_API_KEY")
    System.put_env("OPENAI_API_KEY", "synthetic-embedding-fixture-key")

    try do
      cwd = Path.join(root, "workspace")
      home = Path.join(root, "home")
      dir = Path.join(root, "sessions")
      File.mkdir_p!(cwd)
      {:ok, imported} = Artifact.import(artifact, Path.join(home, "extensions/artifacts"))
      manifest = Jason.decode!(File.read!(Path.join(artifact, "extension.json")))
      "ipse-example/embedding-actions" = manifest["id"]

      capabilities =
        ~w(invoke.command host.actions host.embedding host.results host.actions.mixed)

      true = Enum.sort(manifest["capabilities"]) == Enum.sort(capabilities)

      source = %{
        scope: "operator",
        path: Path.join(root, "operator.json"),
        data: %{
          "extensions" => [
            %{
              "instance" => "embeddings",
              "artifact" => imported.digest,
              "enabled" => true,
              "options" => %{},
              "order" => 1,
              "lifetime" => "persistent"
            }
          ],
          "extension_trust" => [
            %{
              "artifact" => imported.digest,
              "capabilities" => capabilities,
              "allow_project" => false,
              "allow_children" => false
            }
          ]
        }
      }

      {:ok, selections} = Config.resolve([source], [])
      {:ok, entries} = Registry.prepare(selections, home)

      config = %{
        provider: :ollama,
        model: "unused-conversation",
        provider_module: NoModel,
        home: home,
        operator_home: nil,
        approval: :ask,
        extensions: entries,
        compact: false,
        budget: %{
          "version" => 1,
          "max_requests" => 2,
          "max_input_tokens" => 100,
          "reserve_input_tokens" => 20,
          "max_output_tokens" => 0,
          "reserve_output_tokens" => 8
        },
        embedding_profiles: %{
          "local768" => %{
            "operation" => "embedding",
            "provider" => "ollama",
            "model" => "fixture-local-768",
            "dimensions" => 768,
            "dimension_mode" => "native",
            "credential" => "none",
            "base_url" => fixture.base,
            "timeout_ms" => 10_000
          },
          "api4096" => %{
            "operation" => "embedding",
            "provider" => "openai",
            "model" => "fixture-api-4096",
            "dimensions" => 4096,
            "dimension_mode" => "request",
            "credential" => "OPENAI_API_KEY",
            "base_url" => fixture.base <> "/v1",
            "timeout_ms" => 10_000
          }
        }
      }

      pid = start(config, cwd, dir)
      local = arguments("local768", 2)
      api = arguments("api4096", 8)

      :ok = invoke(pid, local)
      denied = approval(pid, local, fixture.base, "/api/embed", 768)
      true = requests(fixture) == []
      :ok = Session.approve(pid, denied, false)
      done(pid)
      "denied" = Session.info(pid).extension_result["value"]["status"]
      true = requests(fixture) == []
      true = Session.info(pid).accounting["request_count"] == 0

      :ok = invoke(pid, local)
      ref = approval(pid, local, fixture.base, "/api/embed", 768)
      true = requests(fixture) == []
      :ok = Session.approve(pid, ref, true)
      done(pid)
      local_value = Session.info(pid).extension_result["value"]
      validate_vectors(local_value, local["inputs"], 768)
      [local_wire] = requests(fixture)
      "/api/embed" = local_wire.path

      true =
        local_wire.body == %{
          "model" => "fixture-local-768",
          "input" => local["inputs"],
          "truncate" => false
        }

      false = Map.has_key?(local_wire.headers, "authorization")
      true = local_value["usage"]["counts"]["input_tokens"] == 7

      :ok = invoke(pid, api)
      ref = approval(pid, api, fixture.base, "/v1/embeddings", 4096)
      true = length(requests(fixture)) == 1
      :ok = Session.approve(pid, ref, true)
      done(pid)
      api_value = Session.info(pid).extension_result["value"]
      validate_vectors(api_value, api["inputs"], 4096)
      [_, api_wire] = requests(fixture)
      "/v1/embeddings" = api_wire.path

      true =
        api_wire.body == %{
          "model" => "fixture-api-4096",
          "input" => api["inputs"],
          "encoding_format" => "float",
          "dimensions" => 4096
        }

      "Bearer synthetic-embedding-fixture-key" = api_wire.headers["authorization"]
      true = api_value["usage"]["counts"]["input_tokens"] == 11
      true = Enum.sum(Enum.map(api_value["vectors"], & &1["pages"])) == 48

      ev = events(dir, pid)
      for value <- [local_value, api_value], do: validate_order(ev, value["request_id"])

      true =
        Enum.count(
          ev,
          &(&1["type"] == "extension_effect_result" and &1["kind"] == "embedding.f32le")
        ) == 2

      true = Enum.count(ev, &(&1["type"] == "request_admitted")) == 2
      false = Enum.any?(ev, &(&1["type"] in ~w(extension_model_request extension_model_response)))

      true =
        Enum.all?(
          for(e <- ev, e["type"] == "request_admitted", do: Usage.operation(e) == "embedding")
        )

      false = Jason.encode!(ev) =~ "synthetic-embedding-fixture-key"
      {:ok, usage} = Usage.restore(ev, Session.info(pid).id)
      true = Usage.snapshot(usage)["version"] == 2

      true =
        Enum.all?(Usage.snapshot(usage)["requests"], fn row ->
          row["usage"]["counts"]["output_tokens"] == nil and
            row["usage"]["not_applicable_fields"] == ["output_tokens"]
        end)

      runtime = :sys.get_state(pid).config
      {:ok, budget} = Budget.snapshot(runtime)
      booked = Map.new(budget["dimensions"], &{&1["unit"], &1["booked"]})

      true =
        budget["request_count"] == 2 and
          booked == %{"requests" => 2, "input_tokens" => 18, "output_tokens" => 0}

      :ok = invoke(pid, local)
      ref = approval(pid, local, fixture.base, "/api/embed", 768)
      :ok = Session.approve(pid, ref, true)
      done(pid)
      "failed" = Session.info(pid).extension_result["value"]["status"]
      true = length(requests(fixture)) == 2
      {:ok, budget} = Budget.snapshot(:sys.get_state(pid).config)
      true = budget["request_count"] == 2 and budget["refused_count"] == 1
      ev = events(dir, pid)

      true =
        Enum.count(
          ev,
          &(&1["type"] == "extension_effect_result" and &1["kind"] == "embedding.f32le")
        ) == 2

      failed =
        ev
        |> Enum.filter(&(&1["type"] == "request_finished" and &1["outcome"] == "failed"))
        |> List.last()

      true = failed["usage"]["counts"]["input_tokens"] == nil and failed["reported_model"] == nil

      id = Session.info(pid).id
      budget_root = :sys.get_state(pid).config.budget_root
      :ok = Session.close_confirmed(pid)
      journal_before = File.read!(Path.join(dir, id <> ".jsonl"))
      budget_before = budget_bytes(budget_root)
      transport_before = requests(fixture)
      resumed = start(config, cwd, dir, id)
      :idle = Session.info(resumed).phase
      true = File.read!(Path.join(dir, id <> ".jsonl")) == journal_before
      true = budget_bytes(:sys.get_state(resumed).config.budget_root) == budget_before
      true = requests(fixture) == transport_before
      :ok = Session.close_confirmed(resumed)
      false = :code.is_loaded(IpseEmbeddingExample.Embed) != false

      %{
        "checks" => %{
          "independent_worker_artifact" => true,
          "exact_profile_inputs_destination_approval" => true,
          "denied_zero_dispatch" => true,
          "native_ollama_and_openai_requests" => true,
          "coordinate_pages_reconstruct_768_and_4096" => true,
          "eight_vector_48_page_roundtrip" => true,
          "private_source_before_completion_and_result" => true,
          "operation_aware_input_usage" => true,
          "shared_budget_zero_output_liability" => true,
          "exhaustion_zero_dispatch" => true,
          "idle_resume_zero_replay" => true,
          "no_host_worker_module_load" => true
        },
        "live_model_calls" => 0,
        "synthetic_provider_calls" => 2,
        "dimensions" => [768, 4096],
        "largest_batch_vectors" => 8
      }
    after
      Enum.each(Process.get(:embedding_proof_sessions), fn pid ->
        if Process.alive?(pid), do: Session.close(pid)
      end)

      stop_fixture(fixture)

      if previous_key,
        do: System.put_env("OPENAI_API_KEY", previous_key),
        else: System.delete_env("OPENAI_API_KEY")

      File.rm_rf!(root)
    end
  end

  defp arguments(profile, count),
    do: %{
      "profile" => profile,
      "inputs" => for(index <- 0..(count - 1), do: "Synthetic public input #{index}"),
      "timeout_ms" => 10_000
    }

  defp invoke(pid, args), do: Session.invoke_export(pid, :command, "ext__embeddings__embed", args)

  defp start(config, cwd, dir, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config, cwd: cwd, state_dir: dir, id: id, subscriber: self(), owner: self()}
      )

    Process.put(:embedding_proof_sessions, [pid | Process.get(:embedding_proof_sessions)])
    pid
  end

  defp approval(pid, args, origin, path, dimensions) do
    receive do
      {:ipse, ^pid, {:approval, ref, "extension:embedding.create", proposed}} ->
        true =
          proposed["request"] == Map.merge(args, %{"op" => "embedding.create", "version" => 1})

        true = proposed["execution"]["id"] == args["profile"]
        true = proposed["execution"]["operation"] == "embedding"
        true = proposed["execution"]["dimensions"] == dimensions

        true =
          proposed["destination"] == %{
            "origin" => origin,
            "target_sha256" => Ipse.JSON.sha256(origin <> path)
          }

        true = proposed["effect_binding"]["execution"] == proposed["execution"]
        true = proposed["effect_binding"]["destination"] == proposed["destination"]
        ref

      {:ipse, ^pid, {:done, status}} ->
        raise "Embedding ended before approval: #{inspect(status)}"

      {:ipse, ^pid, _} ->
        approval(pid, args, origin, path, dimensions)
    after
      10_000 -> raise "Embedding approval not received"
    end
  end

  defp done(pid) do
    receive do
      {:ipse, ^pid, {:done, :ok}} -> :ok
      {:ipse, ^pid, {:done, status}} -> raise "Embedding proof outcome: #{inspect(status)}"
      {:ipse, ^pid, _} -> done(pid)
    after
      30_000 -> raise "Embedding command did not finish"
    end
  end

  defp events(dir, pid) do
    {:ok, events} = Journal.load(dir, Session.info(pid).id)
    {:ok, _} = Session.restore_context(events)
    events
  end

  defp validate_vectors(value, inputs, dimensions) do
    "ok" = value["status"]
    true = length(value["vectors"]) == length(inputs)

    for {summary, index} <- Enum.with_index(value["vectors"]) do
      true = summary["index"] == index and summary["bytes"] == dimensions * 4
      true = summary["sha256"] == sha256(vector_bytes(dimensions, index))
      true = summary["input_sha256"] == Ipse.JSON.digest([Enum.at(inputs, index)])
      true = summary["pages"] == div(dimensions + 767, 768)
    end

    :ok
  end

  defp validate_order(events, request_id) do
    position = fn predicate -> Enum.find_index(events, predicate) end

    action =
      position.(&(&1["type"] == "extension_action_intent" and &1["operation_id"] == request_id))

    source =
      position.(
        &(&1["type"] == "extension_embedding_request" and &1["operation_id"] == request_id)
      )

    admitted = position.(&(&1["type"] == "request_admitted" and &1["request_id"] == request_id))

    vector =
      position.(&(&1["type"] == "extension_effect_result" and &1["operation_id"] == request_id))

    finished = position.(&(&1["type"] == "request_finished" and &1["request_id"] == request_id))

    result =
      position.(&(&1["type"] == "extension_action_result" and &1["operation_id"] == request_id))

    true = Enum.all?([action, source, admitted, vector, finished, result], &is_integer/1)

    true =
      action < source and source < admitted and admitted < vector and vector < finished and
        finished < result

    for event <- events,
        event["type"] == "extension_action_result" and
          event["request"]["op"] == "effect.result.read" and
          event["request"]["operation_id"] == request_id do
      true = Ipse.Extension.validate(Ipse.Extension.Actions.resume(event)) == :ok
      true = byte_size(Base.decode64!(event["outcome"]["value"]["values"])) <= 3072
    end

    :ok
  end

  defp vector(dimensions, index),
    do: for(coordinate <- 0..(dimensions - 1), do: (rem(coordinate + index, 17) - 8) / 16)

  defp vector_bytes(dimensions, index),
    do: for(value <- vector(dimensions, index), into: <<>>, do: <<value::little-float-size(32)>>)

  defp sha256(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp budget_bytes(root) do
    path = Path.join([root["state_dir"], "budgets", root["session_id"] <> ".jsonl"])
    File.read!(path)
  end

  defp requests(fixture), do: Agent.get(fixture.agent, &Enum.reverse/1)

  defp fixture do
    {:ok, agent} = Agent.start_link(fn -> [] end)
    {:ok, supervisor} = Task.Supervisor.start_link()

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    Task.Supervisor.start_child(supervisor, fn -> accept(listener, supervisor, agent) end)
    %{agent: agent, supervisor: supervisor, listener: listener, base: "http://127.0.0.1:#{port}"}
  end

  defp stop_fixture(fixture) do
    :gen_tcp.close(fixture.listener)
    Supervisor.stop(fixture.supervisor)
    Agent.stop(fixture.agent)
  end

  defp accept(listener, supervisor, agent) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, handler} =
          Task.Supervisor.start_child(supervisor, fn ->
            receive do: (:serve -> serve(socket, agent))
          end)

        :ok = :gen_tcp.controlling_process(socket, handler)
        send(handler, :serve)
        accept(listener, supervisor, agent)

      _ ->
        :ok
    end
  end

  defp serve(socket, agent) do
    try do
      wire = read_request(socket, "")
      Agent.update(agent, &[wire | &1])
      count = length(wire.body["input"])

      body =
        case wire.path do
          "/api/embed" ->
            %{
              "model" => "fixture-local-768",
              "embeddings" => for(index <- 0..(count - 1), do: vector(768, index)),
              "prompt_eval_count" => 7,
              "total_duration" => 2_000_000
            }

          "/v1/embeddings" ->
            %{
              "model" => "fixture-api-4096",
              "data" =>
                for(
                  index <- Enum.reverse(0..(count - 1)),
                  do: %{"index" => index, "embedding" => vector(4096, index)}
                ),
              "usage" => %{"prompt_tokens" => 11, "total_tokens" => 11}
            }
        end

      bytes = Jason.encode!(body)

      :ok =
        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(bytes)}\r\nconnection: close\r\n\r\n" <>
            bytes
        )
    after
      :gen_tcp.close(socket)
    end
  end

  defp read_request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [head, body] ->
        [first | lines] = String.split(head, "\r\n")

        headers =
          Map.new(lines, fn line ->
            [key, value] = String.split(line, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        size = String.to_integer(headers["content-length"] || "0")
        ["POST", path, _] = String.split(first, " ")
        %{path: path, headers: headers, body: Jason.decode!(read_body(socket, body, size))}

      [_] ->
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 10_000)
        read_request(socket, buffer <> bytes)
    end
  end

  defp read_body(_, bytes, size) when byte_size(bytes) >= size, do: bytes

  defp read_body(socket, bytes, size) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 10_000)
    read_body(socket, bytes <> chunk, size)
  end
end
