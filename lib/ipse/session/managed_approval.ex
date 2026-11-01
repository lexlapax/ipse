defmodule Ipse.Session.ManagedApproval do
  @moduledoc false
  alias Ipse.{JSON, Session}
  alias Ipse.Session.{Input, ManagedLineage, ManagedReference, ManagedUse, Resources}
  alias Ipse.Runner.LeasedTerminal
  @error {:error, :managed_argument_display_unavailable}

  def start(s, call, arguments) do
    with %{client: client, reader: reader} <- s.operator_channel,
         true <- Process.alive?(client) and Process.alive?(reader),
         true <- s.lock_mode in [:header_share_v2, :resume_share_v2],
         true <- get_in(call, ["function", "name"]) not in ~w(delegate delegate_parallel),
         {:ok, dependencies} <- ManagedLineage.tool_dependencies(s.managed_lineage, call["id"]),
         {:ok, dependencies} <- ManagedReference.union([dependencies]),
         true <- dependencies != [],
         token = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
         external = Ipse.MCP.tool(s.mcp_tools, get_in(call, ["function", "name"])),
         target = if(external, do: Ipse.MCP.manifest(external)),
         {:ok, display} <-
           Ipse.CLI.Terminal.approval_display(
             get_in(call, ["function", "name"]),
             arguments,
             target,
             token,
             s.cwd,
             true
           ),
         true <- byte_size(display) <= 65_536,
         {:ok, release} <- Input.release_for_output() do
      id = Ipse.Usage.id()

      input = %{
        "kind" => "model.tool.approval",
        "session_id" => s.id,
        "request_id" => s.last_request_id,
        "approval_id" => id,
        "call" => call,
        "arguments" => arguments,
        "target" => target,
        "dependencies_sha256" => JSON.digest(dependencies),
        "allow_sha256" => JSON.sha256("allow " <> token),
        "display_sha256" => JSON.sha256(display)
      }

      spec = %{
        id: id,
        call: call,
        arguments: arguments,
        dependencies: dependencies,
        input: input,
        sha256: JSON.digest([input, dependencies]),
        token: token,
        display: display
      }

      owner = self()
      job = make_ref()

      context = %{
        config: s.config,
        cwd: s.cwd,
        session_id: s.id,
        history_dir: s.dir,
        owner: owner,
        job_ref: job,
        source_binding: {:snapshot, "tool.approval", spec.sha256}
      }

      task = Session.owned_task(fn -> run(owner, job, context, spec, release) end)

      s =
        Session.begin_wait(s, "tool", %{"turn_id" => s.turn_id, "request_id" => s.last_request_id})

      Session.notify(s, :managed_approval_wait)
      {:ok, %{s | task: task, job_ref: job, phase: :managed_approval, managed_approval: spec}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def snapshot(s) do
    with %{dependencies: dependencies, input: input, sha256: sha} <- s.managed_approval,
         true <- current?(s, input) do
      {:ok, %{dependencies: dependencies, input: input, sha256: sha}}
    else
      _ -> @error
    end
  end

  def current?(s, input) do
    with %{input: ^input, call: call, arguments: arguments, dependencies: dependencies} <-
           s.managed_approval,
         true <- s.phase == :managed_approval and hd(s.calls) == call,
         true <- s.last_request_id == input["request_id"] and s.id == input["session_id"],
         {:ok, ^arguments} <- JSON.decode_bounded(get_in(call, ["function", "arguments"]), 65_536),
         {:ok, actual} <- ManagedLineage.tool_dependencies(s.managed_lineage, call["id"]),
         {:ok, ^dependencies} <- ManagedReference.union([actual]),
         true <- JSON.digest(dependencies) == input["dependencies_sha256"] do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def ticket(s, caller, job, input, proofs, wall, sources) do
    with true <- s.share_barrier == nil and s.job_ref == job and s.task != nil,
         true <- caller == s.task.pid or Resources.authorized_effect?(s.task.pid, caller),
         true <- current?(s, input),
         true <-
           is_list(proofs) and length(proofs) in 0..128 and
             length(Enum.uniq(proofs)) == length(proofs),
         true <- JSON.safe_uint?(wall) and wall > System.system_time(:millisecond),
         %{client: client, reader: reader} = channel <- s.operator_channel,
         true <- Process.alive?(client) and Process.alive?(reader),
         {:ok, _} <- Session.managed_dependencies(s, "tool.approval"),
         {:ok, journals} <- approval_journals(s),
         true <-
           length(journals.ids) +
             (proofs
              |> Enum.reject(&(&1["session_id"] == s.id))
              |> Enum.uniq_by(& &1["session_id"])
              |> length()) <= 128 do
      now = System.monotonic_time(:millisecond)
      wall = min(wall, System.system_time(:millisecond) + 5_000)
      deadline = now + min(wall - System.system_time(:millisecond), 5_000)
      overall = now + 120_000

      ticket = %{
        ticket: make_ref(),
        operation: :crypto.strong_rand_bytes(16),
        deadline: deadline,
        caller: caller,
        job_ref: job,
        intent: input,
        parent: nil,
        phase: s.phase,
        channel: channel,
        protocol: :managed_approval,
        terminal_purpose: :approval,
        source_proofs: Enum.filter(proofs, &(&1["session_id"] == s.id)),
        expected_sources: sources,
        relation_display_inactive_sources: Enum.reject(proofs, &(&1["session_id"] == s.id)),
        approval_journals: journals,
        wall_deadline: wall,
        overall_deadline: overall,
        overall_wall: System.system_time(:millisecond) + 120_000
      }

      {:reply, {:ok, ticket.ticket, ticket.operation, deadline, overall},
       %{s | share_ticket: ticket}}
    else
      _ -> {:reply, @error, s}
    end
  end

  defp approval_journals(s) do
    acceptances =
      for dependency <- s.managed_approval.dependencies,
          dependency["version"] === 6,
          do: dependency["subject"]["acceptance"]

    if Enum.all?(acceptances, &(&1["journal_kind"] === "knowledge_management")) do
      {:ok,
       %{
         directory: Path.join(s.config.home, "knowledge-management"),
         ids: acceptances |> Enum.map(& &1["journal_id"]) |> Enum.uniq() |> Enum.sort()
       }}
    else
      @error
    end
  end

  def complete(s, {:managed_approval, id, sha, choice})
      when choice in [true, false, :cancel, :exit] do
    with %{id: ^id, input: input, sha256: ^sha, call: call, arguments: args} <- s.managed_approval,
         true <- s.share_barrier == nil and current?(s, input) do
      Session.notify(s, :managed_approval_ready)

      s =
        Session.finish_wait(
          %{s | managed_approval: nil},
          case choice do
            true -> "approved"
            false -> "denied"
            _ -> "cancelled"
          end
        )

      if choice in [:cancel, :exit] do
        Session.notify(s, {:managed_approval_cancel, choice == :exit})

        case Session.cancel_work(s, false) do
          {:reply, :ok, next} -> {:noreply, next}
          {:stop, reason, _, next} -> {:stop, reason, next}
        end
      else
        {:noreply, Session.Turn.complete_managed_approval(s, call, args, choice)}
      end
    else
      _ -> failed(s)
    end
  end

  def complete(s, _), do: failed(s)

  defp failed(s) do
    Session.notify(s, :managed_approval_ready)

    {:noreply,
     Session.Turn.fail(
       %{s | managed_approval: nil},
       "Managed approval display or input could not be confirmed; no proposed tool was started."
     )}
  end

  defp run(owner, job, context, spec, release) do
    with :ok <- Input.await_output_release(release) do
      Resources.file_effect(fn ->
        with {:ok, handle} <-
               ManagedUse.with_approval_dependencies(context, spec.dependencies, fn _, held ->
                 LeasedTerminal.begin_approval(owner, job, spec.input, held, context.cwd)
               end),
             {:ok, allowed} <- LeasedTerminal.finish_approval(handle, spec.token) do
          {:managed_approval, spec.id, spec.sha256, allowed}
        else
          _ -> @error
        end
      end)
    else
      _ -> @error
    end
  end
end
