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
    expected = checksum(archive) <> "  " <> Path.basename(archive) <> "\n"

    with {:ok, %{type: :regular, size: size}} when size <= 512 <- File.lstat(archive <> ".sha256"),
         {:ok, ^expected} <- File.read(archive <> ".sha256") do
      :ok
    else
      _ -> raise "Missing, malformed or mismatching archive SHA256 sidecar"
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

  def verify_assets!(directory) do
    archives = Path.wildcard(Path.join(directory, "*.tar.gz"))

    platforms =
      Enum.map(archives, fn path ->
        cond do
          String.contains?(Path.basename(path), "-linux-") -> :linux
          String.contains?(Path.basename(path), "-darwin-") -> :darwin
          true -> :unknown
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
end
