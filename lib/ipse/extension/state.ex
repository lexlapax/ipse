defmodule Ipse.Extension.State do
  @moduledoc "Bounded scoped JSON state with cross-process CAS and retained deletion revisions."
  alias Ipse.Extension.Registry
  import Bitwise, only: [band: 2]
  @error {:error, :extension_state_unavailable}
  @bytes 1_048_576
  @records 256
  @max_revision 9_007_199_254_740_991

  @doc "Operator-selected logical identity; workers cannot select a storage binding."
  def valid_binding?(binding) when is_map(binding) do
    keys?(binding, ~w(version id scopes)) and binding["version"] === 1 and
      key?(binding["id"]) and is_list(binding["scopes"]) and
      binding["scopes"] != [] and length(binding["scopes"]) <= 3 and
      Enum.all?(binding["scopes"], &(&1 in ~w(operator project session))) and
      length(binding["scopes"]) == length(Enum.uniq(binding["scopes"]))
  end

  def valid_binding?(_), do: false

  def namespace(identity, scope, cwd, session_id) do
    with true <- Registry.valid_identity?(identity),
         true <- scope in ~w(operator project session),
         true <- scope != "operator" or identity["scope"] == "operator",
         true <-
           not Map.has_key?(identity, "state_binding") or
             scope in identity["state_binding"]["scopes"],
         true <- is_binary(cwd) and Path.type(cwd) == :absolute,
         true <- id?(session_id) do
      base = %{
        "scope" => scope,
        "project" => if(scope == "operator", do: nil, else: Ipse.JSON.sha256(cwd)),
        "session" => if(scope == "session", do: session_id)
      }

      descriptor =
        case identity["state_binding"] do
          nil ->
            Map.merge(base, %{
              "version" => 1,
              "instance" => identity["instance"],
              "artifact_sha256" => identity["artifact_sha256"],
              "source_sha256" => identity["source_sha256"]
            })

          binding ->
            Map.merge(base, %{"version" => 2, "binding" => binding["id"]})
        end

      {:ok, Ipse.JSON.digest([descriptor])}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def validate(request) do
    with :ok <- Ipse.Extension.validate(request),
         true <- request["scope"] in ~w(operator project session),
         true <- valid_operation?(request) do
      :ok
    else
      _ -> {:error, :invalid_extension_state_request}
    end
  rescue
    _ -> {:error, :invalid_extension_state_request}
  end

  def capability(%{"op" => op}) when op in ~w(state.get state.list), do: "host.state.read"
  def capability(%{"op" => "state.scan"}), do: "host.state.scan"
  def capability(%{"op" => op}) when op in ~w(state.put state.delete), do: "host.state.write"
  def capability(_), do: nil
  def mutating?(request), do: capability(request) == "host.state.write"

  @doc "Caller supplies an admitted host namespace and operation ID; this function grants no permission."
  def execute(root, namespace, request, operation_id) do
    Ipse.Session.Resources.file_effect(fn ->
      execute_locked(root, namespace, request, operation_id)
    end)
  end

  defp execute_locked(root, namespace, request, operation_id) do
    with true <- is_binary(root) and hash?(namespace) and id?(operation_id),
         :ok <- validate(request),
         :ok <- directory(root),
         path = Path.join(root, namespace),
         :ok <- directory(path),
         lock_path = Path.join(path, ".lock"),
         :ok <- safe_lock(lock_path),
         {:ok, lock} <- Ipse.Runner.lock(lock_path) do
      try do
        with {:ok, state} <- read(path, namespace) do
          apply_operation(path, state, request, operation_id)
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

  defp valid_operation?(%{"op" => "state.get"} = request),
    do: keys?(request, ~w(op scope key)) and key?(request["key"])

  defp valid_operation?(%{"op" => op} = request) when op in ~w(state.list state.scan) do
    keys?(request, ~w(op scope after generation limit)) and
      (is_nil(request["after"]) or key?(request["after"])) and
      (is_nil(request["generation"]) or revision?(request["generation"])) and
      is_integer(request["limit"]) and request["limit"] in 1..16
  end

  defp valid_operation?(%{"op" => "state.put"} = request) do
    keys?(
      Map.drop(request, ~w(write_before_ms expected_generation)),
      ~w(op scope key expected_revision value)
    ) and
      (not Map.has_key?(request, "write_before_ms") or revision?(request["write_before_ms"])) and
      (not Map.has_key?(request, "expected_generation") or
         revision?(request["expected_generation"])) and
      key?(request["key"]) and
      revision?(request["expected_revision"]) and is_map(request["value"]) and
      value?(request["value"])
  end

  defp valid_operation?(%{"op" => "state.delete"} = request) do
    keys?(request, ~w(op scope key expected_revision)) and key?(request["key"]) and
      revision?(request["expected_revision"])
  end

  defp valid_operation?(_), do: false

  defp apply_operation(_path, state, %{"op" => "state.get", "key" => key}, _) do
    {:ok, %{"generation" => state["generation"], "record" => record(state, key)}}
  end

  defp apply_operation(_path, state, %{"op" => op} = request, _)
       when op in ~w(state.list state.scan) do
    if is_nil(request["generation"]) or request["generation"] == state["generation"] do
      keys =
        state["records"]
        |> Map.keys()
        |> Enum.sort()
        |> Enum.filter(&(is_nil(request["after"]) or &1 > request["after"]))

      selected =
        keys
        |> Enum.take(request["limit"])
        |> Enum.reduce_while([], fn key, selected ->
          candidate = selected ++ [key]

          if op == "state.list" or
               byte_size(Jason.encode!(Enum.map(candidate, &record(state, &1)))) <= 12_000,
             do: {:cont, candidate},
             else: {:halt, selected}
        end)

      {:ok,
       %{
         "generation" => state["generation"],
         "records" =>
           Enum.map(selected, fn key ->
             if op == "state.scan",
               do: record(state, key),
               else: Map.drop(record(state, key), ["value"])
           end),
         "next" => if(length(keys) > length(selected), do: List.last(selected))
       }}
    else
      {:conflict, %{"generation" => state["generation"]}}
    end
  end

  defp apply_operation(path, state, request, operation_id) do
    old = record(state, request["key"])
    deadline_check = check_write_deadline(request)

    cond do
      request["expected_revision"] != old["revision"] ->
        {:conflict, %{"record" => Map.drop(old, ["value"]), "generation" => state["generation"]}}

      not generation_matches?(request, state["generation"]) ->
        {:conflict, %{"record" => Map.drop(old, ["value"]), "generation" => state["generation"]}}

      match?({:elapsed, _}, deadline_check) ->
        {:elapsed, checked_at} = deadline_check
        deadline_failure(state, old, checked_at)

      state["generation"] >= @max_revision or old["revision"] >= @max_revision ->
        quota_failure(state, old)

      old["revision"] == 0 and map_size(state["records"]) >= @records ->
        quota_failure(state, old)

      true ->
        record = %{
          "key" => request["key"],
          "revision" => old["revision"] + 1,
          "deleted" => request["op"] == "state.delete",
          "value" => if(request["op"] == "state.put", do: request["value"]),
          "operation_id" => operation_id
        }

        next = %{
          state
          | "generation" => state["generation"] + 1,
            "records" => Map.put(state["records"], request["key"], record)
        }

        with :ok <- write(path, next, request) do
          {:ok, %{"generation" => next["generation"], "record" => record}}
        else
          {:elapsed, checked_at} -> deadline_failure(state, old, checked_at)
          {:error, :extension_state_quota} -> quota_failure(state, old)
          error -> error
        end
    end
  end

  defp record(state, key) do
    Map.get(state["records"], key, %{
      "key" => key,
      "revision" => 0,
      "deleted" => true,
      "value" => nil,
      "operation_id" => nil
    })
  end

  defp read(path, namespace) do
    file = Path.join(path, "state.json")

    case File.lstat(file) do
      {:error, :enoent} ->
        {:ok, %{"version" => 1, "namespace" => namespace, "generation" => 0, "records" => %{}}}

      {:ok, %{type: :regular, size: size, mode: mode}} when size <= @bytes ->
        with true <- band(mode, 0o077) == 0,
             {:ok, bytes} <- bounded_read(file),
             {:ok, state} <- Ipse.JSON.decode_bounded(bytes, @bytes),
             true <- valid_state?(state, namespace) do
          {:ok, state}
        else
          _ -> @error
        end

      _ ->
        @error
    end
  end

  defp bounded_read(path) do
    with {:ok, bytes} <- File.open(path, [:read, :binary], &IO.binread(&1, @bytes + 1)),
         true <- is_binary(bytes) and byte_size(bytes) <= @bytes do
      {:ok, bytes}
    else
      _ -> @error
    end
  end

  defp valid_state?(state, namespace) do
    keys?(state, ~w(version namespace generation records)) and state["version"] === 1 and
      state["namespace"] == namespace and revision?(state["generation"]) and
      is_map(state["records"]) and map_size(state["records"]) <= @records and
      Enum.sum(Enum.map(state["records"], fn {_, record} -> record["revision"] end)) ==
        state["generation"] and
      Enum.all?(state["records"], fn {key, record} ->
        keys?(record, ~w(key revision deleted value operation_id)) and key?(key) and
          record["key"] == key and revision?(record["revision"]) and record["revision"] > 0 and
          record["revision"] <= state["generation"] and is_boolean(record["deleted"]) and
          id?(record["operation_id"]) and
          if(record["deleted"],
            do: is_nil(record["value"]),
            else: value?(record["value"])
          )
      end)
  rescue
    _ -> false
  end

  defp check_write_deadline(%{"write_before_ms" => deadline}) do
    now = System.system_time(:millisecond)
    if now < deadline, do: :ok, else: {:elapsed, now}
  end

  defp check_write_deadline(_), do: :ok

  defp quota_failure(state, old),
    do:
      {:failed,
       %{
         "code" => "extension_state_quota",
         "generation" => state["generation"],
         "record" => Map.drop(old, ["value"])
       }}

  defp deadline_failure(state, old, checked_at),
    do:
      {:failed,
       %{
         "code" => "write_deadline_elapsed",
         "checked_at_ms" => checked_at,
         "generation" => state["generation"],
         "record" => Map.drop(old, ["value"])
       }}

  defp write(path, state, request) do
    with {:ok, bytes} <- Jason.encode(state),
         true <- byte_size(bytes) <= @bytes do
      temporary = Path.join(path, ".pending-" <> Ipse.Usage.id())

      try do
        with :ok <- File.write(temporary, bytes, [:exclusive, :binary, :sync]),
             :ok <- File.chmod(temporary, 0o600),
             :ok <- check_write_deadline(request),
             :ok <- File.rename(temporary, Path.join(path, "state.json")) do
          :ok
        else
          {:elapsed, _} = elapsed -> elapsed
          _ -> @error
        end
      after
        File.rm(temporary)
      end
    else
      _ -> {:error, :extension_state_quota}
    end
  end

  defp directory(path) do
    case File.lstat(path) do
      {:error, :enoent} ->
        case File.mkdir(path) do
          :ok -> File.chmod(path, 0o700)
          {:error, :eexist} -> directory(path)
          _ -> @error
        end

      {:ok, %{type: :directory, mode: mode}} when band(mode, 0o077) == 0 ->
        :ok

      _ ->
        @error
    end
  end

  defp safe_lock(path) do
    case File.lstat(path) do
      {:error, :enoent} -> :ok
      {:ok, %{type: :regular, mode: mode}} when band(mode, 0o077) == 0 -> :ok
      _ -> @error
    end
  end

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)

  defp key?(key),
    do: is_binary(key) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}\z/, key)

  defp hash?(hash), do: is_binary(hash) and Regex.match?(~r/\A[a-f0-9]{64}\z/, hash)
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[a-f0-9]{32}\z/, id)
  defp revision?(revision), do: is_integer(revision) and revision in 0..@max_revision

  defp generation_matches?(request, generation, increment \\ 0) do
    case Map.fetch(request, "expected_generation") do
      :error -> true
      {:ok, expected} -> revision?(expected) and generation == expected + increment
    end
  end

  defp value?(value) do
    is_map(value) and byte_size(Jason.encode!(value)) <= 8192 and
      Ipse.Extension.validate(%{"result" => %{"outcome" => %{"record" => %{"value" => value}}}}) ==
        :ok
  end

  def valid_outcome?(request, status, value, operation_id) do
    (not Map.has_key?(request, "expected_generation") or validate(request) == :ok) and
      is_map(value) and Ipse.Extension.validate(value) == :ok and
      outcome?(request, status, value, operation_id)
  rescue
    _ -> false
  end

  defp outcome?(_, status, value, _) when status in ~w(denied unknown), do: value == %{}

  defp outcome?(%{"op" => op} = request, "ok", value, _)
       when op in ~w(state.list state.scan) do
    records = value["records"]

    keys?(value, ~w(generation records next)) and revision?(value["generation"]) and
      (is_nil(request["generation"]) or request["generation"] == value["generation"]) and
      is_list(records) and length(records) <= request["limit"] and
      Enum.all?(records, fn record ->
        summary?(
          if(op == "state.scan", do: Map.drop(record, ["value"]), else: record),
          value["generation"]
        ) and
          (op != "state.scan" or
             (Map.has_key?(record, "value") and
                if(record["deleted"], do: is_nil(record["value"]), else: value?(record["value"])))) and
          record["revision"] > 0 and
          (is_nil(request["after"]) or record["key"] > request["after"])
      end) and
      Enum.map(records, & &1["key"]) ==
        Enum.map(records, & &1["key"]) |> Enum.uniq() |> Enum.sort() and
      (op != "state.scan" or byte_size(Jason.encode!(records)) <= 12_000) and
      (is_nil(value["next"]) or
         (records != [] and (op == "state.scan" or length(records) == request["limit"]) and
            value["next"] == List.last(records)["key"]))
  end

  defp outcome?(request, "ok", value, operation_id) do
    record = value["record"]

    keys?(value, ~w(generation record)) and revision?(value["generation"]) and
      is_map(record) and keys?(record, ~w(key revision deleted value operation_id)) and
      record["key"] == request["key"] and
      summary?(Map.drop(record, ["value"]), value["generation"]) and
      is_nil(record["operation_id"]) == (record["revision"] == 0) and
      if request["op"] == "state.get" do
        if(record["deleted"], do: is_nil(record["value"]), else: value?(record["value"]))
      else
        record["revision"] == request["expected_revision"] + 1 and
          generation_matches?(request, value["generation"], 1) and
          record["operation_id"] == operation_id and
          record["deleted"] == (request["op"] == "state.delete") and
          record["value"] == if(request["op"] == "state.put", do: request["value"])
      end
  end

  defp outcome?(%{"op" => op} = request, "conflict", value, _)
       when op in ~w(state.list state.scan) do
    keys?(value, ["generation"]) and revision?(value["generation"]) and
      not is_nil(request["generation"]) and request["generation"] != value["generation"]
  end

  defp outcome?(%{"op" => op} = request, "conflict", value, operation_id)
       when op in ~w(state.put state.delete) do
    keys?(value, ~w(generation record)) and revision?(value["generation"]) and
      summary?(value["record"], value["generation"]) and
      value["record"]["key"] == request["key"] and
      (not Map.has_key?(request, "expected_generation") or
         value["record"]["operation_id"] != operation_id) and
      (value["record"]["revision"] != request["expected_revision"] or
         not generation_matches?(request, value["generation"]))
  end

  defp outcome?(
         %{"op" => op} = request,
         "failed",
         %{"code" => "extension_state_quota"} = value,
         operation_id
       )
       when op in ~w(state.put state.delete) do
    validate(request) == :ok and keys?(value, ~w(code generation record)) and
      revision?(value["generation"]) and summary?(value["record"], value["generation"]) and
      value["record"]["key"] == request["key"] and
      value["record"]["operation_id"] != operation_id and
      generation_matches?(request, value["generation"]) and
      value["record"]["revision"] == request["expected_revision"]
  end

  defp outcome?(
         %{"op" => "state.put", "write_before_ms" => deadline} = request,
         "failed",
         value,
         operation_id
       ) do
    validate(request) == :ok and keys?(value, ~w(code checked_at_ms generation record)) and
      value["code"] == "write_deadline_elapsed" and revision?(value["checked_at_ms"]) and
      value["checked_at_ms"] >= deadline and revision?(value["generation"]) and
      summary?(value["record"], value["generation"]) and
      value["record"]["key"] == request["key"] and
      value["record"]["operation_id"] != operation_id and
      generation_matches?(request, value["generation"]) and
      value["record"]["revision"] == request["expected_revision"]
  end

  defp outcome?(_, _, _, _), do: false

  defp summary?(record, generation) do
    keys?(record, ~w(key revision deleted operation_id)) and key?(record["key"]) and
      revision?(record["revision"]) and record["revision"] <= generation and
      is_boolean(record["deleted"]) and
      if(record["revision"] == 0,
        do: is_nil(record["operation_id"]) and record["deleted"],
        else: id?(record["operation_id"])
      )
  end
end
