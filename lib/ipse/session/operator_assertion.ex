defmodule Ipse.Session.OperatorAssertion do
  @moduledoc """
  Exact native review of an operator's own statement and selected note category.

  These pure render/receipt checks grant no effect permission. Session consumes
  the actual volatile input witness before constructing a receipt, and the
  existing protected command path checks consent before any publication. Plain
  input and question answers never acquire this origin by matching text.
  """
  alias Ipse.{JSON, Usage}
  @categories ~w(ordinary preference current)
  @hashes ~w(project_id namespace artifact_sha256 policy_sha256)
  @scope ["workspace" | @hashes]
  @render ~w(version id session_id channel_id category text scope code display)
  @event ~w(type version id session_id channel_id category text scope code input observation)
  @error {:error, :operator_assertion_refused}

  def parse_command("/remember " <> value) do
    case String.split(value, " ", parts: 2) do
      [category, text] -> if statement?(category, text), do: {:ok, category, text}, else: @error
      _ -> @error
    end
  end

  def parse_command(_), do: @error

  @doc false
  def parse_intake(text) do
    case parse_command(text) do
      {:ok, category, statement} -> {:ok, category, statement, nil}
      _ -> parse_relation(text)
    end
  end

  defp parse_relation(text) when is_binary(text) do
    case String.split(text, " ", parts: 3) do
      [command, "note." <> lineage = key, statement] when command in ~w(/correct /supersede) ->
        category = if command == "/correct", do: "ordinary", else: "current"
        mode = if command == "/correct", do: "ordinary", else: "temporal"

        if JSON.sha256?(lineage) and statement?(category, statement),
          do: {:ok, category, statement, %{"mode" => mode, "target_key" => key}},
          else: @error

      _ ->
        @error
    end
  end

  defp parse_relation(_), do: @error

  def scope(%{
        "version" => 2,
        "status" => "active",
        "pin" => pin,
        "policy" => policy,
        "binding" => binding
      }) do
    value = %{
      "project_id" => pin["project_id"],
      "namespace" => pin["namespace"],
      "artifact_sha256" => policy["artifact_sha256"],
      "policy_sha256" => pin["policy_sha256"],
      "workspace" => binding["root"]
    }

    if scope?(value), do: {:ok, value}, else: @error
  rescue
    _ -> @error
  end

  def scope(_), do: @error

  @doc false
  def selection(config) do
    admission = config[:semantic_admission]

    with {:ok, scope} <- scope(admission),
         true <- admission["instance"] == "knowledge",
         %{"kind" => "reviewed.bundle", "artifact_sha256" => digest} <-
           get_in(admission, ["policy", "settings", "activation"]),
         true <- digest == scope["artifact_sha256"],
         categories when is_list(categories) <-
           get_in(admission, ["policy", "settings", "sources", "categories"]),
         true <- "native_operator_assertion" in categories,
         {:ok, mode} <- Ipse.Extension.Mode.capture(config),
         :ok <- Ipse.Extension.Mode.knowledge(mode, "collection.publish"),
         name = "ext__knowledge__capture",
         {:ok, entry, descriptor} <- Ipse.Extension.Catalog.lookup(config, "invoke.command", name),
         true <- entry.identity["artifact_sha256"] == digest,
         true <- capture_contract?(admission, descriptor) do
      {:ok, scope, name}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def capture_contract?(admission, descriptor) do
    settings = get_in(admission, ["policy", "settings"])

    selected =
      Enum.filter(settings["effects"], fn mapping ->
        mapping["class"] == "collection.publish" and
          mapping["outer_sha256"] == JSON.digest([descriptor])
      end)

    with true <- selected != [],
         {:ok, recipes} <-
           Enum.reduce_while(selected, {:ok, []}, fn mapping, {:ok, recipes} ->
             with true <- mapping["inner_op"] == "collection.managed",
                  {:ok, recipe} <- Ipse.Extension.SemanticConsent.recipe(settings, mapping),
                  {:ok, _constraint} <-
                    Ipse.Extension.SemanticConsent.constraints(settings, mapping),
                  true <- recipe["constraints_sha256"] == mapping["constraints_sha256"] do
               {:cont, {:ok, recipes ++ [recipe]}}
             else
               _ -> {:halt, @error}
             end
           end),
         [literal] <- Enum.filter(recipes, &(&1["kind"] == "literal_source")),
         true <-
           Enum.map(literal["rules"], &Map.take(&1, ~w(category max_age_ms))) == [
             %{"category" => "current", "max_age_ms" => nil},
             %{"category" => "ordinary", "max_age_ms" => 90 * 86_400_000},
             %{"category" => "preference", "max_age_ms" => nil}
           ],
         true <- Enum.all?(literal["rules"], &("native_operator_assertion" in &1["origins"])) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def render(session, channel, category, text, scope) do
    value = %{
      "version" => 1,
      "id" => Usage.id(),
      "session_id" => session,
      "channel_id" => channel,
      "category" => category,
      "text" => text,
      "scope" => scope,
      "code" => Usage.id()
    }

    if body?(value),
      do: {:ok, Map.put(value, "display", display(value))},
      else: @error
  end

  def receipt(render, input, observation) do
    with true <- keys?(render, @render) and body?(Map.delete(render, "display")),
         true <- render["display"] == display(render),
         true <- input == "remember " <> render["code"],
         true <- Ipse.Session.Input.valid_observation?(observation, input, 2),
         true <- observation["display_sha256"] == JSON.sha256(render["display"]) do
      {:ok,
       render
       |> Map.delete("display")
       |> Map.merge(%{
         "type" => "operator_assertion",
         "input" => input,
         "observation" => observation
       })}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def valid_event?(%{"planning_decision" => decision} = event, session) do
    Ipse.Session.PlanningDecisions.valid_accepted?(decision, session) and
      event["text"] === decision["text"] and event["category"] === "ordinary" and
      valid_event?(Map.delete(event, "planning_decision"), session)
  rescue
    _ -> false
  end

  def valid_event?(event, session) do
    with true <- keys?(event, @event) and event["type"] == "operator_assertion",
         true <- event["session_id"] == session,
         render = Map.take(event, @render) |> Map.put("display", display(event)),
         {:ok, ^event} <- receipt(render, event["input"], event["observation"]) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def validate_events(events, session) do
    metadata = (List.first(events) || %{})["metadata"] || %{}

    Enum.reduce_while(events, MapSet.new(), fn
      %{"type" => "operator_assertion"} = event, seen ->
        with true <- valid_event?(event, session),
             {:ok, scope} <- scope(metadata["semantic_admission"]),
             true <- event["scope"] === scope and not MapSet.member?(seen, event["id"]) do
          {:cont, MapSet.put(seen, event["id"])}
        else
          _ -> {:halt, @error}
        end

      _, seen ->
        {:cont, seen}
    end)
    |> case do
      %MapSet{} -> :ok
      error -> error
    end
  end

  def kind(category) when category in @categories, do: "input.assertion." <> category
  def kind(_), do: nil

  def asserted_category?(%{"origin" => "native_operator_assertion", "kind" => kind}, category),
    do: category in @categories and kind == __MODULE__.kind(category)

  def asserted_category?(_, _), do: false

  defp body?(value) do
    keys?(value, List.delete(@render, "display")) and value["version"] === 1 and
      Enum.all?(~w(id session_id channel_id code), &id?(value[&1])) and
      statement?(value["category"], value["text"]) and scope?(value["scope"])
  end

  defp scope?(scope),
    do:
      keys?(scope, @scope) and Enum.all?(@hashes, &JSON.sha256?(scope[&1])) and
        path?(scope["workspace"])

  defp path?(path),
    do:
      is_binary(path) and String.valid?(path) and byte_size(path) in 1..4096 and
        not String.contains?(path, <<0>>) and Path.type(path) == :absolute and
        Path.expand(path) == path

  defp statement?(category, text),
    do:
      category in @categories and is_binary(text) and String.valid?(text) and
        byte_size(text) in 1..1024 and String.trim(text) != ""

  defp display(value) do
    retention =
      if value["category"] == "ordinary",
        do: "at most 90 days",
        else: "until changed, forgotten or no longer eligible"

    Ipse.CLI.Terminal.escape(
      "Remember this exact statement as your own #{value["category"]} note?\n" <>
        "Statement: " <>
        Jason.encode!(value["text"]) <>
        "\nRetention: #{retention}.\n" <>
        "Workspace: " <>
        Jason.encode!(value["scope"]["workspace"]) <>
        "\n" <>
        "Project: #{value["scope"]["project_id"]}\n" <>
        "Collection: #{value["scope"]["namespace"]}\n" <>
        "Artifact: #{value["scope"]["artifact_sha256"]}\n" <>
        "Permission: #{value["scope"]["policy_sha256"]}\n" <>
        "This confirms the statement and category; other effects keep their own approvals.\n" <>
        "Type remember #{value["code"]} to confirm. Anything else cancels.\nremember> "
    )
  end

  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp keys?(v, fields), do: is_map(v) and Enum.sort(Map.keys(v)) == Enum.sort(fields)
end
