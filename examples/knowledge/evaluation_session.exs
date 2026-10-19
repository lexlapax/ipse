defmodule IpseKnowledgeExample.EvaluationSession do
  @moduledoc "One owned, catalog-bound Session for a declared knowledge evaluation variant."
  alias Ipse.{Journal, Session, Usage}
  alias Ipse.Extensions.{Catalog, Config, Registry, Store}

  @verbs ~w(ingest inspect index extract query research answer abort forget export import collect)
  @command_ids %{
    "ingest" => "source",
    "inspect" => "source",
    "index" => "index",
    "extract" => "extract",
    "query" => "query",
    "research" => "investigate",
    "answer" => "complete",
    "abort" => "source",
    "forget" => "source",
    "export" => "source",
    "import" => "source",
    "collect" => "source"
  }
  @source_keys ~w(source_id generation title text uri observed_at_ms event_at_ms expires_at_ms)
  @safe 9_007_199_254_740_991

  def open(spec) do
    with :ok <- validate_spec(spec),
         {:ok, _} <- Application.ensure_all_started(:ipse),
         :ok <- ensure_domain_unloaded(),
         directory = Path.join([spec.root, spec.project, spec.variant]),
         :ok <- ensure_fresh(directory),
         :ok <- File.mkdir_p(directory),
         :ok <- File.chmod(directory, 0o700),
         home = Path.join(directory, "home"),
         {:ok, instances, trust} <- import_artifacts(spec.artifacts, home),
         source = %{
           scope: "operator",
           path: Path.join(directory, "operator-selection.json"),
           data: %{"extensions" => instances, "extension_trust" => trust}
         },
         {:ok, selected} <- Config.resolve([source], []),
         {:ok, entries} <- Registry.prepare(selected, home),
         config <-
           Map.merge(spec.runtime, %{
             home: home,
             operator_home: Path.join(directory, "operator-home"),
             extensions: entries,
             approval: :ask
           }),
         {:ok, catalog} <- Catalog.snapshot(config),
         :ok <- validate_bindings(spec.bindings, spec.required_verbs, catalog),
         cwd = Path.join(directory, "workspace"),
         :ok <- File.mkdir_p(cwd),
         state_dir = Path.join(directory, "sessions"),
         {:ok, pid} <- start_owned(config, cwd, state_dir, catalog) do
      {:ok,
       %{
         pid: pid,
         directory: directory,
         state_dir: state_dir,
         catalog: catalog,
         bindings: spec.bindings,
         session_id: Session.info(pid).id,
         approval_validator: spec.approval_validator,
         timeout_ms: spec.timeout_ms,
         max_requests: spec.runtime.budget["max_requests"],
         project: spec.project,
         variant: spec.variant,
         unsettled: false,
         receipts: []
       }}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, {:open_failed, other}}
    end
  rescue
    _ -> {:error, :invalid_session_spec}
  end

  def invoke(
        run,
        "ingest",
        %{"source" => source, "store" => store, "expected_revision" => revision} = params
      ) do
    with true <- exact?(params, ~w(source store expected_revision)),
         true <- source?(source) and profile_name?(store) and uint?(revision),
         true <- byte_size(source["text"]) <= 65_536 do
      put = source(store, "put", Map.put(source, "expected_revision", revision))

      if byte_size(source["text"]) <= 8192 and encoded_safe?(put) do
        one(run, "ingest", put)
      else
        ingest_paged(run, source, store, revision)
      end
    else
      _ -> {:error, :invalid_ingest, run}
    end
  end

  def invoke(run, "inspect", %{"store" => store, "source_id" => id} = params) do
    if exact?(params, ~w(store source_id)) and profile_name?(store) and text?(id, 256),
      do: one(run, "inspect", source(store, "inspect", %{"source_id" => id})),
      else: {:error, :invalid_inspect, run}
  end

  def invoke(run, "index", params) do
    if exact?(params, ~w(store embedding source_id generation chunks)) and
         profile_name?(params["store"]) and profile_name?(params["embedding"]) and
         text?(params["source_id"], 256) and positive?(params["generation"]) and
         chunk_ids?(params["chunks"]),
       do: one(run, "index", Map.put(params, "action", "next")),
       else: {:error, :invalid_index, run}
  end

  def invoke(run, "extract", params) do
    if exact?(params, ~w(store extraction source_id generation max_edges chunks facts)) and
         profile_name?(params["store"]) and profile_name?(params["extraction"]) and
         text?(params["source_id"], 256) and positive?(params["generation"]) and
         is_integer(params["max_edges"]) and params["max_edges"] in 1..32 and
         chunk_ids?(params["chunks"]) and is_list(params["facts"]) and
         length(params["facts"]) <= params["max_edges"],
       do: one(run, "extract", params),
       else: {:error, :invalid_extract, run}
  end

  def invoke(run, "query", params) do
    corpus? =
      exact?(params, ~w(store retrieval rerank query top_k as_of_ms)) and
        profile_name?(params["store"]) and profile_name?(params["retrieval"]) and
        (is_nil(params["rerank"]) or profile_name?(params["rerank"])) and
        text?(params["query"], 1024) and query_tail?(params)

    graph? =
      exact?(params, ~w(store entity depth max_nodes max_edges top_k as_of_ms)) and
        profile_name?(params["store"]) and text?(params["entity"], 256) and
        is_integer(params["depth"]) and params["depth"] in 0..4 and
        is_integer(params["max_nodes"]) and params["max_nodes"] in 1..128 and
        is_integer(params["max_edges"]) and params["max_edges"] in 1..256 and
        query_tail?(params)

    if corpus? or graph?,
      do: one(run, "query", params),
      else: {:error, :invalid_query, run}
  end

  def invoke(run, "research", params) do
    if exact?(
         Map.delete(params, "as_of_ms"),
         ~w(search fetch retrieval rerank query limits sources)
       ) and
         (not Map.has_key?(params, "as_of_ms") or uint?(params["as_of_ms"])) and
         Enum.all?(~w(search fetch retrieval), &profile_name?(params[&1])) and
         (is_nil(params["rerank"]) or profile_name?(params["rerank"])) and
         text?(params["query"], 1024) and is_map(params["limits"]) and
         is_list(params["sources"]) and length(params["sources"]) <= 3,
       do: one(run, "research", params),
       else: {:error, :invalid_research, run}
  end

  def invoke(run, "answer", params) do
    if exact?(params, ~w(instruction input max_output_bytes timeout_ms)) and
         text?(params["instruction"], 2048) and text?(params["input"], 4096) and
         is_integer(params["max_output_bytes"]) and params["max_output_bytes"] in 1..8192 and
         is_integer(params["timeout_ms"]) and params["timeout_ms"] in 1_000..120_000 do
      request =
        Map.merge(params, %{"op" => "model.complete", "version" => 1, "profile" => "p27_answer"})

      one(run, "answer", %{"request" => request})
    else
      {:error, :invalid_answer, run}
    end
  end

  def invoke(run, "abort", params) do
    if exact?(params, ~w(store source_id draft_id expected_revision)) and
         profile_name?(params["store"]) and text?(params["source_id"], 256) and
         is_binary(params["draft_id"]) and Regex.match?(~r/\A[0-9a-f]{32}\z/, params["draft_id"]) and
         uint?(params["expected_revision"]),
       do:
         one(
           run,
           "abort",
           source(
             params["store"],
             "abort",
             Map.take(params, ~w(source_id draft_id expected_revision))
           )
         ),
       else: {:error, :invalid_abort, run}
  end

  def invoke(run, "forget", params) do
    if exact?(params, ~w(store source_id expected_revision)) and profile_name?(params["store"]) and
         text?(params["source_id"], 256) and uint?(params["expected_revision"]),
       do:
         one(
           run,
           "forget",
           source(params["store"], "forget", Map.take(params, ~w(source_id expected_revision)))
         ),
       else: {:error, :invalid_forget, run}
  end

  def invoke(run, "export", params) do
    if exact?(params, ~w(store source_id cursor limit)) and profile_name?(params["store"]) and
         text?(params["source_id"], 256) and
         (is_nil(params["cursor"]) or uint?(params["cursor"])) and
         is_integer(params["limit"]) and params["limit"] in 1..12,
       do:
         one(
           run,
           "export",
           source(params["store"], "export", Map.take(params, ~w(source_id cursor limit)))
         ),
       else: {:error, :invalid_export, run}
  end

  def invoke(run, "import", params) do
    if exact?(params, ~w(store expected_revision export)) and profile_name?(params["store"]) and
         uint?(params["expected_revision"]) and is_map(params["export"]),
       do:
         one(
           run,
           "import",
           source(params["store"], "import", Map.take(params, ~w(expected_revision export)))
         ),
       else: {:error, :invalid_import, run}
  end

  def invoke(run, "collect", params) do
    if exact?(params, ~w(store limit)) and profile_name?(params["store"]) and
         is_integer(params["limit"]) and params["limit"] in 1..12,
       do: one(run, "collect", source(params["store"], "collect", %{"limit" => params["limit"]})),
       else: {:error, :invalid_collect, run}
  end

  def invoke(run, _, _), do: {:error, :unsupported_verb, run}

  def snapshot(run) do
    with {:ok, events} <- Journal.load(run.state_dir, run.session_id),
         {:ok, _} <- Session.restore_context(events),
         {:ok, ledger} <- Usage.restore(events, run.session_id) do
      info = live_info(run.pid)

      {:ok,
       %{
         "session_id" => run.session_id,
         "phase" => if(info, do: info.phase, else: :unavailable),
         "accounting" => Usage.snapshot(ledger),
         "journal_path" => Path.join(run.state_dir, run.session_id <> ".jsonl"),
         "journal_events" => length(events),
         "unsettled" => run.unsettled,
         "receipts" => run.receipts,
         "project" => run.project,
         "variant" => run.variant
       }}
    else
      _ -> {:error, :snapshot_unavailable}
    end
  end

  def close(run) do
    before_close = snapshot(run)

    closure =
      try do
        Session.close_confirmed(run.pid)
      rescue
        _ -> {:error, :close_exception}
      catch
        :exit, _ -> {:error, :close_exit}
      end

    case {closure, before_close} do
      {:ok, {:ok, current}} ->
        {:ok, %{"cleanup" => "confirmed", "snapshot" => current}}

      {:ok, {:error, reason}} ->
        {:error, %{"cleanup" => "confirmed", "snapshot" => %{"error" => Atom.to_string(reason)}}}

      {other, _} ->
        {:error,
         %{
           "cleanup" => "unconfirmed",
           "reason" => inspect(other),
           "snapshot" => unwrap_snapshot(before_close)
         }}
    end
  end

  defp unwrap_snapshot({:ok, value}), do: value
  defp unwrap_snapshot({:error, reason}), do: %{"error" => Atom.to_string(reason)}

  defp ensure_fresh(path),
    do: if(File.exists?(path), do: {:error, :run_directory_exists}, else: :ok)

  defp ensure_domain_unloaded,
    do: if(domain_unloaded?(), do: :ok, else: {:error, :domain_loaded_in_host})

  defp start_owned(config, cwd, state_dir, catalog) do
    with {:ok, pid} <-
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Session,
              config: config, cwd: cwd, state_dir: state_dir, subscriber: self(), owner: self()}
           ) do
      if Session.exports(pid) == catalog do
        {:ok, pid}
      else
        _ = Session.close_confirmed(pid)
        {:error, :catalog_changed}
      end
    end
  end

  defp one(run, verb, arguments) do
    with true <- not run.unsettled and Process.alive?(run.pid),
         {:ok, binding, descriptor} <- binding(run, verb),
         :ok <- Catalog.validate_call(descriptor, arguments),
         {:ok, before} <- journal(run) do
      started = System.monotonic_time(:millisecond)

      submission =
        try do
          Session.invoke_export(run.pid, :command, binding["name"], arguments)
        rescue
          _ -> {:submission_unconfirmed, :exception}
        catch
          :exit, _ -> {:submission_unconfirmed, :exit}
        end

      case submission do
        :ok ->
          {outcome, approvals} =
            try do
              wait(
                run,
                verb,
                binding["name"],
                arguments,
                System.monotonic_time(:millisecond) + run.timeout_ms,
                []
              )
            rescue
              _ -> {{:wait_failed, :exception}, []}
            catch
              :exit, _ -> {{:wait_failed, :exit}, []}
            end

          record_invoked(
            run,
            verb,
            arguments,
            binding["name"],
            before,
            started,
            outcome,
            approvals
          )

        {:submission_unconfirmed, reason} ->
          record_invoked(
            run,
            verb,
            arguments,
            binding["name"],
            before,
            started,
            {:submission_unconfirmed, reason},
            []
          )

        other ->
          {:error, {:invocation_failed, other}, run}
      end
    else
      false ->
        {:error, if(run.unsettled, do: :completion_unconfirmed, else: :session_closed), run}

      {:error, reason} ->
        {:error, reason, run}

      other ->
        {:error, {:invocation_failed, other}, run}
    end
  end

  defp record_invoked(run, verb, arguments, command, before, started, outcome, approvals) do
    after_result =
      try do
        journal(run)
      rescue
        _ -> {:error, :journal_exception}
      catch
        :exit, _ -> {:error, :journal_exit}
      end

    after_events = if match?({:ok, _}, after_result), do: elem(after_result, 1), else: before
    delta = Enum.drop(after_events, length(before))

    result =
      Enum.find(
        Enum.reverse(delta),
        &(&1["type"] == "extension_invocation_result" and
            get_in(&1, ["descriptor", "name"]) == command)
      )

    intent =
      Enum.find(
        delta,
        &(&1["type"] == "extension_invocation_intent" and
            get_in(&1, ["descriptor", "name"]) == command)
      )

    info = live_info(run.pid)
    value = if result, do: result["value"], else: nil
    status = if is_map(value), do: value["status"], else: "failed"

    receipt = %{
      "verb" => verb,
      "command" => command,
      "arguments" => arguments,
      "outcome" => inspect(outcome),
      "status" => status,
      "value" => value,
      "invocation_id" => if(intent, do: intent["invocation_id"], else: nil),
      "result_sha256" => if(result, do: result["text_sha256"], else: nil),
      "journal_event_range" => [length(before), length(after_events)],
      "journal_error" => if(match?({:ok, _}, after_result), do: nil, else: :unavailable),
      "action_count" => Enum.count(delta, &(&1["type"] == "extension_action_intent")),
      "approvals" => Enum.reverse(approvals),
      "elapsed_ms" => System.monotonic_time(:millisecond) - started,
      "accounting" => if(info, do: info.accounting, else: nil)
    }

    unsettled =
      match?({:timeout, _, :completion_unconfirmed}, outcome) or
        match?({:wait_failed, _}, outcome) or
        match?({:submission_unconfirmed, _}, outcome)

    next = %{run | receipts: run.receipts ++ [receipt], unsettled: run.unsettled or unsettled}

    if outcome == :ok and match?({:ok, _}, after_result) and result != nil and intent != nil and
         result["invocation_id"] == intent["invocation_id"] and
         status in ~w(ok draft abstain partial),
       do: {:ok, receipt, next},
       else: {:error, {:command_failed, status}, next}
  end

  defp live_info(pid) do
    if Process.alive?(pid), do: Session.info(pid), else: nil
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp wait(run, verb, command, arguments, deadline, approvals) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {:ipse, pid, {:approval, ref, name, proposed}} when pid == run.pid ->
        ordinal = length(approvals) + 1

        review = %{
          verb: verb,
          command: command,
          arguments: arguments,
          ordinal: ordinal,
          name: name,
          proposed: proposed
        }

        decision = validate_approval(run.approval_validator, review)
        allowed = decision == :approve
        :ok = Session.approve(run.pid, ref, allowed)
        safe_proposed = if is_map(proposed), do: proposed, else: %{}

        approval = %{
          "name" => name,
          "decision" => if(allowed, do: "approved", else: "denied"),
          "proposal_sha256" => Ipse.Compaction.digest([safe_proposed]),
          "binding" => get_in(safe_proposed, ["request", "binding"]),
          "profile" => get_in(safe_proposed, ["request", "profile"]),
          "execution_id" => get_in(safe_proposed, ["execution", "id"]),
          "destination_origin" => get_in(safe_proposed, ["destination", "origin"]),
          "tool_id" => get_in(safe_proposed, ["effect_binding", "manifest", "tool_id"]),
          "ordinal" => ordinal
        }

        wait(run, verb, command, arguments, deadline, [approval | approvals])

      {:ipse, pid, {:done, status}} when pid == run.pid ->
        {status, approvals}

      {:ipse, pid, _} when pid == run.pid ->
        wait(run, verb, command, arguments, deadline, approvals)
    after
      remaining ->
        cancellation =
          try do
            Session.cancel(run.pid)
          catch
            :exit, reason -> {:error, {:cancel_call_exit, reason}}
          end

        completion = wait_cancelled(run.pid, System.monotonic_time(:millisecond) + 10_000)
        {{:timeout, cancellation, completion}, approvals}
    end
  end

  defp wait_cancelled(pid, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {:ipse, ^pid, {:done, status}} ->
        {:done, status}

      {:ipse, ^pid, {:approval, ref, _, _}} ->
        _ = Session.approve(pid, ref, false)
        wait_cancelled(pid, deadline)

      {:ipse, ^pid, _} ->
        wait_cancelled(pid, deadline)
    after
      remaining -> :completion_unconfirmed
    end
  end

  defp validate_approval(validator, review) do
    proposed = review.proposed
    expected = %{name: review.name, proposed: proposed}

    if is_map(proposed) and is_map(proposed["request"]) and
         validator.(review) == {:approve, expected} do
      :approve
    else
      :deny
    end
  rescue
    _ -> :deny
  end

  defp ingest_paged(run, source_doc, store, revision) do
    text = source_doc["text"]

    open_args =
      source_doc
      |> Map.delete("text")
      |> Map.merge(%{
        "expected_revision" => revision,
        "byte_count" => byte_size(text),
        "content_sha256" => sha(text)
      })

    case one(run, "ingest", source(store, "open", open_args)) do
      {:ok, open, next} ->
        continuation = get_in(open, ["value", "continuation"])

        if open["status"] == "draft" and continuation?(continuation) and
             continuation["offset"] == 0 do
          case append_parts(next, store, source_doc["source_id"], text, continuation, [open]) do
            {:ok, appended, current, final} ->
              case one(
                     current,
                     "ingest",
                     source(store, "publish", %{
                       "source_id" => source_doc["source_id"],
                       "draft_id" => final["draft_id"],
                       "expected_revision" => final["expected_revision"]
                     })
                   ) do
                {:ok, published, latest} ->
                  {:ok,
                   %{
                     "status" => published["status"],
                     "steps" => appended ++ [published],
                     "value" => published["value"]
                   }, latest}

                {:error, reason, latest} ->
                  {:error, reason, latest}
              end

            {:error, reason, current, _} ->
              {:error, reason, current}
          end
        else
          {:error, :invalid_draft_continuation, next}
        end

      {:error, reason, next} ->
        {:error, reason, next}
    end
  end

  defp append_parts(run, _store, _source_id, text, continuation, receipts)
       when byte_size(text) == 0 do
    {:ok, receipts, run, continuation}
  end

  defp append_parts(run, store, source_id, remaining, continuation, receipts) do
    case next_append(remaining, store, source_id, continuation, 4096) do
      {:ok, part, rest, args} ->
        case one(run, "ingest", source(store, "append", args)) do
          {:ok, receipt, next} ->
            new = get_in(receipt, ["value", "continuation"])

            if receipt["status"] == "draft" and continuation?(new) and
                 new["draft_id"] == continuation["draft_id"] and
                 new["offset"] == continuation["offset"] + byte_size(part) do
              append_parts(next, store, source_id, rest, new, receipts ++ [receipt])
            else
              {:error, :invalid_draft_continuation, next, receipts ++ [receipt]}
            end

          {:error, reason, next} ->
            {:error, reason, next, receipts}
        end

      {:error, reason} ->
        {:error, reason, run, receipts}
    end
  end

  defp continuation?(value),
    do:
      exact?(value, ~w(draft_id expected_revision offset)) and
        text?(value["draft_id"], 64) and uint?(value["expected_revision"]) and
        uint?(value["offset"])

  defp next_append(text, store, source_id, continuation, limit) when limit >= 4 do
    {part, rest} = take_utf8(text, min(limit, byte_size(text)))

    args = %{
      "source_id" => source_id,
      "draft_id" => continuation["draft_id"],
      "expected_revision" => continuation["expected_revision"],
      "offset" => continuation["offset"],
      "text" => part
    }

    if encoded_safe?(source(store, "append", args)),
      do: {:ok, part, rest, args},
      else: next_append(text, store, source_id, continuation, div(limit, 2))
  end

  defp next_append(_, _, _, _, _), do: {:error, :source_argument_too_large}

  defp encoded_safe?(value), do: byte_size(JSON.encode!(value)) <= 10_000

  defp take_utf8(text, limit) when byte_size(text) <= limit, do: {text, ""}

  defp take_utf8(text, limit) do
    length =
      Enum.find(limit..(limit - 3)//-1, fn n ->
        String.valid?(binary_part(text, 0, n))
      end)

    {binary_part(text, 0, length), binary_part(text, length, byte_size(text) - length)}
  end

  defp binding(run, verb) do
    with %{"instance" => instance, "id" => id} <- run.bindings[verb],
         name = "ext__" <> instance <> "__" <> id,
         descriptor when is_map(descriptor) <-
           Enum.find(
             run.catalog["entries"],
             &(&1["stage"] == "invoke.command" and
                 &1["name"] == name)
           ) do
      {:ok, %{"name" => name}, descriptor}
    else
      _ -> {:error, :unmapped_command}
    end
  end

  defp journal(run) do
    with {:ok, events} <- Journal.load(run.state_dir, run.session_id),
         {:ok, _} <- Session.restore_context(events),
         {:ok, _} <- Usage.restore(events, run.session_id) do
      {:ok, events}
    end
  end

  defp import_artifacts(artifacts, home) do
    Enum.reduce_while(artifacts, {:ok, [], []}, fn artifact, {:ok, instances, trusts} ->
      with {:ok, imported_knowledge_artifact} <-
             Store.import(artifact.path, Path.join(home, "extensions/artifacts")),
           true <- imported_knowledge_artifact.digest == artifact.digest,
           true <- artifact.trust["artifact"] == artifact.digest do
        instance = %{
          "instance" => artifact.instance,
          "artifact" => imported_knowledge_artifact.digest,
          "enabled" => true,
          "options" => artifact.options,
          "order" => artifact.order,
          "lifetime" => "persistent"
        }

        {:cont, {:ok, instances ++ [instance], trusts ++ [artifact.trust]}}
      else
        _ -> {:halt, {:error, :artifact_identity_mismatch}}
      end
    end)
  end

  defp validate_bindings(bindings, required, catalog) do
    valid =
      is_map(bindings) and is_list(required) and required != [] and
        Enum.all?(required, &(&1 in @verbs and Map.has_key?(bindings, &1))) and
        Enum.all?(bindings, fn {verb, binding} ->
          verb in @verbs and exact?(binding, ~w(instance id)) and
            binding["id"] == @command_ids[verb] and
            Enum.any?(catalog["entries"], fn entry ->
              entry["stage"] == "invoke.command" and
                entry["instance"] == binding["instance"] and entry["id"] == binding["id"]
            end)
        end)

    if valid, do: :ok, else: {:error, :invalid_command_bindings}
  end

  defp validate_spec(spec) do
    required =
      ~w(root project variant artifacts runtime bindings required_verbs approval_validator timeout_ms)a

    runtime = if is_map(spec), do: Map.get(spec, :runtime), else: nil
    budget = if is_map(runtime), do: Map.get(runtime, :budget), else: nil

    valid =
      is_map(spec) and Enum.sort(Map.keys(spec)) == Enum.sort(required) and
        is_binary(spec.root) and File.dir?(spec.root) and name?(spec.project) and
        name?(spec.variant) and is_list(spec.artifacts) and spec.artifacts != [] and
        length(spec.artifacts) <= 8 and Enum.all?(spec.artifacts, &artifact?/1) and
        length(Enum.uniq(Enum.map(spec.artifacts, & &1.instance))) == length(spec.artifacts) and
        is_map(runtime) and
        not Enum.any?(
          ~w(home operator_home extensions approval budget_root budget_checkpoint delegation_origin)a,
          &Map.has_key?(runtime, &1)
        ) and is_map(budget) and
        Ipse.Budget.Policy.validate(budget) == :ok and
        Map.has_key?(budget, "max_requests") and
        positive?(budget["max_requests"]) and
        is_function(spec.approval_validator, 1) and
        is_integer(spec.timeout_ms) and spec.timeout_ms in 1_000..300_000

    if valid, do: :ok, else: {:error, :invalid_session_spec}
  end

  defp artifact?(a),
    do:
      is_map(a) and Enum.sort(Map.keys(a)) == ~w(digest instance options order path trust)a and
        name?(a.instance) and is_binary(a.path) and File.dir?(a.path) and
        hash?(a.digest) and is_map(a.options) and is_map(a.trust) and
        is_integer(a.order) and a.order in 0..1000

  defp source(store, action, args), do: %{"store" => store, "action" => action, "args" => args}

  defp source?(value),
    do:
      exact?(value, @source_keys) and
        text?(value["source_id"], 256) and positive?(value["generation"]) and
        text?(value["title"], 128) and text?(value["text"], 65_536) and
        text?(value["uri"], 512) and uint?(value["observed_at_ms"]) and
        (is_nil(value["event_at_ms"]) or uint?(value["event_at_ms"])) and
        (is_nil(value["expires_at_ms"]) or uint?(value["expires_at_ms"]))

  defp chunk_ids?(value),
    do:
      is_list(value) and length(value) in 1..2 and
        Enum.all?(value, &hash?/1)

  defp query_tail?(params),
    do:
      is_integer(params["top_k"]) and
        params["top_k"] in 1..10 and uint?(params["as_of_ms"])

  defp exact?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
  defp name?(value), do: is_binary(value) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, value)

  defp profile_name?(value),
    do: is_binary(value) and Regex.match?(~r/\A[A-Za-z0-9_.-]{1,64}\z/, value)

  defp text?(value, max),
    do:
      is_binary(value) and String.valid?(value) and
        byte_size(value) in 1..max

  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp uint?(value), do: is_integer(value) and value in 0..@safe
  defp positive?(value), do: uint?(value) and value > 0
  defp sha(text), do: Base.encode16(:crypto.hash(:sha256, text), case: :lower)

  defp domain_unloaded? do
    Enum.all?(
      [
        IpseKnowledge.Corpus,
        IpseKnowledge.Graph,
        IpseKnowledge.Research,
        IpseKnowledge.Adapters,
        IpseKnowledge.Evidence,
        IpseKnowledge.Profiles,
        IpseKnowledge.Store,
        IpseKnowledge.Store.State,
        IpseKnowledge.Store.MCPCAS
      ],
      &(:code.is_loaded(&1) == false)
    )
  end
end
