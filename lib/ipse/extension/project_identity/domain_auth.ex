defmodule Ipse.Extension.ProjectIdentity.DomainAuth do
  @moduledoc """
  Private project-domain authentication primitives and bounded callback leases.

  A tag attests a trusted host invocation, not source truth, permission, freshness
  or import adoption. Call only through ProjectIdentity's checked callbacks.
  Collection proof authentication and the final sealed-page size belong to the
  eventual storage adapter. Trusted Core and cooperative protected files are the
  boundary; this does not contain hostile BEAM or arbitrary same-user code.
  """
  alias Ipse.{JSON, Session.Resources}
  @format "managed-metadata-v3"
  @slot {__MODULE__, :lease}
  @error {:error, :project_domain_auth_refused}
  @domain_bytes 196_608
  @namespaces 256
  @per_project 8
  @lifetime 5_000
  @input_bytes 1_048_576
  @body_bytes 6144

  defmodule Capability do
    @moduledoc false
    @enforce_keys [:owner, :ref, :verify, :seal]
    defstruct @enforce_keys

    defimpl Inspect do
      def inspect(_, _), do: "#ProjectIdentity.DomainAuth<private>"
    end
  end

  @doc false
  def limits,
    do: %{
      namespaces: @namespaces,
      per_project: @per_project,
      bytes: @domain_bytes,
      lifetime_ms: @lifetime,
      verify_calls: 128,
      seal_calls: 16,
      input_bytes: @input_bytes,
      body_bytes: @body_bytes
    }

  @doc false
  def scope?(s),
    do: keys?(s, ~w(namespace format)a) and JSON.sha256?(s.namespace) and s.format == @format

  @doc false
  def publication_scope?(s),
    do:
      keys?(s, ~w(namespace format operation_id initialize)a) and
        scope?(Map.take(s, ~w(namespace format)a)) and id?(s.operation_id) and
        is_boolean(s.initialize)

  @doc false
  def expected?(s),
    do:
      keys?(s, ~w(namespace format key_id fence_id operation_id)a) and
        scope?(Map.take(s, ~w(namespace format)a)) and
        Enum.all?(~w(key_id fence_id operation_id)a, &id?(s[&1]))

  @doc false
  def valid_keys?(keys, projects) do
    is_map(keys) and map_size(keys) <= 256 and
      byte_size(Jason.encode!(keys)) <= @domain_bytes and
      Enum.all?(keys, fn {project, record} ->
        Map.has_key?(projects, project) and key_record?(record)
      end) and
      Enum.sum(Enum.map(keys, fn {_, record} -> map_size(record["namespaces"]) end)) <=
        @namespaces
  rescue
    _ -> false
  end

  defp key_record?(r) do
    keys?(r, ~w(version key_id master namespaces)) and r["version"] === 1 and
      id?(r["key_id"]) and match?({:ok, _}, master(r["master"])) and
      is_map(r["namespaces"]) and map_size(r["namespaces"]) <= @per_project and
      Enum.all?(r["namespaces"], fn {namespace, entry} ->
        JSON.sha256?(namespace) and entry?(entry)
      end)
  end

  defp entry?(e),
    do:
      keys?(e, ~w(version format fence_id state first_operation_id first_root_sha256)) and
        e["version"] === 1 and e["format"] == @format and id?(e["fence_id"]) and
        id?(e["first_operation_id"]) and
        ((e["state"] == "prepared" and is_nil(e["first_root_sha256"])) or
           (e["state"] == "active" and JSON.sha256?(e["first_root_sha256"])))

  @doc false
  def select(state, project, scope, status \\ "active") do
    with true <- scope?(Map.take(scope, ~w(namespace format)a)),
         record when is_map(record) <- get_in(state, ["domain_keys", project]),
         entry when is_map(entry) <- record["namespaces"][scope.namespace],
         true <- entry["format"] == scope.format and entry["state"] == status do
      {:ok, record, entry}
    else
      _ -> {:error, :project_domain_unavailable}
    end
  end

  @doc false
  def prepare(state, project, scope) do
    with true <- publication_scope?(scope) do
      case select(state, project, scope) do
        {:ok, record, entry} -> {:ok, state, record, entry, false}
        _ -> prepare_missing(state, project, scope)
      end
    else
      _ -> @error
    end
  end

  defp prepare_missing(state, project, %{initialize: true} = s) do
    all = Map.get(state, "domain_keys", %{})

    record =
      all[project] ||
        %{
          "version" => 1,
          "key_id" => id(),
          "master" => Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false),
          "namespaces" => %{}
        }

    if Map.has_key?(record["namespaces"], s.namespace) do
      {:error, :project_domain_initialization_pending}
    else
      entry = %{
        "version" => 1,
        "format" => s.format,
        "fence_id" => id(),
        "state" => "prepared",
        "first_operation_id" => s.operation_id,
        "first_root_sha256" => nil
      }

      record = put_in(record["namespaces"][s.namespace], entry)

      next =
        state |> Map.put("version", 2) |> Map.put("domain_keys", Map.put(all, project, record))

      if valid_keys?(next["domain_keys"], next["projects"]),
        do: {:ok, next, record, entry, true},
        else: {:error, :project_identity_capacity}
    end
  end

  defp prepare_missing(_, _, _), do: {:error, :project_domain_unavailable}

  @doc false
  def activate(state, project, scope, entry, witness) do
    with true <- witness?(witness, scope, entry),
         true <- get_in(state, ["domain_keys", project, "namespaces", scope.namespace]) === entry,
         true <- entry["state"] == "prepared" do
      active = %{entry | "state" => "active", "first_root_sha256" => witness.root_sha256}
      {:ok, put_in(state, ["domain_keys", project, "namespaces", scope.namespace], active)}
    else
      _ -> @error
    end
  end

  @doc false
  def witness?(w, s, e),
    do:
      keys?(w, ~w(version namespace format fence_id operation_id root_sha256)a) and
        w.version === 1 and w.namespace == s.namespace and w.format == s.format and
        w.fence_id == e["fence_id"] and w.operation_id == e["first_operation_id"] and
        JSON.sha256?(w.root_sha256)

  @doc false
  def receipt(record, entry, namespace),
    do: %{
      "version" => 1,
      "namespace" => namespace,
      "key_id" => record["key_id"],
      "fence_id" => entry["fence_id"],
      "format" => entry["format"],
      "state" => entry["state"]
    }

  @doc false
  def with_auth(record, entry, project, scope, mode, fun) when mode in [:verify, :publish] do
    owner = self()
    upstream = Resources.file_effect_owner()
    ref = make_ref()

    with nil <- Process.get(@slot),
         true <- Process.alive?(upstream),
         {:ok, secret} <- master(record["master"]) do
      derivation = %{
        "domain" => "ipse.project.namespace-key",
        "version" => 1,
        "project_id" => project,
        "namespace" => scope.namespace,
        "format" => scope.format,
        "key_id" => record["key_id"]
      }

      key = :crypto.mac(:hmac, :sha256, secret, JSON.digest([derivation]))

      fixed =
        Map.merge(derivation, %{"domain" => "ipse.managed.page", "fence_id" => entry["fence_id"]})

      Process.put(@slot, %{ref: ref, deadline: now() + @lifetime, verify: 0, seal: 0, bytes: 0})

      verify = fn context, body, tag ->
        crypto(owner, upstream, ref, fixed, key, :verify, scope, context, body, tag)
      end

      seal =
        if mode == :publish,
          do: fn context, body ->
            crypto(owner, upstream, ref, fixed, key, :seal, scope, context, body, nil)
          end

      cap = %Capability{owner: owner, ref: ref, verify: verify, seal: seal}

      try do
        result = fun.(cap, receipt(record, entry, scope.namespace))

        case Process.get(@slot) do
          %{ref: ^ref, deadline: deadline} ->
            if Process.alive?(upstream) and now() < deadline,
              do: result,
              else: {:unknown, :project_domain_callback_expired}

          _ ->
            {:unknown, :project_domain_callback_expired}
        end
      after
        Process.delete(@slot)
      end
    else
      _ -> @error
    end
  end

  @doc "Internal exact-owner tag primitive; no sealed-page wrapper or current authority is implied."
  def seal(%Capability{owner: owner, seal: fun}, context, body)
      when owner == self() and is_function(fun, 2),
      do: fun.(context, body)

  def seal(_, _, _), do: @error

  @doc false
  def verify(%Capability{owner: owner, verify: fun}, context, body, tag)
      when owner == self() and is_function(fun, 3) do
    fun.(context, body, tag)
  end

  def verify(_, _, _, _), do: @error

  defp crypto(owner, upstream, ref, fixed, key, action, scope, context, body, tag) do
    with true <- self() == owner and Process.alive?(upstream),
         %{ref: ^ref} = lease <- Process.get(@slot),
         true <- now() < lease.deadline,
         true <- context?(context) and is_binary(body) and byte_size(body) in 1..@body_bytes,
         true <- action != :seal or context["operation_id"] == scope.operation_id,
         true <- action != :verify or (is_binary(tag) and byte_size(tag) == 32),
         limit = if(action == :seal, do: 16, else: 128),
         input_size = 64 + byte_size(body),
         true <- lease[action] < limit and lease.bytes + input_size <= @input_bytes do
      Process.put(
        @slot,
        lease |> Map.update!(action, &(&1 + 1)) |> Map.update!(:bytes, &(&1 + input_size))
      )

      expected = :crypto.mac(:hmac, :sha256, key, [JSON.digest([fixed, context]), body])
      if action == :seal, do: {:ok, expected}, else: :crypto.hash_equals(tag, expected)
    else
      _ -> @error
    end
  end

  @doc false
  def context?(c),
    do:
      keys?(c, ~w(version schema page_key kind operation_id revision)) and c["version"] === 1 and
        c["schema"] === 3 and c["kind"] in ~w(anchor live format) and id?(c["operation_id"]) and
        JSON.safe_uint?(c["revision"]) and c["revision"] > 0 and
        is_binary(c["page_key"]) and byte_size(c["page_key"]) <= 96 and
        Regex.match?(~r/\Ahost\.validity\.[A-Za-z0-9_.-]+\z/, c["page_key"])

  defp master(value) when is_binary(value) and byte_size(value) == 43 do
    with {:ok, bytes} <- Base.url_decode64(value, padding: false),
         true <- byte_size(bytes) == 32 and Base.url_encode64(bytes, padding: false) == value,
         do: {:ok, bytes},
         else: (_ -> @error)
  end

  defp master(_), do: @error
  defp keys?(v, keys), do: is_map(v) and Enum.sort(Map.keys(v)) == Enum.sort(keys)
  defp id, do: Ipse.Usage.id()
  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp now, do: System.monotonic_time(:millisecond)
end
