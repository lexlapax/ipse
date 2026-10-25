defmodule Ipse.Development.Release do
  @moduledoc "Release artifact integrity and tag admission using the existing OTP toolchain."

  def checksum(path) do
    path
    |> File.stream!(65_536, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  def write_checksum!(archive) do
    File.write!(
      archive <> ".sha256",
      checksum(archive) <> "  " <> Path.basename(archive) <> "\n",
      [:sync]
    )
  end

  def verify_checksum!(archive) do
    with {:ok, %{type: :regular, size: archive_size}} <- File.lstat(archive),
         true <- archive_size > 0,
         {:ok, %{type: :regular, size: size}} <- File.lstat(archive <> ".sha256"),
         true <- size <= 512,
         {:ok, actual} <- File.read(archive <> ".sha256"),
         true <- actual == checksum(archive) <> "  " <> Path.basename(archive) <> "\n" do
      :ok
    else
      _ -> raise "Missing, non-regular, empty archive or malformed or mismatching SHA256 sidecar"
    end
  end

  def validate_tag!(tag, version, root) do
    unless Regex.match?(~r/\Av#{Regex.escape(version)}(?:-rc\.[1-9][0-9]*)?\z/, tag),
      do: raise("Release tag must match mix.exs version, optionally with -rc.N")

    notes = Path.join(root, "docs/releases/v#{version}.md")

    unless File.regular?(notes) and File.stat!(notes).size > 0,
      do: raise("Release notes are missing or empty")

    notes
  end

  def release_notes!(tag, version, root, destination) do
    notes = validate_tag!(tag, version, root)
    body = File.read!(notes) |> String.replace("/blob/v#{version}/", "/blob/#{tag}/")
    File.write!(destination, body)
    destination
  end

  def bundle_documentation!(directory, source, version, commit \\ nil) do
    unless Regex.match?(~r/\A[0-9]+\.[0-9]+\.[0-9]+\z/, version),
      do: raise("Invalid documentation version")

    directory = Path.expand(directory)
    source = Path.expand(source)
    exact_commit = is_binary(commit) and Regex.match?(~r/\A[0-9a-f]{40}\z/, commit)
    reference = if exact_commit, do: commit, else: "v" <> version

    rewritten =
      for path <- documentation_paths(directory), reduce: 0 do
        count ->
          {bytes, links} =
            map_document_links(File.read!(path), fn target ->
              {file, fragment} = document_target(target)

              if external_document_target?(target) or file == "" do
                target
              else
                relative = document_relative!(directory, path, file)

                if File.exists?(Path.join(directory, relative)) do
                  target
                else
                  original = Path.join(source, relative)

                  unless File.exists?(original),
                    do: raise("Documentation target is missing from the source: " <> relative)

                  kind = if File.dir?(original), do: "tree", else: "blob"
                  encoded = Enum.map_join(Path.split(relative), "/", &URI.encode/1)
                  "https://github.com/lexlapax/ipse/#{kind}/#{reference}/#{encoded}" <> fragment
                end
              end
            end)

          File.write!(path, bytes)
          count + links
      end

    manifest = %{
      "version" => 1,
      "source_ref" => reference,
      "source_ref_kind" => if(exact_commit, do: "commit", else: "version_tag"),
      "rewritten_links" => rewritten,
      "historical_records" => "repository"
    }

    File.write!(Path.join(directory, "docs/bundle-links.json"), :json.encode(manifest))
    manifest
  end

  def verify_documentation_archive!(archive) do
    {:ok, inventory} = :erl_tar.table(String.to_charlist(archive), [:compressed])

    names =
      MapSet.new(
        inventory,
        &(to_string(&1) |> String.replace_prefix("./", "") |> String.trim_trailing("/"))
      )

    selected =
      Enum.filter(
        inventory,
        &(manual_document_path?(String.replace_prefix(to_string(&1), "./", "")) or
            String.replace_prefix(to_string(&1), "./", "") == "docs/bundle-links.json")
      )

    {:ok, entries} =
      :erl_tar.extract(String.to_charlist(archive), [:compressed, :memory, {:files, selected}])

    files =
      Map.new(entries, fn {name, bytes} ->
        {to_string(name) |> String.replace_prefix("./", ""), bytes}
      end)

    for path <-
          ~w(README.md docs/index.md docs/operator/index.md docs/operator/install.md docs/operator/usage.md docs/developer/index.md),
        do: true = Map.has_key?(files, path)

    %{
      "version" => 1,
      "source_ref" => reference,
      "source_ref_kind" => reference_kind,
      "historical_records" => "repository"
    } =
      :json.decode(Map.fetch!(files, "docs/bundle-links.json"))

    true =
      case reference_kind do
        "commit" -> Regex.match?(~r/\A[0-9a-f]{40}\z/, reference)
        "version_tag" -> Regex.match?(~r/\Av[0-9]+\.[0-9]+\.[0-9]+\z/, reference)
        _ -> false
      end

    false = Enum.any?(names, &String.starts_with?(&1, "docs/archive/"))

    documents = for {path, bytes} <- files, String.ends_with?(path, ".md"), do: {path, bytes}

    for {path, bytes} <- documents do
      map_document_links(bytes, fn target ->
        {file, _} = document_target(target)

        unless external_document_target?(target) or file == "" do
          relative = document_relative!("/bundle", Path.join("/bundle", path), file)

          unless MapSet.member?(names, relative),
            do: raise("Missing bundled documentation target: " <> relative)
        end

        target
      end)
    end

    %{"documents" => length(documents), "source_ref" => reference, "missing_local_targets" => 0}
  end

  defp documentation_paths(directory) do
    (Path.wildcard(Path.join(directory, "*.md")) ++
       Path.wildcard(Path.join(directory, "docs/**/*.md")))
    |> Enum.sort()
  end

  defp manual_document_path?(path),
    do:
      String.ends_with?(path, ".md") and
        (Path.dirname(path) == "." or String.starts_with?(path, "docs/"))

  defp external_document_target?(target),
    do: String.starts_with?(target, "//") or Regex.match?(~r/\A[A-Za-z][A-Za-z0-9+.-]*:/, target)

  defp document_target(target) do
    case String.split(target, "#", parts: 2) do
      [file] -> {URI.decode(file), ""}
      [file, fragment] -> {URI.decode(file), "#" <> fragment}
    end
  end

  defp document_relative!(root, document, file) do
    relative = Path.expand(file, Path.dirname(document)) |> Path.relative_to(root)

    if Path.type(relative) != :relative or relative == ".." or
         String.starts_with?(relative, "../"),
       do: raise("Documentation target escapes its root")

    relative
  end

  defp map_document_links(bytes, rewrite) do
    {lines, {_, count}} =
      bytes
      |> String.split("\n")
      |> Enum.map_reduce({nil, 0}, fn line, {fence, count} ->
        marker = Regex.run(~r/^\s{0,3}(`{3,}|~{3,})/, line)

        cond do
          fence == nil and marker != nil ->
            [_, marker] = marker
            {line, {{String.first(marker), String.length(marker)}, count}}

          fence != nil ->
            {kind, length} = fence
            close = Regex.run(~r/^\s{0,3}(`{3,}|~{3,})\s*$/, line)

            closed =
              close != nil and String.first(Enum.at(close, 1)) == kind and
                String.length(Enum.at(close, 1)) >= length

            {line, {if(closed, do: nil, else: fence), count}}

          true ->
            matches = Regex.scan(~r/\]\((<[^>\n]+>|[^\s)]+)/, line)

            {rendered, changed} =
              Enum.reduce(matches, {line, 0}, fn [whole, captured], {text, n} ->
                target = captured |> String.trim_leading("<") |> String.trim_trailing(">")
                replacement = rewrite.(target)

                wrapped =
                  if String.starts_with?(captured, "<"),
                    do: "<" <> replacement <> ">",
                    else: replacement

                {String.replace(text, whole, "](" <> wrapped, global: false),
                 n + if(target == replacement, do: 0, else: 1)}
              end)

            {rendered, {nil, count + changed}}
        end
      end)

    {Enum.join(lines, "\n"), count}
  end

  def verify_assets!(directory, version) do
    unless Regex.match?(~r/\A[0-9]+\.[0-9]+\.[0-9]+\z/, version),
      do: raise("Expected a stable application version for archive admission")

    archives = Path.wildcard(Path.join(directory, "*.tar.gz"))

    platforms =
      Enum.map(archives, fn path ->
        cond do
          Regex.match?(
            ~r/\Aipse-#{Regex.escape(version)}-linux-x86_64-(?:glibc-[0-9]+\.[0-9]+|system-libc)\.tar\.gz\z/,
            Path.basename(path)
          ) ->
            :linux

          Path.basename(path) == "ipse-#{version}-darwin-arm64.tar.gz" ->
            :darwin

          true ->
            :unknown
        end
      end)

    unless Enum.sort(platforms) == [:darwin, :linux] and
             Enum.sort(File.ls!(directory)) ==
               Enum.sort(
                 Enum.flat_map(archives, &[Path.basename(&1), Path.basename(&1) <> ".sha256"])
               ),
           do: raise("Expected exactly one Linux and one macOS archive with matching sidecars")

    Enum.each(archives, &verify_checksum!/1)
    :ok
  end

  def runtime_notices!(destination, opts \\ []) do
    {elixir, otp} =
      Keyword.get_lazy(opts, :versions, fn ->
        otp = :erlang.system_info(:otp_release) |> to_string()
        path = Path.join([to_string(:code.root_dir()), "releases", otp, "OTP_VERSION"])
        {System.version(), path |> File.read!() |> String.trim()}
      end)

    unless Regex.match?(~r/\A[0-9]+(?:\.[0-9]+){1,4}(?:-rc\.[0-9]+)?\z/, elixir) and
             Regex.match?(~r/\A[0-9]+(?:\.[0-9]+){0,4}(?:-rc[0-9]+)?\z/, otp),
           do: raise("Unsupported toolchain version for runtime notices")

    if File.exists?(destination), do: raise("Runtime notice destination already exists")
    File.mkdir_p!(destination)
    fetch = Keyword.get(opts, :fetch, &github_json!/1)

    sources =
      for {name, repo, tag, required} <- [
            {"elixir", "elixir-lang/elixir", "v" <> elixir, ["LICENSE"]},
            {"otp", "erlang/otp", "OTP-" <> otp, ["LICENSE.txt"]}
          ] do
        tree_path = "repos/#{repo}/git/trees/#{tag}?recursive=1"
        tree = fetch.(tree_path)

        unless tree["truncated"] == false and is_list(tree["tree"]) and
                 is_binary(tree["sha"]) and Regex.match?(~r/\A[0-9a-f]{40}\z/, tree["sha"]),
               do: raise("Incomplete runtime notice source tree")

        notices =
          Enum.filter(tree["tree"], fn item ->
            item["type"] == "blob" and is_binary(item["path"]) and
              Regex.match?(
                ~r/(?:\A|\/)(?:LICENSES\/.+|(?:LICENSE|LICENCE|NOTICE|COPYING|COPYRIGHT)(?:\.[A-Za-z0-9_.-]+)?)\z/i,
                item["path"]
              )
          end)

        unless length(notices) in 1..256 and
                 Enum.all?(required, fn path -> Enum.any?(notices, &(&1["path"] == path)) end),
               do: raise("Required runtime notices are missing")

        files =
          for item <- notices do
            path = item["path"]
            sha = item["sha"]

            unless String.valid?(path) and Regex.match?(~r/\A[A-Za-z0-9_.\/-]+\z/, path) and
                     Path.type(path) == :relative and
                     not Enum.any?(Path.split(path), &(&1 in [".", ".."])) and
                     is_binary(sha) and Regex.match?(~r/\A[0-9a-f]{40}\z/, sha) and
                     is_integer(item["size"]) and item["size"] in 1..1_048_576,
                   do: raise("Invalid runtime notice identity")

            blob_path = "repos/#{repo}/git/blobs/#{sha}"
            blob = fetch.(blob_path)

            unless blob["encoding"] == "base64" and is_binary(blob["content"]) and
                     byte_size(blob["content"]) <= 1_500_000,
                   do: raise("Invalid runtime notice blob")

            bytes = blob["content"] |> String.replace("\n", "") |> Base.decode64!()

            actual =
              :crypto.hash(:sha, ["blob #{byte_size(bytes)}", <<0>>, bytes])
              |> Base.encode16(case: :lower)

            unless byte_size(bytes) == item["size"] and actual == sha and String.valid?(bytes),
              do: raise("Runtime notice content does not match its source identity")

            relative = Path.join(name, path)
            output = Path.join(destination, relative)
            File.mkdir_p!(Path.dirname(output))
            File.write!(output, bytes, [:exclusive])

            %{
              "path" => relative,
              "source" => "https://api.github.com/" <> blob_path,
              "git_blob_sha" => sha,
              "sha256" => checksum(output)
            }
          end

        %{"repository" => repo, "tag" => tag, "tree_sha" => tree["sha"], "files" => files}
      end

    manifest = %{"version" => 1, "elixir" => elixir, "otp" => otp, "sources" => sources}

    File.write!(Path.join(destination, "runtime-notices.json"), :json.encode(manifest), [
      :exclusive
    ])

    manifest
  end

  defp github_json!(path) do
    case System.cmd("gh", ["api", "--hostname", "github.com", path], stderr_to_stdout: true) do
      {bytes, 0} when byte_size(bytes) <= 8_388_608 -> :json.decode(bytes)
      _ -> raise("Could not retrieve versioned runtime notices with the approved GitHub CLI")
    end
  end
end
