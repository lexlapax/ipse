defmodule IpseKnowledge.Documents.ParserStage do
  @moduledoc false
  import Bitwise
  @image_limit 32 * 1024 * 1024

  # The host admits all descriptor fields. The document/model supplies none of
  # them. Same-UID arbitrary unsandboxed execution remains trusted; this private
  # snapshot boundary excludes source/workspace pathname replacement races.
  def run(
        bytes,
        %{path: _, sha256: _, staging_root: _, uid: _, workspace: _, copy_helper: _} = descriptor,
        limits
      ) do
    caller = self()
    tag = make_ref()

    {guardian, monitor} =
      spawn_monitor(fn ->
        Process.flag(:trap_exit, true)
        :proc_lib.set_label({__MODULE__, :guardian})
        owner = Process.monitor(caller)
        result = job(bytes, descriptor, limits, owner)
        send(caller, {tag, result})
      end)

    receive do
      {^tag, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^guardian, _} ->
        {:error, :pdf_staging_unavailable}
    end
  end

  def run(_, _, _), do: {:error, :pdf_parser_identity_unavailable}

  defp job(bytes, descriptor, limits, owner) do
    with :ok <- root(descriptor), {:ok, stage} <- claim(descriptor) do
      case snapshot(descriptor, stage, owner) do
        {:ok, stage} ->
          {result, quiescent?} = launch(bytes, descriptor, limits, owner, stage)
          if quiescent?, do: cleanup(stage)
          result

        {:error, code, quiescent?} ->
          if quiescent?, do: cleanup_unlaunched(stage, descriptor.uid)
          {:error, code}
      end
    else
      {:error, code} when is_atom(code) -> {:error, code}
      _ -> {:error, :pdf_staging_unavailable}
    end
  rescue
    _ -> {:error, :pdf_staging_unavailable}
  end

  defp snapshot(
         %{
           path: path,
           sha256: digest,
           uid: uid,
           workspace: workspace,
           copy_helper: %{path: copy, sha256: copy_digest}
         },
         stage,
         owner
       )
       when is_binary(path) and is_binary(digest) and is_integer(uid) do
    with true <-
           absolute?(path) and not overlap?(path, workspace) and absolute?(copy) and
             not overlap?(copy, workspace),
         :ok <- ancestors(Path.dirname(path), uid),
         :ok <- ancestors(Path.dirname(copy), uid),
         {:ok, before} <- File.lstat(path),
         true <-
           before.type == :regular and before.links == 1 and before.uid in [0, uid] and
             (before.mode &&& 0o022) == 0 and (before.mode &&& 0o111) != 0 and
             before.size <= @image_limit,
         {:ok, copy_stat} <- File.lstat(copy),
         true <-
           copy_stat.type == :regular and copy_stat.links == 1 and copy_stat.uid in [0, uid] and
             (copy_stat.mode &&& 0o022) == 0 and (copy_stat.mode &&& 0o111) != 0 and
             copy_stat.size <= @image_limit,
         {:ok, copy_bytes} <- File.read(copy),
         true <- hash(copy_bytes) == copy_digest do
      port =
        Port.open(
          {:spawn_executable, String.to_charlist(copy)},
          [
            :binary,
            :exit_status,
            :use_stdio,
            :stderr_to_stdout,
            :hide,
            args: ["--copy-regular", path, stage.path, Integer.to_string(before.size)]
          ]
        )

      case copied(port, owner, "", false, System.monotonic_time(:millisecond) + 6000) do
        {:ok, receipt} ->
          with %{
                 "version" => 1,
                 "bytes" => size,
                 "source" => source,
                 "destination" => destination
               } <- JSON.decode!(receipt),
               true <- size == before.size and source["inode"] == Integer.to_string(before.inode),
               true <- source["nlink"] == "1" and destination["nlink"] == "1",
               {:ok, image_stat} <- File.lstat(stage.path),
               true <-
                 image_stat.type == :regular and image_stat.links == 1 and image_stat.uid == uid and
                   image_stat.size == size and (image_stat.mode &&& 0o777) == 0o600,
               true <- destination["inode"] == Integer.to_string(image_stat.inode),
               {:ok, image} <- File.read(stage.path),
               true <- byte_size(image) == size and hash(image) == digest,
               :ok <- File.chmod(stage.path, 0o500) do
            {:ok, %{stage | image: File.lstat!(stage.path)}}
          else
            _ -> {:error, :pdf_parser_identity_unavailable, true}
          end

        {:error, code, confirmed?} ->
          {:error, code, confirmed?}
      end
    else
      _ -> {:error, :pdf_parser_identity_unavailable, true}
    end
  rescue
    _ -> {:error, :pdf_parser_identity_unavailable, false}
  end

  defp snapshot(_, _, _), do: {:error, :pdf_parser_identity_unavailable, true}

  defp copied(port, owner, output, cancelled?, deadline) do
    receive do
      {:DOWN, ^owner, :process, _, _} ->
        copied(port, owner, output, true, deadline)

      {^port, {:data, data}} when byte_size(output) + byte_size(data) <= 2048 ->
        copied(port, owner, output <> data, cancelled?, deadline)

      {^port, {:exit_status, status}} ->
        cond do
          cancelled? -> {:error, :extraction_cancelled, true}
          status == 0 -> {:ok, output}
          true -> {:error, :pdf_parser_identity_unavailable, true}
        end

      {:EXIT, ^port, _} ->
        copied(port, owner, output, cancelled?, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        if Port.info(port), do: Port.close(port)
        {:error, :extraction_timeout, false}
    end
  end

  defp root(%{staging_root: path, uid: uid, workspace: workspace}) do
    home = Path.dirname(path)

    with true <-
           absolute?(path) and Path.basename(path) == "document-parsers" and
             not overlap?(home, workspace),
         :ok <- ancestors(home, uid),
         :ok <- private(home, uid),
         :ok <- create_private(path, uid) do
      :ok
    else
      _ -> {:error, :unsafe_pdf_staging_root}
    end
  end

  defp root(_), do: {:error, :unsafe_pdf_staging_root}

  defp ancestors(path, uid) do
    root_uid = File.lstat!("/").uid

    Enum.reduce_while(Path.split(path), "", fn component, parent ->
      current = if parent == "" and component == "/", do: "/", else: Path.join(parent, component)

      case File.lstat(current) do
        {:ok, %{type: :directory, uid: owner, mode: mode}} when owner in [0, root_uid, uid] ->
          # A root-owned sticky temporary ancestor can contain an owner-only
          # home, but can never itself serve as the staging/home directory.
          if (mode &&& 0o022) == 0 or (owner in [0, root_uid] and (mode &&& 0o1000) != 0),
            do: {:cont, current},
            else: {:halt, :unsafe}

        _ ->
          {:halt, :unsafe}
      end
    end)
    |> case do
      ^path -> :ok
      _ -> {:error, :unsafe_pdf_staging_root}
    end
  end

  defp private(path, uid) do
    case File.lstat(path) do
      {:ok, %{type: :directory, uid: ^uid, mode: mode}} when (mode &&& 0o077) == 0 -> :ok
      _ -> {:error, :unsafe_pdf_staging_root}
    end
  end

  defp create_private(path, uid) do
    case File.mkdir(path) do
      :ok -> File.chmod(path, 0o700)
      {:error, :eexist} -> :ok
      error -> error
    end
    |> case do
      :ok -> private(path, uid)
      error -> error
    end
  end

  defp claim(descriptor) do
    Enum.reduce_while(0..3, {:error, :pdf_parser_slots_busy}, fn number, _ ->
      slot = Path.join(descriptor.staging_root, "slot-#{number}")
      active = Path.join(slot, "active")

      with :ok <- create_private(slot, descriptor.uid), :ok <- File.mkdir(active) do
        :ok = File.chmod(active, 0o700)
        identity = File.lstat!(active)

        leaf =
          Path.join(
            active,
            "parser-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
          )

        {:halt,
         {:ok,
          %{
            active: active,
            directory: identity,
            path: leaf,
            image: nil,
            digest: descriptor.sha256,
            lock: Path.join(slot, "lock")
          }}}
      else
        {:error, :eexist} -> {:cont, {:error, :pdf_parser_slots_busy}}
        _ -> {:halt, {:error, :unsafe_pdf_staging_root}}
      end
    end)
  end

  defp launch(bytes, _descriptor, limits, owner, stage) do
    receive do
      {:DOWN, ^owner, :process, _, _} -> {{:error, :extraction_cancelled}, true}
    after
      0 ->
        try do
          port =
            Port.open(
              {:spawn_executable, String.to_charlist(stage.path)},
              [
                :binary,
                :exit_status,
                :use_stdio,
                :stderr_to_stdout,
                :hide,
                args: ["--lease", stage.lock]
              ]
            )

          deadline = System.monotonic_time(:millisecond) + 8000

          request =
            <<"IPDF0001", limits.max_pages::32, limits.max_expanded_bytes::32,
              limits.max_text_bytes::32, byte_size(bytes)::32, bytes::binary>>

          {result, sent?, exited?} =
            collect(port, owner, request, limits, deadline, "", false, false)

          if Port.info(port), do: Port.close(port)
          # Before readiness/request dispatch, a confirmed supervisor exit
          # proves no fork could occur. Otherwise the shared native lease is the
          # final authority: it is retained by both supervisor and fork child.
          quiescent? = exited? and (not sent? or probe(stage, 60))
          {result, quiescent?}
        rescue
          _ -> {{:error, :pdf_parser_unavailable}, false}
        end
    end
  end

  defp collect(port, owner, request, limits, deadline, output, ready?, cancelled?) do
    receive do
      {:DOWN, ^owner, :process, _, _} ->
        if ready? and Port.info(port), do: Port.command(port, <<0::192>>)
        collect(port, owner, request, limits, deadline, output, ready?, true)

      {^port, {:data, data}} ->
        output = output <> data

        cond do
          not ready? and byte_size(output) >= 8 ->
            case output do
              <<"IPLEASE1", rest::binary>> ->
                true = Port.command(port, if(cancelled?, do: <<0::192>>, else: request))
                collect(port, owner, request, limits, deadline, rest, true, cancelled?)

              _ ->
                {{:error, :pdf_protocol_error}, false, false}
            end

          byte_size(output) > limits.max_text_bytes + limits.max_pages * 9 + 21 ->
            {{:error, :pdf_output_limit}, ready?, false}

          true ->
            collect(port, owner, request, limits, deadline, output, ready?, cancelled?)
        end

      {^port, {:exit_status, status}} ->
        result =
          cond do
            cancelled? -> {:error, :extraction_cancelled}
            status != 0 -> {:error, :pdf_resource_limit}
            not ready? -> {:error, :pdf_protocol_error}
            true -> {:ok, output}
          end

        {result, ready?, true}

      {:EXIT, ^port, _} ->
        collect(port, owner, request, limits, deadline, output, ready?, cancelled?)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        {{:error, :extraction_timeout}, ready?, false}
    end
  end

  defp probe(_, 0), do: false

  defp probe(stage, remaining) do
    if identity?(stage) do
      port =
        Port.open(
          {:spawn_executable, String.to_charlist(stage.path)},
          [:binary, :exit_status, :use_stdio, :hide, args: ["--lease-check", stage.lock]]
        )

      result = probe_result(port, "", System.monotonic_time(:millisecond) + 1000)
      if Port.info(port), do: Port.close(port)

      case result do
        :free ->
          true

        :busy ->
          Process.sleep(100)
          probe(stage, remaining - 1)

        :unknown ->
          false
      end
    else
      false
    end
  rescue
    _ -> false
  end

  defp probe_result(port, bytes, deadline) do
    receive do
      {^port, {:data, data}} when byte_size(bytes) + byte_size(data) <= 10 ->
        probe_result(port, bytes <> data, deadline)

      {^port, {:exit_status, 0}} ->
        if(bytes == "QUIESCENT\n", do: :free, else: :unknown)

      {^port, {:exit_status, 1}} ->
        :busy

      {^port, {:exit_status, _}} ->
        :unknown

      {:EXIT, ^port, _} ->
        :unknown
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> :unknown
    end
  end

  defp identity?(stage) do
    with {:ok, directory} <- File.lstat(stage.active),
         true <- same?(directory, stage.directory),
         {:ok, image} <- File.lstat(stage.path),
         true <- same?(image, stage.image),
         true <- image.type == :regular and image.links == 1 and (image.mode &&& 0o777) == 0o500,
         {:ok, bytes} <- File.read(stage.path),
         true <- hash(bytes) == stage.digest,
         do: true,
         else: (_ -> false)
  end

  defp cleanup(stage) do
    if identity?(stage) do
      File.rm(stage.path)
      File.rmdir(stage.active)
    end
  end

  defp cleanup_unlaunched(stage, uid) do
    with {:ok, directory} <- File.lstat(stage.active),
         true <- same?(directory, stage.directory) do
      case File.lstat(stage.path) do
        {:ok, %{type: :regular, links: 1, uid: ^uid, size: size}} when size <= @image_limit ->
          File.rm(stage.path)

        {:error, :enoent} ->
          :ok

        _ ->
          :unsafe
      end

      File.rmdir(stage.active)
    end
  end

  defp same?(left, right),
    do:
      left.inode == right.inode and left.major_device == right.major_device and
        left.minor_device == right.minor_device

  defp absolute?(path),
    do: is_binary(path) and Path.type(path) == :absolute and Path.expand(path) == path

  defp overlap?(left, right),
    do:
      left == right or String.starts_with?(left, right <> "/") or
        String.starts_with?(right, left <> "/")

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
