defmodule Ipse.Development.Knowledge.PilotReservation do
  @moduledoc """
  One fixed, permanently charged local-pilot reservation under a retained native lock.

  An existing reservation, including a malformed or interrupted one, refuses
  every later launch. This is a local accounting guard, not a service receipt.
  """
  alias Ipse.{JSON, Runner, Workspace}
  import Bitwise

  @id "6a505a8bc83441888b1997c7f0f941f0"
  @error {:error, :pilot_reservation_unavailable}
  @reservation @id <> ".reservation"
  @lock @id <> ".lock"

  def with_reservation(declaration, fun) when is_map(declaration) and is_function(fun, 1) do
    with {:ok, uid} <- Runner.protected_current_uid(),
         {:ok, file} <- File.open("/etc/passwd", [:read, :binary, :raw]) do
      try do
        with {:ok, home} <- read_account_home(fn count -> :file.read(file, count) end, uid) do
          with_reservation_in_home(home, declaration, fun)
        else
          _ -> @error
        end
      after
        File.close(file)
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def read_account_home(read, uid) when is_function(read, 1) do
    with {:ok, contents} when is_binary(contents) <- read.(1_048_577),
         true <- byte_size(contents) <= 1_048_576,
         :eof <- read.(1),
         do: account_home(contents, uid),
         else: (_ -> @error)
  rescue
    _ -> @error
  end

  def read_account_home(_, _), do: @error

  @doc false
  # No environment-controlled home or fallback: an ambiguous/nonlocal account refuses.
  def account_home(contents, uid) when is_binary(contents) and is_integer(uid) and uid >= 0 do
    homes =
      if byte_size(contents) <= 1_048_576 and String.valid?(contents) do
        for line <- String.split(contents, "\n"),
            [_, _, number, _, _, home, _] <- [String.split(line, ":")],
            Regex.match?(~r/\A[0-9]+\z/, number),
            Integer.parse(number) == {uid, ""},
            do: home
      else
        []
      end

    with [home] <- homes,
         true <- home != "" and Path.type(home) == :absolute and not String.contains?(home, <<0>>) do
      {:ok, home}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def account_home(_, _), do: @error

  @doc false
  # Explicit test entry point; the production launcher never accepts a home argument.
  def with_reservation_in_home(home, declaration, fun)
      when is_binary(home) and is_map(declaration) and is_function(fun, 1) do
    with {:ok, uid} <- Runner.protected_current_uid(),
         {:ok, root} <- root(home, uid),
         :ok <- valid_entries(root),
         {:ok, port} <- Runner.protected_header_lock(Path.join(root, @lock)) do
      result =
        try do
          with {:ok, guard} <- guard(root, port, uid),
               :ok <- guard.(),
               {:ok, retained} <- reserve(root, declaration, guard, uid),
               :ok <- retained.(),
               result <- fun.(retained),
               :ok <- retained.() do
            result
          else
            _ -> @error
          end
        rescue
          _ -> @error
        catch
          _, _ -> @error
        end

      case Runner.unlock_export_candidate(port) do
        :ok -> result
        _ -> {:error, :pilot_reservation_cleanup_unconfirmed}
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def with_reservation_in_home(_, _, _), do: @error

  defp root(home, uid) do
    home = Path.expand(home)
    parent = Path.join(home, ".ipse")
    root = Path.join(parent, "p31a-pilot-authorizations")

    with :ok <- private_dir(parent, uid),
         {:ok, ^parent} <- Workspace.canonical_path(parent),
         :ok <- mkdir(root, parent),
         :ok <- private_dir(root, uid),
         {:ok, canonical} <- Workspace.canonical_path(root),
         true <- canonical == root do
      {:ok, root}
    else
      _ -> @error
    end
  end

  defp mkdir(path, parent) do
    case File.mkdir(path) do
      :ok ->
        with :ok <- File.chmod(path, 0o700),
             do: Runner.protected_sync_directory(parent)

      {:error, :eexist} ->
        :ok

      _ ->
        @error
    end
  end

  defp private_dir(path, uid) do
    case File.lstat(path) do
      {:ok, %{type: :directory, uid: ^uid, mode: mode}} when band(mode, 0o7777) == 0o700 -> :ok
      _ -> @error
    end
  end

  defp valid_entries(root) do
    with {:ok, names} <- File.ls(root),
         true <- names == [],
         do: :ok,
         else: (_ -> @error)
  end

  defp guard(root, port, uid) do
    lock_path = Path.join(root, @lock)

    with {:ok, directory} <- File.lstat(root),
         {:ok, lock} <- File.lstat(lock_path),
         true <- lock.type == :regular and lock.uid == uid and lock.links == 1 and lock.size == 0,
         true <- band(lock.mode, 0o7777) == 0o600,
         {:ok, identity} <- Runner.session_header_lock_identity(port, deadline()),
         true <- same_file?(lock, identity) do
      {:ok,
       fn ->
         with :ok <- private_dir(root, uid),
              {:ok, current_dir} <- File.lstat(root),
              true <- same_stat?(current_dir, directory),
              {:ok, current_lock} <- File.lstat(lock_path),
              true <- same_stat?(current_lock, lock),
              {:ok, current_identity} <- Runner.session_header_lock_identity(port, deadline()),
              true <- same_file?(current_lock, current_identity),
              do: :ok,
              else: (_ -> @error)
       end}
    else
      _ -> @error
    end
  end

  defp reserve(root, declaration, guard, uid) do
    event = %{
      "version" => 1,
      "authorization_id" => @id,
      "local_call_allowance" => 1000,
      "previously_charged" => 4,
      "reserved_calls" => 120,
      "declaration_sha256" => JSON.digest([declaration]),
      "retries" => 0
    }

    path = Path.join(root, @reservation)
    contents = Jason.encode!(event) <> "\n"

    with :ok <- guard.(),
         {:ok, file} <- File.open(path, [:write, :binary, :exclusive]) do
      try do
        with :ok <- File.chmod(path, 0o600),
             :ok <- IO.binwrite(file, contents),
             :ok <- :file.sync(file),
             :ok <- Runner.protected_sync_directory(root),
             :ok <- guard.(),
             {:ok, stat} <- File.lstat(path),
             true <- private_reservation?(stat, uid, byte_size(contents)),
             :ok <- current_reservation(path, stat, contents, uid) do
          {:ok,
           fn ->
             with :ok <- guard.(),
                  do: current_reservation(path, stat, contents, uid)
           end}
        else
          _ -> @error
        end
      after
        File.close(file)
      end
    else
      _ -> @error
    end
  end

  defp current_reservation(path, expected, contents, uid) do
    with {:ok, file} <- File.open(path, [:read, :binary, :raw]) do
      try do
        with {:ok, raw_stat} <- :file.read_file_info(file),
             stat = File.Stat.from_record(raw_stat),
             true <- private_reservation?(stat, uid, byte_size(contents)),
             true <- same_stat?(stat, expected),
             {:ok, ^contents} <- :file.read(file, byte_size(contents)),
             :eof <- :file.read(file, 1),
             {:ok, named} <- File.lstat(path),
             true <- private_reservation?(named, uid, byte_size(contents)),
             true <- same_stat?(named, expected),
             do: :ok,
             else: (_ -> @error)
      after
        File.close(file)
      end
    else
      _ -> @error
    end
  end

  defp private_reservation?(stat, uid, size),
    do:
      stat.type == :regular and stat.uid == uid and stat.links == 1 and stat.size == size and
        band(stat.mode, 0o7777) == 0o600

  defp same_stat?(a, b),
    do: a.major_device == b.major_device and a.inode == b.inode and a.uid == b.uid

  defp same_file?(stat, identity),
    do: stat.major_device == identity.device and stat.inode == identity.inode

  defp deadline, do: System.monotonic_time(:millisecond) + 5_000
end
