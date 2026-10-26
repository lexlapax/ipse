defmodule Ipse.DocumentParser do
  @moduledoc """
  Identifies the optional bundled PDF parser without enabling it. Descriptors
  carry host-selected protected staging authority; acquisition and experimental
  selection remain with the caller. No environment helper override is accepted.
  """
  @helper Path.expand("../../priv/ipse-pdf", __DIR__)
  @external_resource @helper
  @copy_helper Path.expand("../../priv/ipse-runner", __DIR__)
  @external_resource @copy_helper
  @digest (case File.read(@helper) do
             {:ok, bytes} when byte_size(bytes) <= 32 * 1024 * 1024 ->
               :crypto.hash(:sha256, bytes)

             _ ->
               nil
           end)

  if is_binary(@digest) do
    import Bitwise
    @limit 32 * 1024 * 1024
    @copy_digest (case File.read(@copy_helper) do
                    {:ok, bytes} when byte_size(bytes) <= 32 * 1024 * 1024 ->
                      :crypto.hash(:sha256, bytes)

                    _ ->
                      nil
                  end)

    @doc "Returns the compiled bundle identity; bytes are verified in the private execution snapshot."
    def descriptor do
      with {:ok, path} <-
             Ipse.Workspace.canonical_path(bundle_file("ipse-pdf")),
           {:ok, %{uid: owner}} <- File.lstat(path),
           :ok <- protected_image(path, owner) do
        {:ok, %{path: path, sha256: Base.encode16(@digest, case: :lower)}}
      else
        _ -> {:error, :pdf_parser_unavailable}
      end
    rescue
      _ -> {:error, :pdf_parser_unavailable}
    end

    @doc "Adds host staging authority using a transient empty UID probe; creates no directories."
    def descriptor(operator_home, workspace)
        when is_binary(operator_home) and is_binary(workspace) do
      with {:ok, home} <- Ipse.Workspace.canonical_path(operator_home),
           true <- home == Path.expand(operator_home),
           {:ok, %{type: :directory, uid: candidate, mode: mode, access: :read_write} = home_stat} <-
             File.lstat(home),
           true <- (mode &&& 0o077) == 0,
           :ok <- protected_ancestors(home, candidate),
           :ok <- probe_uid(home, home_stat),
           {:ok, workspace} <- Ipse.Workspace.canonical_path(workspace),
           false <- overlap?(home, workspace),
           {:ok, descriptor} <- descriptor(),
           :ok <- protected_image(descriptor.path, candidate),
           false <- within?(descriptor.path, workspace),
           true <- is_binary(@copy_digest),
           {:ok, copy_path} <-
             Ipse.Workspace.canonical_path(bundle_file("ipse-runner")),
           :ok <- protected_image(copy_path, candidate),
           false <- within?(copy_path, workspace),
           {:ok, copy_bytes} <- File.read(copy_path),
           true <-
             byte_size(copy_bytes) <= @limit and :crypto.hash(:sha256, copy_bytes) == @copy_digest,
           {:ok, ^candidate} <- kernel_uid(copy_path) do
        copy = %{path: copy_path, sha256: Base.encode16(@copy_digest, case: :lower)}

        {:ok,
         Map.merge(descriptor, %{
           staging_root: Path.join(home, "document-parsers"),
           uid: candidate,
           workspace: workspace,
           copy_helper: copy
         })}
      else
        _ -> {:error, :pdf_parser_unavailable}
      end
    rescue
      _ -> {:error, :pdf_parser_unavailable}
    end

    def descriptor(_, _), do: {:error, :pdf_parser_unavailable}

    defp probe_uid(home, home_stat) do
      path =
        Path.join(home, ".document-parser-uid-" <> Base.encode16(:crypto.strong_rand_bytes(16)))

      with {:ok, file} <- :file.open(String.to_charlist(path), [:read, :write, :exclusive, :raw]) do
        try do
          with {:ok, record} <- :file.read_file_info(file),
               stat = File.Stat.from_record(record),
               true <-
                 stat.uid == home_stat.uid and stat.type == :regular and stat.links == 1 and
                   stat.size == 0,
               {:ok, current_home} <- File.lstat(home),
               true <- same_inode?(home_stat, current_home) and (current_home.mode &&& 0o077) == 0,
               {:ok, current} <- File.lstat(path),
               true <- same_inode?(stat, current),
               :ok <- File.chmod(path, 0o600),
               {:ok, current} <- File.lstat(path),
               true <- same_inode?(stat, current) and (current.mode &&& 0o777) == 0o600,
               :ok <- File.rm(path) do
            :ok
          else
            _ -> {:error, :pdf_parser_unavailable}
          end
        after
          # The zero-byte probe is inaccessible through the already-private home.
          # Delete only our retained inode, including when validation refuses.
          with {:ok, record} <- :file.read_file_info(file),
               stat = File.Stat.from_record(record),
               {:ok, current} <- File.lstat(path),
               true <- same_inode?(stat, current),
               do: File.rm(path)

          :file.close(file)
        end
      end
    end

    defp same_inode?(left, right),
      do:
        left.type == right.type and left.uid == right.uid and
          left.inode == right.inode and left.major_device == right.major_device and
          left.minor_device == right.minor_device

    defp bundle_file(name),
      do: Path.expand("../priv/" <> name, Path.dirname(to_string(:code.which(__MODULE__))))

    defp protected_image(path, uid) do
      root_uid = File.lstat!("/").uid

      with :ok <- protected_ancestors(Path.dirname(path), uid),
           {:ok, %{type: :regular, links: 1, uid: owner, mode: mode, size: size}} <-
             File.lstat(path),
           true <-
             owner in [0, root_uid, uid] and size > 0 and size <= @limit and
               (mode &&& 0o022) == 0 and (mode &&& 0o111) != 0 do
        :ok
      else
        _ -> {:error, :pdf_parser_unavailable}
      end
    end

    # Bootstrap uses the same protected-host/trusted-same-user boundary as the
    # OS helper. Root-owned sticky ancestors may contain a private host home.
    defp protected_ancestors(path, uid) do
      root_uid = File.lstat!("/").uid

      Enum.reduce_while(Path.split(path), "", fn component, parent ->
        current =
          if parent == "" and component == "/", do: "/", else: Path.join(parent, component)

        case File.lstat(current) do
          {:ok, %{type: :directory, uid: owner, mode: mode}} when owner in [0, root_uid, uid] ->
            if (mode &&& 0o022) == 0 or (owner in [0, root_uid] and (mode &&& 0o1000) != 0),
              do: {:cont, current},
              else: {:halt, :unsafe}

          _ ->
            {:halt, :unsafe}
        end
      end)
      |> case do
        ^path -> :ok
        _ -> {:error, :pdf_parser_unavailable}
      end
    end

    defp within?(path, root),
      do: path == root or String.starts_with?(path, String.trim_trailing(root, "/") <> "/")

    defp overlap?(left, right), do: within?(left, right) or within?(right, left)

    defp kernel_uid(helper) do
      port =
        Port.open({:spawn_executable, String.to_charlist(helper)}, [
          :binary,
          :exit_status,
          :use_stdio,
          :hide,
          args: ["--uid"]
        ])

      try do
        uid_output(port, "", System.monotonic_time(:millisecond) + 2000)
      after
        if Port.info(port), do: Port.close(port)
      end
    end

    defp uid_output(port, bytes, deadline) do
      receive do
        {^port, {:data, data}} when byte_size(bytes) + byte_size(data) <= 64 ->
          uid_output(port, bytes <> data, deadline)

        {^port, {:exit_status, 0}} ->
          case Integer.parse(String.trim(bytes)) do
            {uid, ""} when uid >= 0 -> {:ok, uid}
            _ -> {:error, :pdf_parser_unavailable}
          end

        {^port, _} ->
          {:error, :pdf_parser_unavailable}
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          {:error, :pdf_parser_unavailable}
      end
    end
  else
    def descriptor, do: {:error, :pdf_parser_unavailable}
    def descriptor(_, _), do: {:error, :pdf_parser_unavailable}
  end
end
