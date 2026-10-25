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
