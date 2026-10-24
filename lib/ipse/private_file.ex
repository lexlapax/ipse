defmodule Ipse.PrivateFile do
  @moduledoc "Owner-only atomic files using existing OTP file operations."

  def write_atomic(path, bytes, opts \\ [])

  def write_atomic(path, bytes, opts) when is_binary(path) and is_binary(bytes) do
    path = Path.expand(path)
    directory = Path.dirname(path)

    temporary =
      Path.join(
        directory,
        ".ipse-private-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
      )

    try do
      with :ok <- prepare_directory(directory),
           {:ok, file} <- :file.open(String.to_charlist(temporary), [:write, :binary, :exclusive]) do
        result =
          try do
            with :ok <- File.chmod(temporary, 0o600),
                 :ok <- :file.write(file, bytes),
                 :ok <- :file.sync(file),
                 do: :ok
          after
            :file.close(file)
          end

        with :ok <- result do
          if Keyword.get(opts, :replace, true),
            do: File.rename(temporary, path),
            else: File.ln(temporary, path)
        end
      end
    after
      File.rm(temporary)
    end
  rescue
    _ -> {:error, :private_file_unavailable}
  end

  def write_atomic(_, _, _), do: {:error, :invalid_private_file}

  defp prepare_directory(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        :ok

      {:error, :enoent} ->
        with :ok <- prepare_directory(Path.dirname(path)) do
          case File.mkdir(path) do
            :ok -> File.chmod(path, 0o700)
            {:error, :eexist} -> prepare_directory(path)
            error -> error
          end
        end

      _ ->
        {:error, :unsafe_private_directory}
    end
  end
end
