defmodule Ipse.CLI.Documents do
  @moduledoc "Explicit selection of inert packaged document artifacts through ordinary operator configuration."
  alias Ipse.CLI.{Errors, Setup, Terminal}
  alias Ipse.Extension.{Bundles, ProjectIdentity}
  @options ~w(config cwd profile scope write replace)a

  def run(command, opts, home, cwd) do
    path =
      Path.expand(
        opts[:config] || System.get_env("IPSE_CONFIG") || Path.join(home, "config.json")
      )

    with true <- command in ~w(setup disable),
         true <- Enum.all?(Keyword.keys(opts), &(&1 in @options)),
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         true <- File.dir?(cwd),
         {:ok, original} <- Setup.read_existing(path),
         {:ok, proposal} <- propose(command, opts, original.document),
         :ok <- Setup.validate(proposal.document),
         bytes = Jason.encode!(proposal.document, pretty: true) <> "\n",
         true <- byte_size(bytes) <= 16_384,
         {:ok, effective} <-
           Ipse.Config.preview(cwd, home, [config: path, project_config: false], bytes),
         true <- Enum.any?(effective.extensions["instances"], &selected?(&1, proposal.instance)) do
      review = review(command, path, cwd, opts, effective, proposal)

      if opts[:write] == true do
        with :ok <- confirm(command, review),
             :ok <-
               Setup.write_configuration(path, bytes, original, fn ->
                 with :ok <- prepare_install(command, proposal, home, cwd, opts) do
                   if command == "setup" do
                     case Ipse.Extension.Registry.prepare(effective.extensions, home) do
                       {:ok, _} -> :ok
                       error -> error
                     end
                   else
                     :ok
                   end
                 end
               end) do
          Terminal.puts(
            "Saved private document selection for the next new session using this operator configuration."
          )

          Terminal.puts(
            "Running sessions retain their pinned selection. Resume needs the original configuration. No document was read or deleted."
          )

          0
        else
          {:error, reason} -> fail(reason)
        end
      else
        Terminal.puts(review)
        Terminal.puts("Dry run; repeat with --write in a native terminal to review and save.")
        0
      end
    else
      {:error, reason} ->
        fail(reason)

      _ ->
        fail(
          "Document setup refused. Choose setup --profile state, or setup --profile collection --scope folder|repository; disable takes no profile or scope. Unsupported flags cannot bypass native review."
        )
    end
  end

  defp propose("setup", opts, document) do
    profile = opts[:profile]

    with true <- profile in ~w(state collection),
         true <-
           (profile == "state" and is_nil(opts[:scope])) or
             (profile == "collection" and opts[:scope] in ~w(folder repository)),
         {:ok, entries} <- Bundles.inventory(),
         entry when is_map(entry) <- Enum.find(entries, &(&1.id == "corpus-#{profile}-documents")),
         true <- Ipse.Extension.Artifact.compatible?(entry.manifest),
         true <- entry.manifest["id"] == "ipse-knowledge/corpus",
         options = options(profile),
         :ok <- Ipse.JSON.validate_arguments(entry.manifest["options_schema"], options),
         instance = %{
           "instance" => "documents",
           "artifact" => entry.digest,
           "enabled" => true,
           "options" => options,
           "order" => 0,
           "lifetime" => "session"
         },
         existing =
           Enum.find(Map.get(document, "extensions", []), &(&1["instance"] == "documents")),
         true <-
           (is_nil(existing) or opts[:replace] == true) ||
             {:error,
              "The documents instance already exists; review with --replace to change it."},
         trust = trust(entry, profile),
         old_trust =
           Enum.find(Map.get(document, "extension_trust", []), &(&1["artifact"] == entry.digest)),
         true <-
           (is_nil(old_trust) or old_trust == trust) ||
             {:error,
              "This artifact already has a different trust grant. Preserve it and inspect the operator configuration."} do
      document =
        document
        |> Map.put(
          "extensions",
          replace(Map.get(document, "extensions", []), "instance", "documents", instance)
        )
        |> Map.put(
          "extension_trust",
          replace(Map.get(document, "extension_trust", []), "artifact", entry.digest, trust)
        )

      {:ok,
       %{document: document, instance: instance, entry: entry, trust: trust, profile: profile}}
    else
      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error,
         "Select an available compatible packaged document profile: --profile state, or --profile collection --scope folder|repository. Rebuild or reinstall Ipse if its bundle catalog is missing."}
    end
  end

  defp propose("disable", opts, document) do
    with true <- is_nil(opts[:profile]) and is_nil(opts[:scope]) and opts[:replace] != true,
         instance when is_map(instance) <-
           Enum.find(Map.get(document, "extensions", []), &(&1["instance"] == "documents")) do
      instance = Map.put(instance, "enabled", false)

      document =
        Map.put(
          document,
          "extensions",
          replace(document["extensions"], "instance", "documents", instance)
        )

      {:ok, %{document: document, instance: instance, trust: nil, profile: nil}}
    else
      _ ->
        {:error,
         "No documents instance to disable, or unsupported disable options. Stored documents and trust grants are retained."}
    end
  end

  defp options(profile) do
    Map.new(~w(search fetch embedding rerank extraction), &{&1, %{}})
    |> Map.merge(%{
      "version" => 1,
      "stores" => %{
        "notes" => %{"kind" => profile, "scope" => "project", "partition" => "documents"}
      },
      "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}}
    })
  end

  defp trust(entry, profile) do
    base = %{
      "artifact" => entry.digest,
      "capabilities" => entry.manifest["capabilities"],
      "allow_project" => false,
      "allow_children" => false
    }

    if profile == "state" do
      Map.put(base, "state_bindings", [
        %{"version" => 1, "instance" => "documents", "id" => "documents", "scopes" => ["project"]}
      ])
    else
      Map.put(base, "collection_bindings", [
        %{
          "version" => 1,
          "instance" => "documents",
          "id" => "documents",
          "scope" => "project",
          "profile" => "document_graph_v1"
        }
      ])
    end
  end

  defp selected?(actual, expected),
    do: Enum.all?(expected, fn {key, value} -> actual[key] == value end)

  defp replace(entries, key, value, replacement),
    do: Enum.reject(entries, &(&1[key] == value)) ++ [replacement]

  defp review(command, path, cwd, opts, effective, proposal) do
    instance =
      if command == "disable",
        do:
          proposal.instance
          |> Map.delete("options")
          |> Map.put("options_sha256", Ipse.JSON.digest([proposal.instance["options"]])),
        else: proposal.instance

    selection = %{"extensions" => [instance]}

    selection =
      if proposal.trust,
        do: Map.put(selection, "extension_trust", [proposal.trust]),
        else: selection

    admission =
      if proposal.profile == "collection",
        do:
          "Admit/revalidate #{opts[:scope]} identity at #{cwd}. Collection storage is experimental and must be supported by the local protected-storage profile.\n",
        else: ""

    "Document #{command}; operator configuration: #{path}\n" <>
      "Applies to next new sessions using this configuration across workspaces; storage is project-scoped.\n" <>
      admission <>
      "Selected conversation: #{effective.settings["provider"]}/#{effective.settings["model"]}; no route or model changes.\n" <>
      "Lexical retrieval uses no embedding or secondary model service. Retrieved excerpts can enter that conversation.\n" <>
      "Workspace reads and storage writes keep their ordinary action approvals. Notes permission is separate.\n" <>
      "Disabling preserves stored documents and trust; running sessions retain their pinned selection. Resume needs the original configuration.\n" <>
      "Exact document selection:\n" <> Jason.encode!(selection, pretty: true)
  end

  defp confirm(command, review) do
    code = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    action = if command == "setup", do: "enable", else: "disable"

    display =
      Terminal.escape(
        review <>
          "\nType #{action} #{code} to confirm this exact review, or anything else to cancel.\n> "
      )

    with {:ok, observation} <- Ipse.Runner.operator_input(display, 120_000, 2),
         true <- observation["display_sha256"] == Ipse.JSON.sha256(display),
         true <- observation["text"] == action <> " " <> code,
         true <- observation["text_sha256"] == Ipse.JSON.sha256(observation["text"]) do
      :ok
    else
      _ ->
        {:error,
         "Document setup cancelled or native terminal review unavailable; no configuration was written."}
    end
  end

  defp prepare_install("disable", _, _, _, _), do: :ok

  defp prepare_install("setup", proposal, home, cwd, opts) do
    with {:ok, artifact} <- Bundles.install(proposal.entry.id, home),
         true <- artifact.digest == proposal.entry.digest,
         :ok <- admission(proposal.profile, home, cwd, opts[:scope]) do
      :ok
    else
      _ -> {:error, :document_install_unavailable}
    end
  end

  defp admission("state", _, _, _), do: :ok

  defp admission("collection", home, cwd, scope) do
    case ProjectIdentity.admit(home, cwd, if(scope == "folder", do: :folder, else: :repository)) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp fail(reason) do
    Terminal.puts(:stderr, Errors.format(reason))
    1
  end
end
