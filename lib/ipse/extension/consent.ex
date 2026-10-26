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
  import Bitwise, only: [band: 2]
  @bytes 8_388_608
  @entries 16_384
  @pending 128
  @resources ~w(operations model_calls input_bytes output_bytes download_bytes cost_nanos)
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
           nil <- s["operations"][request["id"]],
           :ok <- eligible(s, request, now),
           true <- map_size(s["operations"]) < @entries and pending(s) < @pending,
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
    transaction(root, project, fn s ->
      with {:ok, r} <- current(s, ticket, now) do
        admitted = put_in(s["operations"][r["id"]]["status"], "publishing")

        with :ok <- write(Path.join(root, project), admitted) do
          try do
            case fun.() do
              {:ok, actual, receipt} ->
                finish(admitted, admitted["operations"][r["id"]], actual, receipt)

              _ ->
                {:unknown, :publication_unconfirmed}
            end
          catch
            _, _ -> {:unknown, :publication_unconfirmed}
          end
        else
          _ -> {:unknown, :consent_write_unconfirmed}
        end
      else
        _ -> {:error, :consent_publication_refused}
      end
    end)
  end

  @doc "Settle known work, retain unknown liability, or reconcile explicitly; never replay."
  def settle(root, project, ticket, outcome) do
    transaction(root, project, fn s ->
      with {:ok, r} <- lookup(s, ticket) do
        case {r["status"], outcome} do
          {"reserved", :unstarted} ->
            finish(s, r, zero(), %{"unstarted" => true})

          {status, {:known, actual}} when status in ~w(admitted publishing) ->
            finish(s, r, actual, %{})

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
      else
        _ -> {:error, :consent_settlement_refused}
      end
    end)
  end

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
         (not r["headless"] or p["headless"]), do: :ok, else: {:error, :consent_denied}
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

    not quarantined?(s) and
      within?(add(used, reserved), s["policy"]["limits"])
  end

  defp add(a, b), do: Map.new(@resources, &{&1, a[&1] + b[&1]})
  defp within?(a, b), do: Enum.all?(@resources, &(a[&1] <= b[&1]))
  defp terminal?(r), do: r["status"] in ~w(settled reconciled_overrun)
  defp quarantined?(s), do: Enum.any?(s["operations"], fn {_, r} -> r["status"] == "overrun" end)
  defp pending(s), do: Enum.count(s["operations"], fn {_, r} -> not terminal?(r) end)

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
    Ipse.Session.Resources.file_effect(fn -> locked(root, project, fun) end)
  end

  defp locked(root, project, fun) do
    with true <- is_binary(root) and Path.type(root) == :absolute and JSON.sha256?(project),
         {:ok, uid} <- Ipse.Runner.current_uid(),
         :ok <- directory(Path.dirname(root), uid, false),
         :ok <- directory(root, uid, true),
         path = Path.join(root, project),
         :ok <- directory(path, uid, true),
         :ok <- safe_lock(Path.join(path, ".lock"), uid),
         {:ok, lock} <- Ipse.Runner.lock(Path.join(path, ".lock")) do
      try do
        with {:ok, s} <- read(path, project, uid) do
          case fun.(s) do
            {:read, value} ->
              {:ok, value}

            {:write, next, value} ->
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
      after
        Ipse.Runner.unlock(lock)
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
                 :ok <- Ipse.Runner.sync_directory(Path.dirname(path)),
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
    do: s.type == :regular and s.uid == uid and s.links == 1 and band(s.mode, 0o077) == 0

  defp read(path, project, uid) do
    file = Path.join(path, "control.json")

    case File.lstat(file) do
      {:error, :enoent} ->
        {:ok,
         %{
           "version" => 1,
           "project" => project,
           "epoch" => 0,
           "sequence" => 0,
           "policy" => nil,
           "operations" => %{}
         }}

      {:ok, stat} ->
        with true <- safe_file?(stat, uid) and stat.size <= @bytes,
             {:ok, bytes} <- File.open(file, [:read, :binary], &IO.binread(&1, @bytes + 1)),
             true <- is_binary(bytes) and byte_size(bytes) <= @bytes,
             {:ok, s} <- JSON.decode_unique(bytes),
             true <- valid_state?(s, project),
             do: {:ok, s},
             else: (_ -> @error)

      _ ->
        @error
    end
  end

  defp write(path, s) do
    temporary = Path.join(path, ".pending-" <> Ipse.Usage.id())

    try do
      with {:ok, bytes} <- Jason.encode(s),
           true <- byte_size(bytes) <= @bytes,
           {:ok, ^s} <- JSON.decode_unique(bytes),
           :ok <- File.write(temporary, bytes, [:exclusive, :binary]),
           :ok <- File.chmod(temporary, 0o600),
           {:ok, f} <- :file.open(String.to_charlist(temporary), [:read, :write, :binary, :raw]) do
        try do
          with :ok <- :file.sync(f),
               :ok <- File.rename(temporary, Path.join(path, "control.json")),
               do: Ipse.Runner.sync_directory(path)
        after
          :file.close(f)
        end
      else
        _ -> @error
      end
    after
      File.rm(temporary)
    end
  end

  defp valid_state?(s, project) do
    keys?(s, ~w(version project epoch sequence policy operations)) and s["version"] === 1 and
      s["project"] == project and uint?(s["epoch"]) and uint?(s["sequence"]) and
      (s["policy"] == nil or (valid_policy?(s["policy"]) and s["policy"]["project"] == project)) and
      is_map(s["operations"]) and map_size(s["operations"]) <= @entries and pending(s) <= @pending and
      s["sequence"] == map_size(s["operations"]) and
      Enum.all?(s["operations"], fn {id, r} ->
        keys?(
          r,
          ~w(id operation artifact_sha256 source_sha256 policy_sha256 request_sha256 source_generation reserved headless sequence epoch created_at_ms status actual receipt)
        ) and
          request?(Map.drop(r, ~w(sequence epoch created_at_ms status actual receipt))) and
          id == r["id"] and
          uint?(r["sequence"]) and r["sequence"] in 1..s["sequence"] and
          uint?(r["epoch"]) and r["epoch"] in 1..s["epoch"] and uint?(r["created_at_ms"]) and
          valid_settlement?(r)
      end) and
      s["sequence"] == length(Enum.uniq_by(Map.values(s["operations"]), & &1["sequence"]))
  rescue
    _ -> false
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
