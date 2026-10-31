defmodule Ipse.Session.ManagedToolUse do
  @moduledoc "Host-owned current admission of exact managed-derived ordinary tool effects."
  alias Ipse.{JSON, Session}
  alias Ipse.Session.{ManagedLineage, ManagedReference, ManagedUse, Resources}
  @error {:error, :managed_tool_inputs_unavailable}
  @layout "managed_tool_effects_v1"
  @native_tools ~w(read write edit shell load_skill load_skill_resource research_source research_claim research_ledger saved_result_read source_list source_read source_quote)
  @record_keys ~w(type version effect_id session_id request_id call_id input_sha256 snapshot_sha256 dependencies_sha256 binding binding_sha256 checked_at_ms deadline_ms)
  @unknown {:unknown,
            "Managed tool effect may have occurred; current admission or cleanup is unconfirmed. Inspect before retrying."}

  def layout, do: @layout

  def marker(metadata) do
    case Map.fetch(metadata, "managed_tool_layout") do
      :error -> {:ok, nil}
      {:ok, @layout} -> {:ok, @layout}
      _ -> @error
    end
  end

  @doc false
  def input(session, request, call, arguments, approval, mcp),
    do: %{
      "session_id" => session,
      "request_id" => request,
      "call" => call,
      "arguments" => arguments,
      "approval" => approval,
      "mcp" => mcp
    }

  @doc false
  def valid_record?(event, session, %{call: call, request_id: request}, started, dependencies) do
    with true <- is_map(event) and Enum.sort(Map.keys(event)) == Enum.sort(@record_keys),
         true <- event["type"] == "managed_tool_effect_admitted" and event["version"] === 1,
         true <-
           is_binary(event["effect_id"]) and
             Regex.match?(~r/\A[0-9a-f]{32}\z/, event["effect_id"]),
         true <- event["session_id"] == session and event["request_id"] == request,
         true <- event["call_id"] == call["id"] and started["call_id"] == call["id"],
         true <- started["name"] == get_in(call, ["function", "name"]),
         {:ok, arguments} <- JSON.decode_bounded(get_in(call, ["function", "arguments"]), 65_536),
         true <- is_map(arguments) and dependencies != [],
         {:ok, ^dependencies} <- ManagedReference.union([dependencies]),
         input = input(session, request, call, arguments, started["approval"], started["mcp"]),
         true <-
           event["input_sha256"] == JSON.digest([input]) and
             event["snapshot_sha256"] == JSON.digest([input, dependencies]) and
             event["dependencies_sha256"] == JSON.digest(dependencies),
         true <- event["binding_sha256"] == JSON.digest([event["binding"]]),
         true <- record_target?(event["binding"], input),
         true <- JSON.safe_uint?(event["checked_at_ms"]) and JSON.safe_uint?(event["deadline_ms"]),
         true <-
           event["checked_at_ms"] < event["deadline_ms"] and
             event["deadline_ms"] - event["checked_at_ms"] <= 5000 do
      byte_size(Jason.encode!(event)) <= 65_536
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def valid_record?(_, _, _, _, _), do: false

  @doc false
  def effect_key(input_sha256, kind), do: JSON.digest([input_sha256, kind])

  @doc false
  def valid_effect_cleanup?(event, id, sha),
    do:
      keys?(event, ~w(type version effect_id admission_sha256 status)) and
        event["type"] == "managed_tool_effect_cleanup" and event["version"] === 1 and
        event["effect_id"] == id and event["admission_sha256"] == sha and
        event["status"] in ~w(confirmed unknown)

  @doc false
  def result_message(message, "current"), do: message

  def result_message(message, "withdrawn") do
    message
    |> Map.put(
      "content",
      "Managed tool result withheld because its inputs are unavailable. Inspect the original receipts; any admitted effects may have occurred."
    )
    |> Map.put("ipse_tool_outcome", %{
      "status" => "unknown",
      "approval" => message["ipse_tool_outcome"]["approval"]
    })
    |> Map.delete("ipse_external_result")
  end

  @doc false
  def valid_observed?(event, session, %{call: call, request_id: request}, started, deps) do
    with true <-
           keys?(
             event,
             ~w(type version result_id session_id request_id call_id input_sha256 dependencies_sha256 message message_sha256 checked_at_ms deadline_ms)
           ),
         true <- event["type"] == "managed_tool_result_observed" and event["version"] === 1,
         true <-
           id?(event["result_id"]) and event["session_id"] == session and
             event["request_id"] == request,
         true <- event["call_id"] == call["id"] and started["call_id"] == call["id"],
         true <- started["name"] == get_in(call, ["function", "name"]),
         {:ok, args} <- JSON.decode_bounded(get_in(call, ["function", "arguments"]), 65_536),
         true <- deps != [] and ManagedReference.union([deps]) == {:ok, deps},
         true <-
           event["input_sha256"] ==
             JSON.digest([
               input(session, request, call, args, started["approval"], started["mcp"])
             ]),
         true <- event["dependencies_sha256"] == JSON.digest(deps),
         message when is_map(message) <- event["message"],
         true <-
           keys?(
             Map.delete(message, "ipse_external_result"),
             ~w(role tool_call_id content ipse_tool_outcome)
           ),
         true <- message["role"] == "tool" and message["tool_call_id"] == call["id"],
         true <- is_binary(message["content"]) and String.valid?(message["content"]),
         true <- keys?(message["ipse_tool_outcome"], ~w(status approval)),
         true <-
           message["ipse_tool_outcome"]["approval"] == started["approval"] and
             message["ipse_tool_outcome"]["status"] in ~w(result_recorded error unknown),
         true <- external_result?(message, call, started),
         true <- event["message_sha256"] == JSON.digest([message]),
         true <- JSON.safe_uint?(event["checked_at_ms"]) and JSON.safe_uint?(event["deadline_ms"]),
         true <-
           event["checked_at_ms"] < event["deadline_ms"] and
             event["deadline_ms"] - event["checked_at_ms"] <= 5000 do
      byte_size(Jason.encode!(event)) <= 131_072
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def valid_observed?(_, _, _, _, _), do: false

  defp external_result?(message, call, started) do
    if started["mcp"] != nil and message["ipse_tool_outcome"]["status"] == "result_recorded" do
      metadata = message["ipse_external_result"]

      keys?(metadata, ~w(call_id tool recorded_at)) and metadata["call_id"] == call["id"] and
        metadata["tool"] == get_in(call, ["function", "name"]) and
        match?({:ok, _, _}, DateTime.from_iso8601(metadata["recorded_at"])) and
        String.starts_with?(
          message["content"],
          "Host-recorded MCP result: #{Jason.encode!(metadata)}\n"
        )
    else
      not Map.has_key?(message, "ipse_external_result")
    end
  end

  @doc false
  def valid_release?(event, observed) do
    keys?(
      event,
      ~w(type version result_id observed_sha256 decision projection_sha256 checked_at_ms deadline_ms)
    ) and
      event["type"] == "managed_tool_result_release" and event["version"] === 1 and
      event["result_id"] == observed["result_id"] and
      event["observed_sha256"] == JSON.digest([observed]) and
      event["decision"] in ~w(current withdrawn) and
      event["projection_sha256"] ==
        JSON.digest([result_message(observed["message"], event["decision"])]) and
      JSON.safe_uint?(event["checked_at_ms"]) and JSON.safe_uint?(event["deadline_ms"]) and
      event["checked_at_ms"] >= observed["checked_at_ms"] and
      event["deadline_ms"] <= observed["deadline_ms"] and
      (event["decision"] != "current" or event["checked_at_ms"] < event["deadline_ms"])
  rescue
    _ -> false
  end

  @doc false
  def valid_result_cleanup?(event, observed, admission),
    do:
      keys?(event, ~w(type version result_id release_sha256 status)) and
        event["type"] == "managed_tool_result_cleanup" and event["version"] === 1 and
        event["result_id"] == observed["result_id"] and
        event["release_sha256"] == JSON.digest([admission]) and
        event["status"] in ~w(confirmed unknown)

  @doc false
  def release_result(%{owner: owner, job_ref: job}, {status, text}) when is_binary(text) do
    outcome =
      cond do
        status == :unknown -> "unknown"
        status in [:error, :tool_error] -> "error"
        true -> "result_recorded"
      end

    text =
      if status == :tool_error,
        do: "MCP tool reported an error after dispatch; effects may have happened.\n" <> text,
        else: text

    case GenServer.call(owner, {:managed_tool_result_prepare, job, outcome, text}, 5_000) do
      {:ok, spec} -> release_prepared_result(owner, job, spec)
      _ -> @unknown
    end
  catch
    _, _ -> @unknown
  end

  def release_result(_, _), do: @unknown

  defp release_prepared_result(owner, job, spec) do
    entered = :atomics.new(1, signed: false)

    result =
      Resources.file_effect(fn ->
        ManagedUse.with_dependencies(spec.context, spec.dependencies, fn current ->
          :atomics.put(entered, 1, 1)

          GenServer.call(
            owner,
            {:managed_tool_result_admit, job, spec.id, :current, deadline(spec, current)},
            5_000
          )
        end)
      end)

    cond do
      result == {:ok, spec.id} ->
        cleanup_result(owner, job, spec.id, "confirmed")

      :atomics.get(entered, 1) != 0 ->
        cleanup_result(owner, job, spec.id, "unknown")

      true ->
        case GenServer.call(
               owner,
               {:managed_tool_result_admit, job, spec.id, :withdrawn, nil},
               5_000
             ) do
          {:ok, _} -> cleanup_result(owner, job, spec.id, "confirmed")
          _ -> @unknown
        end
    end
  end

  defp cleanup_result(owner, job, id, status) do
    case GenServer.call(owner, {:managed_tool_result_cleanup, job, id, status}, 5_000) do
      :ok when status == "confirmed" -> {:managed_tool_released, id}
      _ -> @unknown
    end
  end

  @doc false
  def prepare_result(s, caller, outcome, text) do
    s = if unresolved_effect?(s), do: interrupted(s), else: s

    with true <- caller?(s, caller) and s.managed_tool_result == nil,
         true <-
           outcome in ~w(result_recorded error unknown) and is_binary(text) and
             String.valid?(text),
         {:ok, base} <- snapshot(s),
         true <- base.dependencies != [],
         true <- s.config[:managed_tool_layout] == @layout,
         [call | tail] <- s.calls,
         message = Session.Turn.tool_message(call, text, outcome, s.tool_decision),
         now = System.system_time(:millisecond),
         id = Ipse.Usage.id(),
         observed = %{
           "type" => "managed_tool_result_observed",
           "version" => 1,
           "result_id" => id,
           "session_id" => s.id,
           "request_id" => s.last_request_id,
           "call_id" => call["id"],
           "input_sha256" => base.input_sha256,
           "dependencies_sha256" => JSON.digest(base.dependencies),
           "message" => message,
           "message_sha256" => JSON.digest([message]),
           "checked_at_ms" => now,
           "deadline_ms" => now + 5000
         },
         true <- byte_size(Jason.encode!(observed)) <= 131_072 do
      Session.record(s, observed)
      next = Session.managed_event(s, observed)

      snapshot = %{
        base
        | sha256: JSON.digest([base.sha256, observed]),
          input_sha256: JSON.digest([observed])
      }

      pending = %{
        id: id,
        observed: observed,
        snapshot: snapshot,
        job: s.job_ref,
        worker: s.task.pid,
        before_calls: s.calls,
        after_calls: tail,
        consumed: false,
        admission: nil,
        cleanup: nil
      }

      context = %{
        config: s.config,
        cwd: s.cwd,
        session_id: s.id,
        history_dir: s.dir,
        owner: self(),
        job_ref: s.job_ref,
        source_binding: {:snapshot, "tool.result", snapshot.sha256}
      }

      {:reply,
       {:ok, %{id: id, context: context, dependencies: base.dependencies, deadline: now + 5000}},
       %{next | managed_tool_result: pending}}
    else
      _ -> {:reply, @error, s}
    end
  end

  @doc false
  def result_snapshot(s) do
    with pending when is_map(pending) <- s.managed_tool_result,
         true <-
           s.phase == :tool and s.task != nil and s.task.pid == pending.worker and
             s.job_ref == pending.job,
         true <-
           s.calls == if(pending.consumed, do: pending.after_calls, else: pending.before_calls) do
      {:ok, pending.snapshot}
    else
      _ -> @error
    end
  end

  @doc false
  def admit_result(s, caller, id, mode, deadline) do
    with true <- caller?(s, caller),
         {:ok, _} <- result_snapshot(s),
         pending = s.managed_tool_result,
         true <- pending.id == id and pending.admission == nil,
         now = System.system_time(:millisecond),
         true <-
           mode == :withdrawn or
             (mode == :current and JSON.safe_uint?(deadline) and
                now < deadline and deadline <= pending.observed["deadline_ms"]),
         decision = if(mode == :current, do: "current", else: "withdrawn"),
         message = result_message(pending.observed["message"], decision),
         event = %{
           "type" => "managed_tool_result_release",
           "version" => 1,
           "result_id" => id,
           "observed_sha256" => JSON.digest([pending.observed]),
           "decision" => decision,
           "projection_sha256" => JSON.digest([message]),
           "checked_at_ms" => now,
           "deadline_ms" =>
             if(mode == :current, do: deadline, else: pending.observed["deadline_ms"])
         } do
      Session.record(s, event)
      next = Session.managed_event(s, event)
      pending = %{pending | admission: event}
      next = %{next | managed_tool_result: pending}

      if match?(%ManagedLineage{unavailable: false}, next.managed_lineage) and
           (mode != :current or System.system_time(:millisecond) < deadline) do
        result =
          if mode == :current,
            do: Session.Turn.commit_tool_result(next, hd(s.calls), message, deadline),
            else: {:ok, Session.Turn.commit_tool_result(next, hd(s.calls), message)}

        case result do
          {:ok, published} ->
            {:reply, {:ok, id}, %{published | managed_tool_result: %{pending | consumed: true}}}

          {:error, expired} ->
            {:reply, @error, %{expired | managed_tool_result: %{pending | consumed: true}}}
        end
      else
        {:reply, @error, next}
      end
    else
      _ -> {:reply, @error, s}
    end
  end

  @doc false
  def finish_result(s, caller, id, status) do
    with true <- caller?(s, caller),
         {:ok, _} <- result_snapshot(s),
         p = s.managed_tool_result,
         true <- p.id == id and p.admission != nil and p.cleanup == nil,
         true <- status in ~w(confirmed unknown),
         event = %{
           "type" => "managed_tool_result_cleanup",
           "version" => 1,
           "result_id" => id,
           "release_sha256" => JSON.digest([p.admission]),
           "status" => status
         } do
      Session.record(s, event)

      next =
        if status == "unknown",
          do: %{s | messages: withhold_result(s.messages, s.managed_lineage)},
          else: s

      next = Session.managed_event(next, event)
      {:reply, :ok, %{next | managed_tool_result: %{p | cleanup: status}}}
    else
      _ -> {:reply, @error, s}
    end
  end

  @doc false
  def complete_result(s, id) do
    case s.managed_tool_result do
      %{id: ^id, cleanup: "confirmed", admission: admission, observed: observed} ->
        next = %{s | managed_tool_result: nil, managed_tool_effect: nil}

        if admission["decision"] == "current" and
             observed["message"]["ipse_tool_outcome"]["status"] != "unknown",
           do: {:noreply, Session.Turn.next_tool(next)},
           else:
             {:noreply,
              Session.Turn.fail(
                next,
                "Managed tool output was withheld or its outcome is unknown; inspect original receipts."
              )}

      _ ->
        {:noreply,
         Session.Turn.fail(s, "Managed tool release is unconfirmed; inspect original receipts.")}
    end
  end

  @doc false
  def withhold_result(messages, %{
        tool_result_release: %{observed: observed, admission: admission}
      })
      when is_map(observed) and is_map(admission) do
    original = result_message(observed["message"], admission["decision"])
    replacement = result_message(observed["message"], "withdrawn")

    case Enum.reverse(messages) do
      [^original | rest] -> Enum.reverse([replacement | rest])
      _ -> messages
    end
  end

  def withhold_result(messages, _), do: messages

  @doc false
  def interrupted(s) do
    pending_result =
      is_map(s[:managed_tool_result]) and s.managed_tool_result.cleanup != "confirmed"

    if unresolved_effect?(s) or pending_result do
      lineage =
        case s.managed_lineage do
          %ManagedLineage{} = value -> %{value | unavailable: true}
          other -> other
        end

      %{s | messages: withhold_result(s.messages, s.managed_lineage), managed_lineage: lineage}
    else
      s
    end
  end

  defp unresolved_effect?(s),
    do:
      is_map(s[:managed_tool_effect]) and s.managed_tool_effect.admitted and
        s.managed_tool_effect.cleanup != "confirmed"

  @doc false
  def native_binding(name, arguments),
    do: %{"kind" => "native.tool", "name" => name, "arguments_sha256" => JSON.digest([arguments])}

  @doc "Run only the actual bounded effect/send/start continuation while current authority is held."
  def with_effect(%{owner: owner, job_ref: job}, binding, fun) when is_function(fun, 1) do
    case GenServer.call(owner, {:managed_tool_effect_prepare, job, binding}, 5_000) do
      {:ok, :ordinary} -> fun.(nil)
      {:ok, spec} -> use_prepared(owner, job, spec, fun)
      _ -> @error
    end
  catch
    :exit, _ -> @unknown
  end

  def with_effect(_, _, _), do: @error

  defp use_prepared(owner, job, spec, fun) do
    entered = :atomics.new(1, signed: false)

    result =
      Resources.file_effect(fn ->
        ManagedUse.with_dependencies(spec.context, spec.dependencies, fn current ->
          deadline = deadline(spec, current)

          with :ok <-
                 GenServer.call(
                   owner,
                   {:managed_tool_effect_admit, job, spec.id, deadline},
                   5_000
                 ),
               true <- System.system_time(:millisecond) < deadline and Resources.active?() do
            :atomics.put(entered, 1, 1)
            value = fun.(deadline)
            {:managed_effect_return, spec.id, value}
          else
            _ -> @error
          end
        end)
      end)

    case result do
      {:managed_effect_return, id, value} when id == spec.id ->
        if GenServer.call(owner, {:managed_tool_effect_cleanup, job, id, "confirmed"}, 5_000) ==
             :ok, do: value, else: @unknown

      _ ->
        GenServer.call(owner, {:managed_tool_effect_cleanup, job, spec.id, "unknown"}, 5_000)
        if(:atomics.get(entered, 1) != 0, do: @unknown, else: @error)
    end
  catch
    _, _ -> @unknown
  end

  defp deadline(spec, current) do
    literal =
      for dep <- current,
          value = get_in(dep, ["subject", "validity", "valid_until_ms"]),
          is_integer(value),
          do: value

    Enum.min([
      spec.deadline,
      spec.context.config.semantic_admission["policy"]["expires_at_ms"] | literal
    ])
  end

  @doc false
  def snapshot(s) do
    with true <- s.phase == :tool and s.task != nil and s.job_ref != nil,
         [call | _] <- s.calls,
         {:ok, arguments} <- JSON.decode_bounded(get_in(call, ["function", "arguments"]), 65_536),
         true <- is_map(arguments),
         {:ok, deps} <- ManagedLineage.tool_dependencies(s.managed_lineage, call["id"]),
         {:ok, deps} <- ManagedReference.union([deps]) do
      selected = Ipse.MCP.tool(s.mcp_tools, get_in(call, ["function", "name"]))

      input =
        input(
          s.id,
          s.last_request_id,
          call,
          arguments,
          s.tool_decision,
          if(selected, do: Ipse.MCP.manifest(selected))
        )

      {:ok,
       %{
         dependencies: deps,
         sha256: JSON.digest([input, deps]),
         input_sha256: JSON.digest([input]),
         plan: nil,
         input: input
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def prepare(s, caller, binding) do
    with true <- caller?(s, caller),
         {:ok, snapshot} <- snapshot(s),
         true <- target?(s, snapshot, binding) do
      if snapshot.dependencies == [] do
        {:reply, {:ok, :ordinary}, s}
      else
        with true <-
               s.config[:managed_tool_layout] == @layout and
                 next_stage?(s.managed_tool_effect, snapshot, binding),
             now = System.system_time(:millisecond),
             id = Ipse.Usage.id() do
          pending = %{
            id: id,
            snapshot: snapshot,
            binding: binding,
            job: s.job_ref,
            worker: s.task.pid,
            admitted: false,
            admission: nil,
            cleanup: nil,
            deadline: now + 5000
          }

          context = %{
            config: s.config,
            cwd: s.cwd,
            session_id: s.id,
            history_dir: s.dir,
            owner: self(),
            job_ref: s.job_ref,
            source_binding: {:snapshot, "tool.effect", snapshot.sha256}
          }

          {:reply,
           {:ok,
            %{
              id: id,
              context: context,
              dependencies: snapshot.dependencies,
              deadline: pending.deadline
            }}, %{s | managed_tool_effect: pending}}
        else
          _ -> {:reply, @error, s}
        end
      end
    else
      _ -> {:reply, @error, s}
    end
  end

  @doc false
  def admit(s, caller, id, deadline) do
    with true <- caller?(s, caller),
         pending when is_map(pending) <- s.managed_tool_effect,
         true <- pending.id == id and pending.job == s.job_ref and pending.worker == s.task.pid,
         false <- pending.admitted,
         {:ok, snapshot} <- snapshot(s),
         true <- snapshot == pending.snapshot and target?(s, snapshot, pending.binding),
         true <- JSON.safe_uint?(deadline) and deadline <= pending.deadline,
         now = System.system_time(:millisecond),
         true <- now < deadline do
      event = %{
        "type" => "managed_tool_effect_admitted",
        "version" => 1,
        "effect_id" => id,
        "session_id" => s.id,
        "request_id" => s.last_request_id,
        "call_id" => hd(s.calls)["id"],
        "input_sha256" => snapshot.input_sha256,
        "snapshot_sha256" => snapshot.sha256,
        "dependencies_sha256" => JSON.digest(snapshot.dependencies),
        "binding" => pending.binding,
        "binding_sha256" => JSON.digest([pending.binding]),
        "checked_at_ms" => now,
        "deadline_ms" => deadline
      }

      Session.record(s, event)
      next = Session.managed_event(s, event)
      next = %{next | managed_tool_effect: %{pending | admitted: true, admission: event}}

      allowed =
        match?(%ManagedLineage{unavailable: false}, next.managed_lineage) and
          System.system_time(:millisecond) < deadline

      {:reply, if(allowed, do: :ok, else: @error), next}
    else
      _ -> {:reply, @error, s}
    end
  end

  @doc false
  def finish_effect(s, caller, id, status) do
    with true <- caller?(s, caller),
         p when is_map(p) <- s.managed_tool_effect,
         true <- p.id == id and p.job == s.job_ref and p.worker == s.task.pid and p.admitted,
         true <- p.cleanup == nil and is_map(p.admission) and status in ~w(confirmed unknown),
         event = %{
           "type" => "managed_tool_effect_cleanup",
           "version" => 1,
           "effect_id" => id,
           "admission_sha256" => JSON.digest([p.admission]),
           "status" => status
         } do
      Session.record(s, event)
      next = Session.managed_event(s, event)
      {:reply, :ok, %{next | managed_tool_effect: %{p | cleanup: status}}}
    else
      _ -> {:reply, @error, s}
    end
  end

  defp next_stage?(nil, _, %{"kind" => kind}), do: kind != "mcp.send"

  defp next_stage?(
         %{cleanup: "confirmed", binding: %{"kind" => "mcp.start"}, snapshot: previous},
         snapshot,
         %{"kind" => "mcp.send"}
       ),
       do: previous == snapshot

  defp next_stage?(_, _, _), do: false

  defp target?(s, snapshot, %{"kind" => "native.tool"} = binding) do
    name = get_in(snapshot.input, ["call", "function", "name"])

    name in @native_tools and
      binding == native_binding(name, snapshot.input["arguments"]) and
      Ipse.MCP.tool(s.mcp_tools, name) == nil
  end

  defp target?(s, snapshot, %{"kind" => "mcp.start", "descriptor_sha256" => digest} = binding) do
    selected = Ipse.MCP.tool(s.mcp_tools, get_in(snapshot.input, ["call", "function", "name"]))
    keys?(binding, ~w(kind descriptor_sha256)) and selected != nil and selected.digest == digest
  end

  defp target?(
         s,
         snapshot,
         %{"kind" => "mcp.send", "descriptor_sha256" => digest, "request" => request} = binding
       ) do
    descriptor = Ipse.MCP.tool(s.mcp_tools, get_in(snapshot.input, ["call", "function", "name"]))

    Enum.sort(Map.keys(binding)) == ~w(descriptor_sha256 kind request) and
      descriptor != nil and descriptor.digest == digest and
      Ipse.MCP.managed_request?(descriptor, snapshot.input["arguments"], request)
  end

  defp target?(_, _, _), do: false

  defp record_target?(%{"kind" => "native.tool"} = binding, input),
    do:
      input["mcp"] == nil and
        get_in(input, ["call", "function", "name"]) in @native_tools and
        binding == native_binding(get_in(input, ["call", "function", "name"]), input["arguments"])

  defp record_target?(%{"kind" => "mcp.start", "descriptor_sha256" => digest} = binding, input),
    do:
      keys?(binding, ~w(kind descriptor_sha256)) and is_map(input["mcp"]) and
        input["mcp"]["descriptor_sha256"] == digest

  defp record_target?(
         %{"kind" => "mcp.send", "descriptor_sha256" => digest, "request" => request} = binding,
         input
       ),
       do:
         Enum.sort(Map.keys(binding)) == ~w(descriptor_sha256 kind request) and
           is_map(input["mcp"]) and input["mcp"]["descriptor_sha256"] == digest and
           Ipse.MCP.managed_request?(input["mcp"], input["arguments"], request)

  defp record_target?(_, _), do: false

  defp caller?(s, caller),
    do:
      s.phase == :tool and s.task != nil and s.job_ref != nil and
        (s.task.pid == caller or Resources.authorized_effect?(s.task.pid, caller))

  defp keys?(value, fields), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(fields)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
