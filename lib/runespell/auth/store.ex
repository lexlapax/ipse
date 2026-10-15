defmodule Runespell.Auth.Store do
  @moduledoc false
  @filename "chatgpt.json"

  def with_lock(dir, fun, timeout \\ 10_000) do
    with :ok <- prepare(dir) do
      lock = Path.join(dir, ".chatgpt.lock")
      deadline = System.monotonic_time(:millisecond) + timeout
      acquire(lock, deadline, fun)
    end
  end

  def read(dir) do
    path = Path.join(dir, @filename)

    case File.lstat(path) do
      {:error, :enoent} ->
        {:ok, %{}}

      {:ok, %{type: :regular, mode: mode, size: size}} when size <= 1_048_576 ->
        if Bitwise.band(mode, 0o077) == 0 do
          with {:ok, bytes} <- File.read(path),
               {:ok, value} when is_map(value) <- Jason.decode(bytes) do
            {:ok, value}
          else
            _ -> {:error, "ChatGPT credential file is unreadable or invalid."}
          end
        else
          {:error, "ChatGPT credential file must have owner-only permissions (chmod 600)."}
        end

      _ ->
        {:error, "ChatGPT credential path must be a regular protected file."}
    end
  end

  def write(dir, value) do
    temp =
      Path.join(
        dir,
        ".chatgpt-#{Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)}"
      )

    try do
      with {:ok, file} <- :file.open(String.to_charlist(temp), [:write, :binary, :exclusive]) do
        result =
          with :ok <- File.chmod(temp, 0o600),
               :ok <- :file.write(file, Jason.encode!(value)),
               :ok <- :file.sync(file),
               do: :ok

        :file.close(file)
        with :ok <- result, :ok <- File.rename(temp, Path.join(dir, @filename)), do: :ok
      end
    after
      File.rm(temp)
    end
    |> case do
      :ok -> :ok
      _ -> {:error, "Could not save protected ChatGPT credentials."}
    end
  end

  defp prepare(dir) do
    with :ok <- File.mkdir_p(dir),
         {:ok, %{type: :directory}} <- File.lstat(dir),
         :ok <- File.chmod(dir, 0o700) do
      :ok
    else
      _ -> {:error, "Could not prepare protected ChatGPT credential directory."}
    end
  end

  defp acquire(lock, deadline, fun) do
    case Runespell.Runner.lock(lock) do
      {:ok, owner} ->
        try do
          File.chmod(lock, 0o600)
          fun.()
        after
          Runespell.Runner.unlock(owner)
        end

      {:error, reason} when is_binary(reason) ->
        if String.starts_with?(reason, "cannot acquire session lock") and
             System.monotonic_time(:millisecond) < deadline do
          Process.sleep(50)
          acquire(lock, deadline, fun)
        else
          {:error,
           "ChatGPT credentials are busy. Retry after the other sign-in or refresh finishes."}
        end

      _ ->
        {:error, "Could not lock ChatGPT credentials."}
    end
  end
end
