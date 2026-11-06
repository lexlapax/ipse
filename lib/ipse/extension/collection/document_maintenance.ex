defmodule Ipse.Extension.Collection.DocumentMaintenance do
  @moduledoc """
  Internal document metadata epochs and the exact open/close reservation.

  This supplies no SDK operation or authority. The trusted host binds the owner;
  Collection applies transitions and publication checks under its native CAS.
  General GC, adoption and semantic producer-continuation integration stay closed.
  """
  alias Ipse.JSON
  alias Ipse.Extension.Collection.{DocumentStage, Migration}
  @key "document_maintenance"
  @idle ~w(version epoch status)
  @active @idle ++
            ~w(maintenance_id purpose owner opening_generation opening_sha256 open_operation_id close_operation_id)

  def request?(%{"op" => "maintenance.inspect"} = r), do: exact?(r, ~w(op))

  def request?(%{"op" => "maintenance.open"} = r) do
    exact?(r, ~w(op expected_generation expected_epoch maintenance_id purpose close_operation_id)) and
      JSON.safe_uint?(r["expected_generation"]) and JSON.safe_uint?(r["expected_epoch"]) and
      id?(r["maintenance_id"]) and id?(r["close_operation_id"]) and
      r["purpose"] === "checkpoint_inspection"
  end

  def request?(%{"op" => "maintenance.close"} = r),
    do:
      exact?(r, ~w(op expected_generation expected_epoch maintenance_id)) and
        JSON.safe_uint?(r["expected_generation"]) and JSON.safe_uint?(r["expected_epoch"]) and
        id?(r["maintenance_id"])

  def request?(_), do: false

  def metadata(state),
    do: Map.get(state, @key, %{"version" => 1, "epoch" => 0, "status" => "idle"})

  def present?(state), do: Map.has_key?(state, @key)
  def reserved_slots(state), do: if(metadata(state)["status"] === "active", do: 1, else: 0)

  def valid?(state) do
    m = metadata(state)
    base = is_map(m) and m["version"] === 1 and JSON.safe_uint?(m["epoch"])

    base and
      case m["status"] do
        "idle" ->
          exact?(m, @idle) and (not present?(state) or m["epoch"] > 0)

        "active" ->
          receipt = Migration.known_operations(state)[m["open_operation_id"]]

          exact?(m, @active) and m["epoch"] > 0 and
            id?(m["maintenance_id"]) and id?(m["open_operation_id"]) and
            id?(m["close_operation_id"]) and m["open_operation_id"] !== m["close_operation_id"] and
            DocumentStage.owner?(m["owner"]) and m["purpose"] === "checkpoint_inspection" and
            Ipse.Extension.CollectionStore.namespace(m["owner"]["project_id"]) ===
              state["project"] and
            state["migration"] === nil and
            JSON.sha256?(m["opening_sha256"]) and JSON.safe_uint?(m["opening_generation"]) and
            m["opening_generation"] === state["generation"] and
            is_map(receipt) and receipt["generation"] === m["opening_generation"] and
            receipt["request_sha256"] === JSON.digest([opening_request(m)]) and
            m["opening_sha256"] ===
              opening_commitment(%{
                state
                | "generation" => m["opening_generation"] - 1,
                  "operations" => Map.delete(state["operations"], m["open_operation_id"])
              }) and
            not Map.has_key?(Migration.known_operations(state), m["close_operation_id"])

        _ ->
          false
      end
  rescue
    _ -> false
  end

  @doc "Check an ordinary document mutation at the actual locked publication boundary."
  def admission_error(state, operation_id, admitted_epoch) do
    m = metadata(state)

    cond do
      m["status"] === "active" and operation_id === m["close_operation_id"] ->
        "collection_operation_identity"

      m["status"] === "active" ->
        "collection_writer_fenced"

      (present?(state) or not is_nil(admitted_epoch)) and admitted_epoch !== m["epoch"] ->
        "collection_document_epoch"

      true ->
        nil
    end
  end

  def prepare(state, %{"op" => "maintenance.open"} = r, operation_id, limit) do
    m = metadata(state)
    known = Migration.known_operations(state)

    cond do
      m["status"] !== "idle" or state["migration"] !== nil ->
        {:failed, "collection_writer_fenced"}

      r["expected_epoch"] !== m["epoch"] ->
        {:failed, "collection_document_epoch"}

      not JSON.safe_uint?(m["epoch"] + 1) ->
        {:failed, "collection_document_epoch"}

      operation_id === r["close_operation_id"] or Map.has_key?(known, r["close_operation_id"]) ->
        {:failed, "collection_operation_identity"}

      map_size(known) + 2 > limit ->
        {:failed, "collection_capacity"}

      true ->
        active = %{
          "version" => 1,
          "epoch" => m["epoch"] + 1,
          "status" => "active",
          "maintenance_id" => r["maintenance_id"],
          "purpose" => r["purpose"],
          "owner" => r["owner"],
          "opening_generation" => state["generation"] + 1,
          "opening_sha256" => opening_commitment(state),
          "open_operation_id" => operation_id,
          "close_operation_id" => r["close_operation_id"]
        }

        {:ok, Map.put(state, @key, active), %{}, %{}}
    end
  end

  def prepare(state, %{"op" => "maintenance.close"} = r, operation_id, _limit) do
    m = metadata(state)

    if m["status"] === "active" and r["expected_epoch"] === m["epoch"] and
         r["maintenance_id"] === m["maintenance_id"] and r["owner"] === m["owner"] and
         operation_id === m["close_operation_id"] do
      {:ok, Map.put(state, @key, %{"version" => 1, "epoch" => m["epoch"], "status" => "idle"}),
       %{}, %{}}
    else
      {:failed, "collection_document_maintenance_owner"}
    end
  end

  defp opening_commitment(state) do
    checkpoint =
      case state["checkpoint"] do
        nil -> nil
        c -> Map.put(Map.delete(c, "records"), "records_sha256", Migration.digest(c["records"]))
      end

    JSON.digest([%{"descriptor" => Migration.descriptor(state), "checkpoint" => checkpoint}])
  end

  defp opening_request(m) do
    %{
      "op" => "maintenance.open",
      "expected_generation" => m["opening_generation"] - 1,
      "expected_epoch" => m["epoch"] - 1,
      "maintenance_id" => m["maintenance_id"],
      "purpose" => m["purpose"],
      "close_operation_id" => m["close_operation_id"],
      "owner" => m["owner"]
    }
  end

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
  defp exact?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) === Enum.sort(keys)
end
