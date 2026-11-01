defmodule Ipse.Session.WorkerInput do
  @moduledoc false
  alias Ipse.{JSON, Session}
  alias Ipse.Extension.{Actions, Registry, ResultSource, Worker}
  alias Ipse.Session.{ManagedLineage, ManagedReference, ManagedUse, Resources}
  alias Ipse.Runner.{SessionSource, Transaction}
  @error {:error, :worker_input_unavailable}
  @unknown {:unknown, :worker_input_unconfirmed}
  @intent_keys ~w(type version input_id session_id invocation_id parent_sha256 actions_sha256 stage payload_sha256 artifact_sha256 protocol_id frame_sha256 frame_bytes dependencies_sha256 checked_at_ms deadline_ms)
  @result_keys ~w(type version input_id intent_sha256 status)
  @transition_keys ~w(type version input_id intent_sha256 evidence checked_at_ms deadline_ms)

  def record?(%{"type" => "worker_input_intent"} = event) do
    keys?(event, @intent_keys) and event["version"] === 1 and
      Enum.all?(~w(input_id session_id invocation_id), &id?(event[&1])) and
      Enum.all?(
        ~w(parent_sha256 actions_sha256 payload_sha256 artifact_sha256 frame_sha256 dependencies_sha256),
        &JSON.sha256?(event[&1])
      ) and is_binary(event["stage"]) and
      JSON.safe_uint?(event["protocol_id"]) and event["protocol_id"] > 0 and
      is_integer(event["frame_bytes"]) and event["frame_bytes"] in 5..32_772 and
      JSON.safe_uint?(event["checked_at_ms"]) and JSON.safe_uint?(event["deadline_ms"]) and
      (event["deadline_ms"] - event["checked_at_ms"]) in 1..30_000
  rescue
    _ -> false
  end

  def record?(%{"type" => "worker_input_result"} = event),
    do:
      keys?(event, @result_keys) and event["version"] === 1 and id?(event["input_id"]) and
        JSON.sha256?(event["intent_sha256"]) and event["status"] in ~w(delivered unknown)

  def record?(%{"type" => "worker_input_root_transition"} = event) do
    evidence = event["evidence"]

    keys?(event, @transition_keys) and event["version"] === 1 and id?(event["input_id"]) and
      JSON.sha256?(event["intent_sha256"]) and
      keys?(
        evidence,
        ~w(fresh_dependency fresh_observation inspection operation_id own_action_sha256 receipt_sha256)
      ) and
      id?(evidence["operation_id"]) and
      JSON.sha256?(evidence["own_action_sha256"]) and JSON.sha256?(evidence["receipt_sha256"]) and
      ManagedReference.dependency?(evidence["fresh_dependency"]) and
      evidence["fresh_dependency"]["version"] === 3 and
      JSON.safe_uint?(event["checked_at_ms"]) and JSON.safe_uint?(event["deadline_ms"]) and
      (event["deadline_ms"] - event["checked_at_ms"]) in 1..30_000 and
      byte_size(Jason.encode!(event)) <= 16_384
  rescue
    _ -> false
  end

  def record?(_), do: false

  def valid_intent?(event, parent, actions_sha, payload) do
    with true <- record?(event),
         true <- event["type"] == "worker_input_intent",
         true <- event["invocation_id"] == parent["invocation_id"],
         true <- event["session_id"] == parent["payload"]["session_id"],
         true <- event["parent_sha256"] == JSON.digest([parent]),
         true <- event["artifact_sha256"] == parent["identity"]["artifact_sha256"],
         true <- event["actions_sha256"] == actions_sha,
         true <- event["payload_sha256"] == JSON.digest([payload]),
         {:ok, frame} <- Worker.frame(event["protocol_id"], event["stage"], payload),
         true <- event["frame_bytes"] == byte_size(frame),
         true <- event["frame_sha256"] == JSON.sha256(frame),
         do: true,
         else: (_ -> false)
  rescue
    _ -> false
  end

  def bound_result?(event, intent),
    do:
      record?(event) and event["type"] == "worker_input_result" and
        event["input_id"] == intent["input_id"] and
        event["intent_sha256"] == JSON.digest([intent])

  def bound_transition?(event, intent),
    do:
      record?(event) and event["type"] == "worker_input_root_transition" and
        event["input_id"] == intent["input_id"] and
        event["intent_sha256"] == JSON.digest([intent]) and
        event["checked_at_ms"] >= intent["checked_at_ms"] and
        event["deadline_ms"] == intent["deadline_ms"]

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)

  # This entry point accepts the actual Host request. Session independently
  # resolves its committed parent/result before preparation can send any bytes.
  def call(owner, job, worker, stage, payload, timeout) do
    case GenServer.call(owner, {:worker_input_select, job, stage, payload}, 5_000) do
      {:ok, :ordinary} -> Worker.call(worker, stage, payload, timeout)
      {:ok, :managed} -> guarded_call(owner, job, worker, stage, payload, timeout)
      _ -> @error
    end
  catch
    :exit, _ -> @unknown
  end

  defp guarded_call(owner, job, worker, stage, payload, timeout) do
    Resources.file_effect(fn ->
      with {:ok, handle, binding} <- Worker.prepare_input(worker, stage, payload, timeout),
           {:ok, spec} <-
             GenServer.call(
               owner,
               {:worker_input_prepare, job, worker, handle, stage, payload},
               5_000
             ) do
        result =
          with {:ok, use_spec} <- rebase_if_needed(owner, job, spec) do
            ManagedUse.with_worker_dependencies(use_spec.context, use_spec.dependencies, fn _,
                                                                                            held ->
              wall =
                Enum.min([
                  held.deadline_ms,
                  use_spec.intent["deadline_ms"],
                  System.system_time(:millisecond) +
                    binding.deadline - System.monotonic_time(:millisecond) - 1
                ])

              SessionSource.with_worker_input(
                held.collection,
                use_spec.context,
                use_spec.intent,
                use_spec.sha256,
                held.source_leases,
                held.source_proofs,
                wall,
                fn ->
                  with_journals(held.collection, held.journal_leases, fn ->
                    deliver(worker, handle, held, wall)
                  end)
                end
              )
            end)
          end

        if result == {:ok, :input_delivered} and
             GenServer.call(
               owner,
               {:worker_input_finish, job, spec.intent["input_id"], :delivered}
             ) ==
               :ok do
          # All retained source/policy scopes have returned. Keep this original
          # publisher alive, but hold no policy locks while waiting for compute.
          Worker.await_input(worker, handle)
        else
          Worker.close(worker)
          GenServer.call(owner, {:worker_input_finish, job, spec.intent["input_id"], :unknown})
          @unknown
        end
      else
        _ ->
          Worker.close(worker)
          @unknown
      end
    end)
  rescue
    _ -> @unknown
  catch
    _, _ -> @unknown
  end

  defp with_journals(_, [], fun), do: fun.()

  defp with_journals(cap, [lease | rest], fun) do
    Transaction.with_inactive_acceptance_journal_lease(cap, lease.token, fn ->
      with_journals(cap, rest, fun)
    end)
  end

  defp rebase_if_needed(_, _, %{candidate: nil} = spec), do: {:ok, spec}

  defp rebase_if_needed(owner, job, spec) do
    with {:ok, %{observation: observation, inspected: inspection}} <-
           ManagedUse.root_transition_observation(spec.context, spec.dependencies, spec.candidate) do
      GenServer.call(
        owner,
        {:worker_input_rebase, job, spec.intent["input_id"], observation, inspection},
        5_000
      )
    else
      _ -> @error
    end
  end

  defp deliver(worker, handle, held, wall) do
    cap = held.collection

    with {:ok, binding} <- Worker.bind_stdin(worker, handle, wall),
         {:ok, %{pid: recipient}} <- Transaction.retained_share_identity(cap) do
      name = :crypto.strong_rand_bytes(16)
      secret = :crypto.strong_rand_bytes(32)
      pipe = binding.pipe
      expected = entry(pipe.pid, name, secret, pipe.device, pipe.inode)
      target = entry(recipient, name, secret, pipe.device, pipe.inode)

      importing =
        :gen_server.send_request(
          cap.controller,
          {:pipe_import, cap, binding.operation, expected, binding.wall_deadline, held.deadline,
           binding.frame}
        )

      with :ok <- Worker.export_stdin(worker, handle, target),
           {:reply, :ok} <- response(importing, held.deadline),
           :ok <-
             GenServer.call(
               cap.controller,
               {:pipe_write, cap, binding.operation, binding.frame},
               remaining(held.deadline)
             ) do
        closing = :gen_server.send_request(cap.controller, {:pipe_close, cap, binding.operation})

        with :ok <- Worker.settle_stdin(worker, handle),
             {:reply, :ok} <- response(closing, held.deadline),
             do: {:ok, :input_delivered},
             else: (_ -> @unknown)
      else
        _ -> @unknown
      end
    else
      _ -> @unknown
    end
  rescue
    _ -> @unknown
  catch
    _, _ -> @unknown
  end

  defp entry(pid, name, secret, device, inode),
    do: <<pid::32, name::binary, secret::binary, device::64, inode::64>>

  defp response(request, deadline), do: :gen_server.receive_response(request, remaining(deadline))
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 1)

  def select(s, caller, stage, payload) do
    with true <- worker?(s, caller),
         true <- is_nil(s.invocation.worker_input),
         {:ok, snapshot} <- request_snapshot(s, stage, payload) do
      {:reply, {:ok, if(snapshot.dependencies == [], do: :ordinary, else: :managed)}, s}
    else
      _ -> {:reply, @error, s}
    end
  end

  def prepare(s, caller, worker, handle, stage, payload) do
    with true <- worker?(s, caller) and is_nil(s.invocation.worker_input),
         {:ok, snapshot} <- request_snapshot(s, stage, payload),
         true <- snapshot.dependencies != [],
         {:ok, binding} <- Worker.input_binding(worker, handle, stage, payload),
         true <- binding.worker == worker and binding.owner == s.task.pid,
         true <- binding.caller == caller,
         true <- binding.artifact == s.invocation.parent["identity"]["artifact_sha256"],
         true <- binding.payload_sha256 == JSON.digest([payload]),
         true <- binding.frame_sha256 == JSON.sha256(binding.frame),
         true <- binding.deadline > System.monotonic_time(:millisecond) do
      now = System.system_time(:millisecond)

      intent = %{
        "type" => "worker_input_intent",
        "version" => 1,
        "input_id" => Ipse.Usage.id(),
        "session_id" => s.id,
        "invocation_id" => s.invocation.parent["invocation_id"],
        "parent_sha256" => JSON.digest([s.invocation.parent]),
        "actions_sha256" => JSON.digest(s.invocation.results),
        "stage" => stage,
        "payload_sha256" => binding.payload_sha256,
        "artifact_sha256" => binding.artifact,
        "protocol_id" => binding.sequence,
        "frame_sha256" => binding.frame_sha256,
        "frame_bytes" => byte_size(binding.frame),
        "dependencies_sha256" => JSON.digest(snapshot.dependencies),
        "checked_at_ms" => now,
        "deadline_ms" => now + binding.deadline - System.monotonic_time(:millisecond)
      }

      pending = %{
        intent: intent,
        snapshot: snapshot,
        parent: s.invocation.parent,
        actions_sha256: JSON.digest(s.invocation.results),
        worker: worker,
        handle: handle,
        caller: caller,
        binding: binding,
        job: s.job_ref,
        phase: s.phase,
        stage: stage
      }

      Session.record(s, intent)

      next =
        s
        |> Session.managed_event(intent)
        |> put_in([Access.key(:invocation), Access.key(:worker_input)], pending)

      context = %{
        config: s.config,
        cwd: s.cwd,
        session_id: s.id,
        history_dir: s.dir,
        owner: self(),
        job_ref: s.job_ref,
        source_binding: {:snapshot, "extension.input", snapshot.sha256}
      }

      spec = %{
        intent: intent,
        context: context,
        dependencies: snapshot.dependencies,
        sha256: snapshot.sha256,
        candidate:
          case ManagedLineage.root_candidate(s.managed_lineage, snapshot.dependencies) do
            {:ok, candidate} -> candidate
            _ -> nil
          end
      }

      {:reply, {:ok, spec}, next}
    else
      _ -> {:reply, @error, s}
    end
  rescue
    _ -> {:reply, @error, s}
  end

  def rebase(s, caller, id, observation, inspection) do
    with p when is_map(p) <- s.invocation.worker_input,
         true <- caller == p.caller and p.intent["input_id"] == id,
         true <- current?(s, p.intent) and s.share_barrier == nil,
         {:ok, event, _} <-
           ManagedLineage.worker_root_transition(
             s.managed_lineage,
             p.intent,
             observation,
             inspection,
             System.system_time(:millisecond)
           ),
         true <- record?(event) do
      Session.record(s, event)
      next = Session.managed_event(s, event)

      with {:ok, payload} <- expected_payload(next, p.stage),
           {:ok, snapshot} <- request_snapshot(next, p.stage, payload) do
        next = put_in(next.invocation.worker_input, %{p | snapshot: snapshot})

        context = %{
          config: s.config,
          cwd: s.cwd,
          session_id: s.id,
          history_dir: s.dir,
          owner: self(),
          job_ref: s.job_ref,
          source_binding: {:snapshot, "extension.input", snapshot.sha256}
        }

        {:reply,
         {:ok,
          %{
            intent: p.intent,
            context: context,
            dependencies: snapshot.dependencies,
            sha256: snapshot.sha256,
            candidate: nil
          }}, next}
      else
        _ -> {:reply, @error, next}
      end
    else
      _ -> {:reply, @error, s}
    end
  end

  def snapshot(s) do
    with p when is_map(p) <- s.invocation.worker_input,
         true <- current?(s, p.intent),
         do: {:ok, p.snapshot},
         else: (_ -> @error)
  end

  def current?(s, intent) do
    with p when is_map(p) <- s.invocation.worker_input,
         true <- p.intent === intent and p.job == s.job_ref and p.phase == s.phase,
         true <- worker?(s, p.caller) and p.parent === s.invocation.parent,
         true <- p.actions_sha256 == JSON.digest(s.invocation.results),
         {:ok, payload} <- expected_payload(s, p.stage),
         {:ok, snapshot} <- request_snapshot(s, p.stage, payload),
         true <- snapshot === p.snapshot,
         {:ok, binding} <- Worker.input_binding(p.worker, p.handle, p.stage, payload),
         true <- Map.take(binding, Map.keys(p.binding)) === p.binding do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def ticket(s, caller, ref, intent, sha, proofs, wall, sources) do
    with true <- s.share_barrier == nil and s.job_ref == ref,
         true <- s.lock_mode in [:header_share_v2, :resume_share_v2],
         true <- current?(s, intent),
         p = s.invocation.worker_input,
         true <- caller == p.caller and sha == p.snapshot.sha256,
         true <- is_list(proofs) and length(proofs) <= 128,
         true <- Enum.all?(proofs, &is_map/1) and length(Enum.uniq(proofs)) == length(proofs),
         true <- JSON.safe_uint?(wall) and wall > System.system_time(:millisecond),
         true <- wall <= p.intent["deadline_ms"] do
      remaining =
        min(
          min(p.binding.deadline - System.monotonic_time(:millisecond), 5_000),
          wall - System.system_time(:millisecond)
        )

      wall = min(wall, System.system_time(:millisecond) + remaining)
      deadline = min(p.binding.deadline, System.monotonic_time(:millisecond) + remaining)

      ticket = %{
        ticket: make_ref(),
        operation: :crypto.strong_rand_bytes(16),
        deadline: deadline,
        caller: caller,
        job_ref: ref,
        intent: intent,
        parent: p.parent,
        phase: s.phase,
        channel: nil,
        worker_input: sha,
        source_proofs: Enum.filter(proofs, &(&1["session_id"] == s.id)),
        expected_sources: sources,
        worker_source_proofs: Enum.reject(proofs, &(&1["session_id"] == s.id)),
        wall_deadline: wall
      }

      {:reply, {:ok, ticket.ticket, ticket.operation, deadline}, %{s | share_ticket: ticket}}
    else
      _ -> {:reply, @error, s}
    end
  end

  def finish(s, caller, id, status) when status in [:delivered, :unknown] do
    with p when is_map(p) <- s.invocation.worker_input,
         true <- p.caller == caller and worker?(s, caller),
         true <- p.intent["input_id"] == id and p.job == s.job_ref,
         true <- s.share_barrier == nil,
         true <- status == :unknown or current?(s, p.intent) do
      event = %{
        "type" => "worker_input_result",
        "version" => 1,
        "input_id" => id,
        "intent_sha256" => JSON.digest([p.intent]),
        "status" => Atom.to_string(status)
      }

      Session.record(s, event)
      s = Session.managed_event(s, event)

      next = %{
        s
        | invocation: %{
            s.invocation
            | worker_input: nil,
              interrupted: s.invocation.interrupted or status == :unknown
          }
      }

      {:reply, :ok, next}
    else
      _ -> {:reply, @error, s}
    end
  end

  def finish(s, _, _, _), do: {:reply, @error, s}

  defp worker?(s, caller),
    do:
      is_map(s.task) and s.job_ref != nil and
        (s.task.pid == caller or Resources.authorized_effect?(s.task.pid, caller))

  defp request_snapshot(s, stage, payload) do
    with true <- s.phase in [:tool, :extension_command, :extension_service, :extension_events],
         true <- s.task != nil and s.job_ref != nil,
         true <- is_nil(s.invocation.action) and not s.invocation.interrupted,
         parent when is_map(parent) <- s.invocation.parent,
         true <- Registry.live?(parent["identity"]),
         true <- Ipse.Session.Invocation.output_timely?(s),
         %ManagedLineage{unavailable: false, active_invocation: id} <- s.managed_lineage,
         true <- id == parent["invocation_id"],
         %{parent: ^parent} <- s.managed_lineage.invocations[id],
         {:ok, expected} <- expected_payload(s, stage),
         true <- payload === expected,
         {:ok, dependencies} <-
           ManagedLineage.invocation_dependencies(
             s.managed_lineage,
             id,
             s.invocation.managed_reads
           ) do
      input = %{
        "parent_sha256" => JSON.digest([parent]),
        "actions_sha256" => JSON.digest(s.invocation.results),
        "stage" => stage,
        "payload" => payload
      }

      {:ok,
       %{
         dependencies: dependencies,
         sha256: JSON.digest([input, dependencies]),
         input_sha256: JSON.digest([input]),
         plan: nil
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp expected_payload(s, "host.actions") do
    case List.last(s.invocation.results) do
      event when is_map(event) -> {:ok, Actions.resume(event)}
      _ -> @error
    end
  end

  defp expected_payload(s, "result.output") do
    with %{id: output} <- s.extension_output,
         %ResultSource{intent: parent} = source <- s.extension_result_sources.sources[output],
         true <- parent === s.invocation.parent,
         do: ResultSource.request(source),
         else: (_ -> @error)
  end

  defp expected_payload(s, stage) do
    if s.invocation.results == [] and stage == s.invocation.parent["descriptor"]["stage"],
      do: {:ok, s.invocation.parent["payload"]},
      else: @error
  end
end
