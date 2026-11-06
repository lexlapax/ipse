defmodule Ipse.Extension.Collection.ManagedRetention do
  @moduledoc """
  Pure interpretation of already authenticated literal retention metadata.

  Callers must authenticate the actual anchor/live pages and source recipe under
  the owning current boundary. JSON-shaped rows, capsules or returned metadata
  grant no authority. Explicit native choices may change the effective deadline;
  the original automatic admission clocks remain separate and nonrenewable.
  """
  alias Ipse.{JSON, Extension.Collection.ManagedPages}
  @ordinary 90 * 86_400_000
  @history 365 * 86_400_000
  @error {:error, :managed_retention_refused}
  @categories ~w(ordinary preference current pin history)

  def policy?(%{"kind" => kind} = policy) when kind in ~w(pin ordinary session),
    do: map_size(policy) == 1

  def policy?(%{"kind" => "duration", "duration_ms" => duration} = policy),
    do: map_size(policy) == 2 and JSON.safe_uint?(duration) and duration > 0

  def policy?(_), do: false

  def command(%{"kind" => "session"}), do: "forget"
  def command(%{"kind" => kind}) when kind in ~w(pin ordinary duration), do: kind
  def command(_), do: nil

  @doc "An exact relative deadline rule shown before the native confirmation time is known."
  def deadline_rule(%{"kind" => "pin"} = policy) when map_size(policy) == 1, do: nil

  def deadline_rule(policy) do
    with true <- policy?(policy), age when is_integer(age) <- age(policy) do
      %{"basis" => "native_confirmation_time", "duration_ms" => age}
    else
      _ -> @error
    end
  end

  def selected(policy, at) do
    with true <- policy?(policy) and JSON.safe_uint?(at) do
      case policy["kind"] do
        "pin" ->
          {:ok, "pin", nil}

        "session" ->
          @error

        _ ->
          deadline = at + age(policy)
          if JSON.safe_uint?(deadline), do: {:ok, "ordinary", deadline}, else: @error
      end
    else
      _ -> @error
    end
  end

  @doc "Validate exact signed rows and retain the original publication policy independently of a choice."
  def metadata(candidate, value_sha256, anchor, live) do
    with true <- candidate["kind"] == "literal_source" and JSON.sha256?(value_sha256),
         lineage = candidate["lineage"],
         key = candidate["key"],
         true <- key == "note." <> lineage and JSON.sha256?(lineage),
         {:ok, _} <- ManagedPages.pack(:anchor, ManagedPages.zero(:anchor), %{lineage => anchor}),
         {:ok, _} <-
           ManagedPages.pack(:live, ManagedPages.zero(:live), %{
             ManagedPages.live_identity(key) => live
           }),
         %{"clocks" => [first, baseline, _, _], "choice" => choice, "retirement" => nil} <-
           anchor,
         true <- JSON.safe_uint?(first),
         [
           packed_lineage,
           packed_value,
           packed_recipe,
           packed_policy,
           live_first,
           live_deadline,
           category,
           0
         ] <- live,
         true <- unpack(packed_lineage) == lineage and unpack(packed_value) == value_sha256,
         true <- unpack(packed_recipe) == candidate["recipe_sha256"],
         {:ok, assigned, deadline} <- effective(candidate, first, baseline, choice, value_sha256),
         true <- live_first == number(first) and live_deadline == number(deadline),
         true <- Enum.at(@categories, category) == assigned,
         metadata = %{
           "lineage" => lineage,
           "recipe_sha256" => unpack(packed_recipe),
           "policy_sha256" => unpack(packed_policy),
           "first_admitted_ms" => first,
           "valid_until_ms" => deadline,
           "category" => assigned
         } do
      {:ok, if(is_nil(choice), do: metadata, else: Map.put(metadata, "choice", choice))}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Consistency only: the owning reader must separately authenticate this metadata and current sources."
  def eligible_metadata?(candidate, value_sha256, metadata, now) do
    choice = metadata["choice"]
    first = metadata["first_admitted_ms"]
    deadline = metadata["valid_until_ms"]
    fields = ~w(lineage recipe_sha256 policy_sha256 first_admitted_ms valid_until_ms category)
    fields = if is_nil(choice), do: fields, else: ["choice" | fields]
    anchor = %{"clocks" => [first, nil, nil, nil], "choice" => choice, "retirement" => nil}

    with true <- is_map(metadata) and Enum.sort(Map.keys(metadata)) == Enum.sort(fields),
         true <-
           metadata["lineage"] == candidate["lineage"] and
             metadata["recipe_sha256"] == candidate["recipe_sha256"],
         true <- JSON.sha256?(metadata["policy_sha256"]) and JSON.sha256?(value_sha256),
         true <- JSON.safe_uint?(first) and JSON.safe_uint?(now) and first <= now,
         true <-
           is_nil(deadline) or
             (JSON.safe_uint?(deadline) and deadline >= first and deadline > now),
         true <- is_nil(choice) or choice["observed_at_ms"] <= now,
         {:ok, _} <-
           ManagedPages.pack(:anchor, ManagedPages.zero(:anchor), %{
             candidate["lineage"] => anchor
           }),
         {:ok, assigned, ^deadline} <-
           effective(candidate, first, deadline, choice, value_sha256),
         true <- assigned == metadata["category"] do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def history_gap?(category, policy),
    do: category in ~w(preference current pin history) and policy["kind"] != "pin"

  @doc "Consistency only: an authenticated finite ordinary deadline has elapsed; persistent classes never expire here."
  def expired_metadata?(candidate, value_sha256, metadata, now) do
    deadline = metadata["valid_until_ms"]

    metadata["category"] == "ordinary" and JSON.safe_uint?(now) and
      JSON.safe_uint?(deadline) and deadline > 0 and deadline <= now and
      eligible_metadata?(candidate, value_sha256, metadata, deadline - 1)
  rescue
    _ -> false
  end

  @doc "Exact host history rule; ordinary corrections keep their old deadline and temporal support lasts 365 days."
  def history_rule(%{"category" => "ordinary", "valid_until_ms" => deadline}, "ordinary") do
    if JSON.safe_uint?(deadline) and deadline > 0,
      do: %{"basis" => "existing_deadline", "at_ms" => deadline},
      else: @error
  end

  def history_rule(%{"category" => category, "valid_until_ms" => nil}, "temporal")
      when category in ~w(current preference),
      do: %{"basis" => "native_confirmation_time", "duration_ms" => @history}

  def history_rule(%{"category" => "pin", "valid_until_ms" => nil}, "temporal"), do: nil
  def history_rule(_, _), do: @error

  def history_deadline(metadata, mode, at) do
    with true <- JSON.safe_uint?(at) do
      case history_rule(metadata, mode) do
        nil ->
          {:ok, nil}

        %{"basis" => "existing_deadline", "at_ms" => deadline} when deadline > at ->
          {:ok, deadline}

        %{"basis" => "native_confirmation_time", "duration_ms" => duration} ->
          deadline = at + duration
          if JSON.safe_uint?(deadline), do: {:ok, deadline}, else: @error

        _ ->
          @error
      end
    else
      _ -> @error
    end
  end

  @doc "Interpret an already authenticated retained literal and exact successor edge; this never grants current eligibility."
  def history_metadata(candidate, value_sha256, anchor, live) do
    with true <- candidate["kind"] == "literal_source" and JSON.sha256?(value_sha256),
         lineage = candidate["lineage"],
         key = candidate["key"],
         true <- key == "note." <> lineage and JSON.sha256?(lineage),
         {:ok, _} <- ManagedPages.pack(:anchor, ManagedPages.zero(:anchor), %{lineage => anchor}),
         {:ok, _} <-
           ManagedPages.pack(:live, ManagedPages.zero(:live), %{
             ManagedPages.live_identity(key) => live
           }),
         %{
           "clocks" => [first, baseline, _, _],
           "choice" => choice,
           "retirement" =>
             %{"record_key" => next_key, "record_value_sha256" => next_value, "at_ms" => at} =
               retired
         } <- anchor,
         true <- Enum.sort(Map.keys(retired)) == ~w(at_ms record_key record_value_sha256),
         true <- JSON.safe_uint?(first) and JSON.safe_uint?(at) and first <= at,
         true <- is_nil(choice) or choice["observed_at_ms"] <= at,
         "note." <> next_lineage <- next_key,
         true <-
           JSON.sha256?(next_lineage) and next_lineage != lineage and JSON.sha256?(next_value),
         {:ok, previous, previous_deadline} <-
           effective(candidate, first, baseline, choice, value_sha256),
         mode = if(previous == "ordinary", do: "ordinary", else: "temporal"),
         {:ok, deadline} <-
           history_deadline(
             %{"category" => previous, "valid_until_ms" => previous_deadline},
             mode,
             at
           ),
         [
           packed_lineage,
           packed_value,
           packed_recipe,
           packed_policy,
           live_first,
           live_deadline,
           4,
           2
         ] <- live,
         true <- unpack(packed_lineage) == lineage and unpack(packed_value) == value_sha256,
         true <- unpack(packed_recipe) == candidate["recipe_sha256"],
         true <- live_first == number(first) and live_deadline == number(deadline) do
      {:ok,
       %{
         "lineage" => lineage,
         "recipe_sha256" => unpack(packed_recipe),
         "policy_sha256" => unpack(packed_policy),
         "first_admitted_ms" => first,
         "valid_until_ms" => deadline,
         "category" => "history",
         "previous_category" => previous,
         "superseded_at_ms" => at,
         "choice" => choice,
         "successor" => %{"key" => next_key, "sha256" => next_value}
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Clock consistency only; callers must first authenticate the history closure and separately admit its source use."
  def eligible_history_metadata?(metadata, now) do
    metadata["category"] == "history" and JSON.safe_uint?(now) and
      JSON.safe_uint?(metadata["first_admitted_ms"]) and
      JSON.safe_uint?(metadata["superseded_at_ms"]) and
      metadata["first_admitted_ms"] <= metadata["superseded_at_ms"] and
      metadata["superseded_at_ms"] <= now and
      (is_nil(metadata["valid_until_ms"]) or
         (JSON.safe_uint?(metadata["valid_until_ms"]) and now < metadata["valid_until_ms"]))
  rescue
    _ -> false
  end

  @doc "Consistency only: signed finite history has elapsed; pinned history never expires here."
  def expired_history_metadata?(metadata, now) do
    deadline = metadata["valid_until_ms"]

    JSON.safe_uint?(now) and JSON.safe_uint?(deadline) and deadline > 0 and deadline <= now and
      eligible_history_metadata?(metadata, deadline - 1)
  rescue
    _ -> false
  end

  defp effective(candidate, first, baseline, nil, _) do
    age = candidate["max_age_ms"]

    if (is_nil(baseline) and is_nil(age)) or
         (is_integer(baseline) and JSON.safe_uint?(baseline) and baseline >= first and
            (is_nil(age) or baseline <= first + age)),
       do: {:ok, candidate["category"], baseline},
       else: @error
  end

  defp effective(candidate, first, _, choice, value_sha256) do
    with true <-
           choice["lineage"] == candidate["lineage"] and choice["target_key"] == candidate["key"],
         true <-
           choice["target_value_sha256"] == value_sha256 and choice["observed_at_ms"] >= first,
         {:ok, _, _} = result <- selected(choice["policy"], choice["observed_at_ms"]) do
      result
    else
      _ -> @error
    end
  end

  defp age(%{"kind" => "ordinary"}), do: @ordinary
  defp age(%{"kind" => "duration", "duration_ms" => duration}), do: duration
  defp age(_), do: nil
  defp number(nil), do: nil
  defp number(value), do: value |> Integer.to_string(36) |> String.downcase()

  defp unpack(value),
    do: value |> Base.url_decode64!(padding: false) |> Base.encode16(case: :lower)
end
