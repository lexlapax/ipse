defmodule Ipse.Session.ManagedCapture do
  @moduledoc false
  alias Ipse.JSON
  alias Ipse.Extension.{Collection, ManagedCollectionCall, Registry}
  alias Ipse.Session.{ManagedToolUse, ManagedUse, Resources}
  alias Ipse.Runner.{SessionSource, Transaction}
  @error {:error, :managed_capture_unavailable}

  # Structural admission only. Current records, policy and original sources
  # are revalidated after intent and retained through the native decision.
  def supported?(s, request, binding) do
    with true <- ManagedCollectionCall.new_capture?(request),
         {:ok, dependencies} <- ManagedToolUse.invocation_dependencies(s),
         true <- dependencies != [] do
      binding["namespace"] == get_in(s.config, [:semantic_admission, "pin", "namespace"]) and
        ManagedToolUse.source_dependencies_supported?(dependencies)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def prepare(s, caller, intent) do
    with true <- actor?(s, caller, intent),
         {:ok, dependencies} <- ManagedToolUse.invocation_dependencies(s) do
      if dependencies != [] and not ManagedToolUse.root_only?(s, dependencies) do
        with true <- supported?(s, intent["request"], intent["effect_binding"]) do
          {:ok, %{dependencies: dependencies, sha256: digest(s, intent, dependencies)}}
        else
          _ -> @error
        end
      else
        {:ok, nil}
      end
    else
      _ -> @error
    end
  end

  def binding_current?(s, sha) do
    with %{action: %{intent: intent}, interrupted: false} <- s.invocation,
         {:ok, dependencies} <- ManagedToolUse.invocation_dependencies(s),
         true <- supported?(s, intent["request"], intent["effect_binding"]),
         true <- digest(s, intent, dependencies) === sha,
         do: true,
         else: (_ -> false)
  rescue
    _ -> false
  end

  def actor?(s, caller, intent) do
    s.task != nil and s.job_ref != nil and
      (caller == s.task.pid or Resources.authorized_effect?(s.task.pid, caller)) and
      s.invocation.action != nil and s.invocation.action.intent === intent and
      not s.invocation.interrupted and Registry.live?(s.invocation.parent["identity"])
  rescue
    _ -> false
  end

  defp digest(s, intent, dependencies),
    do: JSON.digest([s.invocation.parent, intent, dependencies])

  def with_publication(c, i, fun) do
    with {:ok, spec} <- GenServer.call(c.owner, {:managed_capture_prepare, c.job_ref, i}, 5_000) do
      case spec do
        nil ->
          fun.(c)

        %{dependencies: dependencies, sha256: sha} ->
          with {:ok, _, proofs} <- ManagedCollectionCall.supersession_sources(c, i) do
            context = Map.put(c, :source_binding, {:capture, sha})

            ManagedUse.with_publication_dependencies(
              context,
              dependencies,
              Enum.map(proofs, & &1["proof"]),
              fn held ->
                fun.(
                  Map.put(c, :managed_capture, %{
                    context: context,
                    intent: i,
                    sha256: sha,
                    held: held
                  })
                )
              end
            )
          else
            _ -> @error
          end
      end
    else
      _ -> @error
    end
  end

  def ticket(s, caller, ref, intent, sha, proofs, wall, sources) do
    with true <- s.share_barrier == nil and s.share_ticket == nil and s.job_ref == ref,
         true <- s.lock_mode in [:header_share_v2, :resume_share_v2],
         true <- actor?(s, caller, intent) and binding_current?(s, sha),
         true <- is_list(proofs) and length(proofs) in 1..128,
         true <- Enum.all?(proofs, &is_map/1) and Enum.uniq(proofs) === proofs,
         true <- JSON.safe_uint?(wall) and wall > System.system_time(:millisecond) do
      remaining = min(wall - System.system_time(:millisecond), 5_000)
      deadline = System.monotonic_time(:millisecond) + remaining

      ticket = %{
        ticket: make_ref(),
        operation: :crypto.strong_rand_bytes(16),
        deadline: deadline,
        caller: caller,
        job_ref: ref,
        intent: intent,
        parent: s.invocation.parent,
        phase: s.phase,
        channel: nil,
        managed_capture: sha,
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

  def with_native_publication(
        cap,
        witness,
        %{context: c, intent: i, sha256: sha, held: held},
        fun
      ) do
    with true <- held.owner == self(),
         {:ok, pointer} <- JSON.decode_bounded(witness["root_bytes"], 1024),
         {:ok, root} <-
           Ipse.Extension.Collection.ObservedRead.root_identity(
             witness
             |> Map.take(~w(version root_state root_sha256 manifest_sha256))
             |> Map.put("root", pointer),
             i["namespace"]
           ),
         true <- Enum.all?(held.current, &(&1["collection"] === root)),
         true <- root["generation"] === i["request"]["request"]["expected_generation"],
         true <- System.system_time(:millisecond) < held.deadline_ms do
      SessionSource.with_capture(
        cap,
        c,
        i,
        sha,
        held.source_leases,
        held.source_proofs,
        held.deadline_ms,
        fn ->
          with_journals(cap, held.journal_leases, fn ->
            Collection.with_notes_publication_deadline(held.deadline_ms, fun)
          end)
        end
      )
    else
      _ -> @error
    end
  end

  defp with_journals(_, [], fun), do: fun.()

  defp with_journals(cap, [lease | rest], fun) do
    Transaction.with_inactive_acceptance_journal_lease(cap, lease.token, fn ->
      with_journals(cap, rest, fun)
    end)
  end
end
