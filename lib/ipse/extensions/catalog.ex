defmodule Ipse.Extensions.Catalog do
  @moduledoc "Inert, versioned tool/command/service declarations; discovery never executes code."
  alias Ipse.MCP.Schema

  @groups %{
    "tools" => "invoke.tool",
    "commands" => "invoke.command",
    "services" => "invoke.service",
    "jobs" => "event.job"
  }
  @error {:error, :invalid_extension_catalog}

  def capabilities,
    do:
      ~w(transform.prompt transform.presentation invoke.tool invoke.command invoke.service host.actions host.state.read host.state.write host.question host.tools host.services host.context stream.text stream.text.events lifecycle.record lifecycle.tools event.notify event.job event.feed event.prompt.original event.prompt.effective event.answer.original event.answer.presented event.tool.input event.tool.result observe.local observe.export) ++
        Ipse.Extensions.History.capabilities()

  def empty,
    do: %{"version" => 1, "tools" => [], "commands" => [], "services" => []}

  def normalize(nil), do: Map.put(empty(), "jobs", [])
  def normalize(exports) when is_map(exports), do: Map.put_new(exports, "jobs", [])
  def normalize(exports), do: exports

  def validate(exports, capabilities) do
    exports = normalize(exports)

    with :ok <- Schema.validate_object(exports),
         true <- "lifecycle.tools" not in capabilities or "lifecycle.record" in capabilities,
         true <- "stream.text.events" not in capabilities or "stream.text" in capabilities,
         true <- Enum.sort(Map.keys(exports)) == ~w(commands jobs services tools version),
         true <- exports["version"] === 1,
         true <-
           not Enum.any?(
             ~w(host.state.read host.state.write host.question host.tools host.services host.context) ++
               Ipse.Extensions.History.capabilities(),
             &(&1 in capabilities)
           ) or
             "host.actions" in capabilities,
         true <-
           not Enum.any?(
             Ipse.Extensions.History.capabilities() -- ["host.history"],
             &(&1 in capabilities)
           ) or
             "host.history" in capabilities,
         true <-
           Enum.all?(@groups, fn {group, capability} ->
             records = exports[group]

             is_list(records) and length(records) <= 8 and
               Enum.all?(records, &descriptor?/1) and unique?(Enum.map(records, & &1["id"])) and
               records != [] == capability in capabilities
           end),
         :ok <-
           Schema.validate_object(%{
             "sdk" => 1,
             "capabilities" => capabilities,
             "exports" => exports
           }) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Derive a bounded catalog from already admitted entries, without module loading."
  def snapshot(config) do
    entries =
      for entry <- Map.get(config, :extensions, []),
          {group, stage} <- Enum.sort(@groups),
          descriptor <- Map.get(entry.exports, group, []) do
        Map.merge(descriptor, %{
          "instance" => entry.identity["instance"],
          "stage" => stage,
          "name" => name(entry.identity["instance"], descriptor["id"])
        })
      end

    snapshot = %{"version" => 1, "entries" => entries}

    with true <- length(entries) <= 32,
         true <- unique?(Enum.map(entries, &{&1["stage"], &1["name"]})),
         true <- Enum.all?(entries, &(byte_size(&1["name"]) <= 64)),
         :ok <- validate_snapshot(snapshot) do
      {:ok, snapshot}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def definitions(config) do
    {:ok, catalog} = snapshot(config)

    catalog["entries"]
    |> Enum.filter(&(&1["stage"] == "invoke.tool"))
    |> Enum.map(fn descriptor ->
      %{
        "type" => "function",
        "function" => %{
          "name" => descriptor["name"],
          "description" => descriptor["description"],
          "parameters" => descriptor["arguments_schema"]
        }
      }
    end)
  end

  def validate_snapshot(%{"version" => 1, "entries" => entries} = snapshot) do
    with :ok <- Schema.validate_object(snapshot),
         true <- Enum.sort(Map.keys(snapshot)) == ~w(entries version),
         true <- is_list(entries) and length(entries) <= 32,
         true <-
           Enum.all?(entries, fn export ->
             is_map(export) and export["stage"] in Map.values(@groups) and
               is_binary(export["instance"]) and
               Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, export["instance"]) and
               descriptor?(Map.drop(export, ~w(instance stage name))) and
               export["name"] == name(export["instance"], export["id"]) and
               byte_size(export["name"]) <= 64
           end),
         true <- unique?(Enum.map(entries, &{&1["stage"], &1["name"]})) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def validate_snapshot(_), do: @error

  def from_metadata(metadata) do
    identities = Map.get(metadata, "extensions", [])
    snapshot = Map.get(metadata, "extension_catalog", %{"version" => 1, "entries" => []})

    with true <- is_list(identities) and length(identities) <= 8,
         true <- Enum.all?(identities, &Ipse.Extensions.Identity.valid?/1),
         true <- unique?(Enum.map(identities, & &1["instance"])),
         :ok <- validate_snapshot(snapshot),
         true <-
           Enum.all?(snapshot["entries"], fn export ->
             Enum.any?(identities, &(&1["instance"] == export["instance"]))
           end),
         true <-
           Enum.all?(identities, fn identity ->
             exports =
               Enum.reduce(@groups, empty(), fn {group, stage}, exports ->
                 records =
                   snapshot["entries"]
                   |> Enum.filter(
                     &(&1["instance"] == identity["instance"] and &1["stage"] == stage)
                   )
                   |> Enum.map(&Map.drop(&1, ~w(instance stage name)))

                 Map.put(exports, group, records)
               end)

             validate(exports, identity["capabilities"]) == :ok and
               digest(exports) == identity["exports_sha256"]
           end) do
      {:ok, snapshot}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def validate_call(descriptor, arguments) do
    with :ok <- Schema.validate_arguments(descriptor["arguments_schema"], arguments),
         :ok <-
           Schema.validate_object(%{
             "api_version" => 1,
             "invocation_id" => String.duplicate("0", 32),
             "session_id" => String.duplicate("0", 32),
             "turn_id" => String.duplicate("0", 32),
             "id" => descriptor["id"],
             "arguments" => arguments
           }) do
      :ok
    else
      _ -> {:error, :invalid_extension_arguments}
    end
  rescue
    _ -> {:error, :invalid_extension_arguments}
  end

  def validate_response(descriptor, response) do
    with :ok <- Schema.validate_object(response),
         true <- Enum.sort(Map.keys(response)) == ~w(api_version kind value),
         true <- response["api_version"] === 1 and response["kind"] == "result",
         :ok <- Schema.validate_arguments(descriptor["result_schema"], response["value"]) do
      {:ok, response["value"]}
    else
      _ -> {:error, :invalid_extension_response}
    end
  rescue
    _ -> {:error, :invalid_extension_response}
  end

  def lookup(config, stage, name) do
    with {:ok, snapshot} <- snapshot(config),
         descriptor when is_map(descriptor) <-
           Enum.find(snapshot["entries"], &(&1["stage"] == stage and &1["name"] == name)),
         entry when is_map(entry) <-
           Enum.find(
             Map.get(config, :extensions, []),
             &(&1.identity["instance"] == descriptor["instance"])
           ) do
      {:ok, entry, descriptor}
    else
      _ -> {:error, :extension_export_unavailable}
    end
  end

  def external?(name), do: is_binary(name) and String.starts_with?(name, "ext__")

  def digest(exports) do
    exports = normalize(exports)
    exports = if exports["jobs"] == [], do: Map.delete(exports, "jobs"), else: exports
    Ipse.Compaction.digest([exports])
  end

  defp name(instance, id), do: "ext__" <> instance <> "__" <> id

  defp descriptor?(descriptor) when is_map(descriptor) do
    Enum.sort(Map.keys(descriptor)) == ~w(arguments_schema description id result_schema) and
      is_binary(descriptor["id"]) and
      Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, descriptor["id"]) and
      is_binary(descriptor["description"]) and String.valid?(descriptor["description"]) and
      byte_size(descriptor["description"]) in 1..1024 and
      Enum.all?(~w(arguments_schema result_schema), fn field ->
        Schema.validate_schema(descriptor[field]) == :ok and descriptor[field]["type"] == "object"
      end)
  end

  defp descriptor?(_), do: false
  defp unique?(records), do: length(records) == length(Enum.uniq(records))
end
