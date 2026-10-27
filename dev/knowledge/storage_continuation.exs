defmodule Ipse.Development.StorageContinuation do
  @moduledoc false
  alias Ipse.Runner.Transaction, as: T
  @limit 2 * 1024 * 1024
  @quota 8 * 1024 * 1024

  # This out-of-band benchmark oracle is not a product backup or checkpoint.
  # Every transaction is short; no capability escapes into the workload loop.
  def start(directory, identity) do
    with {:error, :enoent} <- File.lstat(directory),
         :ok <- File.mkdir(directory),
         :ok <- File.chmod(directory, 0o700),
         :ok <- Ipse.Runner.protected_sync_directory(Path.dirname(directory)) do
      marker = pending()

      locked(directory, fn cap ->
        with :ok <- T.stage(cap, ".", [{marker, Jason.encode!(identity)}]) do
          {:ok, %{directory: directory, marker: marker}}
        end
      end)
    else
      _ -> {:error, :continuation_directory_already_exists_or_unsafe}
    end
  end

  def finish(handle, checkpoint, report) do
    report_bytes = Jason.encode!(report)
    report_sha = Ipse.JSON.sha256(report_bytes)
    checkpoint = Map.put(checkpoint, "report_sha256", report_sha)
    bytes = Jason.encode!(checkpoint)

    if byte_size(bytes) + byte_size(report_bytes) <= @limit do
      locked(handle.directory, fn cap ->
        with {:ok, names} <- File.ls(handle.directory),
             true <- pending_names(names) == [handle.marker],
             false <- "root.json" in names,
             staged = pending(),
             report_staged = pending(),
             :ok <- T.preflight(cap, [byte_size(bytes), byte_size(report_bytes)]),
             :ok <- T.stage(cap, ".", [{staged, bytes}, {report_staged, report_bytes}]),
             {:ok, peak} <- T.allocation(cap, :flat),
             :ok <- T.install(cap, ".", report_staged, report_sha <> ".json"),
             :ok <- T.switch(cap, staged, "root.json"),
             :ok <- T.reclaim(cap, ".", [handle.marker]),
             {:ok, final} <- T.allocation(cap, :flat) do
          {:ok,
           %{
             "path" => Path.join(handle.directory, "root.json"),
             "sha256" => Ipse.JSON.sha256(bytes),
             "report_sha256" => report_sha,
             "report_path" => Path.join(handle.directory, report_sha <> ".json"),
             "serialized_bytes" => byte_size(bytes) + byte_size(report_bytes),
             "peak_allocation" => peak,
             "final_allocation" => final,
             "separate_oracle_quota_bytes" => @quota
           }}
        else
          _ -> {:unknown, :continuation_finish_unconfirmed}
        end
      end)
    else
      {:error, :continuation_oracle_capacity}
    end
  end

  def read(path, expected_sha) do
    if Path.basename(path) == "root.json" and Ipse.JSON.sha256?(expected_sha) do
      locked(Path.dirname(path), fn cap ->
        with {:ok, names} <- File.ls(Path.dirname(path)),
             true <- length(names) <= 8 and pending_names(names) == [],
             {:ok, bytes} <- T.read(cap, ".", "root.json", @limit),
             true <- Ipse.JSON.sha256(bytes) == expected_sha,
             {:ok, checkpoint} <- Ipse.JSON.decode_unique(bytes),
             report_sha = checkpoint["report_sha256"],
             true <- Ipse.JSON.sha256?(report_sha),
             {:ok, report} <- T.read(cap, ".", report_sha <> ".json", @limit),
             true <- Ipse.JSON.sha256(report) == report_sha,
             true <- byte_size(bytes) + byte_size(report) <= @limit,
             {:ok, decoded_report} <- Ipse.JSON.decode_unique(report) do
          {:ok, checkpoint, decoded_report}
        else
          _ -> {:error, :continuation_unclean_or_corrupt}
        end
      end)
    else
      {:error, :invalid_continuation_reference}
    end
  end

  def binding(files, beam_directory, workspace) do
    library = Path.dirname(Path.dirname(beam_directory))

    beams =
      (Path.wildcard(Path.join([library, "*", "ebin", "*.beam"])) ++
         Path.wildcard(Path.join([library, "*", "consolidated", "*.beam"])))
      |> Enum.sort()

    true = length(files) <= 256 and length(beams) in 1..8192
    {:ok, helper} = Ipse.Runner.protected_helper(workspace)

    %{
      "sources" => Enum.map(Enum.sort(files), &[&1, hash_file(&1)]),
      "beams" => Enum.map(beams, &[Path.relative_to(&1, library), hash_file(&1)]),
      "helper" => hash_file(helper),
      "elixir" => System.version(),
      "otp" => to_string(:erlang.system_info(:system_version))
    }
    |> then(&Ipse.JSON.digest([&1]))
  end

  def record_digest(rows) do
    rows
    |> Enum.sort()
    |> Enum.map(fn {key, row} ->
      [key, row["revision"], Ipse.JSON.digest([row["value"]])]
    end)
    |> then(&Ipse.JSON.digest([&1]))
  end

  def validate(checkpoint, binding, options) do
    fields =
      ~w(version binding options segment progress descriptor records_digest state calls resume_calls first_wall_ms cumulative_ms previous report_sha256)

    with true <- is_map(checkpoint) and Enum.sort(Map.keys(checkpoint)) == Enum.sort(fields),
         true <- checkpoint["version"] === 1 and checkpoint["binding"] == binding,
         true <- checkpoint["options"] == options,
         true <- checkpoint["segment"] in 1..3,
         %{"day" => day, "cycle" => cycle} = progress <- checkpoint["progress"],
         true <- Enum.sort(Map.keys(progress)) == ~w(cycle day),
         true <- is_integer(day) and day in 0..options["days"],
         true <- is_integer(cycle) and cycle in 0..options["cycles"],
         true <- cycle == 0 or day == options["days"],
         true <- day < options["days"] or cycle < options["cycles"],
         true <- Ipse.Extension.Collection.Migration.descriptor?(checkpoint["descriptor"]),
         true <- checkpoint["descriptor"]["operations"] == checkpoint["descriptor"]["generation"],
         true <- Ipse.JSON.sha256?(checkpoint["records_digest"]),
         true <- valid_state?(checkpoint["state"], checkpoint["descriptor"]),
         true <-
           valid_counters?(checkpoint["calls"]) and valid_counters?(checkpoint["resume_calls"]),
         true <- is_integer(checkpoint["first_wall_ms"]) and checkpoint["first_wall_ms"] > 0,
         true <-
           is_integer(checkpoint["cumulative_ms"]) and
             checkpoint["cumulative_ms"] in 0..21_600_000 do
      :ok
    else
      _ -> {:error, :continuation_binding_or_progress}
    end
  rescue
    _ -> {:error, :continuation_binding_or_progress}
  end

  defp valid_state?(state, descriptor) do
    fields =
      ~w(generation samples peak peak_allocated peak_ram pauses migrations queued_actions checkpoints)

    is_map(state) and Enum.sort(Map.keys(state)) == Enum.sort(fields) and
      state["generation"] === descriptor["generation"] and
      is_list(state["samples"]) and length(state["samples"]) == descriptor["generation"] and
      length(state["samples"]) <= 32_768 and
      Enum.all?(state["samples"], &(is_number(&1) and &1 >= 0 and &1 <= 7_200_000)) and
      Enum.all?(~w(peak peak_allocated), fn key ->
        is_integer(state[key]) and state[key] in 0..67_108_864
      end) and
      is_integer(state["peak_ram"]) and state["peak_ram"] in 0..536_870_912 and
      state["pauses"] === 0 and is_integer(state["queued_actions"]) and
      state["queued_actions"] in 0..217 and is_list(state["migrations"]) and
      length(state["migrations"]) <= 2 and is_map(state["checkpoints"]) and
      Enum.all?(Map.keys(state["checkpoints"]), &(&1 in ~w(30 90 365)))
  end

  defp valid_counters?(counters) do
    is_map(counters) and map_size(counters) <= 32 and
      Enum.all?(counters, fn {key, count} ->
        is_binary(key) and byte_size(key) <= 64 and is_integer(count) and count in 0..100_000
      end)
  end

  defp locked(directory, function) do
    with {:ok, ^directory} <- Ipse.Workspace.canonical_path(directory),
         {:ok, cap} <- T.acquire(Path.join(directory, ".lock"), cwd: directory) do
      result =
        try do
          with :ok <- T.quota(cap, :flat, @quota), do: function.(cap)
        rescue
          _ -> {:error, :continuation_oracle_unconfirmed}
        end

      checked = T.check(cap)
      released = T.release(cap)

      if checked == :ok and released == :ok,
        do: result,
        else: {:unknown, :continuation_oracle_unconfirmed}
    else
      _ -> {:error, :continuation_oracle_unavailable}
    end
  end

  defp hash_file(path), do: path |> File.read!() |> Ipse.JSON.sha256()
  defp pending, do: ".pending-" <> Ipse.Usage.id()

  defp pending_names(names),
    do: names |> Enum.filter(&String.starts_with?(&1, ".pending-")) |> Enum.sort()
end
