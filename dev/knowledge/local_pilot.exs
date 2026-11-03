Code.require_file("pilot.exs", __DIR__)
Code.require_file("pilot_reservation.exs", __DIR__)

defmodule Ipse.Development.Knowledge.LocalPilot do
  @moduledoc false
  alias Ipse.Development.Knowledge.{Pilot, PilotReservation}
  alias Ipse.Provider.Ollama.Models

  @origin "http://127.0.0.1:11434"
  @model "qwen3.5:4b"
  @manifest "d8b0f5e9760cd1682034f292d7ef72ec46f432149be0df7574bf2d6e92e38c04"
  @metadata "c2ed7207a7cd47d14d7f7ddd1ab7a9e013ba0b94e95e11ab9c582f91c545cbe2"
  @runtime "0.40.13"
  @context 8192
  @max_calls 120

  def main do
    with "ollama-qwen3.5:4b" <- System.get_env("IPSE_KNOWLEDGE_PILOT_CONFIRM"),
         directory when is_binary(directory) and directory != "" <-
           System.get_env("IPSE_KNOWLEDGE_PILOT_AUDIT_DIR"),
         true <- Path.type(directory) == :absolute,
         {:ok, candidates} <- Pilot.open_audit(directory),
         {:ok, ^directory} <- Ipse.Workspace.canonical_path(directory) do
      try do
        run(directory, candidates)
      after
        File.close(candidates)
      end
    else
      _ -> refuse()
    end
  rescue
    _ -> refuse()
  catch
    _, _ -> refuse()
  end

  defp run(directory, candidates) do
    with {:ok, attempts} <- open_private(directory, "attempts.jsonl"),
         {:ok, progress} <- open_private(directory, "progress.jsonl") do
      try do
        config = config()
        declaration = declaration(config)
        :ok = write_private(directory, "declaration.json", declaration)
        :ok = Ipse.Runner.protected_sync_directory(directory)
        :ok = Ipse.Runner.protected_sync_directory(Path.dirname(directory))

        case PilotReservation.with_reservation(declaration, fn guard ->
               execute(config, declaration, attempts, progress, candidates, guard)
             end) do
          {:ok, receipt} ->
            :ok = write_private(directory, "result.json", receipt)
            :ok = Ipse.Runner.protected_sync_directory(directory)
            IO.puts(Jason.encode!(receipt))
            if receipt["status"] != "completed", do: System.halt(1)

          _ ->
            refuse()
        end
      after
        File.close(progress)
        File.close(attempts)
      end
    else
      _ -> refuse()
    end
  end

  defp execute(config, declaration, attempts, progress, candidates, guard) do
    counter = :atomics.new(1, signed: false)

    request = fn selected, messages, tools, emit ->
      guarded_request(selected, messages, tools, emit, attempts, counter, guard)
    end

    result =
      Pilot.run(
        config,
        request,
        fn row -> :ok = Pilot.write_audit(progress, row) end,
        &Pilot.write_audit(candidates, &1)
      )

    {status, reported_count} =
      case result do
        {:ok, _, count} -> {"completed", count}
        {:error, _, _, count} -> {"stopped", count}
      end

    unchanged = declaration(config) === declaration
    status = if unchanged, do: status, else: "stopped"

    {:ok,
     %{
       "version" => 1,
       "status" => status,
       "observed_input_hashes_match_before_after" => unchanged,
       "pre_dispatch_records" => :atomics.get(counter, 1),
       "pilot_loop_reported_calls" => reported_count,
       "conservatively_charged_calls" => @max_calls,
       "reserved_calls" => @max_calls,
       "published" => 0
     }}
  end

  @doc false
  def guarded_request(
        config,
        messages,
        tools,
        emit,
        attempts,
        counter,
        guard,
        models \\ Models,
        provider \\ &Ipse.Provider.complete/4
      ) do
    with :ok <- guard.(),
         {:ok, job} when not is_nil(job) <- models.begin_job(config, :text, 80_000) do
      models.with_job(job, config, fn selected ->
        number = :atomics.get(counter, 1) + 1

        if :ok == guard.() and number <= @max_calls and
             Pilot.write_audit(attempts, %{"version" => 1, "attempt" => number}) == :ok do
          :atomics.put(counter, 1, number)
          result = provider.(selected, messages, tools, emit)
          models.finish_job(job, selected, result)
        else
          {:error, :pilot_attempt_unavailable}
        end
      end)
    else
      _ -> {:error, :pilot_model_unavailable}
    end
  end

  defp config do
    pin = %{
      "version" => 1,
      "trust_boundary" => "cooperative_service_metadata",
      "manifest_sha256" => @manifest,
      "metadata_sha256" => @metadata,
      "runtime_version" => @runtime,
      "minimum_context_tokens" => @context
    }

    %{
      provider: :ollama,
      model: @model,
      base_url: @origin,
      reasoning_effort: "none",
      ollama_context_tokens: @context,
      ollama_model_pin: pin,
      execution: %{
        provider: "ollama",
        model: @model,
        ollama_context_tokens: @context,
        ollama_model_pin: pin
      },
      timeout_ms: 60_000,
      max_response_bytes: 131_072,
      max_output_tokens: 4096
    }
  end

  defp declaration(config) do
    paths = [
      __ENV__.file,
      Path.expand("../pilot-knowledge-local.exs", __DIR__),
      Path.expand("pilot.exs", __DIR__),
      Path.expand("pilot_reservation.exs", __DIR__),
      Path.expand("../../lib/ipse/provider.ex", __DIR__),
      Path.expand("../../lib/ipse/provider/ollama.ex", __DIR__),
      Path.expand("../../lib/ipse/provider/ollama_models.ex", __DIR__),
      Path.expand("../../lib/ipse/provider/registry.ex", __DIR__),
      Path.expand("../../lib/ipse/provider/stream.ex", __DIR__),
      Path.expand("../../lib/ipse/provider/transport.ex", __DIR__),
      Path.expand("../../lib/ipse/provider/completion_witness.ex", __DIR__),
      Path.expand("../../lib/ipse/json.ex", __DIR__),
      Path.expand("../../lib/ipse/http.ex", __DIR__),
      Path.expand("../../lib/ipse/usage.ex", __DIR__)
    ]

    # Pilot is compiled from source by Code.require_file, not from a BEAM path.
    modules = [
      Ipse.Provider,
      Ipse.Provider.Ollama,
      Models,
      Ipse.Provider.Registry,
      Ipse.Provider.Stream,
      Ipse.Provider.Transport,
      Ipse.Provider.CompletionWitness,
      Ipse.JSON,
      Ipse.HTTP,
      Ipse.Usage,
      Jason
    ]

    %{
      "version" => 1,
      "route" =>
        Map.take(config, [
          :provider,
          :model,
          :base_url,
          :ollama_model_pin,
          :ollama_context_tokens,
          :reasoning_effort,
          :timeout_ms,
          :max_response_bytes,
          :max_output_tokens
        ]),
      "case_sha256" => Ipse.JSON.digest([Pilot.cases()]),
      "tool_sha256" => Ipse.JSON.digest([Pilot.tool()]),
      "source_sha256" => Map.new(paths, &{Path.relative_to_cwd(&1), sha_file(&1)}),
      "beam_path_sha256" =>
        Map.new(modules, &{Atom.to_string(&1), sha_file(to_string(:code.which(&1)))}),
      "source_to_executing_beam_correspondence" => "unverified",
      "maximum_inference_calls_reserved" => @max_calls,
      "maximum_metadata_requests" => @max_calls * 12,
      "sessions" => 3,
      "turns_per_session" => 20,
      "retries" => 0,
      "published" => 0,
      "identity_assurance" => "cooperative service metadata; not per-request weight attestation"
    }
  end

  defp sha_file(path), do: path |> File.read!() |> Ipse.JSON.sha256()

  defp open_private(directory, name) do
    path = Path.join(directory, name)

    with {:ok, file} <- File.open(path, [:write, :binary, :exclusive]),
         :ok <- File.chmod(path, 0o600),
         do: {:ok, file}
  end

  defp write_private(directory, name, value) do
    with {:ok, file} <- open_private(directory, name) do
      try do
        Pilot.write_audit(file, value)
      after
        File.close(file)
      end
    end
  end

  defp refuse do
    IO.puts(
      :stderr,
      "Local pilot refused; inspect its private declaration and first outcome before any further run."
    )

    System.halt(1)
  end
end
