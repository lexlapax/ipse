defmodule Ipse.Extension.Consent do
  @moduledoc """
  Protected host control ledger for versioned saved consent and finite reservations.

  This internal API establishes no operator-channel proof and is not exposed to
  workers. The reviewing host must verify origin, artifact trust and semantic
  policy before saving a grant. Each effect owner must check both its ordinary
  mode ceiling and the exact grant before reserving. A reservation is never an
  instruction to dispatch or replay work.
  """
  alias Ipse.JSON
  alias Ipse.Runner.Transaction
  import Bitwise, only: [band: 2]
  @bytes 8_388_608
  @write_bytes 6 * 1024 * 1024 - 65_536
  @legacy_entries 16_384
  @entries 32_768
  @recent 64
  @pending 128
  @allocated_bytes 18 * 1024 * 1024
  @lock_key {__MODULE__, :lock_held}
  # Version-2 compact vectors persist this exact resource order.
  @resources ~w(operations model_calls input_bytes output_bytes download_bytes cost_nanos)
  @max_actual_bytes byte_size(Jason.encode!(Map.new(@resources, &{&1, 9_007_199_254_740_991})))
  @max_status_bytes byte_size(Jason.encode!("reconciled_overrun"))
  @policy_bytes 32_768
  @error {:error, :consent_unavailable}

  def resources, do: @resources
  def zero, do: Map.new(@resources, &{&1, 0})

  def valid_policy?(p) do
    keys?(
      p,
      ~w(version project artifact_sha256 source_sha256 operations settings limits period_ms expires_at_ms headless)
    ) and
      p["version"] === 1 and JSON.sha256?(p["project"]) and
      JSON.sha256?(p["artifact_sha256"]) and JSON.sha256?(p["source_sha256"]) and
      is_list(p["operations"]) and length(p["operations"]) in 1..16 and
      p["operations"] == Enum.sort(Enum.uniq(p["operations"])) and
      Enum.all?(p["operations"], &name?/1) and is_map(p["settings"]) and
      json_map?(p["settings"], 16_384) and
      vector?(p["limits"]) and p["limits"]["operations"] > 0 and
      is_integer(p["period_ms"]) and p["period_ms"] in 1_000..31_536_000_000 and
      uint?(p["expires_at_ms"]) and is_boolean(p["headless"])
  rescue
    _ -> false
  end

  def snapshot(root, project), do: transaction(root, project, &{:read, &1})

  @doc "Read only an existing protected ledger, without creation, repair or pending-file reclamation. Absence grants no authority."
  def existing_snapshot(root, project), do: existing_transaction(root, project, &{:ok, &1})

  @doc "Check an existing exact policy for an advisory read-only host callback, without mutation recovery."
  def with_existing_policy(root, project, epoch, policy_sha256, now, fun)
      when is_function(fun, 1) do
    if uint?(epoch) and JSON.sha256?(policy_sha256) and uint?(now) do
      existing_transaction(root, project, fn state ->
        if is_map(state) and policy_matches?(state, epoch, policy_sha256, now),
          do: existing_callback(fun, Map.take(state, ~w(epoch policy))),
          else: {:error, :consent_read_refused}
      end)
    else
      {:error, :consent_read_refused}
    end
  end

  def with_existing_policy(_, _, _, _, _, _), do: {:error, :consent_read_refused}

  defp policy_matches?(state, epoch, sha, now) do
    policy = state["policy"]

    state["epoch"] === epoch and is_map(policy) and JSON.digest([policy]) == sha and
      policy["expires_at_ms"] > now and not quarantined?(state)
  end

  defp existing_callback(fun, value) do
    case fun.(value) do
      {:ok, _} = result -> result
      {:error, _} = result -> result
      _ -> {:error, :consent_read_refused}
    end
  end

  @doc "Check a pinned policy under control, then perform one short host storage read without a period ID."
  def with_policy(root, project, epoch, policy_sha256, now, fun) when is_function(fun, 1) do
    if uint?(epoch) and JSON.sha256?(policy_sha256) and uint?(now) do
      transaction(root, project, fn state ->
        policy = state["policy"]

        if state["epoch"] === epoch and is_map(policy) and
             JSON.digest([policy]) == policy_sha256 and policy["expires_at_ms"] > now and
             not quarantined?(state) do
          case fun.(Map.take(state, ~w(epoch policy))) do
            {:ok, value} -> {:read, value}
            {:error, _} = error -> error
            _ -> {:error, :consent_read_refused}
          end
        else
          {:error, :consent_read_refused}
        end
      end)
    else
      {:error, :consent_read_refused}
    end
  end

  def with_policy(_, _, _, _, _, _), do: {:error, :consent_read_refused}

  @doc "Save already reviewed policy with CAS. Existing reservations and liabilities survive changes."
  def replace(root, project, expected_epoch, policy, now) do
    transaction(root, project, fn s ->
      cond do
        not uint?(expected_epoch) or s["epoch"] != expected_epoch ->
          {:error, :consent_conflict}

        not valid_policy?(policy) or policy["project"] != project or
          not uint?(now) or policy["expires_at_ms"] <= now ->
          {:error, :invalid_consent}

        true ->
          update_policy(s, policy)
      end
    end)
  end

  def revoke(root, project, expected_epoch) do
    transaction(root, project, fn s ->
      if uint?(expected_epoch) and s["epoch"] == expected_epoch,
        do: update_policy(s, nil),
        else: {:error, :consent_conflict}
    end)
  end

  defp update_policy(s, p) do
    if s["epoch"] < 9_007_199_254_740_991 do
      next = %{s | "epoch" => s["epoch"] + 1, "policy" => p}
      {:write, next, %{"epoch" => next["epoch"], "in_flight" => pending(s)}}
    else
      {:error, :consent_capacity}
    end
  end

  @doc "Reserve before egress; duplicate IDs return inspection data and never new admission."
  def reserve(root, project, request, now) do
    transaction(root, project, fn s ->
      with true <- request?(request) and uint?(now),
           nil <- existing(s, request["id"]),
           :ok <- eligible(s, request, now),
           :ok <- capacity(s),
           true <- s["sequence"] < 9_007_199_254_740_991,
           true <- fits?(s, request["reserved"], now) do
        r =
          Map.merge(request, %{
            "sequence" => s["sequence"] + 1,
            "epoch" => s["epoch"],
            "created_at_ms" => now,
            "status" => "reserved",
            "actual" => nil,
            "receipt" => nil
          })

        next = %{
          s
          | "sequence" => r["sequence"],
            "operations" => Map.put(s["operations"], r["id"], r)
        }

        {:write, next, ticket(project, r)}
      else
        existing when is_map(existing) -> {:read, %{"existing" => existing}}
        {:error, _} = error -> error
        _ -> {:error, :consent_reservation_refused}
      end
    end)
  end

  @doc "Durably mark possible dispatch before egress. A repeated admission is refused."
  def admit(root, project, ticket, now) do
    transaction(root, project, fn s ->
      with {:ok, r} <- current(s, ticket, now),
           true <- r["status"] == "reserved" do
        next = put_in(s["operations"][r["id"]]["status"], "admitted")
        {:write, next, ticket}
      else
        _ -> {:error, :consent_admission_refused}
      end
    end)
  end

  @doc "Recheck under the control lock, then run only a short host storage publication."
  def publish(root, project, ticket, now, fun) when is_function(fun, 0) do
    publication(root, project, ticket, now, fun, :settle)
  end

  @doc """
  Run a short publication while retaining its full pending reservation.

  A successful result is provisional trusted-host data. It leaves the durable
  operation publishing, with no actual usage or receipt. Only after all outer
  authority checks and lock releases succeed may the host settle with
  `{:known, packet["actual"], packet["receipt"]}`. Never replay the callback.
  A final settlement failure may have persisted its result; inspect it without
  replay rather than assuming the full reservation remains after settlement begins.
  """
  def publish_deferred(root, project, ticket, now, fun) when is_function(fun, 0) do
    publication(root, project, ticket, now, fun, :defer)
  end

  defp publication(root, project, ticket, now, fun, mode) do
    transaction(root, project, fn s ->
      with {:ok, r} <- current(s, ticket, now) do
        admitted = put_in(s["operations"][r["id"]]["status"], "publishing")

        with :ok <- write(Path.join(root, project), admitted) do
          try do
            case fun.() do
              {:ok, actual, receipt} ->
                result = finish(admitted, admitted["operations"][r["id"]], actual, receipt)
                publication_result(result, mode, ticket, actual, receipt)

              _ ->
                {:unknown, :publication_unconfirmed}
            end
          catch
            _, _ -> {:unknown, :publication_unconfirmed}
          end
        else
          {:error, _} = error -> error
          _ -> {:unknown, :consent_write_unconfirmed}
        end
      else
        _ -> {:error, :consent_publication_refused}
      end
    end)
  end

  defp publication_result({:write, _next, _value}, :defer, ticket, actual, receipt) do
    {:read, %{"version" => 1, "ticket" => ticket, "actual" => actual, "receipt" => receipt}}
  end

  defp publication_result(result, _mode, _ticket, _actual, _receipt), do: after_effect(result)

  @doc "Settle known work, retain unknown liability, or reconcile explicitly; never replay."
  def settle(root, project, ticket, outcome) do
    transaction(root, project, fn s ->
      with {:ok, r} <- lookup(s, ticket) do
        result =
          case {r["status"], outcome} do
            {"reserved", :unstarted} ->
              finish(s, r, zero(), %{"unstarted" => true})

            {status, {:known, actual}} when status in ~w(admitted publishing) ->
              finish(s, r, actual, %{})

            {status, {:known, actual, receipt}} when status in ~w(admitted publishing) ->
              finish(s, r, actual, receipt)

            {status, :unknown} when status in ~w(admitted publishing unknown) ->
              next = put_in(s["operations"][r["id"]]["status"], "unknown")
              {:write, next, %{"status" => "unknown"}}

            {"unknown", {:reconciled, actual}} ->
              finish(s, r, actual, %{"reconciled" => true})

            {"overrun", {:reconciled, actual}} ->
              if vector?(actual) and within?(r["actual"], actual) do
                r = %{
                  r
                  | "status" => "reconciled_overrun",
                    "actual" => actual,
                    "receipt" => %{"reconciled" => true}
                }

                {:write, put_in(s["operations"][r["id"]], r), %{"status" => "reconciled_overrun"}}
              else
                {:error, :consent_settlement_refused}
              end

            _ ->
              {:error, :consent_settlement_refused}
          end

        if r["status"] == "reserved", do: result, else: after_effect(result)
      else
        _ -> {:error, :consent_settlement_refused}
      end
    end)
  end

  defp after_effect({:write, next, value}), do: {:write_effect, next, value}
  defp after_effect(other), do: other

  defp finish(s, r, actual, receipt) do
    cond do
      not vector?(actual) ->
        {:unknown, :consent_settlement_exceeds_reservation}

      not within?(actual, r["reserved"]) ->
        r = %{r | "status" => "overrun", "actual" => actual, "receipt" => nil}

        {:write_unknown, put_in(s["operations"][r["id"]], r),
         :consent_settlement_exceeds_reservation}

      not json_map?(receipt, 8_192) ->
        {:unknown, :consent_receipt_invalid}

      true ->
        r = %{r | "status" => "settled", "actual" => actual, "receipt" => receipt}
        next = put_in(s["operations"][r["id"]], r)
        {:write, next, %{"status" => "settled", "receipt" => receipt}}
    end
  end

  defp eligible(s, r, now) do
    p = s["policy"]

    if p != nil and p["expires_at_ms"] > now and r["policy_sha256"] == JSON.digest([p]) and
         r["artifact_sha256"] == p["artifact_sha256"] and
         r["source_sha256"] == p["source_sha256"] and r["operation"] in p["operations"] and
         (not r["headless"] or p["headless"]) do
      :ok
    else
      {:error, :consent_denied}
    end
  end

  defp current(s, t, now) do
    with true <- uint?(now),
         {:ok, r} <- lookup(s, t),
         false <- quarantined?(s),
         true <- r["epoch"] == s["epoch"] and r["status"] in ~w(reserved admitted),
         :ok <- eligible(s, r, now),
         do: {:ok, r},
         else: (_ -> {:error, :consent_denied})
  end

  defp lookup(s, t) do
    with true <- is_map(t) and keys?(t, ~w(project id sequence epoch request_sha256)),
         true <- t["project"] == s["project"],
         r when is_map(r) <- s["operations"][t["id"]],
         true <- ticket(s["project"], r) === t,
         do: {:ok, r},
         else: (_ -> {:error, :consent_ticket_refused})
  end

  defp ticket(project, r),
    do: Map.put(Map.take(r, ~w(id sequence epoch request_sha256)), "project", project)

  defp fits?(s, reserved, now) do
    start = div(now, s["policy"]["period_ms"]) * s["policy"]["period_ms"]

    used =
      Enum.reduce(s["operations"], zero(), fn {_, r}, used ->
        cond do
          not terminal?(r) -> add(used, r["reserved"])
          r["created_at_ms"] >= start -> add(used, r["actual"])
          true -> used
        end
      end)

    counts = List.to_tuple(Enum.map(@resources, &used[&1]))

    counts =
      Enum.reduce(s["compacted"], counts, fn
        {_, [_, _, _, created, _, [a, b, c, d, e, f], _]}, {u, v, w, x, y, z}
        when created >= start ->
          {u + a, v + b, w + c, x + d, y + e, z + f}

        _, counts ->
          counts
      end)

    used = Map.new(Enum.zip(@resources, Tuple.to_list(counts)))

    not quarantined?(s) and
      within?(add(used, reserved), s["policy"]["limits"])
  end

  defp add(a, b), do: Map.new(@resources, &{&1, a[&1] + b[&1]})
  defp within?(a, b), do: Enum.all?(@resources, &(a[&1] <= b[&1]))
  defp terminal?(r), do: r["status"] in ~w(settled reconciled_overrun)
  defp quarantined?(s), do: Enum.any?(s["operations"], fn {_, r} -> r["status"] == "overrun" end)
  defp pending(s), do: Enum.count(s["operations"], fn {_, r} -> not terminal?(r) end)

  defp operation_count(s), do: map_size(s["operations"]) + map_size(s["compacted"])

  defp capacity(s) do
    if operation_count(s) < @entries and pending(s) < @pending,
      do: :ok,
      else: {:error, :consent_capacity}
  end

  defp existing(s, id) do
    case s["operations"][id] do
      nil ->
        case s["compacted"][id] do
          [sequence, epoch, request, created, status, actual, receipt] ->
            %{
              "id" => id,
              "sequence" => sequence,
              "epoch" => epoch,
              "request_sha256" => request,
              "created_at_ms" => created,
              "status" => status,
              "actual" => Map.new(Enum.zip(@resources, actual)),
              "receipt_compacted" => true,
              "receipt_sha256" => receipt
            }

          _ ->
            nil
        end

      r ->
        r
    end
  end

  # Terminal receipt bytes are bounded independently of the durable deduplication
  # and accounting rows. Unknown liabilities and unresolved overruns stay intact.
  defp compact(s) do
    terminal =
      s["operations"]
      |> Map.values()
      |> Enum.filter(&terminal?/1)
      |> Enum.sort_by(& &1["sequence"], :desc)
      |> Enum.drop(@recent)

    Enum.reduce(terminal, %{s | "version" => 2}, fn r, next ->
      row = [
        r["sequence"],
        r["epoch"],
        r["request_sha256"],
        r["created_at_ms"],
        r["status"],
        Enum.map(@resources, &r["actual"][&1]),
        JSON.digest([r["receipt"]])
      ]

      next
      |> update_in(["operations"], &Map.delete(&1, r["id"]))
      |> put_in(["compacted", r["id"]], row)
    end)
  end

  defp request?(r) do
    keys?(
      r,
      ~w(id operation artifact_sha256 source_sha256 policy_sha256 request_sha256 source_generation reserved headless)
    ) and
      id?(r["id"]) and name?(r["operation"]) and
      Enum.all?(
        ~w(artifact_sha256 source_sha256 policy_sha256 request_sha256),
        &JSON.sha256?(r[&1])
      ) and
      uint?(r["source_generation"]) and vector?(r["reserved"]) and
      r["reserved"]["operations"] == 1 and is_boolean(r["headless"])
  end

  defp transaction(root, project, fun) do
    if Process.get(@lock_key) != nil or
         Process.get({Ipse.Extension.Collection, :lock_held}) != nil,
       do: @error,
       else: Ipse.Session.Resources.file_effect(fn -> locked(root, project, fun) end)
  end

  defp existing_transaction(root, project, fun) do
    if Process.get(@lock_key) != nil or
         Process.get({Ipse.Extension.Collection, :lock_held}) != nil,
       do: @error,
       else: Ipse.Session.Resources.file_effect(fn -> existing_locked(root, project, fun) end)
  end

  defp existing_locked(root, project, fun) do
    with true <- is_binary(root) and Path.type(root) == :absolute and JSON.sha256?(project),
         {:ok, uid} <- Ipse.Runner.protected_current_uid(),
         :ok <- existing_directory(root, uid),
         :ok <- directory(Path.dirname(root), uid, false),
         path = Path.join(root, project),
         :ok <- existing_directory(path, uid),
         {:ok, control} <- existing_file(Path.join(path, "control.json"), uid, true),
         {:ok, %{size: 0} = retained} <- existing_file(Path.join(path, ".lock"), uid, false),
         {:ok, %{size: 0} = writer} <- existing_file(Path.join(path, ".writer.lock"), uid, false),
         {:ok, lock} <- Transaction.acquire(Path.join(path, ".lock")) do
      Process.put(@lock_key, lock)

      result =
        try do
          with :ok <- Transaction.check(lock),
               :ok <- retained_file(Path.join(path, ".lock"), retained),
               :ok <- retained_file(Path.join(path, ".writer.lock"), writer),
               :ok <- Transaction.quota(lock, :flat, @allocated_bytes),
               :ok <- retained_file(Path.join(path, ".writer.lock"), writer),
               {:ok, _} <- pending_names(path, uid),
               {:ok, state} <- read_present(path, project, uid, control),
               :ok <- retained_file(Path.join(path, "control.json"), control),
               {:ok, _} = result <- existing_callback(fun, state),
               :ok <- retained_file(Path.join(path, ".lock"), retained),
               :ok <- retained_file(Path.join(path, ".writer.lock"), writer),
               :ok <- retained_file(Path.join(path, "control.json"), control),
               :ok <- Transaction.check(lock) do
            result
          end
        rescue
          _ -> {:unknown, :consent_transaction_unconfirmed}
        catch
          _, _ -> {:unknown, :consent_transaction_unconfirmed}
        after
          Process.delete(@lock_key)
        end

      case Transaction.release(lock) do
        :ok -> result
        _ -> {:unknown, :consent_lock_unconfirmed}
      end
    else
      :absent -> existing_callback(fun, nil)
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp existing_directory(path, uid) do
    case File.lstat(path) do
      {:error, :enoent} -> :absent
      {:ok, _} -> directory(path, uid, false)
      _ -> @error
    end
  end

  defp existing_file(path, uid, absent?) do
    case File.lstat(path) do
      {:error, :enoent} when absent? ->
        :absent

      {:ok, stat} ->
        if safe_file?(stat, uid) and stat.size <= @bytes, do: {:ok, stat}, else: @error

      _ ->
        @error
    end
  end

  defp retained_file(path, expected) do
    fields = ~w(type major_device minor_device inode uid gid mode links size mtime ctime)a

    with {:ok, actual} <- File.lstat(path),
         true <- Map.take(actual, fields) === Map.take(expected, fields),
         do: :ok,
         else: (_ -> @error)
  end

  defp locked(root, project, fun) do
    with true <- is_binary(root) and Path.type(root) == :absolute and JSON.sha256?(project),
         {:ok, uid} <- Ipse.Runner.protected_current_uid(),
         :ok <- directory(Path.dirname(root), uid, false),
         :ok <- directory(root, uid, true),
         path = Path.join(root, project),
         :ok <- directory(path, uid, true),
         :ok <- safe_lock(Path.join(path, ".lock"), uid),
         {:ok, lock} <- Transaction.acquire(Path.join(path, ".lock")) do
      Process.put(@lock_key, lock)

      result =
        try do
          with :ok <- Transaction.check(lock),
               :ok <- reclaim_pending(path, uid, lock),
               {:ok, s} <- read(path, project, uid) do
            case fun.(s) do
              {:read, value} ->
                with :ok <- Transaction.check(lock), do: {:ok, value}

              {:write, next, value} ->
                with true <- valid_state?(next, project), :ok <- write(path, next) do
                  {:ok, value}
                else
                  {:error, reason}
                  when reason in [:consent_capacity, :consent_filesystem_unsupported] ->
                    {:error, reason}

                  _ ->
                    {:unknown, :consent_write_unconfirmed}
                end

              {:write_effect, next, value} ->
                with true <- valid_state?(next, project), :ok <- write(path, next) do
                  {:ok, value}
                else
                  _ -> {:unknown, :consent_write_unconfirmed}
                end

              {:write_unknown, next, reason} ->
                with true <- valid_state?(next, project), :ok <- write(path, next) do
                  {:unknown, reason}
                else
                  _ -> {:unknown, :consent_write_unconfirmed}
                end

              other ->
                other
            end
          end
        rescue
          _ -> {:unknown, :consent_transaction_unconfirmed}
        catch
          _, _ -> {:unknown, :consent_transaction_unconfirmed}
        after
          Process.delete(@lock_key)
        end

      case Transaction.release(lock) do
        :ok -> result
        _ -> {:unknown, :consent_lock_unconfirmed}
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp directory(path, uid, create) do
    case File.lstat(path) do
      {:error, :enoent} when create ->
        case File.mkdir(path) do
          :ok ->
            with :ok <- File.chmod(path, 0o700),
                 :ok <- Ipse.Runner.protected_sync_directory(Path.dirname(path)),
                 do: directory(path, uid, false)

          {:error, :eexist} ->
            directory(path, uid, false)

          _ ->
            @error
        end

      {:ok, %{type: :directory, uid: ^uid, mode: mode}} when band(mode, 0o077) == 0 ->
        case Ipse.Workspace.canonical_path(path) do
          {:ok, ^path} -> :ok
          _ -> @error
        end

      _ ->
        @error
    end
  end

  defp safe_lock(path, uid) do
    case File.lstat(path) do
      {:error, :enoent} -> :ok
      {:ok, stat} -> if safe_file?(stat, uid), do: :ok, else: @error
      _ -> @error
    end
  end

  defp safe_file?(s, uid),
    do: s.type == :regular and s.uid == uid and s.links == 1 and band(s.mode, 0o7777) == 0o600

  defp read(path, project, uid) do
    file = Path.join(path, "control.json")

    case File.lstat(file) do
      {:error, :enoent} ->
        {:ok,
         %{
           "version" => 2,
           "project" => project,
           "epoch" => 0,
           "sequence" => 0,
           "policy" => nil,
           "operations" => %{},
           "compacted" => %{}
         }}

      {:ok, stat} ->
        read_present(path, project, uid, stat)

      _ ->
        @error
    end
  end

  defp read_present(_path, project, uid, stat) do
    lock = Process.get(@lock_key)

    with true <- safe_file?(stat, uid) and stat.size <= @bytes,
         {:ok, bytes} <- Transaction.read(lock, ".", "control.json", @bytes),
         true <- is_binary(bytes) and byte_size(bytes) <= @bytes,
         {:ok, s} <- JSON.decode_unique(bytes),
         true <- valid_state?(s, project),
         do: {:ok, upgrade(s)},
         else: (_ -> @error)
  end

  defp write(path, s) do
    s = compact(s)
    pending = ".pending-" <> Ipse.Usage.id()
    lock = Process.get(@lock_key)

    with true <- lock != nil and Path.basename(path) == s["project"],
         {:ok, bytes} <- Jason.encode(s),
         :ok <- maintenance_capacity(s, bytes),
         {:ok, ^s} <- JSON.decode_unique(bytes),
         :ok <- Transaction.quota(lock, :flat, @allocated_bytes),
         :ok <- Transaction.preflight(lock, [byte_size(bytes)]),
         {:ok, before} <- Transaction.allocation(lock, :flat),
         true <- before.allocated + byte_size(bytes) <= @allocated_bytes do
      with :ok <- Transaction.stage(lock, ".", [{pending, bytes}]),
           {:ok, staged} <- Transaction.allocation(lock, :flat),
           true <- staged.allocated <= @allocated_bytes,
           :ok <- Transaction.switch(lock, pending, "control.json"),
           {:ok, committed} <- Transaction.allocation(lock, :flat),
           true <- committed.allocated <= @allocated_bytes do
        :ok
      else
        _ -> {:unknown, :consent_write_unconfirmed}
      end
    else
      {:error, :transaction_capacity} -> {:error, :consent_capacity}
      {:error, :transaction_filesystem_unsupported} -> {:error, :consent_filesystem_unsupported}
      {:error, :consent_capacity} = error -> error
      _ -> @error
    end
  end

  defp maintenance_capacity(s, bytes) do
    receipt_bytes =
      Enum.reduce(s["operations"], 0, fn {_, r}, n ->
        if terminal?(r), do: n + byte_size(Jason.encode!(r["receipt"])), else: n
      end)

    growth =
      Enum.reduce(s["operations"], 0, fn {_, r}, n ->
        if terminal?(r) do
          n
        else
          n + @max_actual_bytes - byte_size(Jason.encode!(r["actual"])) +
            @max_status_bytes - byte_size(Jason.encode!(r["status"]))
        end
      end)

    # Reserve the maximum future representation, crediting fields already stored.
    # Keeping the same additive margin during settlement would prevent a measured
    # overrun or a policy replacement from consuming its own reserved headroom.
    # Nonterminal null receipts remain in the base; only terminal bodies are
    # replaced by the global maximum of 64 full recent receipts.
    required =
      byte_size(bytes) - receipt_bytes - byte_size(Jason.encode!(s["policy"])) +
        @recent * 8192 + growth + @policy_bytes + 16 - byte_size(Integer.to_string(s["epoch"]))

    if required <= @write_bytes, do: :ok, else: {:error, :consent_capacity}
  end

  defp reclaim_pending(path, uid, lock) do
    with {:ok, names} <- pending_names(path, uid) do
      names
      |> Enum.filter(&pending_name?/1)
      |> Enum.sort()
      |> Enum.chunk_every(64)
      |> Enum.reduce_while(:ok, fn batch, :ok ->
        case Transaction.reclaim(lock, ".", batch) do
          :ok -> {:cont, :ok}
          _ -> {:halt, @error}
        end
      end)
    end
  end

  defp pending_names(path, uid) do
    with {:ok, names} <- File.ls(path),
         true <- length(names) <= 131,
         true <-
           Enum.all?(names, &(&1 in ~w(.lock .writer.lock control.json) or pending_name?(&1))),
         true <-
           Enum.all?(names, fn name ->
             case File.lstat(Path.join(path, name)) do
               {:ok, stat} -> safe_file?(stat, uid) and stat.size <= @bytes
               _ -> false
             end
           end) do
      {:ok, names}
    else
      _ -> @error
    end
  end

  defp pending_name?(name), do: Regex.match?(~r/\A\.pending-[a-f0-9]{32}\z/, name)

  defp upgrade(%{"version" => 1} = s), do: s |> Map.put("compacted", %{}) |> Map.put("version", 2)
  defp upgrade(s), do: s

  defp valid_state?(s, project) do
    legacy = s["version"] === 1 and keys?(s, ~w(version project epoch sequence policy operations))

    current =
      s["version"] === 2 and
        keys?(s, ~w(version project epoch sequence policy operations compacted))

    (legacy or current) and valid_contents?(upgrade(s), project, legacy)
  rescue
    _ -> false
  end

  defp valid_contents?(s, project, legacy) do
    compacted = s["compacted"]

    s["project"] == project and uint?(s["epoch"]) and uint?(s["sequence"]) and
      (s["policy"] == nil or (valid_policy?(s["policy"]) and s["policy"]["project"] == project)) and
      is_map(s["operations"]) and is_map(compacted) and
      operation_count(s) <= if(legacy, do: @legacy_entries, else: @entries) and
      pending(s) <= @pending and s["sequence"] == operation_count(s) and
      Enum.all?(compacted, fn {id, row} ->
        valid_compact?(id, row, s) and not Map.has_key?(s["operations"], id)
      end) and
      Enum.all?(s["operations"], fn {id, r} ->
        valid_operation?(id, r, s)
      end) and
      s["sequence"] ==
        MapSet.size(
          MapSet.new(
            Enum.map(Map.values(s["operations"]), & &1["sequence"]) ++
              Enum.map(Map.values(compacted), &hd/1)
          )
        )
  end

  defp valid_compact?(id, [sequence, epoch, request, created, status, actual, receipt], s) do
    id?(id) and uint?(sequence) and sequence in 1..s["sequence"] and
      uint?(epoch) and epoch in 1..s["epoch"] and JSON.sha256?(request) and uint?(created) and
      status in ~w(settled reconciled_overrun) and is_list(actual) and
      length(actual) == length(@resources) and Enum.all?(actual, &uint?/1) and
      JSON.sha256?(receipt)
  end

  defp valid_compact?(_, _, _), do: false

  defp valid_operation?(id, r, s) do
    keys?(
      r,
      ~w(id operation artifact_sha256 source_sha256 policy_sha256 request_sha256 source_generation reserved headless sequence epoch created_at_ms status actual receipt)
    ) and
      request?(Map.drop(r, ~w(sequence epoch created_at_ms status actual receipt))) and
      id == r["id"] and
      uint?(r["sequence"]) and r["sequence"] in 1..s["sequence"] and
      uint?(r["epoch"]) and r["epoch"] in 1..s["epoch"] and uint?(r["created_at_ms"]) and
      valid_settlement?(r)
  end

  defp vector?(v), do: keys?(v, @resources) and Enum.all?(Map.values(v), &uint?/1)

  defp valid_settlement?(%{"status" => status} = r)
       when status in ~w(settled reconciled_overrun) do
    vector?(r["actual"]) and json_map?(r["receipt"], 8_192) and
      within?(r["actual"], r["reserved"]) == (status == "settled")
  end

  defp valid_settlement?(%{"status" => "overrun"} = r),
    do: vector?(r["actual"]) and not within?(r["actual"], r["reserved"]) and r["receipt"] == nil

  defp valid_settlement?(%{"status" => status} = r)
       when status in ~w(reserved admitted publishing unknown),
       do: r["actual"] == nil and r["receipt"] == nil

  defp valid_settlement?(_), do: false

  defp json_map?(m, limit) when is_map(m) do
    bytes = Jason.encode!(m)
    byte_size(bytes) <= limit and JSON.decode_unique(bytes, 12) == {:ok, m}
  rescue
    _ -> false
  end

  defp json_map?(_, _), do: false
  defp uint?(v), do: JSON.safe_uint?(v)
  defp keys?(m, ks), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(ks)
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[a-f0-9]{32}\z/, id)
  defp name?(n), do: is_binary(n) and Regex.match?(~r/\A[a-z][a-z0-9_.]{0,63}\z/, n)
end
