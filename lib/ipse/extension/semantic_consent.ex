defmodule Ipse.Extension.SemanticConsent do
  @moduledoc """
  Pure reviewed semantic-policy admission for trusted host adapters.

  These functions perform no IO and attest no operator interaction. Setup must
  separately establish the operator channel, executable artifact trust and a
  freshly revalidated ProjectIdentity binding before saving `prepare/3`'s policy
  through Consent.replace. Project configuration cannot call this into authority.
  A Session saves `admit/3`'s pin in its journal metadata. Resume preserves that
  pin, including nil, rather than activating a grant saved after Session creation.

  The host, never worker data, maps exact outer exports and inner requests to
  reviewed effects. `authorize/5` checks that mapping and produces a reservation
  request; Consent.reserve/admit/publish remain mandatory durable boundaries.
  Source origin, exact quotes, suppression and source-window generations must be
  verified by the source owner before constructing the effect context. No semantic
  label grants workspace, shell, MCP, service or delegation authority.
  """
  alias Ipse.{JSON, Extension.Consent, Extension.Mode}
  @error {:error, :semantic_consent_denied}
  @settings ~w(version domain instance identity_sha256 namespace scope sources storage retention routes effects)
  @selection ~w(domain namespace scope sources storage retention routes effects limits period_ms expires_at_ms headless)
  @pin ~w(version session_id project_id worktree_id binding_sha256 epoch policy_sha256 identity_sha256 namespace routes_sha256 source_sha256)
  @context ~w(session_id binding identity namespace routes mode source_generation)
  @effect ~w(id operation class outer_sha256 inner_op request_sha256 source_generation sources reserved)
  @mapping ~w(operation class outer_sha256 inner_op)
  @route ~w(operation provider profile model endpoint service_id billing_mode processing_region storage_region cache_retention account_controls)

  @doc "Build the exact policy shown by an operator setup UI; does not save or grant it."
  def prepare(binding, identity, selection) do
    with true <- binding?(binding) and identity?(identity) and keys?(selection, @selection),
         settings =
           selection
           |> Map.take(@settings)
           |> Map.merge(%{
             "version" => 1,
             "instance" => identity["instance"],
             "identity_sha256" => JSON.digest([identity])
           }),
         true <- settings?(settings),
         true <- scope?(settings["scope"], binding),
         policy =
           selection
           |> Map.take(~w(limits period_ms expires_at_ms headless))
           |> Map.merge(%{
             "version" => 1,
             "project" => binding["project_id"],
             "artifact_sha256" => identity["artifact_sha256"],
             "source_sha256" => JSON.digest([settings["sources"]]),
             "operations" =>
               settings["effects"] |> Enum.map(& &1["operation"]) |> Enum.uniq() |> Enum.sort(),
             "settings" => settings
           }),
         true <- policy?(policy) do
      {:ok, policy}
    else
      _ -> {:error, :invalid_semantic_selection}
    end
  rescue
    _ -> {:error, :invalid_semantic_selection}
  end

  @doc "Only a fresh Session may take current saved permission into its metadata."
  def admit(snapshot, context, now) do
    with true <- context?(context) and JSON.safe_uint?(now),
         true <- is_map(snapshot) and JSON.safe_uint?(snapshot["epoch"]),
         policy when is_map(policy) <- snapshot["policy"],
         true <- policy?(policy) and policy["expires_at_ms"] > now,
         true <- matches?(policy, context) do
      {:ok,
       %{
         "version" => 1,
         "session_id" => context["session_id"],
         "project_id" => context["binding"]["project_id"],
         "worktree_id" => context["binding"]["worktree_id"],
         "binding_sha256" => context["binding"]["binding_sha256"],
         "epoch" => snapshot["epoch"],
         "policy_sha256" => JSON.digest([policy]),
         "identity_sha256" => JSON.digest([context["identity"]]),
         "namespace" => context["namespace"],
         "routes_sha256" => JSON.digest([context["routes"]]),
         "source_sha256" => policy["source_sha256"]
       }}
    else
      nil -> {:ok, nil}
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Preserve a saved Session pin; current revocation is checked at every effect."
  def resume(nil, context), do: if(context?(context), do: {:ok, nil}, else: @error)

  def resume(pin, context) do
    if pin?(pin) and context?(context) and pin_context?(pin, context),
      do: {:ok, pin},
      else: @error
  rescue
    _ -> @error
  end

  @doc "Validate host-classified outer/inner coverage and return a durable reservation request."
  def authorize(pin, snapshot, context, effect, now) do
    if is_map(effect) and effect["class"] == "collection.read",
      do: {:error, :semantic_read_requires_check},
      else: authorization(pin, snapshot, context, effect, now)
  end

  @doc "Check a local collection read without creating a durable reservation or consuming a period ID."
  def check(pin, snapshot, context, effect, now) do
    if is_map(effect) and effect["class"] == "collection.read" do
      case authorization(pin, snapshot, context, effect, now) do
        {:ok, _} -> :ok
        _ -> @error
      end
    else
      @error
    end
  end

  defp authorization(pin, snapshot, context, effect, now) do
    with true <- pin?(pin) and context?(context) and effect?(effect),
         true <- JSON.safe_uint?(now) and pin_context?(pin, context),
         true <- is_map(snapshot) and snapshot["epoch"] === pin["epoch"],
         policy when is_map(policy) <- snapshot["policy"],
         true <- policy?(policy) and policy["expires_at_ms"] > now,
         true <- JSON.digest([policy]) == pin["policy_sha256"] and matches?(policy, context),
         true <- effect["source_generation"] === context["source_generation"],
         true <-
           Enum.any?(policy["settings"]["effects"], fn mapping ->
             Map.take(mapping, @mapping) === Map.take(effect, @mapping)
           end),
         true <- source?(policy["settings"]["sources"], effect),
         true <-
           effect["class"] == "collection.read" or within?(effect["reserved"], policy["limits"]),
         true <- funded?(policy["settings"]["routes"], effect),
         :ok <- Mode.knowledge(context["mode"], effect["class"]),
         headless = context["mode"]["headless"],
         true <- not headless or policy["headless"] do
      {:ok,
       %{
         "id" => effect["id"],
         "operation" => effect["operation"],
         "artifact_sha256" => policy["artifact_sha256"],
         "source_sha256" => pin["source_sha256"],
         "policy_sha256" => pin["policy_sha256"],
         "request_sha256" => effect["request_sha256"],
         "source_generation" => effect["source_generation"],
         "reserved" => effect["reserved"],
         "headless" => headless
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def policy?(policy) do
    Consent.valid_policy?(policy) and settings?(policy["settings"]) and
      namespace(policy["project"], policy["settings"]["storage"]["collection"]) ===
        {:ok, policy["settings"]["namespace"]} and
      policy["source_sha256"] == JSON.digest([policy["settings"]["sources"]]) and
      policy["operations"] ==
        policy["settings"]["effects"] |> Enum.map(& &1["operation"]) |> Enum.uniq() |> Enum.sort()
  rescue
    _ -> false
  end

  def settings?(settings) do
    keys?(settings, @settings) and settings["version"] === 1 and
      id?(settings["domain"]) and id?(settings["instance"]) and
      JSON.sha256?(settings["identity_sha256"]) and JSON.sha256?(settings["namespace"]) and
      scope?(settings["scope"]) and sources?(settings["sources"]) and
      storage?(settings["storage"]) and retention?(settings["retention"]) and
      routes?(settings["routes"]) and mappings?(settings["effects"]) and
      Enum.all?(settings["effects"], fn e ->
        e["class"] in ~w(collection.read collection.publish) or
          Enum.any?(settings["routes"], &(&1["operation"] == e["class"]))
      end) and bounded?(settings)
  rescue
    _ -> false
  end

  def pin?(pin) do
    keys?(pin, @pin) and pin["version"] === 1 and uuid?(pin["session_id"]) and
      JSON.safe_uint?(pin["epoch"]) and
      Enum.all?(@pin -- ~w(version session_id epoch), &JSON.sha256?(pin[&1]))
  end

  def context?(c) do
    keys?(c, @context) and uuid?(c["session_id"]) and binding?(c["binding"]) and
      identity?(c["identity"]) and JSON.sha256?(c["namespace"]) and routes?(c["routes"]) and
      Mode.valid?(c["mode"]) and JSON.safe_uint?(c["source_generation"])
  end

  defp matches?(p, c) do
    s = p["settings"]

    p["project"] == c["binding"]["project_id"] and
      p["artifact_sha256"] == c["identity"]["artifact_sha256"] and
      s["identity_sha256"] == JSON.digest([c["identity"]]) and
      s["instance"] == c["identity"]["instance"] and s["namespace"] == c["namespace"] and
      s["routes"] === c["routes"] and scope?(s["scope"], c["binding"])
  end

  defp pin_context?(p, c) do
    p["session_id"] == c["session_id"] and p["project_id"] == c["binding"]["project_id"] and
      p["worktree_id"] == c["binding"]["worktree_id"] and
      p["binding_sha256"] == c["binding"]["binding_sha256"] and
      p["identity_sha256"] == JSON.digest([c["identity"]]) and
      p["namespace"] == c["namespace"] and p["routes_sha256"] == JSON.digest([c["routes"]])
  end

  defp effect?(e) do
    keys?(e, @effect) and uuid?(e["id"]) and mapping?(Map.take(e, @mapping)) and
      JSON.sha256?(e["request_sha256"]) and JSON.safe_uint?(e["source_generation"]) and
      evidence_rows?(e["sources"]) and
      if(e["class"] == "collection.read", do: e["sources"] === [], else: e["sources"] != []) and
      vector?(e["reserved"]) and
      (e["class"] != "collection.read" or e["reserved"] === Consent.zero()) and
      e["reserved"]["operations"] === if(e["class"] == "collection.read", do: 0, else: 1) and
      if(e["class"] in ~w(collection.read collection.publish),
        do: e["reserved"]["model_calls"] === 0,
        else: e["reserved"]["model_calls"] > 0
      )
  end

  defp source?(s, e) do
    Enum.all?(e["sources"], fn source ->
      source["category"] in s["categories"] and
        (is_nil(source["path"]) or
           not Enum.any?(s["exclusions"], fn excluded ->
             source["path"] == excluded or
               (String.ends_with?(excluded, "/") and String.starts_with?(source["path"], excluded))
           end))
    end)
  end

  defp evidence_rows?(sources),
    do:
      is_list(sources) and length(sources) <= 64 and
        Enum.all?(sources, fn source ->
          keys?(source, ~w(category path)) and id?(source["category"]) and
            (is_nil(source["path"]) or relative?(source["path"]))
        end)

  defp funded?(routes, effect) do
    case Enum.find(routes, &(&1["operation"] == effect["class"])) do
      %{"billing_mode" => "api"} -> effect["reserved"]["cost_nanos"] > 0
      _ -> true
    end
  end

  defp scope?(s),
    do:
      keys?(s, ~w(kind worktree_id)) and
        ((s["kind"] == "project" and is_nil(s["worktree_id"])) or
           (s["kind"] == "worktree" and JSON.sha256?(s["worktree_id"])))

  defp scope?(s, b),
    do:
      scope?(s) and
        (s["kind"] == "project" or s["worktree_id"] == b["worktree_id"])

  defp sources?(s),
    do:
      keys?(s, ~w(categories exclusions)) and
        sorted?(s["categories"], 1, 16, &id?/1) and sorted?(s["exclusions"], 0, 64, &exclusion?/1)

  defp storage?(s),
    do: keys?(s, ~w(kind collection)) and s["kind"] == "local_collection" and id?(s["collection"])

  defp retention?(r),
    do:
      is_map(r) and map_size(r) in 1..16 and
        Enum.all?(r, fn {category, days} ->
          id?(category) and is_integer(days) and days in 1..36_500
        end)

  defp routes?(r),
    do:
      is_list(r) and length(r) in 1..8 and Enum.any?(r, &(&1["operation"] == "main")) and
        Enum.all?(r, &route?/1) and Enum.sort_by(r, & &1["operation"]) === r and
        length(Enum.uniq_by(r, & &1["operation"])) == length(r)

  defp route?(r),
    do:
      keys?(r, @route) and
        r["operation"] in ~w(main model.complete embedding.create decision.create) and
        if(r["operation"] == "main", do: is_nil(r["profile"]), else: id?(r["profile"])) and
        id?(r["provider"]) and (is_nil(r["profile"]) or id?(r["profile"])) and
        text?(r["model"], 200) and endpoint?(r["endpoint"], r["provider"]) and
        id?(r["service_id"]) and
        r["billing_mode"] in ~w(subscription api local none) and billing?(r) and
        Enum.all?(
          ~w(processing_region storage_region cache_retention account_controls),
          &(is_nil(r[&1]) or text?(r[&1], 512))
        )

  defp mappings?(es),
    do:
      is_list(es) and length(es) in 1..16 and Enum.all?(es, &mapping?/1) and
        length(Enum.uniq_by(es, &Map.take(&1, @mapping))) == length(es) and
        Enum.sort_by(es, &{&1["operation"], &1["class"], &1["outer_sha256"], &1["inner_op"]}) ===
          es

  defp mapping?(e),
    do:
      (keys?(e, @mapping) or
         (keys?(e, ["constraints" | @mapping]) and e["class"] == "collection.publish" and
            Ipse.Extension.CollectionPolicy.valid_constraints?(e["constraints"]))) and
        id?(e["operation"]) and e["class"] in Mode.classes() and
        JSON.sha256?(e["outer_sha256"]) and
        ((e["class"] in ~w(collection.read collection.publish) and
            e["inner_op"] == "collection.call") or
           (e["class"] in ~w(model.complete embedding.create decision.create) and
              e["inner_op"] == e["class"]))

  @doc false
  def binding?(b),
    do:
      keys?(
        b,
        ~w(version project_id worktree_id scope root primary_root common_directory binding_sha256)
      ) and
        b["version"] === 1 and b["scope"] in ~w(repository folder) and
        Enum.all?(~w(project_id worktree_id binding_sha256), &JSON.sha256?(b[&1])) and
        Enum.all?(~w(root primary_root), &absolute?(b[&1])) and
        (is_nil(b["common_directory"]) or absolute?(b["common_directory"]))

  defp identity?(identity), do: Ipse.Extension.Registry.valid_identity?(identity)

  @doc "Derive the host collection namespace; a supplied project ID is not identity proof."
  def namespace(project_id, collection_id) do
    if JSON.sha256?(project_id) and id?(collection_id),
      do:
        {:ok,
         JSON.digest([%{"version" => 1, "project" => project_id, "collection" => collection_id}])},
      else: {:error, :invalid_collection_namespace}
  end

  defp vector?(v),
    do: keys?(v, Consent.resources()) and Enum.all?(v, fn {_, n} -> JSON.safe_uint?(n) end)

  defp within?(v, limit), do: vector?(limit) and Enum.all?(v, fn {key, n} -> n <= limit[key] end)

  defp sorted?(xs, low, high, fun),
    do:
      is_list(xs) and length(xs) in low..high and
        xs === Enum.sort(Enum.uniq(xs)) and Enum.all?(xs, fun)

  defp billing?(r) do
    case Ipse.Provider.Registry.fetch(r["provider"]) do
      {:ok, spec} -> r["billing_mode"] == spec.billing_mode
      :error -> r["billing_mode"] != "none"
    end
  end

  defp endpoint?("demo://local", "demo"), do: true
  defp endpoint?(_, "demo"), do: false

  defp endpoint?(s, provider) when is_binary(s) do
    u = URI.parse(s)

    query =
      case Ipse.Provider.Registry.fetch(provider) do
        {:ok, spec} -> spec.wire_query
        :error -> nil
      end

    text?(s, 2048) and not Regex.match?(~r/\s/u, s) and is_binary(u.host) and u.host != "" and
      is_nil(u.userinfo) and u.query == query and is_nil(u.fragment) and
      (u.scheme == "https" or (u.scheme == "http" and u.host in ~w(localhost 127.0.0.1 ::1)))
  end

  defp endpoint?(_, _), do: false

  defp relative?(s),
    do:
      text?(s, 1024) and Path.type(s) == :relative and
        not String.contains?(s, ["\\", "//"]) and
        Enum.all?(String.split(s, "/"), &(&1 not in [".", ".."]))

  defp exclusion?(s), do: relative?(s) and not String.contains?(s, ["*", "?", "[", "]", "{", "}"])

  defp absolute?(s), do: text?(s, 4096) and Path.type(s) == :absolute
  defp uuid?(s), do: is_binary(s) and Regex.match?(~r/\A[0-9a-f]{32}\z/, s)
  defp id?(s), do: is_binary(s) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}\z/, s)

  defp text?(s, limit),
    do:
      is_binary(s) and byte_size(s) in 1..limit and String.valid?(s) and
        not Enum.any?(String.to_charlist(s), &(&1 < 32 or &1 == 127))

  defp keys?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)

  defp bounded?(m) do
    bytes = Jason.encode!(m)
    byte_size(bytes) <= 16_384 and JSON.decode_unique(bytes, 12) === {:ok, m}
  end
end
