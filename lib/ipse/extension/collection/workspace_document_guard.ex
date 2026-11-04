defmodule Ipse.Extension.Collection.WorkspaceDocumentGuard do
  @moduledoc false
  alias Ipse.Extension.Collection.{DocumentSourceUse, DocumentStage}

  def guarded_request?(request) when is_map(request) do
    guard = request["workspace_guard"]

    Enum.sort(Map.keys(request)) == ~w(op request scope workspace_guard) and
      request["op"] === "collection.store" and request["scope"] === "project" and
      is_map(request["request"]) and
      (request["request"]["op"] in ~w(commit value.put_inline) or
         (request["request"]["op"] === "value.write_parts" and
            request["request"]["publish"] === true)) and is_map(guard) and
      Enum.sort(Map.keys(guard)) ==
        ~w(bundle_sha256 generation opening_operation_id original_sha256 path source_id) and
      is_binary(guard["path"]) and String.valid?(guard["path"]) and
      byte_size(guard["path"]) in 1..1024 and
      is_binary(guard["source_id"]) and String.valid?(guard["source_id"]) and
      byte_size(guard["source_id"]) in 1..256 and
      is_integer(guard["generation"]) and guard["generation"] > 0 and
      Ipse.JSON.safe_uint?(guard["generation"]) and
      Ipse.JSON.sha256?(guard["original_sha256"]) and
      Ipse.JSON.sha256?(guard["bundle_sha256"]) and
      is_binary(guard["opening_operation_id"]) and
      Regex.match?(~r/\A[0-9a-f]{32}\z/, guard["opening_operation_id"])
  rescue
    _ -> false
  end

  def guarded_request?(_), do: false

  def preflight_read(request) do
    if guarded_request?(request) do
      guard = request["workspace_guard"]

      {:ok,
       %{
         "op" => "tool.call",
         "name" => "read",
         "timeout_ms" => 5000,
         "arguments" => %{
           "snapshot" => "start",
           "path" => guard["path"],
           "expected_sha256" => guard["original_sha256"]
         }
       }}
    else
      {:error, :document_store_refused}
    end
  end

  # Called only by the actual Session while the exact document action is live.
  # It returns an internal classification, never an extension-facing grant.
  def authorize(session, intent, :not_workspace_document) do
    parent = session.invocation.parent
    outer = get_in(parent, ["payload", "arguments"])
    action = if is_map(outer), do: outer["action"]
    args = if is_map(outer), do: outer["args"]

    document_invocation =
      get_in(parent, ["descriptor", "id"]) === "source" and
        (action in ~w(read_document continue_collection_document put_document) or
           (action === "continue_collection_source" and is_map(args) and
              args["input_action"] === "put_document"))

    if document_invocation or guarded_request?(intent["request"]),
      do: {:error, :document_store_refused},
      else: {:ok, :other_source}
  rescue
    _ -> {:error, :document_store_refused}
  end

  def authorize(session, intent, document) do
    parent = session.invocation.parent
    identity = parent["identity"]
    descriptor = parent["descriptor"]
    outer = parent["payload"]["arguments"]

    with true <- is_map(document) and is_map(outer),
         true <- descriptor["id"] === "source" and descriptor["stage"] === "invoke.command",
         {:ok, entry, ^descriptor} <-
           Ipse.Extension.Catalog.lookup(session.config, descriptor["stage"], descriptor["name"]),
         true <- entry.identity === identity and Ipse.Extension.Registry.live?(identity),
         {:ok, kind, args} <- source_args(outer),
         true <-
           args["source_id"] === document["source_id"] and
             args["generation"] === document["generation"] do
      case kind do
        :supplied -> supplied(intent, args, document)
        :workspace -> workspace(session, intent, parent, identity, document)
      end
    else
      _ -> {:error, :document_store_refused}
    end
  rescue
    _ -> {:error, :document_store_refused}
  end

  defp source_args(%{"action" => "put_document", "args" => args}) when is_map(args),
    do: {:ok, :supplied, args}

  defp source_args(%{"action" => "continue_collection_source", "args" => args})
       when is_map(args) do
    if args["input_action"] === "put_document" and is_map(args["input_args"]),
      do: {:ok, :supplied, args["input_args"]},
      else: {:error, :document_store_refused}
  end

  defp source_args(%{"action" => action, "args" => args})
       when action in ~w(read_document continue_collection_document) and is_map(args),
       do: {:ok, :workspace, args}

  defp source_args(_), do: {:error, :document_store_refused}

  defp supplied(intent, args, document) do
    with false <- guarded_request?(intent["request"]),
         true <- is_nil(document["path"]) and is_nil(document["acquisition_operation_id"]),
         encoded when is_binary(encoded) and byte_size(encoded) <= 8192 <- args["bytes_base64"],
         {:ok, bytes} <- Base.decode64(encoded),
         true <- byte_size(bytes) === document["original_bytes"],
         true <- Ipse.JSON.sha256(bytes) === document["original_sha256"] do
      {:ok, :supplied}
    else
      _ -> {:error, :document_store_refused}
    end
  end

  defp workspace(session, intent, parent, identity, document) do
    outer = parent["payload"]["arguments"]
    args = outer["args"]
    identity_sha = Ipse.JSON.digest([identity])

    with true <- guarded_request?(intent["request"]),
         path when is_binary(path) <- document["path"],
         true <- args["path"] === path,
         sha when is_binary(sha) <- document["original_sha256"],
         true <- is_nil(args["expected_sha256"]) or args["expected_sha256"] === sha,
         guard = intent["request"]["workspace_guard"],
         expected = %{
           "path" => path,
           "original_sha256" => sha,
           "opening_operation_id" => document["acquisition_operation_id"],
           "source_id" => document["source_id"],
           "generation" => document["generation"],
           "bundle_sha256" => document["bundle_sha256"]
         },
         true <- guard === expected do
      case Ipse.Journal.Writer.source_query(
             session.journal_writer,
             {:workspace_acquisition, guard["opening_operation_id"], identity_sha}
           ) do
        {:ok, receipt} ->
          binding = Ipse.Session.WorkspaceAcquisition.source_binding(outer)

          if receipt["path"] === path and receipt["sha256"] === sha and
               receipt["byte_count"] === document["original_bytes"] and
               receipt["artifact_sha256"] === identity["artifact_sha256"] and
               Ipse.JSON.sha256?(binding) and binding === receipt["source_binding_sha256"] and
               (receipt["parent_invocation_id"] === parent["invocation_id"] or
                  receipt["plan_sha256"] === document["bundle_sha256"]) do
            {:ok, :workspace}
          else
            {:error, :document_store_refused}
          end

        _ ->
          with {:ok, receipt} <-
                 Ipse.Journal.Writer.source_query(
                   session.journal_writer,
                   {:legacy_workspace_acquisition, parent["invocation_id"], identity_sha, path,
                    sha}
                 ),
               true <- receipt["operation_id"] === guard["opening_operation_id"],
               true <- receipt["byte_count"] === document["original_bytes"] do
            {:ok, :legacy_workspace}
          else
            _ -> {:error, :document_store_refused}
          end
      end
    else
      _ -> {:error, :document_store_refused}
    end
  end

  def check(context, intent, changes, read) do
    guarded = guarded_request?(intent["request"])

    source_write =
      Enum.any?(changes, fn change ->
        is_binary(change["key"]) and String.starts_with?(change["key"], "source.") and
          not is_nil(change["value"])
      end)

    if guarded or source_write do
      case pinned_corpus(context) do
        {:ok, true} -> check_corpus(context, intent, changes, read)
        {:ok, false} when guarded -> {:error, :document_store_refused}
        {:ok, false} -> :ok
        _ -> {:unknown, :document_guard_unconfirmed}
      end
    else
      :ok
    end
  rescue
    _ -> {:unknown, :document_guard_unconfirmed}
  catch
    :exit, _ -> {:unknown, :document_guard_unconfirmed}
  end

  # Catalog entries are host-shipped metadata, not values supplied by a Worker.
  def selected_bundle?(identity, bundles) when is_map(identity) and is_list(bundles) do
    Enum.any?(bundles, fn bundle ->
      bundle.id === "corpus-collection-documents" and
        bundle.digest === identity["artifact_sha256"]
    end)
  rescue
    _ -> false
  end

  def selected_bundle?(_, _), do: false

  @doc false
  def bundle_selection(identity, "ipse-knowledge/corpus", {:ok, bundles})
      when is_map(identity) and is_list(bundles) do
    case Enum.filter(bundles, &(&1.id === "corpus-collection-documents")) do
      [bundle] -> {:ok, bundle.digest === identity["artifact_sha256"]}
      _ -> {:error, :document_guard_unconfirmed}
    end
  rescue
    _ -> {:error, :document_guard_unconfirmed}
  end

  def bundle_selection(_identity, "ipse-knowledge/corpus", _),
    do: {:error, :document_guard_unconfirmed}

  def bundle_selection(_identity, _other_id, _inventory), do: {:ok, false}

  defp pinned_corpus(context) do
    identity = context.identity
    parent = context.parent
    entry = Enum.find(context.config[:extensions] || [], &(&1.identity === identity))

    with true <- is_map(entry) and parent["identity"] === identity,
         true <- Ipse.Extension.Registry.live?(identity),
         {:ok, artifact} <- Ipse.Extension.Registry.lookup(entry.store, identity["artifact"]),
         true <- artifact.digest === identity["artifact_sha256"] do
      bundle_selection(identity, artifact.manifest["id"], Ipse.Extension.Bundles.inventory())
    else
      _ -> {:error, :document_store_refused}
    end
  end

  defp check_corpus(context, intent, changes, read) do
    with {:ok, documents} <- inspect_changes(changes, read, intent["operation_id"]),
         :ok <- check_documents(context, intent, documents),
         :ok <-
           GenServer.call(
             context.owner,
             {:extension_document_current, context.job_ref, intent}
           ),
         true <- Ipse.Session.Resources.active?() do
      :ok
    else
      {:unknown, _} = unknown -> unknown
      _ -> {:error, :document_store_refused}
    end
  end

  defp check_documents(context, intent, documents) do
    Enum.reduce_while(documents, :ok, fn document, :ok ->
      case GenServer.call(
             context.owner,
             {:extension_workspace_document_authorize, context.job_ref, intent, document}
           ) do
        {:ok, kind} when kind in [:supplied, :other_source] ->
          {:cont, :ok}

        {:ok, kind} when kind in [:workspace, :legacy_workspace] ->
          case current_file(context, document) do
            :ok -> {:cont, :ok}
            other -> {:halt, other}
          end

        _ ->
          {:halt, {:error, :document_store_refused}}
      end
    end)
  end

  # The Session Worker starts this task before entering its tracked file effect.
  # The task waits until the authenticated publication callback asks it to read.
  def with_snapshot_reader(context, intent, fun) when is_function(fun, 1) do
    if guarded_request?(intent["request"]) do
      guard = intent["request"]["workspace_guard"]
      token = make_ref()

      task =
        Ipse.Session.Resources.async(fn -> snapshot_reader(context, intent, guard, token) end)

      Process.unlink(task.pid)
      reader = %{pid: task.pid, token: token, path: guard["path"], sha: guard["original_sha256"]}

      result =
        try do
          fun.(
            context
            |> Map.put(:workspace_snapshot_reader, reader)
            |> Map.put(:snapshot_intent, intent)
          )
        catch
          _, _ -> {:unknown, :workspace_check_unconfirmed}
        end

      cleanup = Task.yield(task, 0) || Task.shutdown(task, :brutal_kill)

      case cleanup do
        {:ok, :reader_finished} -> result
        nil -> result
        _ -> {:unknown, :workspace_check_unconfirmed}
      end
    else
      fun.(context)
    end
  end

  def run_document_effect(context, intent, fun) when is_function(fun, 0) do
    case context[:workspace_snapshot_reader] do
      %{pid: reader, token: token} ->
        Ipse.Session.Resources.document_file_effect(fun, fn peer ->
          GenServer.call(
            context.owner,
            {:extension_workspace_snapshot_register, context.job_ref, intent, reader, peer, token}
          )
        end)

      _ ->
        Ipse.Session.Resources.file_effect(fun)
    end
  end

  defp snapshot_reader(context, intent, guard, token) do
    receive do
      {:workspace_snapshot_read, ^token, peer} when is_pid(peer) ->
        allowed =
          try do
            GenServer.call(
              context.owner,
              {:extension_workspace_snapshot_peer, context.job_ref, intent, peer, token}
            ) == :ok
          catch
            :exit, _ -> false
          end

        result =
          if allowed do
            Ipse.Session.Resources.file_effect(fn ->
              Ipse.Tools.workspace_binary_snapshot(
                guard["path"],
                guard["original_sha256"],
                context
              )
            end)
          else
            {:error, :workspace_snapshot_refused}
          end

        send(peer, {:workspace_snapshot_result, token, result})
        :reader_finished
    after
      30_000 -> :reader_expired
    end
  end

  defp current_file(context, document) do
    deadline = System.monotonic_time(:millisecond) + 5_000

    with %{pid: pid, token: token, path: path, sha: sha} <- context[:workspace_snapshot_reader],
         true <- document["path"] === path and document["original_sha256"] === sha,
         :ok <-
           GenServer.call(
             context.owner,
             {:extension_workspace_snapshot_bind, context.job_ref, context.snapshot_intent, pid,
              token},
             max(deadline - System.monotonic_time(:millisecond), 1)
           ),
         true <- System.monotonic_time(:millisecond) < deadline do
      ref = Process.monitor(pid)
      send(pid, {:workspace_snapshot_read, token, self()})

      result = await_snapshot_reader(pid, token, ref, deadline)

      case result do
        {:ok, _bytes, metadata} ->
          if metadata["path"] === path and metadata["byte_count"] === document["original_bytes"] and
               metadata["sha256"] === sha,
             do: :ok,
             else: {:error, :document_store_refused}

        {:error, _} ->
          {:error, :document_store_refused}

        _ ->
          {:unknown, :workspace_check_unconfirmed}
      end
    else
      _ -> {:error, :document_store_refused}
    end
  end

  @doc false
  def await_snapshot_reader(pid, token, ref, deadline) do
    result =
      receive do
        {:workspace_snapshot_result, ^token, value} ->
          receive do
            {:DOWN, ^ref, :process, ^pid, :normal} -> value
            {:DOWN, ^ref, :process, ^pid, _} -> {:unknown, :workspace_check_unconfirmed}
          after
            max(deadline - System.monotonic_time(:millisecond), 0) ->
              {:unknown, :workspace_check_unconfirmed}
          end

        {:DOWN, ^ref, :process, ^pid, _} ->
          {:unknown, :workspace_check_unconfirmed}
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          {:unknown, :workspace_check_unconfirmed}
      end

    Process.demonitor(ref, [:flush])
    result
  end

  # Inspect the exact proposed source heads, including blocks changed in the
  # same commit. This is source-data identification, not an authority grant.
  def inspect_changes(changes, read, operation) when is_list(changes) and is_function(read, 1) do
    with true <- length(changes) <= 32,
         true <- Enum.all?(changes, &valid_change?/1),
         true <- length(Enum.uniq_by(changes, & &1["key"])) == length(changes) do
      overlay =
        Map.new(changes, fn change ->
          row =
            if is_nil(change["value"]) do
              nil
            else
              %{
                "value" => change["value"],
                "revision" => change["expected_revision"] + 1,
                "operation_id" => operation
              }
            end

          {change["key"], row}
        end)

      proposed_read = fn key ->
        case Map.fetch(overlay, key) do
          {:ok, row} -> {:ok, row}
          :error -> read.(key)
        end
      end

      Enum.reduce_while(changes, {:ok, []}, fn change, {:ok, found} ->
        if String.starts_with?(change["key"], "source.") and not is_nil(change["value"]) do
          with {:ok, head} <- DocumentStage.decode_packed(change["value"]) do
            if head["kind"] === "source_head" do
              case DocumentSourceUse.inspect_workspace_document(
                     proposed_read,
                     change["key"],
                     head
                   ) do
                {:ok, :not_workspace_document} ->
                  {:cont, {:ok, [:not_workspace_document | found]}}

                {:ok, document} when is_map(document) ->
                  {:cont, {:ok, [document | found]}}

                _ ->
                  {:halt, {:error, :document_store_refused}}
              end
            else
              {:cont, {:ok, [:not_workspace_document | found]}}
            end
          else
            _ -> {:halt, {:error, :document_store_refused}}
          end
        else
          {:cont, {:ok, found}}
        end
      end)
      |> case do
        {:ok, documents} -> {:ok, Enum.reverse(documents)}
        other -> other
      end
    else
      _ -> {:error, :document_store_refused}
    end
  rescue
    _ -> {:error, :document_store_refused}
  end

  def inspect_changes(_, _, _), do: {:error, :document_store_refused}

  defp valid_change?(change) do
    is_map(change) and Enum.sort(Map.keys(change)) == ~w(expected_revision key value) and
      is_binary(change["key"]) and Ipse.JSON.safe_uint?(change["expected_revision"])
  end
end
