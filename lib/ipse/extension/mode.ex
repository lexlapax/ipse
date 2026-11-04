defmodule Ipse.Extension.Mode do
  @moduledoc """
  Closed host execution ceilings, separate from saved semantic permission.

  The CLI must record why approval is denied. Missing legacy origin is explicit
  denial; it never becomes the default-headless exception by inference. A mode
  value grants no semantic authority. Only the host's reviewed effect mapping may
  call `knowledge/2` after checking its saved semantic pin and current policy.
  """
  @ceilings ~w(normal read_only planning draft)
  @classes ~w(collection.read collection.publish model.complete embedding.create decision.create)
  @keys ~w(version approval approval_origin headless ceiling enclosing_ceiling knowledge)

  def classes, do: @classes

  @doc "Capture explicit host policy; broad --yes is ordinary approval only."
  def capture(config) when is_map(config) do
    value = %{
      "version" => 1,
      "approval" => word(Map.get(config, :approval, :ask)),
      "approval_origin" => word(Map.get(config, :approval_origin, :explicit)),
      "headless" =>
        Map.get(config, :headless, Map.get(config, :approval_origin) == :default_headless),
      "ceiling" => word(Map.get(config, :execution_mode, :normal)),
      "enclosing_ceiling" => word(Map.get(config, :enclosing_mode, :normal)),
      "knowledge" => word(Map.get(config, :knowledge_ceiling, :available))
    }

    if valid?(value), do: {:ok, value}, else: {:error, :invalid_execution_mode}
  end

  def capture(_), do: {:error, :invalid_execution_mode}

  @doc "Resume/child admission may narrow a saved ceiling; CLI approval cannot widen it."
  def inherit(saved, config) do
    with true <- valid?(saved), {:ok, current} <- capture(config) do
      ceilings = [saved["ceiling"], saved["enclosing_ceiling"], current["enclosing_ceiling"]]
      enclosing = Enum.max_by(ceilings, &ceiling_rank/1)
      knowledge = Enum.max_by([saved["knowledge"], current["knowledge"]], &knowledge_rank/1)
      current = %{current | "enclosing_ceiling" => enclosing, "knowledge" => knowledge}

      current =
        if saved["approval"] == "deny" and saved["approval_origin"] == "explicit",
          do: %{current | "approval" => "deny", "approval_origin" => "explicit"},
          else: current

      {:ok, current}
    else
      _ -> {:error, :invalid_execution_mode}
    end
  end

  @doc "Resume the same owner while retaining separate local and enclosing ceilings."
  def resume(saved, config) do
    with true <- valid?(saved), {:ok, current} <- capture(config) do
      ceiling = Enum.max_by([saved["ceiling"], current["ceiling"]], &ceiling_rank/1)

      enclosing =
        Enum.max_by([saved["enclosing_ceiling"], current["enclosing_ceiling"]], &ceiling_rank/1)

      knowledge = Enum.max_by([saved["knowledge"], current["knowledge"]], &knowledge_rank/1)

      current = %{
        current
        | "ceiling" => ceiling,
          "enclosing_ceiling" => enclosing,
          "knowledge" => knowledge
      }

      current =
        if saved["approval"] == "deny" and saved["approval_origin"] == "explicit",
          do: %{current | "approval" => "deny", "approval_origin" => "explicit"},
          else: current

      {:ok, current}
    else
      _ -> {:error, :invalid_execution_mode}
    end
  end

  @doc false
  def resumed?(saved, current) do
    with true <- valid?(saved) and valid?(current),
         {:ok, resumed} <- resume(saved, config(current)) do
      resumed === current
    else
      _ -> false
    end
  end

  @doc false
  def inherited?(saved, current) do
    with true <- valid?(saved) and valid?(current),
         {:ok, inherited} <- inherit(saved, config(current)) do
      inherited === current
    else
      _ -> false
    end
  end

  @doc false
  def config(mode) do
    %{
      approval: mode["approval"],
      approval_origin: mode["approval_origin"],
      headless: mode["headless"],
      execution_mode: mode["ceiling"],
      enclosing_mode: mode["enclosing_ceiling"],
      knowledge_ceiling: mode["knowledge"]
    }
  end

  @doc false
  def checkpoint_required?(nil, current) do
    current["ceiling"] != "normal" or current["enclosing_ceiling"] != "normal" or
      current["knowledge"] != "available" or
      (current["approval"] == "deny" and current["approval_origin"] == "explicit")
  end

  def checkpoint_required?(previous, current), do: previous !== current

  def valid?(value) when is_map(value) do
    Enum.sort(Map.keys(value)) == Enum.sort(@keys) and value["version"] === 1 and
      value["approval"] in ~w(ask allow deny) and
      value["approval_origin"] in ~w(explicit interactive yes default_headless) and
      is_boolean(value["headless"]) and
      value["ceiling"] in @ceilings and value["enclosing_ceiling"] in @ceilings and
      value["knowledge"] in ~w(available disabled paused) and origin?(value)
  end

  def valid?(_), do: false

  @doc "Knowledge-only ceiling check; this function never establishes saved permission."
  def knowledge(value, class) do
    cond do
      not valid?(value) or class not in @classes ->
        {:error, :knowledge_mode_denied}

      value["knowledge"] != "available" ->
        {:error, :knowledge_disabled}

      value["approval"] == "deny" and value["approval_origin"] != "default_headless" ->
        {:error, :knowledge_mode_denied}

      class != "collection.read" and
          (value["ceiling"] != "normal" or value["enclosing_ceiling"] != "normal") ->
        {:error, :knowledge_mode_denied}

      true ->
        :ok
    end
  end

  @doc false
  # An inert outer callback is separate from the classes a saved effect mapping
  # may grant. It admits no host action, read, publication or inference.
  def nomination(value) do
    if valid?(value) and value["headless"] === false and
         value["ceiling"] === "normal" and value["enclosing_ceiling"] === "normal" and
         value["knowledge"] === "available" and value["approval"] in ~w(ask allow),
       do: :ok,
       else: {:error, :knowledge_mode_denied}
  end

  @doc "Preserve normal approval for unrelated effects; saved consent is not consulted."
  def ordinary(value, mutating?) when is_boolean(mutating?) do
    cond do
      not valid?(value) -> :deny
      not mutating? -> :not_required
      value["ceiling"] != "normal" or value["enclosing_ceiling"] != "normal" -> :deny
      true -> String.to_existing_atom(value["approval"])
    end
  end

  def ordinary(_, _), do: :deny

  @doc "Ordinary approval for an independently declared planning read; grants no declaration."
  def planning_read(value) do
    cond do
      not valid?(value) ->
        :deny

      value["ceiling"] == "read_only" or value["enclosing_ceiling"] == "read_only" ->
        :deny

      value["ceiling"] not in ~w(draft planning) and value["enclosing_ceiling"] != "planning" ->
        :deny

      true ->
        String.to_existing_atom(value["approval"])
    end
  end

  defp origin?(%{
         "approval_origin" => "default_headless",
         "approval" => "deny",
         "headless" => true
       }),
       do: true

  defp origin?(%{"approval_origin" => "default_headless"}), do: false
  defp origin?(%{"approval_origin" => "yes", "approval" => "allow"}), do: true
  defp origin?(%{"approval_origin" => "yes"}), do: false
  defp origin?(_), do: true
  defp word(value) when is_atom(value), do: Atom.to_string(value)
  defp word(value), do: value
  defp ceiling_rank("normal"), do: 0
  defp ceiling_rank("draft"), do: 1
  defp ceiling_rank("planning"), do: 2
  defp ceiling_rank("read_only"), do: 3
  defp knowledge_rank("available"), do: 0
  defp knowledge_rank("paused"), do: 1
  defp knowledge_rank("disabled"), do: 2
end
