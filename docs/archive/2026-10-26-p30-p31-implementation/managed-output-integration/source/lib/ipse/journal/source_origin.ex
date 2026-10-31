defmodule Ipse.Journal.SourceOrigin do
  @moduledoc """
  Original journal location for newly created Session sources.

  The creator records facts from the newly opened file in its first record.
  A live owner compares them with its actual descriptor before accepting the
  journal for work. Copies remain inspectable, but cannot inherit the original
  file's live authority. Legacy histories are distinguishable and never acquire
  an origin during resume. This is a cooperative-storage check, not protection
  against arbitrary code rewriting an operator's files and records coherently.
  """
  alias Ipse.{JSON, Workspace}
  @layout "journal_origin_v1"
  @keys ~w(version session_id directory major_device minor_device inode uid)
  @error {:error, :journal_origin_unavailable}

  def layout, do: @layout

  @doc false
  def create(file, path, id, metadata) do
    case metadata["source_origin_layout"] do
      nil ->
        if Map.has_key?(metadata, "source_origin"), do: @error, else: {:ok, metadata}

      @layout ->
        with false <- Map.has_key?(metadata, "source_origin"),
             {:ok, origin} <- facts(file, path, id) do
          {:ok, Map.put(metadata, "source_origin", origin)}
        else
          _ -> @error
        end

      _ ->
        @error
    end
  end

  @doc "Validate recorded shape without establishing that its source still exists."
  def recorded(metadata, id) when is_map(metadata) do
    case {metadata["source_origin_layout"], Map.fetch(metadata, "source_origin")} do
      {nil, :error} -> {:ok, nil}
      {@layout, {:ok, origin}} -> if valid?(origin, id), do: {:ok, origin}, else: @error
      _ -> @error
    end
  end

  def recorded(_, _), do: @error

  @doc false
  def check(file, path, id, metadata) do
    with {:ok, recorded} <- recorded(metadata, id) do
      if is_nil(recorded) do
        :ok
      else
        case facts(file, path, id) do
          {:ok, ^recorded} -> :ok
          _ -> @error
        end
      end
    end
  end

  @doc false
  def check_path(directory, id, metadata) do
    path = Path.join(directory, id <> ".jsonl")

    with {:ok, file} <- :file.open(String.to_charlist(path), [:read, :binary, :raw]) do
      try do
        check(file, path, id, metadata)
      after
        :file.close(file)
      end
    else
      _ -> @error
    end
  end

  defp facts(file, path, id) do
    with {:ok, directory} <- Workspace.canonical_path(Path.dirname(path)),
         {:ok, path_stat} <- File.lstat(path),
         {:ok, info} <- :file.read_file_info(file),
         stat = File.Stat.from_record(info),
         true <- protected?(stat) and protected?(path_stat),
         true <- identity(stat) == identity(path_stat),
         {:ok, parent} <- File.lstat(directory),
         true <- parent.type == :directory and parent.uid == stat.uid,
         true <- Bitwise.band(parent.mode, 0o077) == 0,
         origin = %{
           "version" => 1,
           "session_id" => id,
           "directory" => directory,
           "major_device" => stat.major_device,
           "minor_device" => stat.minor_device,
           "inode" => stat.inode,
           "uid" => stat.uid
         },
         true <- valid?(origin, id) do
      {:ok, origin}
    else
      _ -> @error
    end
  end

  defp valid?(origin, id) do
    is_map(origin) and Enum.sort(Map.keys(origin)) == Enum.sort(@keys) and
      origin["version"] === 1 and origin["session_id"] === id and
      is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id) and
      is_binary(origin["directory"]) and String.valid?(origin["directory"]) and
      byte_size(origin["directory"]) in 1..4096 and
      not String.contains?(origin["directory"], <<0>>) and
      Path.type(origin["directory"]) == :absolute and
      Path.expand(origin["directory"]) == origin["directory"] and
      Enum.all?(~w(major_device minor_device inode uid), &JSON.safe_uint?(origin[&1])) and
      origin["inode"] > 0
  rescue
    _ -> false
  end

  defp protected?(stat),
    do: stat.type == :regular and stat.links == 1 and Bitwise.band(stat.mode, 0o077) == 0

  defp identity(stat), do: {stat.major_device, stat.minor_device, stat.inode, stat.uid}
end
