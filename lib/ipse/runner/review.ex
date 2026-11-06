defmodule Ipse.Runner.Review do
  @moduledoc """
  Native terminal review with an owner-bound, one-use consumption permit.

  This internal host primitive observes exact terminal input; it grants no
  effect permission, source truth or current storage authority. Its trusted
  caller must supply the complete proposed facts, release all locks before
  review, and revalidate those facts and authority under the effect's locks
  before consuming. No worker/SDK or serialized-observation constructor exists.
  """
  alias Ipse.{JSON, Runner, Session.Resources}
  @slot {__MODULE__, :permit}
  @lifetime 30_000
  @facts_bytes 16_384
  @display_bytes 65_536
  @error {:error, :native_review_refused}
  @unknown {:unknown, :native_review_unconfirmed}

  defmodule Permit do
    @moduledoc false
    @enforce_keys [:owner, :ref]
    defstruct @enforce_keys

    defimpl Inspect do
      def inspect(_, _), do: "#NativeReview<private>"
    end
  end

  @doc "Observe a fresh exact command/challenge, then enter a bounded host callback without holding terminal IO locks."
  def with_review(command, facts, fun), do: with_review(command, facts, fun, nil)

  @doc false
  def with_review(command, facts, fun, guard)
      when is_function(fun, 1) and (is_nil(guard) or is_function(guard, 1)) do
    review(command, facts, fun, guard, :direct)
  end

  def with_review(_, _, _, _), do: @error

  # The coordinator is an internal Host task, never a worker-supplied PID or
  # observation. It accepts only the tracked publication peer and one fresh
  # ticket, and performs the actual native input in an owned cleanup scope.
  @doc false
  def with_coordinated_review(command, facts, fun, guard, {coordinator, ticket})
      when is_function(fun, 1) and is_function(guard, 1) and is_pid(coordinator) and
             node(coordinator) == node() and is_reference(ticket) do
    review(command, facts, fun, guard, {:coordinator, coordinator, ticket})
  end

  def with_coordinated_review(_, _, _, _, _), do: @error

  # This entry accepts only the live, same-process handle produced by the
  # retained native management display, never a serialized observation.
  @doc false
  def with_management_input(command, facts, handle, fun) when is_function(fun, 1) do
    with true <-
           command === "forget" or
             (command === "reject" and Ipse.Session.PendingRejection.valid_facts?(facts)) or
             (command === "correct" and
                Ipse.Session.PendingCorrection.current_review?(
                  facts,
                  System.system_time(:millisecond)
                )) or
             (command === "accept" and Ipse.Session.PendingAcceptance.valid_facts?(facts)) or
             Ipse.Session.ManagedLifecycle.retention_review?(
               command,
               facts,
               System.system_time(:millisecond)
             ),
         true <- is_nil(Process.get(@slot)),
         true <- valid?(command, facts) and Resources.active?(),
         upstream when is_pid(upstream) <- Resources.file_effect_owner(),
         true <- Process.alive?(upstream),
         scope = Resources.current(),
         {:ok, observation, challenge, deadline} <-
           Ipse.Runner.ManagementTerminal.finish_review(handle, facts, command),
         observed_at = System.system_time(:millisecond),
         input = command <> " " <> challenge,
         true <- JSON.safe_uint?(observed_at),
         true <- observation["text"] === input,
         true <- Ipse.Session.Input.valid_observation?(Map.delete(observation, "text"), input, 2),
         true <-
           Resources.current() === scope and Resources.active?() and Process.alive?(upstream),
         true <- now() < deadline do
      receipt = %{
        "version" => 1,
        "kind" => "native_review",
        "command" => command,
        "event_id" => observation["event_id"],
        "display_sha256" => observation["display_sha256"],
        "challenge" => challenge,
        "input_sha256" => observation["text_sha256"],
        "observed_at_ms" => observed_at,
        "facts_sha256" => JSON.digest([facts])
      }

      enter(command, facts, receipt, upstream, scope, deadline, fun)
    else
      {:unknown, _} -> @unknown
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def with_management_input(_, _, _, _), do: @error

  @doc false
  def with_session_input(command, facts, handle, fun) when is_function(fun, 1) do
    with true <- command in ~w(correct supersede),
         true <-
           Ipse.Session.ManagedSupersession.reviewed_relation?(
             command,
             facts,
             System.system_time(:millisecond)
           ),
         true <- is_nil(Process.get(@slot)) and valid?(command, facts) and Resources.active?(),
         upstream when is_pid(upstream) <- Resources.file_effect_owner(),
         true <- Process.alive?(upstream),
         scope = Resources.current(),
         {:ok, observation, challenge, deadline} <-
           Ipse.Runner.LeasedTerminal.finish_relation(handle, facts, command),
         observed_at = System.system_time(:millisecond),
         input = command <> " " <> challenge,
         true <- JSON.safe_uint?(observed_at) and observation["text"] === input,
         true <- Ipse.Session.Input.valid_observation?(Map.delete(observation, "text"), input, 2),
         true <-
           observation["display_sha256"] === JSON.sha256(display(command, facts, challenge)),
         true <-
           Resources.current() === scope and Resources.active?() and Process.alive?(upstream),
         true <- now() < deadline do
      receipt = %{
        "version" => 1,
        "kind" => "native_review",
        "command" => command,
        "event_id" => observation["event_id"],
        "display_sha256" => observation["display_sha256"],
        "challenge" => challenge,
        "input_sha256" => observation["text_sha256"],
        "observed_at_ms" => observed_at,
        "facts_sha256" => JSON.digest([facts])
      }

      enter(command, facts, receipt, upstream, scope, deadline, fun)
    else
      {:unknown, _} -> @unknown
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def with_session_input(_, _, _, _), do: @error

  defp review(command, facts, fun, guard, input_source) do
    with true <- is_nil(Process.get(@slot)),
         true <- valid?(command, facts) and Resources.active?(),
         upstream = Resources.file_effect_owner(),
         true <- is_pid(upstream) and Process.alive?(upstream),
         scope = Resources.current(),
         challenge = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
         input = command <> " " <> challenge,
         display = display(command, facts, challenge),
         true <- byte_size(display) <= @display_bytes,
         {:ok, observation} <- review_input(display, guard, input_source),
         observed_at = System.system_time(:millisecond),
         deadline = now() + @lifetime,
         true <- JSON.safe_uint?(observed_at),
         true <- observation["text"] === input,
         true <-
           Ipse.Session.Input.valid_observation?(Map.delete(observation, "text"), input, 2),
         true <- observation["display_sha256"] == JSON.sha256(display),
         true <- Resources.current() === scope and Resources.active?(),
         true <- Process.alive?(upstream),
         true <- now() < deadline do
      receipt = %{
        "version" => 1,
        "kind" => "native_review",
        "command" => command,
        "event_id" => observation["event_id"],
        "display_sha256" => observation["display_sha256"],
        "challenge" => challenge,
        "input_sha256" => observation["text_sha256"],
        "observed_at_ms" => observed_at,
        "facts_sha256" => JSON.digest([facts])
      }

      enter(command, facts, receipt, upstream, scope, deadline, fun)
    else
      {:unknown, _} -> @unknown
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  defp review_input(display, nil, :direct), do: Runner.operator_input(display, 120_000, 2)

  defp review_input(display, guard, :direct),
    do: Runner.operator_input(display, 120_000, 2, guard)

  defp review_input(display, guard, {:coordinator, coordinator, ticket}) do
    monitor = Process.monitor(coordinator)
    deadline = now() + 130_000
    send(coordinator, {:managed_review_input, ticket, self(), display, guard})

    try do
      receive do
        {:managed_review_guard_authority, ^ticket, ^coordinator, secret}
        when is_reference(secret) ->
          coordinated_guard(display, guard, coordinator, ticket, secret, monitor, deadline)

        {:managed_review_result, ^ticket, ^coordinator, {:unknown, _} = result} ->
          result

        {:managed_review_result, ^ticket, ^coordinator, {:error, _} = result} ->
          result

        {:DOWN, ^monitor, :process, ^coordinator, _} ->
          @unknown
      after
        max(deadline - now(), 0) -> @unknown
      end
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp coordinated_guard(_display, guard, coordinator, ticket, secret, coordinator_ref, deadline) do
    receive do
      {:managed_review_guard, ^ticket, ^secret, child, guard_ref}
      when is_pid(child) and node(child) == node() and is_reference(guard_ref) ->
        child_ref = Process.monitor(child)
        owner = self()
        used = :atomics.new(1, [])

        continuation = fn wall, authority ->
          if self() == owner and is_integer(wall) and is_map(authority) and
               :atomics.compare_exchange(used, 1, 0, 1) == :ok do
            send(child, {:managed_review_deadline, ticket, owner, guard_ref, wall, authority})

            result =
              receive do
                {:managed_review_displayed, ^ticket, ^child, ^guard_ref, result} -> result
                {:DOWN, ^child_ref, :process, ^child, _} -> @unknown
                {:DOWN, ^coordinator_ref, :process, ^coordinator, _} -> @unknown
              after
                max(deadline - now(), 0) -> @unknown
              end

            if result === :ok, do: :atomics.put(used, 1, 2)
            result
          else
            :atomics.put(used, 1, 3)
            @error
          end
        end

        guard_result =
          try do
            guard.(continuation)
          rescue
            _ -> @error
          catch
            _, _ -> @error
          end

        accepted = guard_result === :ok and :atomics.get(used, 1) == 2
        :atomics.put(used, 1, 3)
        release = if accepted, do: :ok, else: @error
        send(child, {:managed_review_release, ticket, owner, guard_ref, release})
        Process.demonitor(child_ref, [:flush])

        receive do
          {:managed_review_result, ^ticket, ^coordinator, result} ->
            cond do
              match?({:unknown, _}, guard_result) -> @unknown
              accepted or match?({:unknown, _}, result) -> result
              true -> @error
            end

          {:DOWN, ^coordinator_ref, :process, ^coordinator, _} ->
            @unknown
        after
          max(deadline - now(), 0) -> @unknown
        end

      {:managed_review_result, ^ticket, ^coordinator, {:unknown, _} = result} ->
        result

      {:managed_review_result, ^ticket, ^coordinator, {:error, _} = result} ->
        result

      {:DOWN, ^coordinator_ref, :process, ^coordinator, _} ->
        @unknown
    after
      max(deadline - now(), 0) -> @unknown
    end
  end

  @doc "Check an exact live review before reserving its bounded effect; does not consume permission."
  def check(permit, command, facts) do
    with {:ok, _} <- pending(permit, command, facts, :available), do: :ok
  end

  @doc "Return the actual consumed review only to its same live owner and exact facts."
  def consumed_receipt(permit, command, facts) do
    with {:ok, pending} <- pending(permit, command, facts, :consumed),
         do: {:ok, pending.receipt}
  end

  @doc false
  def claim_supersession_effect(
        %Permit{owner: owner, ref: ref},
        facts,
        intent,
        request,
        normalized,
        receipt
      )
      when owner == self() do
    case Process.get(@slot) do
      %{ref: ^ref, status: :consumed} = held ->
        Process.put(@slot, %{held | status: :refused})
        command = if facts["mode"] == "ordinary", do: "correct", else: "supersede"
        wall = System.system_time(:millisecond)

        with true <- held.command === command and held.facts === facts and live?(held),
             true <- Ipse.Session.ManagedSupersession.reviewed_relation?(command, facts, wall),
             true <- facts["request_sha256"] === JSON.digest([request]),
             true <-
               receipt["kind"] === "native_literal_supersession" and receipt["version"] === 3,
             true <- receipt["action_sha256"] === facts["action_sha256"],
             true <- receipt["native_review_sha256"] === JSON.digest([held.receipt]),
             true <- JSON.safe_uint?(receipt["publish_before_ms"]),
             deadline = min(receipt["publish_before_ms"], wall + held.deadline - now()),
             true <- wall < deadline do
          claim = %{
            intent: JSON.digest([intent]),
            original: JSON.digest([request]),
            normalized: JSON.digest([normalized]),
            normalization: JSON.digest([receipt]),
            deadline: deadline
          }

          Process.put(
            @slot,
            held |> Map.put(:status, :effect_claimed) |> Map.put(:supersession_claim, claim)
          )

          {:ok, %{review: held.receipt, publish_before_ms: deadline}}
        else
          _ -> @error
        end

      _ ->
        @error
    end
  rescue
    _ -> @error
  end

  def claim_supersession_effect(_, _, _, _, _, _), do: @error

  @doc false
  def claimed_supersession_effect(permit, facts, intent, request, normalized, receipt) do
    command = if facts["mode"] == "ordinary", do: "correct", else: "supersede"

    with {:ok, held} <- pending(permit, command, facts, :effect_claimed),
         claim when is_map(claim) <- held[:supersession_claim],
         true <-
           claim.intent === JSON.digest([intent]) and claim.original === JSON.digest([request]),
         true <-
           claim.normalized === JSON.digest([normalized]) and
             claim.normalization === JSON.digest([receipt]),
         true <- System.system_time(:millisecond) < claim.deadline do
      {:ok, %{review: held.receipt, publish_before_ms: claim.deadline}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def claimed_supersession_receipt(permit, command, facts) do
    with true <- command in ~w(correct supersede),
         {:ok, held} <- pending(permit, command, facts, :effect_claimed),
         %{deadline: deadline} <- held[:supersession_claim],
         true <- System.system_time(:millisecond) < deadline,
         do: {:ok, held.receipt},
         else: (_ -> @error)
  end

  @doc false
  def claim_pending_correction_effect(
        %Permit{owner: owner, ref: ref},
        facts,
        intent,
        request,
        normalized,
        receipt
      )
      when owner == self() do
    case Process.get(@slot) do
      %{ref: ^ref, status: :consumed} = held ->
        Process.put(@slot, %{held | status: :refused})
        wall = System.system_time(:millisecond)

        with true <- held.command === "correct" and held.facts === facts and live?(held),
             true <- Ipse.Session.PendingCorrection.current_review?(facts, wall),
             true <-
               intent === %{
                 "type" => "managed_lifecycle_intent",
                 "version" => 1,
                 "operation_id" => facts["operation_id"],
                 "facts" => facts
               },
             true <-
               request === facts["request"] and facts["request_sha256"] === JSON.digest([request]),
             true <- Ipse.Extension.Collection.valid_request?(normalized),
             true <- Map.delete(request, "changes") === Map.delete(normalized, "changes"),
             {original, extras} = Enum.split(normalized["changes"], 3),
             true <- original === request["changes"] and length(extras) in 1..5,
             true <- Enum.all?(extras, &String.starts_with?(&1["key"], "host.validity.")),
             true <- receipt["kind"] === "native_pending_correction" and receipt["version"] === 3,
             true <- receipt["action_sha256"] === facts["action_sha256"],
             true <- receipt["native_review_sha256"] === JSON.digest([held.receipt]),
             true <- receipt["publish_before_ms"] === facts["publish_before_ms"],
             deadline = min(facts["publish_before_ms"], wall + held.deadline - now()),
             true <- wall < deadline do
          claim = %{
            intent: JSON.digest([intent]),
            original: JSON.digest([request]),
            normalized: JSON.digest([normalized]),
            normalization: JSON.digest([receipt]),
            deadline: deadline
          }

          Process.put(
            @slot,
            held |> Map.put(:status, :effect_claimed) |> Map.put(:pending_correction_claim, claim)
          )

          {:ok, %{review: held.receipt, publish_before_ms: deadline}}
        else
          _ -> @error
        end

      _ ->
        @error
    end
  rescue
    _ -> @error
  end

  def claim_pending_correction_effect(_, _, _, _, _, _), do: @error

  @doc false
  def claimed_pending_correction_effect(permit, facts, intent, request, normalized, receipt) do
    with {:ok, held} <- pending(permit, "correct", facts, :effect_claimed),
         claim when is_map(claim) <- held[:pending_correction_claim],
         true <-
           claim.intent === JSON.digest([intent]) and claim.original === JSON.digest([request]),
         true <-
           claim.normalized === JSON.digest([normalized]) and
             claim.normalization === JSON.digest([receipt]),
         true <- System.system_time(:millisecond) < claim.deadline do
      {:ok, %{review: held.receipt, publish_before_ms: claim.deadline}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def claim_retention_effect(
        %Permit{owner: owner, ref: ref},
        facts,
        intent,
        request,
        normalized,
        receipt
      )
      when owner == self() do
    case Process.get(@slot) do
      %{ref: ^ref, status: :consumed} = pending ->
        Process.put(@slot, %{pending | status: :refused})
        command = Ipse.Extension.Collection.ManagedRetention.command(facts["policy"])
        wall = System.system_time(:millisecond)
        remaining = pending.deadline - now()
        selected_deadline = receipt["valid_until_ms"]
        old_deadline = facts["old_deadline_ms"]
        deadlines = Enum.reject([old_deadline, selected_deadline], &is_nil/1)
        accepted? = facts["kind"] == "managed_accepted_decision_retention"

        with true <- pending.command === command and facts === pending.facts and live?(pending),
             true <- Ipse.Session.ManagedLifecycle.retention_review?(command, facts, wall),
             true <- is_integer(remaining) and remaining > 0,
             true <- JSON.safe_uint?(wall + remaining),
             true <- Enum.sort(Map.keys(intent)) === ~w(facts operation_id type version),
             true <- intent["type"] === "managed_lifecycle_intent" and intent["version"] === 1,
             true <-
               intent["facts"] === facts and intent["operation_id"] === facts["operation_id"],
             true <- facts["request_sha256"] === JSON.digest([request]),
             true <- Ipse.Extension.Collection.valid_request?(request),
             true <- request["op"] === "commit" and request["advance_floor"] === true,
             [change] <- request["changes"],
             target when is_map(target) <- facts["target"],
             true <-
               change["key"] === target["key"] and
                 change["expected_revision"] === target["revision"] and
                 change["value"] === target["value"],
             true <- Ipse.Extension.Collection.valid_request?(normalized),
             true <- Map.delete(request, "changes") === Map.delete(normalized, "changes"),
             {original, extras} <-
               if(accepted?,
                 do: {[], normalized["changes"]},
                 else: Enum.split(normalized["changes"], length(request["changes"]))
               ),
             true <- original === if(accepted?, do: [], else: request["changes"]),
             true <- length(extras) in 1..5,
             true <- Enum.all?(extras, &String.starts_with?(&1["key"], "host.validity.")),
             true <-
               is_map(receipt) and Map.has_key?(receipt, "valid_until_ms") and
                 Map.has_key?(receipt, "publish_before_ms") and receipt["version"] === 3 and
                 receipt["kind"] ===
                   if(accepted?,
                     do: "native_accepted_decision_retention",
                     else: "native_literal_retention"
                   ) and
                 receipt["policy"] === facts["policy"],
             true <- receipt["action_sha256"] === facts["action_sha256"],
             true <-
               receipt["record_key"] === target["key"] and
                 receipt["lineage"] === facts["metadata"]["lineage"],
             true <- receipt["native_review_sha256"] === JSON.digest([pending.receipt]),
             {:ok, category, ^selected_deadline} <-
               Ipse.Extension.Collection.ManagedRetention.selected(
                 facts["policy"],
                 pending.receipt["observed_at_ms"]
               ),
             true <-
               receipt["category"] === category and
                 receipt["first_admitted_ms"] === facts["metadata"]["first_admitted_ms"],
             true <- is_nil(selected_deadline) or JSON.safe_uint?(selected_deadline),
             true <- receipt["publish_before_ms"] === Enum.min(deadlines, fn -> nil end),
             deadline = Enum.min([wall + remaining | deadlines]),
             true <- wall < deadline do
          Process.put(
            @slot,
            pending
            |> Map.put(:status, :effect_claimed)
            |> Map.put(:retention_intent_sha256, JSON.digest([intent]))
            |> Map.put(:retention_original_sha256, JSON.digest([request]))
            |> Map.put(:retention_request_sha256, JSON.digest([normalized]))
            |> Map.put(:retention_receipt_sha256, JSON.digest([receipt]))
            |> Map.put(:retention_deadline_ms, deadline)
          )

          {:ok, %{review: pending.receipt, publish_before_ms: deadline}}
        else
          _ -> @error
        end

      _ ->
        @error
    end
  rescue
    _ -> @error
  end

  def claim_retention_effect(_, _, _, _, _, _), do: @error

  @doc false
  def claimed_retention_effect(permit, facts, intent, request, normalized, receipt) do
    command = Ipse.Extension.Collection.ManagedRetention.command(facts["policy"])

    with {:ok, pending} <- pending(permit, command, facts, :effect_claimed),
         true <- pending[:retention_intent_sha256] === JSON.digest([intent]),
         true <- pending[:retention_original_sha256] === JSON.digest([request]),
         true <- pending[:retention_request_sha256] === JSON.digest([normalized]),
         true <- pending[:retention_receipt_sha256] === JSON.digest([receipt]),
         true <- JSON.safe_uint?(pending[:retention_deadline_ms]),
         true <- System.system_time(:millisecond) < pending.retention_deadline_ms do
      {:ok, %{review: pending.receipt, publish_before_ms: pending.retention_deadline_ms}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def claimed_retention_receipt(permit, command, facts) do
    with {:ok, pending} <- pending(permit, command, facts, :effect_claimed),
         true <- command in ~w(pin ordinary duration),
         true <- JSON.sha256?(pending[:retention_intent_sha256]),
         true <- JSON.safe_uint?(pending[:retention_deadline_ms]),
         true <- System.system_time(:millisecond) < pending.retention_deadline_ms do
      {:ok, pending.receipt}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Bind a consumed acceptance to its exact prepared combined request; grants no publication authority."
  def bind_acceptance_request(permit, facts, intent, request, deadline) do
    with {:ok, pending} <- pending(permit, "accept", facts, :consumed),
         false <- Map.has_key?(pending, :acceptance_request_sha256),
         true <- JSON.safe_uint?(facts["valid_until_ms"]),
         true <- is_nil(deadline) or JSON.safe_uint?(deadline),
         effective =
           if(is_nil(deadline),
             do: facts["valid_until_ms"],
             else: min(deadline, facts["valid_until_ms"])
           ),
         true <- System.system_time(:millisecond) < effective,
         true <- Ipse.Session.PendingAcceptance.normalized_acceptance?(intent, request) do
      Process.put(
        @slot,
        pending
        |> Map.put(:acceptance_request_sha256, JSON.digest([request]))
        |> Map.put(:bound_acceptance_intent_sha256, JSON.digest([intent]))
        |> Map.put(:acceptance_effect_deadline, effective)
      )

      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Spend a consumed acceptance once for its single effect attempt."
  def claim_acceptance_effect(%Permit{owner: owner, ref: ref}, facts, intent)
      when owner == self() do
    case Process.get(@slot) do
      %{ref: ^ref, status: :consumed} = pending ->
        Process.put(@slot, %{pending | status: :refused})

        event = %{
          "type" => "pending_proposal_accepted",
          "version" => 1,
          "facts" => facts,
          "review" => pending.receipt
        }

        with true <- pending.command === "accept" and facts === pending.facts and live?(pending),
             true <- JSON.sha256?(pending[:acceptance_request_sha256]),
             true <- pending[:bound_acceptance_intent_sha256] === JSON.digest([intent]),
             true <- JSON.safe_uint?(pending[:acceptance_effect_deadline]),
             true <-
               JSON.safe_uint?(facts["valid_until_ms"]) and
                 System.system_time(:millisecond) < pending.acceptance_effect_deadline,
             {:ok, ^intent} <-
               Ipse.Session.PendingAcceptance.effect_intent(event, intent["request"]) do
          Process.put(
            @slot,
            pending
            |> Map.put(:status, :effect_claimed)
            |> Map.put(:effect_intent_sha256, JSON.digest([intent]))
          )

          {:ok, pending.receipt}
        else
          _ -> @error
        end

      _ ->
        @error
    end
  rescue
    _ -> @error
  end

  def claim_acceptance_effect(_, _, _), do: @error

  @doc "Inspect the same live, already claimed acceptance effect without enabling a second claim."
  def claimed_acceptance_receipt(permit, facts, intent) do
    with {:ok, pending} <- pending(permit, "accept", facts, :effect_claimed),
         true <- JSON.safe_uint?(facts["valid_until_ms"]),
         true <- JSON.safe_uint?(pending[:acceptance_effect_deadline]),
         true <- System.system_time(:millisecond) < pending.acceptance_effect_deadline,
         true <- pending.effect_intent_sha256 === JSON.digest([intent]),
         do: {:ok, pending.receipt},
         else: (_ -> @error)
  rescue
    _ -> @error
  end

  @doc "Check the exact combined request against an already claimed acceptance."
  def claimed_acceptance_request(permit, facts, intent, request) do
    with {:ok, receipt} <- claimed_acceptance_receipt(permit, facts, intent),
         {:ok, pending} <- pending(permit, "accept", facts, :effect_claimed),
         true <- pending.acceptance_request_sha256 === JSON.digest([request]),
         do: {:ok, receipt},
         else: (_ -> @error)
  rescue
    _ -> @error
  end

  @doc "Inspect the actual pending receipt for bounded planning; it is not a permit or effect authority."
  def preview_receipt(permit, command, facts) do
    with {:ok, pending} <- pending(permit, command, facts, :available),
         do: {:ok, pending.receipt}
  end

  defp pending(%Permit{owner: owner, ref: ref}, command, facts, status) when owner == self() do
    case Process.get(@slot) do
      %{ref: ^ref, status: ^status} = pending ->
        if command === pending.command and facts === pending.facts and live?(pending),
          do: {:ok, pending},
          else: @error

      _ ->
        @error
    end
  end

  defp pending(_, _, _, _), do: @error

  @doc "Consume once against the exact revalidated facts, before attempting the bound effect."
  def consume(%Permit{owner: owner, ref: ref}, command, facts) when owner == self() do
    case Process.get(@slot) do
      %{ref: ^ref, status: :available} = pending ->
        # A real owner's first attempt spends the permit even when its facts
        # changed. It cannot silently rebase to another target or retry a write.
        Process.put(@slot, %{pending | status: :refused})

        if command === pending.command and facts === pending.facts and live?(pending) do
          Process.put(@slot, %{pending | status: :consumed})
          {:ok, pending.receipt}
        else
          @error
        end

      _ ->
        @error
    end
  end

  def consume(_, _, _), do: @error

  defp enter(command, facts, receipt, upstream, scope, deadline, fun) do
    ref = make_ref()

    pending = %{
      ref: ref,
      status: :available,
      command: command,
      facts: facts,
      receipt: receipt,
      upstream: upstream,
      scope: scope,
      deadline: deadline
    }

    Process.put(@slot, pending)

    try do
      result = fun.(%Permit{owner: self(), ref: ref})

      case Process.get(@slot) do
        %{ref: ^ref, status: status} = current when status in [:consumed, :effect_claimed] ->
          if (result === :ok or match?({:ok, _}, result)) and live?(current),
            do: result,
            else: @unknown

        %{ref: ^ref, status: :available} ->
          if match?({:error, _}, result), do: result, else: @error

        _ ->
          @error
      end
    rescue
      _ -> interrupted()
    catch
      _, _ -> interrupted()
    after
      Process.delete(@slot)
    end
  end

  defp interrupted do
    case Process.get(@slot) do
      %{status: status} when status in [:consumed, :effect_claimed] -> @unknown
      _ -> @error
    end
  end

  defp live?(pending) do
    remaining = pending.deadline - now()

    remaining > 0 and Process.alive?(pending.upstream) and
      Resources.current() === pending.scope and Resources.active?(min(remaining, 5_000)) and
      now() < pending.deadline and Process.alive?(pending.upstream) and
      Resources.current() === pending.scope
  end

  defp valid?(command, facts),
    do:
      is_binary(command) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, command) and
        is_map(facts) and map_size(facts) > 0 and JSON.validate_object(facts) == :ok and
        byte_size(Jason.encode!(facts)) <= @facts_bytes

  # Private rendering candidate only. A generated challenge is not an input
  # observation or a Review permit, and callers must not treat it as one.
  @doc false
  def preview_display(command, facts) do
    with true <- valid?(command, facts),
         challenge = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
         display = display(command, facts, challenge),
         true <- byte_size(display) <= @display_bytes do
      {:ok, display, challenge}
    else
      _ -> {:error, :review_unavailable}
    end
  rescue
    _ -> {:error, :review_unavailable}
  end

  @doc false
  def preview_management_display(command, facts, checked_at)
      when is_integer(checked_at) and checked_at >= 0 do
    with {:ok, body, challenge} <- preview_display(command, facts),
         deadline <- get_in(facts, ["metadata", "valid_until_ms"]),
         true <- is_nil(deadline) or (is_integer(deadline) and deadline >= 0),
         status =
           (cond do
              is_nil(deadline) -> "no signed deadline"
              deadline <= checked_at -> "signed deadline elapsed"
              true -> "signed deadline not yet elapsed"
            end),
         label =
           "Retained management target at #{checked_at}: #{status}. Original source availability and current-use eligibility are not checked.\n",
         display = label <> body,
         true <- byte_size(display) <= @display_bytes do
      {:ok, display, challenge}
    else
      _ -> {:error, :review_unavailable}
    end
  end

  def preview_management_display(_, _, _), do: {:error, :review_unavailable}

  defp display(command, facts, challenge) do
    Ipse.CLI.Terminal.escape(
      "Review the complete proposed facts below. This confirmation applies only to this exact review.\n" <>
        Jason.encode!(facts, pretty: true) <>
        "\nType #{command} #{challenge} to confirm, or anything else to cancel.\n> "
    )
  end

  defp now, do: System.monotonic_time(:millisecond)
end
