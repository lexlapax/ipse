defmodule Ipse.Extension.CollectionStore do
  @moduledoc "Explicit operator-bound project storage, separate from signed-note admission."
  alias Ipse.{JSON, Extension}
  alias Ipse.Extension.{ProjectIdentity, Registry}
  alias Ipse.Extension.Collection.{DocumentStage, Profile}
  @error {:error, :document_store_refused}
  @project_fields ~w(version project_id worktree_id scope root primary_root common_directory binding_sha256)
  @binding_fields ~w(kind version namespace profile operator_binding project session_id identity_sha256 request_sha256)

  def operation?(r), do: is_map(r) and r["op"] == "collection.store"
  def mutating?(r), do: operation?(r) and DocumentStage.mutating?(r["request"])

  def validate(r) do
    if exact?(r, ~w(op scope request)) and operation?(r) and r["scope"] == "project" and
         DocumentStage.request?(r["request"]) and Extension.validate(r) == :ok,
       do: :ok,
       else: @error
  rescue
    _ -> @error
  end

  def operator_binding?(b),
    do:
      b === %{
        "version" => 1,
        "id" => "documents",
        "scope" => "project",
        "profile" => Profile.documents()
      }

  def trust_bindings?(bindings) when is_list(bindings) do
    length(bindings) <= 8 and
      Enum.all?(bindings, fn b ->
        exact?(b, ~w(version instance id scope profile)) and
          is_binary(b["instance"]) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, b["instance"]) and
          operator_binding?(Map.delete(b, "instance"))
      end) and length(Enum.uniq_by(bindings, & &1["instance"])) == length(bindings)
  end

  def trust_bindings?(_), do: false

  @doc "Resolve existing identity outside Session; this never admits or joins a project."
  def prepare(home, cwd, identity, request, session_id) do
    with :ok <- validate(request),
         true <- selected?(identity),
         {:ok, project} when is_map(project) <- ProjectIdentity.existing(home, cwd),
         true <- project?(project),
         binding = %{
           "kind" => "document_store",
           "version" => 1,
           "namespace" => namespace(project["project_id"]),
           "profile" => Profile.documents(),
           "operator_binding" => identity["collection_binding"],
           "project" => project,
           "session_id" => session_id,
           "identity_sha256" => JSON.digest([identity]),
           "request_sha256" => JSON.digest([request])
         },
         true <- valid_binding?(binding, request, identity) do
      {:ok, binding}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def valid_binding?(b, request, identity) do
    validate(request) == :ok and selected?(identity) and exact?(b, @binding_fields) and
      b["kind"] == "document_store" and b["version"] === 1 and
      b["profile"] == Profile.documents() and
      b["operator_binding"] === identity["collection_binding"] and
      project?(b["project"]) and b["namespace"] == namespace(b["project"]["project_id"]) and
      id?(b["session_id"]) and b["identity_sha256"] == JSON.digest([identity]) and
      b["request_sha256"] == JSON.digest([request]) and Extension.validate(b) == :ok
  rescue
    _ -> false
  end

  def execute(context, intent) do
    b = intent["effect_binding"]

    with true <- valid_binding?(b, intent["request"], context.identity),
         true <- b["session_id"] == context.session_id and intent["namespace"] == b["namespace"],
         true <- intent["parent_invocation_id"] == context.parent["invocation_id"],
         true <- Registry.live?(context.identity),
         :ok <-
           GenServer.call(context.owner, {:extension_document_current, context.job_ref, intent}) do
      Ipse.Session.Resources.file_effect(fn ->
        Ipse.Session.ManagedToolUse.with_effect(
          context.managed_tool,
          Ipse.Session.ManagedToolUse.document_binding(intent),
          fn deadline ->
            if mutating?(intent["request"]) and not is_nil(deadline) do
              @error
            else
              binding_use =
                if is_nil(deadline),
                  do: &ProjectIdentity.with_existing_binding/4,
                  else: &ProjectIdentity.with_held_binding/4

              binding_use.(context.config[:home], context.cwd, b["project"], fn _ ->
                with :ok <-
                       GenServer.call(
                         context.owner,
                         {:extension_document_current, context.job_ref, intent}
                       ) do
                  DocumentStage.execute(
                    root(context.config[:home]),
                    b["namespace"],
                    intent["request"]["request"],
                    intent["operation_id"],
                    %{
                      "project_id" => b["project"]["project_id"],
                      "session_id" => context.session_id,
                      "identity_sha256" => JSON.digest([context.identity]),
                      "invocation_id" => intent["parent_invocation_id"]
                    },
                    if(is_nil(deadline), do: [], else: [publish_before_ms: deadline])
                  )
                else
                  _ -> @error
                end
              end)
            end
          end
        )
      end)
      |> normalize(intent)
    else
      _ -> failed()
    end
  rescue
    _ -> :unknown
  catch
    :exit, _ -> :unknown
  end

  def root(home), do: Path.join(home, "document-collections")

  def namespace(project_id),
    do: JSON.digest(["document-store", 1, Profile.documents(), project_id])

  def valid_outcome?(request, status, value, operation_id) do
    with :ok <- validate(request),
         true <- is_map(value) and Extension.validate(value) == :ok do
      cond do
        status in ~w(unknown denied) ->
          value == %{}

        status == "failed" ->
          value == %{"code" => "document_store_refused"} or
            (mutating?(request) and value == %{"code" => "document_store_deadline_unavailable"})

        status in ~w(ok conflict) ->
          exact?(value, ~w(version operation_id request_sha256 result)) and value["version"] === 1 and
            value["operation_id"] == operation_id and
            value["request_sha256"] == JSON.digest([request]) and
            result?(request["request"], status, value["result"])

        true ->
          false
      end
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def bound_outcome?(event) do
    if get_in(event, ["outcome", "status"]) == "ok" and
         not mutating?(event["request"]),
       do:
         get_in(event, ["outcome", "value", "result", "project"]) ==
           get_in(event, ["effect_binding", "namespace"]),
       else: true
  end

  defp result?(r, "ok", v) do
    cond do
      r["op"] == "value.write_parts" ->
        next = r["offset"] + Enum.sum(Enum.map(r["data"], &byte_size/1))

        state =
          if next == r["byte_count"],
            do: if(r["publish"], do: "published", else: "sealed"),
            else: "open"

        exact?(v, ~w(generation floor request_sha256 write)) and
          mutation_summary?(r, Map.take(v, ~w(generation floor request_sha256))) and
          exact?(
            v["write"],
            ~w(slot epoch key expected_revision byte_count sha256 offset state expires_at_ms publish revision)
          ) and
          Map.take(v["write"], ~w(slot epoch key expected_revision byte_count sha256 publish)) ===
            Map.take(r, ~w(slot epoch key expected_revision byte_count sha256 publish)) and
          v["write"]["offset"] === next and v["write"]["state"] == state and
          JSON.safe_uint?(v["write"]["expires_at_ms"]) and v["write"]["expires_at_ms"] > 0 and
          v["write"]["revision"] === if(state == "published", do: v["generation"], else: 0)

      r["op"] == "value.put_inline" ->
        exact?(v, ~w(generation floor request_sha256 key record)) and
          mutation_summary?(r, Map.take(v, ~w(generation floor request_sha256))) and
          v["key"] == r["key"] and exact?(v["record"], ~w(revision sha256 byte_count)) and
          v["record"]["revision"] == v["generation"] and
          v["record"]["sha256"] == r["sha256"] and
          v["record"]["byte_count"] === r["byte_count"]

      r["op"] == "value.prepare_inline" ->
        exact?(v, ~w(generation floor request_sha256 stage)) and
          mutation_summary?(r, Map.take(v, ~w(generation floor request_sha256))) and
          exact?(
            v["stage"],
            ~w(version slot epoch key expected_revision byte_count sha256 state offset expires_at_ms)
          ) and
          v["stage"]["version"] === 1 and v["stage"]["state"] == "sealed" and
          Map.take(v["stage"], ~w(slot epoch key expected_revision byte_count sha256)) ===
            Map.take(r, ~w(slot epoch key expected_revision byte_count sha256)) and
          v["stage"]["offset"] === r["byte_count"] and
          JSON.safe_uint?(v["stage"]["expires_at_ms"])

      DocumentStage.mutating?(r) ->
        mutation_summary?(r, v)

      r["op"] == "snapshot" ->
        summary?(v) or
          (exact?(v, ~w(version project generation floor floor_anchor document_store)) and
             summary?(Map.delete(v, "document_store")) and
             v["document_store"] in [
               %{"version" => 1, "inline_bytes" => 8192},
               %{"version" => 2, "inline_bytes" => 8192, "write_parts" => 2}
             ])

      r["op"] == "stage.list" ->
        exact?(v, ~w(version project generation floor floor_anchor stages)) and
          summary?(Map.delete(v, "stages")) and is_list(v["stages"]) and length(v["stages"]) <= 16 and
          Enum.all?(v["stages"], fn row ->
            exact?(row, ~w(slot epoch state byte_count offset expires_at_ms)) and
              is_integer(row["slot"]) and row["slot"] in 0..15 and id?(row["epoch"]) and
              row["state"] in ~w(open sealed) and JSON.safe_uint?(row["byte_count"]) and
              JSON.safe_uint?(row["offset"]) and JSON.safe_uint?(row["expires_at_ms"])
          end)

      r["op"] == "value.read" ->
        exact?(
          v,
          ~w(version project generation floor floor_anchor sha256 byte_count key revision offset data next)
        ) and
          summary?(Map.take(v, ~w(version project generation floor floor_anchor))) and
          v["generation"] == r["generation"] and v["key"] == r["key"] and
          v["offset"] == r["offset"] and
          JSON.sha256?(v["sha256"]) and JSON.safe_uint?(v["byte_count"]) and
          JSON.safe_uint?(v["revision"]) and v["revision"] in 1..v["generation"] and
          is_binary(v["data"]) and byte_size(v["data"]) <= 6144 and
          (v["next"] == v["offset"] + byte_size(v["data"]) or
             (is_nil(v["next"]) and v["byte_count"] == v["offset"] + byte_size(v["data"])))

      r["op"] == "stage.inspect" ->
        exact?(v, ~w(version project generation floor floor_anchor stage)) and
          summary?(Map.take(v, ~w(version project generation floor floor_anchor))) and
          v["generation"] == r["generation"] and
          exact?(
            Map.delete(v["stage"], "write_publish"),
            ~w(slot epoch key expected_revision byte_count sha256 state offset expires_at_ms)
          ) and
          (not Map.has_key?(v["stage"], "write_publish") or
             is_boolean(v["stage"]["write_publish"])) and
          v["stage"]["slot"] == r["slot"] and v["stage"]["epoch"] == r["epoch"] and
          v["stage"]["state"] in ~w(open sealed) and
          Enum.all?(
            ~w(expected_revision byte_count offset expires_at_ms),
            &JSON.safe_uint?(v["stage"][&1])
          ) and
          Ipse.Extension.Collection.Directory.key?(v["stage"]["key"]) and
          not String.starts_with?(v["stage"]["key"], "host.") and
          v["stage"]["expected_revision"] <= v["generation"] and
          v["stage"]["byte_count"] in 2..61_440 and
          v["stage"]["offset"] <= v["stage"]["byte_count"] and JSON.sha256?(v["stage"]["sha256"])

      r["op"] == "value.stat" ->
        exact?(v, ~w(version project generation floor floor_anchor key record)) and
          summary?(Map.take(v, ~w(version project generation floor floor_anchor))) and
          v["generation"] == r["generation"] and v["key"] == r["key"] and
          (is_nil(v["record"]) or
             (exact?(v["record"], ~w(revision sha256 byte_count)) and
                JSON.safe_uint?(v["record"]["revision"]) and v["record"]["revision"] > 0 and
                v["record"]["revision"] <= v["generation"] and
                JSON.sha256?(v["record"]["sha256"]) and
                is_integer(v["record"]["byte_count"]) and v["record"]["byte_count"] in 2..61_440))

      r["op"] == "value.index" ->
        exact?(v, ~w(version project generation floor floor_anchor records next count coverage)) and
          summary?(Map.take(v, ~w(version project generation floor floor_anchor))) and
          v["generation"] === r["generation"] and v["coverage"] == "public_document_records" and
          is_integer(v["count"]) and v["count"] in 0..8192 and is_list(v["records"]) and
          length(v["records"]) <= r["limit"] and length(v["records"]) <= v["count"] and
          Enum.all?(v["records"], fn row ->
            exact?(row, ~w(key revision record_sha256 record_bytes)) and
              Ipse.Extension.Collection.Directory.key?(row["key"]) and
              not String.starts_with?(row["key"], "host.") and
              (is_nil(r["after"]) or row["key"] > r["after"]) and
              JSON.safe_uint?(row["revision"]) and row["revision"] in 1..v["generation"] and
              JSON.sha256?(row["record_sha256"]) and is_integer(row["record_bytes"]) and
              row["record_bytes"] in 2..65_536
          end) and
          Enum.map(v["records"], & &1["key"]) ===
            Enum.sort(Enum.uniq(Enum.map(v["records"], & &1["key"]))) and
          (is_nil(v["next"]) or
             (v["records"] != [] and v["next"] === List.last(v["records"])["key"])) and
          byte_size(Jason.encode!(v)) <= 4096

      true ->
        false
    end
  end

  defp result?(_, "conflict", v), do: summary?(v)

  defp mutation_summary?(r, v),
    do:
      exact?(v, ~w(generation floor request_sha256)) and
        v["generation"] == r["generation"] + 1 and JSON.safe_uint?(v["floor"]) and
        v["floor"] <= v["generation"] and JSON.sha256?(v["request_sha256"])

  defp summary?(v),
    do:
      exact?(v, ~w(version project generation floor floor_anchor)) and v["version"] === 3 and
        JSON.sha256?(v["project"]) and JSON.safe_uint?(v["generation"]) and
        JSON.safe_uint?(v["floor"]) and
        v["floor"] <= v["generation"] and (is_nil(v["floor_anchor"]) or id?(v["floor_anchor"]))

  defp normalize({status, result}, intent) when status in [:ok, :conflict] do
    value = %{
      "version" => 1,
      "operation_id" => intent["operation_id"],
      "request_sha256" => JSON.digest([intent["request"]]),
      "result" => result
    }

    if valid_outcome?(intent["request"], Atom.to_string(status), value, intent["operation_id"]),
      do: {status, value},
      else: :unknown
  end

  defp normalize(:unknown, _), do: :unknown
  defp normalize({:unknown, _}, _), do: :unknown

  defp normalize({:error, :collection_deadline_fence_unavailable}, intent) do
    if mutating?(intent["request"]),
      do: {:failed, %{"code" => "document_store_deadline_unavailable"}},
      else: failed()
  end

  defp normalize(_, _), do: failed()
  defp failed, do: {:failed, %{"code" => "document_store_refused"}}

  defp selected?(identity),
    do:
      is_map(identity) and identity["scope"] == "operator" and
        "host.collection.store" in (identity["capabilities"] || []) and
        operator_binding?(identity["collection_binding"])

  defp project?(p),
    do:
      exact?(p, @project_fields) and p["version"] === 1 and
        Enum.all?(~w(project_id worktree_id binding_sha256), &JSON.sha256?(p[&1])) and
        p["scope"] in ~w(folder repository) and
        Enum.all?(~w(root primary_root), &(is_binary(p[&1]) and Path.type(p[&1]) == :absolute)) and
        (is_nil(p["common_directory"]) or
           (is_binary(p["common_directory"]) and Path.type(p["common_directory"]) == :absolute))

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
  defp exact?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
end
