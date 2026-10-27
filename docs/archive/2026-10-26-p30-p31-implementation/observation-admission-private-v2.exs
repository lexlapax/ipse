defmodule Ipse.Session.ObservationAdmission do
  @moduledoc false
  alias Ipse.{JSON, Journal.Writer}
  alias Ipse.Session.{ObservationReceipt, Resources}
  alias Ipse.Extension.Actions

  # Private prototype: Session must create this only after authenticating its
  # actual reviewed artifact, outer policy, action intent and worker scope. The
  # hash argument is an attestation from trusted host selection, not a worker
  # field or an independent proof. No observation value is returned to worker.
  def start(job, worker, intent, identity, reviewed_hash, writer)
      when is_reference(job) and is_pid(worker) and is_pid(writer) and is_map(intent) and
             is_map(identity) do
    with true <- JSON.sha256?(reviewed_hash) and identity["artifact_sha256"] === reviewed_hash,
         true <-
           Ipse.Extension.CollectionCall.valid_binding?(
             intent["effect_binding"],
             intent["request"],
             identity
           ),
         true <- intent["identity_sha256"] === JSON.digest([identity]),
         true <- intent["namespace"] === intent["effect_binding"]["namespace"],
         true <- is_binary(intent["operation_id"]) and is_binary(intent["parent_invocation_id"]) do
      token = make_ref()

      {:ok,
       %{
         owner: self(),
         worker: worker,
         job: job,
         token: token,
         intent: intent,
         identity: identity,
         writer: writer,
         phase: :pending
       }, token}
    else
      _ -> {:error, :observation_admission_refused}
    end
  rescue
    _ -> {:error, :observation_admission_refused}
  end

  def start(_, _, _, _, _, _), do: {:error, :observation_admission_refused}

  # Must execute in owning Session. The caller is the exact GenServer.from pid;
  # the opaque token is only given to the selected trusted host effect, not VM.
  # Every unsuccessful attempt consumes the state; caller must retain it.
  def admit(
        %{owner: owner, worker: worker, job: job, token: token, phase: :pending} = state,
        caller,
        job,
        token,
        observation
      )
      when owner == self() do
    failed = %{state | phase: :failed, token: nil}

    with true <- caller != worker and Resources.authorized_effect?(worker, caller),
         {:ok, prepared} <- ObservationReceipt.prepare(state.intent, state.identity, observation),
         {:ok, result} <-
           Actions.result(state.intent, %{"status" => "ok", "value" => prepared.value}),
         {:ok, receipt} <-
           ObservationReceipt.bind(state.intent, state.identity, observation, result),
         marker = marker(state.intent),
         :ok <- append_triplet(state.writer, [marker, result, receipt]) do
      {:ok, %{state | phase: :recorded, token: nil}}
    else
      _ -> {:error, failed}
    end
  rescue
    _ -> {:error, %{state | phase: :failed, token: nil}}
  catch
    _, _ -> {:error, %{state | phase: :failed, token: nil}}
  end

  def admit(state, _, _, _, _) when is_map(state),
    do: {:error, Map.merge(state, %{phase: :failed, token: nil})}

  # Applies only to a triplet selected by authenticated Session replay. The
  # caller must require one for every protected read and validate surrounding
  # action chronology, pinned artifact, journal and all later lineage uses.
  def replay(intent, [marker, result, receipt]) do
    if marker === marker(intent) and Actions.result_intent(result) === intent and
         ObservationReceipt.verify(result, receipt) == :ok,
       do: {:ok, receipt["dependency"]},
       else: {:error, :observation_replay_refused}
  rescue
    _ -> {:error, :observation_replay_refused}
  end

  def replay(_, _), do: {:error, :observation_replay_refused}

  # Caller must independently derive `required` from authenticated, versioned
  # Session intents and validate the complete outer journal chronology. It must
  # not obtain this list from a worker or the receipts being verified.
  def replay_stream(events, required)
      when is_list(events) and is_list(required) and length(required) <= 512 do
    with true <-
           length(events) <= Ipse.Journal.limits()["max_events"] and Enum.all?(events, &is_map/1),
         true <- Enum.all?(required, &is_map/1),
         ids = Enum.map(required, & &1["operation_id"]),
         true <- Enum.all?(ids, &is_binary/1) and length(Enum.uniq(ids)) == length(ids),
         expected = Map.new(required, &{&1["operation_id"], &1}),
         {:ok, seen} <- replay_events(events, expected, %{}),
         true <- map_size(seen) == map_size(expected) and Enum.all?(Map.values(seen), &is_map/1) do
      {:ok, seen}
    else
      _ -> {:error, :observation_replay_refused}
    end
  rescue
    _ -> {:error, :observation_replay_refused}
  end

  def replay_stream(_, _), do: {:error, :observation_replay_refused}

  defp replay_events([], _, seen), do: {:ok, seen}

  defp replay_events(
         [
           %{"type" => "collection_observation_begin", "operation_id" => id} = marker,
           result,
           receipt | rest
         ],
         expected,
         seen
       ) do
    with intent when is_map(intent) <- expected[id],
         :intent <- seen[id],
         {:ok, dependency} <- replay(intent, [marker, result, receipt]) do
      replay_events(rest, expected, Map.put(seen, id, dependency))
    else
      _ -> {:error, :observation_replay_refused}
    end
  end

  defp replay_events([%{"type" => type} | _], _, _)
       when type in ["collection_observation_begin", "collection_observation_receipt"],
       do: {:error, :observation_replay_refused}

  defp replay_events(
         [%{"type" => "extension_action_intent", "operation_id" => id} = intent | rest],
         expected,
         seen
       ) do
    case expected[id] do
      nil ->
        replay_events(rest, expected, seen)

      ^intent ->
        if(Map.has_key?(seen, id),
          do: {:error, :observation_replay_refused},
          else: replay_events(rest, expected, Map.put(seen, id, :intent))
        )

      _ ->
        {:error, :observation_replay_refused}
    end
  end

  defp replay_events(
         [%{"type" => "extension_action_result", "operation_id" => id} | rest],
         expected,
         seen
       ) do
    if Map.has_key?(expected, id),
      do: {:error, :observation_replay_refused},
      else: replay_events(rest, expected, seen)
  end

  defp replay_events([_ | rest], expected, seen), do: replay_events(rest, expected, seen)

  defp marker(intent) do
    %{
      "type" => "collection_observation_begin",
      "version" => 1,
      "parent_invocation_id" => intent["parent_invocation_id"],
      "operation_id" => intent["operation_id"],
      "intent_sha256" => JSON.digest([intent])
    }
  end

  defp bytes(event), do: byte_size(Jason.encode!(event)) + 1

  defp append_triplet(writer, events) do
    case Writer.reserve(writer, %{bytes: Enum.reduce(events, 0, &(bytes(&1) + &2)), events: 3}) do
      {:ok, reservation} ->
        result =
          Enum.reduce_while(events, :ok, fn event, :ok ->
            if Writer.append_reserved(writer, reservation, event) == :ok,
              do: {:cont, :ok},
              else: {:halt, :error}
          end)

        released = Writer.release(writer, reservation)
        if result == :ok and released == :ok, do: :ok, else: :error

      _ ->
        :error
    end
  end
end
