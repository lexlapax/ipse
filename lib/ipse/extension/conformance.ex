defmodule Ipse.Extension.Conformance do
  @moduledoc "Explicit synthetic SDK exercise through ordinary owned Sessions, never a provider replay."
  alias Ipse.Session
  alias Ipse.Journal
  alias Ipse.Observability.Trace
  alias Ipse.JSON, as: Schema
  alias Ipse.Extension.Registry
  @text %{"type" => "string", "maxLength" => 8192}
  @object %{"type" => "object"}
  @statuses ~w(ok error question cancelled refused timeout)

  defmodule Model do
    @moduledoc false
    def complete(config, messages, _tools, emit) do
      marker = config.conformance_case["expect"]["context_contains"]
      reference = Enum.at(messages, 1, %{})

      seen =
        is_binary(marker) and reference["role"] == "user" and
          String.contains?(reference["content"] || "", marker)

      user_marker = config.conformance_case["expect"]["user_contains"]
      user = Enum.reverse(messages) |> Enum.find(%{}, &(&1["role"] == "user"))
      user_seen = is_binary(user_marker) and String.contains?(user["content"] || "", user_marker)

      send(
        config.conformance_owner,
        {:conformance_request, config.conformance_ref, %{context: seen, user: user_seen}}
      )

      index = Enum.count(messages, &(&1["role"] == "assistant"))

      frame =
        Enum.at(config.conformance_script, index, %{
          "assistant" => "Conformance fixture completed."
        })

      assistant =
        case frame do
          %{"assistant" => text} ->
            emit.({:text, text})
            %{"role" => "assistant", "content" => text}

          %{"tool" => tool} ->
            %{
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [
                %{
                  "id" => "fixture_call_#{index + 1}",
                  "type" => "function",
                  "function" => %{
                    "name" => tool["name"],
                    "arguments" => Jason.encode!(tool["arguments"])
                  }
                }
              ]
            }
        end

      {:ok, assistant, %{}}
    end
  end

  def read(path) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        with bytes when is_binary(bytes) <- IO.binread(file, 16_385),
             {:ok, fixture} <- Ipse.JSON.decode_bounded(bytes, 16_384),
             :ok <- validate(fixture) do
          {:ok, fixture, Ipse.JSON.sha256(bytes)}
        else
          _ -> {:error, :invalid_conformance_fixture}
        end
      after
        File.close(file)
      end
    else
      _ -> {:error, :invalid_conformance_fixture}
    end
  end

  def validate(fixture) do
    with :ok <- Schema.validate_arguments(schema(), fixture),
         true <- fixture["version"] === 1,
         true <- files?(Map.get(fixture, "files", %{})),
         true <- options?(Map.get(fixture, "options", %{})),
         cases = fixture["cases"],
         true <- length(cases) == length(Enum.uniq_by(cases, & &1["id"])),
         true <- Enum.all?(cases, &case?/1) do
      :ok
    else
      _ -> {:error, :invalid_conformance_fixture}
    end
  rescue
    _ -> {:error, :invalid_conformance_fixture}
  end

  def schema do
    expectation =
      object(
        %{
          "status" => %{"type" => "string", "enum" => @statuses},
          "final" => @text,
          "value" => @object,
          "context_contains" => @text,
          "user_contains" => @text,
          "records" => @object,
          "files" => @object,
          "requests" => integer(0, 10),
          "cleanup" => %{"type" => "boolean"},
          "action_statuses" => %{
            "type" => "array",
            "maxItems" => 128,
            "items" => %{
              "type" => "string",
              "enum" => ~w(ok conflict denied unknown answered cancelled failed)
            }
          }
        },
        ["status"]
      )

    scenario =
      object(
        %{
          "id" => %{"type" => "string", "minLength" => 1, "maxLength" => 32},
          "kind" => %{"type" => "string", "enum" => ~w(prompt command service tool)},
          "text" => @text,
          "name" => @text,
          "arguments" => @object,
          "options" => @object,
          "answers" => %{"type" => "array", "maxItems" => 8, "items" => @object},
          "timeout_ms" => integer(100, 60_000),
          "cancel_after_ms" => integer(1, 60_000),
          "script" => %{
            "type" => "array",
            "maxItems" => 8,
            "items" =>
              object(%{
                "assistant" => @text,
                "tool" => object(%{"name" => @text, "arguments" => @object}, ~w(name arguments))
              })
          },
          "expect" => expectation
        },
        ~w(id kind expect)
      )

    object(
      %{
        "version" => %{"type" => "integer", "enum" => [1]},
        "files" => @object,
        "options" => @object,
        "cases" => %{"type" => "array", "minItems" => 1, "maxItems" => 16, "items" => scenario}
      },
      ~w(version cases)
    )
  end

  def run(catalog, installation_home, fixture, opts \\ []) do
    with {:ok, trace_policy} <- Trace.policy(opts),
         :ok <- validate(fixture),
         true <- selected?(catalog, fixture),
         root = Path.join(System.tmp_dir!(), "ipse-conformance-#{Ipse.Usage.id()}"),
         :ok <- File.mkdir(root),
         :ok <- File.chmod(root, 0o700) do
      try do
        workspace = Path.join(root, "workspace")
        home = Path.join(root, "home")
        File.mkdir!(workspace)
        File.mkdir!(home)
        :ok = seed(workspace, expand(Map.get(fixture, "files", %{}), workspace, home))

        cases =
          Enum.reduce_while(fixture["cases"], [], fn scenario, completed ->
            result =
              exercise(
                catalog,
                installation_home,
                fixture,
                scenario,
                root,
                workspace,
                home,
                Keyword.put(opts, :trace_policy, trace_policy)
              )

            next = [result | completed]

            if result["passed"] and result["cleanup_confirmed"],
              do: {:cont, next},
              else: {:halt, next}
          end)
          |> Enum.reverse()

        stopped = length(cases) != length(fixture["cases"])

        artifacts =
          cases
          |> Enum.flat_map(&Map.get(&1, "selected_artifacts", []))
          |> Enum.uniq()
          |> Enum.sort_by(&{&1["instance"], &1["artifact_sha256"]})

        cases = Enum.map(cases, &Map.delete(&1, "selected_artifacts"))

        report = %{
          "version" => 1,
          "provider" => "synthetic",
          "passed" => not stopped and Enum.all?(cases, & &1["passed"]),
          "case_count" => length(cases),
          "declared_cases" => length(fixture["cases"]),
          "stopped_early" => stopped,
          "safe_to_continue" => Enum.all?(cases, & &1["cleanup_confirmed"]),
          "selected_artifacts" => artifacts,
          "cases" => cases,
          "retained" => opts[:keep] == true
        }

        {:ok, if(opts[:keep] == true, do: Map.put(report, "directory", root), else: report)}
      after
        unless opts[:keep] == true, do: File.rm_rf!(root)
      end
    else
      _ -> {:error, :invalid_conformance_configuration}
    end
  rescue
    _ -> {:error, :conformance_failed}
  catch
    :exit, _ -> {:error, :conformance_failed}
  end

  defp exercise(catalog, installation_home, fixture, scenario, root, cwd, home, opts) do
    scenario = expand(scenario, cwd, home)
    overrides = Map.merge(Map.get(fixture, "options", %{}), Map.get(scenario, "options", %{}))

    catalog =
      Map.update!(catalog, "instances", fn instances ->
        Enum.map(instances, fn instance ->
          value = Map.get(overrides, instance["instance"], instance["options"])
          Map.put(instance, "options", expand(value, cwd, home))
        end)
      end)

    case Registry.prepare(catalog, installation_home) do
      {:ok, entries} ->
        ref = make_ref()

        config = %{
          provider: :demo,
          model: "synthetic-conformance",
          provider_module: Model,
          home: home,
          operator_home: nil,
          extensions: entries,
          approval: if(opts[:yes] == true, do: :allow, else: :deny),
          operator_questions: true,
          compact: false,
          context_bytes: 65_536,
          max_steps: 10,
          sandbox: Keyword.get(opts, :sandbox, :off),
          subagents: false,
          mcp_servers: [],
          conformance_owner: self(),
          conformance_ref: ref,
          conformance_case: scenario,
          conformance_script: script(scenario),
          observability: Keyword.get(opts, :observability, Ipse.Observability.defaults())
        }

        directory = Path.join(root, "sessions")

        case DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                [
                  config: config,
                  cwd: cwd,
                  state_dir: directory,
                  subscriber: self(),
                  owner: self()
                ]}
             ) do
          {:ok, session} ->
            exercise_traced(session, scenario, ref, directory, cwd, opts[:trace_policy])
            |> Map.put(
              "selected_artifacts",
              Enum.map(
                entries,
                &Map.take(
                  &1.identity,
                  ~w(instance artifact artifact_sha256 host_sha256 runtime sdk protocol)
                )
              )
            )

          _ ->
            result(scenario, "refused", [], 0, %{}, true, %{}, cwd)
        end

      _ ->
        result(scenario, "refused", [], 0, %{}, true, %{}, cwd)
    end
  end

  defp exercise_traced(session, scenario, ref, directory, cwd, policy) do
    case Trace.start(session, policy) do
      {:ok, tracer} ->
        try do
          report = exercise_session(session, scenario, ref, directory, cwd)

          case Trace.stop(tracer) do
            {:ok, nil} ->
              report

            {:ok, trace} ->
              report
              |> Map.put("developer_trace", trace)
              |> Map.update!(
                "passed",
                &(&1 and trace["cleanup_confirmed"] and
                    trace["reason"] not in ["trace_error", "watchdog_down"])
              )

            _ ->
              report
              |> Map.put("passed", false)
              |> Map.put("developer_trace", %{"error" => "capture_lost"})
          end
        after
          if tracer != nil and Process.alive?(tracer), do: Trace.stop(tracer)
          if Process.alive?(session), do: Session.close(session)
        end

      _ ->
        cleanup = Session.close(session) == :ok

        result(scenario, "refused", [], 0, %{}, cleanup, %{}, cwd)
        |> Map.put("passed", false)
        |> Map.put("developer_trace", %{"error" => "capture_unavailable"})
    end
  end

  defp exercise_session(session, scenario, ref, directory, cwd) do
    try do
      admission =
        case scenario["kind"] do
          kind when kind in ~w(prompt tool) ->
            Session.prompt(session, Map.get(scenario, "text", "Synthetic SDK fixture"))

          "command" ->
            Session.invoke_export(session, :command, scenario["name"], scenario["arguments"])

          "service" ->
            Session.invoke_export(session, :service, scenario["name"], scenario["arguments"])
        end

      deadline = System.monotonic_time(:millisecond) + Map.get(scenario, "timeout_ms", 15_000)

      cancel =
        if scenario["cancel_after_ms"],
          do: System.monotonic_time(:millisecond) + scenario["cancel_after_ms"]

      outcome =
        if admission == :ok,
          do: await(session, ref, Map.get(scenario, "answers", []), deadline, cancel, 0, %{}),
          else: {"refused", 0, %{}}

      {status, requests, seen} = outcome
      info = Session.info(session)
      cleanup = Session.close(session) == :ok
      {_callbacks, seen} = drain_requests(ref, requests, seen)
      requests = info.accounting["request_count"]
      {:ok, events} = Journal.load(directory, info.id)

      valid =
        match?({:ok, _}, Ipse.Session.Saved.inspect_saved(directory, info.id)) and
          Ipse.Extension.TextResources.validate_events(events, info.id) == :ok

      report = result(scenario, status, events, requests, seen, cleanup, info, cwd)
      Map.update!(report, "passed", &(&1 and valid)) |> Map.put("journal_valid", valid)
    after
      if Process.alive?(session), do: Session.close(session)
    end
  catch
    :exit, _ ->
      result(scenario, "error", [], 0, %{}, false, %{}, cwd)
      |> Map.put("passed", false)
      |> Map.put("journal_valid", false)
  end

  defp drain_requests(ref, count, seen) do
    receive do
      {:conformance_request, ^ref, hit} -> drain_requests(ref, count + 1, merge_seen(seen, hit))
    after
      0 -> {count, seen}
    end
  end

  defp await(session, ref, answers, deadline, cancel, requests, seen) do
    now = System.monotonic_time(:millisecond)

    cond do
      now >= deadline ->
        Session.cancel(session)
        {"timeout", requests, seen}

      cancel != nil and now >= cancel ->
        Session.cancel(session)
        {"cancelled", requests, seen}

      true ->
        wait = min(deadline - now, if(cancel, do: max(cancel - now, 0), else: 1000))

        receive do
          {:conformance_request, ^ref, hit} ->
            await(session, ref, answers, deadline, cancel, requests + 1, merge_seen(seen, hit))

          {:ipse, ^session, {:question, id, _}} ->
            case answers do
              [answer | rest] ->
                if Session.answer(session, id, answer) == :ok,
                  do: await(session, ref, rest, deadline, cancel, requests, seen),
                  else: {"refused", requests, seen}

              [] ->
                {"question", requests, seen}
            end

          {:ipse, ^session, {:done, status}} ->
            {to_string(status), requests, seen}

          {:ipse, ^session, _} ->
            await(session, ref, answers, deadline, cancel, requests, seen)
        after
          wait -> await(session, ref, answers, deadline, cancel, requests, seen)
        end
    end
  end

  defp result(scenario, status, events, requests, seen, cleanup, info, cwd) do
    expected = scenario["expect"]
    records = Map.get(expected, "records", %{})

    counts =
      Map.new(records, fn {type, _} -> {type, Enum.count(events, &(&1["type"] == type))} end)

    actions =
      for %{"type" => "extension_action_result", "outcome" => outcome} <- events,
          do: outcome["status"]

    value = result_value(events)

    checks = %{
      "status" => status == expected["status"],
      "cleanup" => cleanup == Map.get(expected, "cleanup", true),
      "records" => counts == records,
      "requests" => not Map.has_key?(expected, "requests") or requests == expected["requests"],
      "context" => not Map.has_key?(expected, "context_contains") or seen[:context] == true,
      "user" => not Map.has_key?(expected, "user_contains") or seen[:user] == true,
      "final" => not Map.has_key?(expected, "final") or info[:final] == expected["final"],
      "value" => not Map.has_key?(expected, "value") or value === {:found, expected["value"]},
      "actions" =>
        not Map.has_key?(expected, "action_statuses") or actions == expected["action_statuses"],
      "files" =>
        Enum.all?(Map.get(expected, "files", %{}), fn {path, text} ->
          File.read(Path.join(cwd, path)) == {:ok, text}
        end)
    }

    %{
      "id" => scenario["id"],
      "status" => status,
      "passed" => Enum.all?(checks, fn {_, ok} -> ok end),
      "checks" => checks,
      "cleanup_confirmed" => cleanup,
      "model_requests" => requests,
      "record_counts" => counts
    }
  end

  defp script(%{"kind" => "tool"} = scenario),
    do: [%{"tool" => Map.take(scenario, ~w(name arguments))}]

  defp script(scenario), do: Map.get(scenario, "script", [])
  defp merge_seen(seen, hit), do: Map.merge(seen, hit, fn _, first, second -> first or second end)

  defp selected?(catalog, fixture) do
    instances =
      for instance <- catalog["instances"], instance["enabled"], do: instance["instance"]

    instances != [] and
      Enum.all?(
        [
          Map.get(fixture, "options", %{})
          | Enum.map(fixture["cases"], &Map.get(&1, "options", %{}))
        ],
        fn overrides -> Enum.all?(Map.keys(overrides), &(&1 in instances)) end
      )
  end

  defp expand(value, cwd, home) when is_binary(value),
    do: value |> String.replace("{{workspace}}", cwd) |> String.replace("{{home}}", home)

  defp expand(value, cwd, home) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, expand(item, cwd, home)} end)

  defp expand(value, cwd, home) when is_list(value), do: Enum.map(value, &expand(&1, cwd, home))
  defp expand(value, _, _), do: value

  defp seed(cwd, files) do
    Enum.each(files, fn {path, text} ->
      target = Path.join(cwd, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, text)
      File.chmod!(target, 0o600)
    end)

    :ok
  end

  defp case?(scenario) do
    id?(scenario["id"]) and options?(Map.get(scenario, "options", %{})) and
      files?(Map.get(scenario["expect"], "files", %{})) and
      Enum.all?(Map.get(scenario["expect"], "records", %{}), fn {key, count} ->
        is_binary(key) and Regex.match?(~r/\A[a-z_]{1,64}\z/, key) and is_integer(count) and
          count in 0..1000
      end) and
      Enum.all?(Map.get(scenario, "script", []), fn frame ->
        Enum.sort(Map.keys(frame)) in [["assistant"], ["tool"]]
      end) and
      if(scenario["kind"] == "prompt",
        do: is_binary(scenario["text"]),
        else:
          is_binary(scenario["name"]) and is_map(scenario["arguments"]) and
            not Map.has_key?(scenario, "script")
      )
  end

  defp result_value(events) do
    case Enum.find(Enum.reverse(events), &(&1["type"] == "extension_invocation_result")) do
      %{"version" => 1, "value" => value} ->
        {:found, value}

      %{"version" => 2, "delivery" => delivery} ->
        with {:ok, index} <- Ipse.Extension.ResultSource.restore(events),
             {:ok, %{value: value}} <- Ipse.Extension.ResultSource.materialize(index, delivery),
             do: {:found, value}

      _ ->
        nil
    end
  end

  defp options?(value),
    do: is_map(value) and Enum.all?(value, fn {key, options} -> id?(key) and is_map(options) end)

  defp files?(value),
    do:
      is_map(value) and map_size(value) <= 16 and
        Enum.all?(value, fn {path, text} ->
          is_binary(path) and byte_size(path) <= 256 and Path.type(path) == :relative and
            Regex.match?(~r/\A[A-Za-z0-9_. -]+(?:\/[A-Za-z0-9_. -]+)*\z/, path) and
            Enum.all?(Path.split(path), &(&1 not in [".", ".."])) and
            is_binary(text) and byte_size(text) <= 4096
        end)

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, id)

  defp object(properties, required \\ []),
    do: %{
      "type" => "object",
      "properties" => properties,
      "required" => required,
      "additionalProperties" => false
    }

  defp integer(minimum, maximum),
    do: %{"type" => "integer", "minimum" => minimum, "maximum" => maximum}
end
