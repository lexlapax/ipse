defmodule Ipse.Extension.Collection do
  @moduledoc """
  Internal bounded immutable collection storage. This API grants no authority.

  The host selects the protected root and admitted project identity. Callers must
  journal intent and hold the project control lock before a publication requiring
  consent. Storage never calls back into consent or performs inference. Readers
  take the same retained OS lock as writers, so reclamation cannot race a read.

  Values and bounded metadata blocks are content addressed. Successful
  operation IDs remain inspectable and cannot execute twice. Exhaustion refuses
  publication; the operation ledger is never silently reset. Export pages carry
  a floor advanced by destructive operations. Typed staged import fences ordinary
  writers and replaces records atomically after every page and digest validates.
  It retains inspected source IDs, including across abort and rollback, and
  cannot import below the current floor. The small `import` operation remains a
  separate bounded merge; complete migration uses `import.open/page/operations/commit`.

  This is an internal storage component, not a shipped knowledge host call.
  Domain policy belongs to the extension; protected consent and project identity
  admission belong to the host. The native quota profile currently accepts only
  explicitly reviewed Linux filesystems and fails closed on unsupported hosts.
  """
  alias Ipse.JSON
  alias Ipse.Runner.Transaction

  alias Ipse.Extension.Collection.{
    Blocks,
    Directory,
    DocumentDraft,
    DocumentMigration,
    DocumentMaintenance,
    Encoding,
    Migration,
    Planning,
    ReadView,
    Profile
  }

  import Bitwise, only: [band: 2]
  @value_bytes 6 * 1024
  @publication_error :collection_deadline_fence_unavailable
  @data_bytes 24 * 1024 * 1024
  @total_bytes 64 * 1024 * 1024
  # Consent's active/staged ledger allowance is 18 MiB; shared project identity
  # adds 4 MiB. Both owners independently enforce their protected native budgets.
  @control_bytes 22 * 1024 * 1024
  @records 8192
  @operations 32_768
  @lock_key {__MODULE__, :lock_held}
  @path_key {__MODULE__, :directory}
  @switch_deadline_key {__MODULE__, :switch_deadline}
  @notes_admission_key {__MODULE__, :notes_publication_admission}
  @acceptance_attempt_key {__MODULE__, :acceptance_effect_attempted}
  @document_epoch_key {__MODULE__, :document_epoch}
  @document_progress_key {__MODULE__, :document_progress}
  @document_retirement_owner_key {__MODULE__, :document_retirement_owner}
  @document_retirement_wall_key {__MODULE__, :document_retirement_wall}
  @document_migration_key {__MODULE__, :document_migration}
  @error {:error, :collection_unavailable}

  def limits do
    %{
      "value_bytes" => @value_bytes,
      "data_bytes" => @data_bytes,
      "total_bytes" => @total_bytes,
      "control_reserved_bytes" => @control_bytes,
      "records" => @records,
      "operations" => @operations
    }
  end

  def limits(profile) do
    case Profile.fetch(profile) do
      {:ok, %{"id" => "notes-v1"}} ->
        limits()

      {:ok, values} ->
        Map.take(
          values,
          ~w(value_bytes data_bytes total_bytes reserved_bytes control_reserved_bytes notes_reserved_bytes records operations)
        )
        |> Map.put("storage_profile", profile)

      error ->
        error
    end
  end

  def execute(root, project, request, operation_id),
    do: execute_profile(root, project, request, operation_id, Profile.notes())

  @doc "Refuse strict-deadline publication until the clock-to-rename scheduling gap has an enforceable fence."
  def publication_deadline_admission(_deadline),
    do: {:error, @publication_error}

  @doc "Report strict-publication support without preparing authority or running an effect."
  def publication_support,
    do: %{"supported" => false, "reason" => Atom.to_string(@publication_error)}

  @doc "Host deadline entry currently refuses without invoking its callback; grants no authority."
  def with_publication_deadline(deadline, fun) when is_function(fun, 0),
    # Fixed host dispatch keeps historical caller result contracts available
    # without a configurable backend or a callback execution path.
    do: apply(__MODULE__, :publication_deadline_admission, [deadline])

  @doc """
  Scope a trusted notes-profile final locked admission, without granting authority.

  The authenticated policy deadline and any earlier inherited deadline narrow
  the actual native root-switch decision. Capture normalization can further
  narrow it to original lineage expiry; selected management adapters provide
  their effective target deadline, and unmanaged SDK publication supplies current
  consent expiry. Admitted completion may occur later. Strict physical-deadline
  APIs retain their separate refusal.
  The callback runs once in the tracked file-effect owner and prior state is
  restored on every exit. Source, consent, mode and accounting remain caller duties.
  """
  def with_notes_publication_deadline(deadline, fun) when is_function(fun, 0) do
    inherited = Process.get(@switch_deadline_key)

    if JSON.safe_uint?(deadline) and deadline > 0 and
         (is_nil(inherited) or (JSON.safe_uint?(inherited) and inherited > 0)) do
      selected = if is_nil(inherited), do: deadline, else: min(deadline, inherited)

      Ipse.Session.Resources.file_effect(fn ->
        before = Process.get(@notes_admission_key)
        token = {self(), make_ref()}
        Process.put(@notes_admission_key, token)

        try do
          Profile.run(Profile.notes(), fn -> with_switch_deadline(selected, fun) end)
        after
          if is_nil(before),
            do: Process.delete(@notes_admission_key),
            else: Process.put(@notes_admission_key, before)
        end
      end)
    else
      {:error, :invalid_collection_request}
    end
  end

  def with_notes_publication_deadline(_, _), do: {:error, :invalid_collection_request}

  @doc "Host SDK legacy access: refuse a managed namespace under the same lock as the operation."
  def execute_unmanaged(root, project, request, operation_id) do
    with false <- Process.get(@lock_key, false) != false,
         true <- valid_request?(request) and id?(operation_id),
         true <- request["op"] in ~w(status snapshot get inspect scan commit) do
      Ipse.Session.Resources.file_effect(fn ->
        locked(root, project, request, operation_id, :unmanaged)
      end)
    else
      _ -> {:error, :invalid_collection_request}
    end
  rescue
    _ -> @error
  end

  @doc "Trusted fixed-profile storage entry; caller must establish project and operator authority."
  def execute_profile(root, project, request, operation_id, profile) do
    Profile.run(profile, fn -> execute_selected(root, project, request, operation_id, profile) end)
  end

  @doc "Internal document metadata lifecycle; the caller must establish ordinary host authority. No SDK operation is exposed."
  def document_maintenance(root, namespace, request, operation_id, owner) do
    with false <- Process.get(@lock_key, false) != false,
         true <- DocumentMaintenance.request?(request) and id?(operation_id),
         true <- Ipse.Extension.Collection.DocumentStage.owner?(owner),
         true <- namespace === Ipse.Extension.CollectionStore.namespace(owner["project_id"]) do
      Ipse.Session.Resources.file_effect(fn ->
        Profile.run(Profile.documents(), fn ->
          locked(root, namespace, request, operation_id, {:document_maintenance, owner})
        end)
      end)
    else
      _ -> {:error, :invalid_document_maintenance_request}
    end
  rescue
    _ -> @error
  end

  @doc false
  def document_snapshot(root, namespace) do
    with false <- Process.get(@lock_key, false) != false do
      Ipse.Session.Resources.file_effect(fn ->
        Profile.run(Profile.documents(), fn ->
          locked(root, namespace, %{"op" => "snapshot"}, nil, :document_snapshot)
        end)
      end)
    else
      _ -> {:error, :collection_lock_order}
    end
  rescue
    _ -> @error
  end

  @doc """
  Trusted document backup/restore entry; supplies no approval or result-data grant.

  For open/page, with_input retains the selected source lease while invoking its
  accept/1 callback exactly once with the complete decoded map. input_sha256 is
  the digest of Migration.encode(map); raw result delivery digests remain the
  Host's independent responsibility. Every mutation requires publication_guard/0
  and rechecks it immediately before the native root switch. The actual owner is
  supplied by the Host, never read from the page. No input/source path is accepted.
  """
  def document_migration(root, namespace, request, operation_id, owner, opts \\ []) do
    inherited = Process.get(@switch_deadline_key)

    with false <- Process.get(@lock_key, false) != false,
         true <- is_nil(Process.get(@document_migration_key)),
         true <- is_nil(inherited) or (JSON.safe_uint?(inherited) and inherited > 0),
         true <- DocumentMigration.request?(request) and id?(operation_id),
         true <- Ipse.Extension.Collection.DocumentStage.owner?(owner),
         true <- namespace === Ipse.Extension.CollectionStore.namespace(owner["project_id"]),
         true <-
           Keyword.keyword?(opts) and
             Keyword.keys(opts) === Enum.uniq(Keyword.keys(opts)) and
             Enum.all?(
               Keyword.keys(opts),
               &(&1 in [
                   :with_input,
                   :publication_guard,
                   :publish_before_ms,
                   :input_binding_sha256,
                   :plan_binding_sha256,
                   :dependency_union_sha256
                 ])
             ),
         deadline = opts[:publish_before_ms],
         true <- is_nil(deadline) or (JSON.safe_uint?(deadline) and deadline > 0),
         true <- DocumentMigration.read?(request) or is_function(opts[:publication_guard], 0),
         true <-
           DocumentMigration.read?(request) or
             (opts[:plan_binding_sha256] === request["plan_binding_sha256"] and
                opts[:dependency_union_sha256] === request["dependency_union_sha256"]),
         true <-
           not DocumentMigration.input?(request) or
             opts[:input_binding_sha256] ===
               request[
                 if(request["op"] === "restore.open",
                   do: "plan_binding_sha256",
                   else: "data_binding_sha256"
                 )
               ],
         true <- not DocumentMigration.input?(request) or is_function(opts[:with_input], 1) do
      Ipse.Session.Resources.file_effect(fn ->
        with_switch_deadline(inherited, fn ->
          with_switch_deadline(deadline, fn ->
            Profile.run(Profile.documents(), fn ->
              slot = {__MODULE__, make_ref()}
              Process.put(slot, :ready)

              accept = fn input ->
                if Process.get(slot) === :ready do
                  Process.put(slot, :used)
                  previous = Process.get(@document_migration_key)

                  Process.put(@document_migration_key, %{
                    guard: opts[:publication_guard],
                    owner: owner
                  })

                  try do
                    result =
                      if not DocumentMigration.input?(request) or
                           (is_map(input) and
                              JSON.sha256(Migration.encode(input)) === request["input_sha256"]) do
                        locked(
                          root,
                          namespace,
                          request,
                          operation_id,
                          {:document_migration, owner, input}
                        )
                      else
                        {:error, :invalid_document_migration_input}
                      end

                    Process.put(slot, {:complete, result})
                    result
                  after
                    if is_nil(previous),
                      do: Process.delete(@document_migration_key),
                      else: Process.put(@document_migration_key, previous)
                  end
                else
                  {:error, :document_migration_input_reused}
                end
              end

              try do
                result =
                  if DocumentMigration.input?(request),
                    do: opts[:with_input].(accept),
                    else: accept.(nil)

                case Process.get(slot) do
                  {:complete, ^result} ->
                    result

                  :ready ->
                    if match?({:error, _}, result),
                      do: result,
                      else: {:error, :document_migration_input_not_consumed}

                  _ ->
                    {:unknown, :collection_publication_unconfirmed}
                end
              rescue
                _ ->
                  if Process.get(slot) === :ready,
                    do: @error,
                    else: {:unknown, :collection_publication_unconfirmed}
              catch
                _, _ ->
                  if Process.get(slot) === :ready,
                    do: @error,
                    else: {:unknown, :collection_publication_unconfirmed}
              after
                Process.delete(slot)
              end
            end)
          end)
        end)
      end)
    else
      _ -> {:error, :invalid_document_migration_request}
    end
  rescue
    _ -> @error
  end

  @doc "Internal host admission from an actual protected snapshot; no caller supplies an epoch."
  def with_document_admission(root, namespace, owner, fun) when is_function(fun, 1) do
    Ipse.Session.Resources.file_effect(fn ->
      document_admission(root, namespace, owner, fun)
    end)
  end

  # Host-only scope. The worker supplies neither this context nor authority;
  # Collection rechecks the real locked draft before reaching the switch.
  @doc false
  def with_document_retirement_owner(context, intent, authority, fun) when is_function(fun, 0) do
    with nil <- Process.get(@document_retirement_owner_key),
         %{"op" => "collection.store", "request" => %{"progress" => %{"action" => "retire"}}} <-
           intent["request"],
         true <- context.parent["invocation_id"] === intent["parent_invocation_id"] do
      Process.put(@document_retirement_owner_key, {context, intent, authority})

      try do
        fun.()
      after
        Process.delete(@document_retirement_owner_key)
      end
    else
      _ -> {:error, :invalid_document_admission}
    end
  rescue
    _ -> {:unknown, :collection_publication_unconfirmed}
  end

  defp document_admission(root, namespace, owner, fun) do
    with true <- Ipse.Extension.Collection.DocumentStage.owner?(owner),
         true <- namespace === Ipse.Extension.CollectionStore.namespace(owner["project_id"]),
         {:ok, snapshot} <- document_snapshot(root, namespace) do
      previous = Process.get(@document_epoch_key)

      admission = %{
        path: Path.expand(Path.join(root, namespace)),
        namespace: namespace,
        owner: owner,
        status: snapshot["document_maintenance"]["status"],
        epoch: snapshot["document_maintenance"]["epoch"],
        drafts: Map.get(snapshot, "document_drafts", %{}),
        available_slots: Map.get(snapshot, "document_available_slots", [])
      }

      Process.put(@document_epoch_key, admission)

      try do
        fun.(
          Map.drop(snapshot, ~w(document_maintenance document_drafts document_available_slots))
        )
      after
        if is_nil(previous),
          do: Process.delete(@document_epoch_key),
          else: Process.put(@document_epoch_key, previous)
      end
    else
      _ -> {:error, :invalid_document_admission}
    end
  end

  @doc false
  def admitted_document_epoch do
    case Process.get(@document_epoch_key) do
      %{epoch: epoch} -> epoch
      nil -> nil
    end
  end

  @doc false
  def admitted_document_status do
    case Process.get(@document_epoch_key) do
      %{status: status} -> status
      nil -> nil
    end
  end

  @doc false
  def admitted_document_drafts do
    case Process.get(@document_epoch_key) do
      %{drafts: drafts} -> drafts
      _ -> %{}
    end
  end

  @doc false
  def admitted_document_available_slots do
    case Process.get(@document_epoch_key) do
      %{available_slots: slots} -> slots
      _ -> []
    end
  end

  @doc false
  def with_document_progress(request, request_sha256, operation_id, fun)
      when is_function(fun, 0) do
    admission = Process.get(@document_epoch_key)

    with true <- is_map(admission),
         true <- is_nil(Process.get(@document_progress_key)),
         true <- is_map(request) and DocumentDraft.tag?(request["progress"]),
         true <- JSON.sha256?(request_sha256) and id?(operation_id) do
      Process.put(@document_progress_key, %{
        request: request,
        request_sha256: request_sha256,
        operation_id: operation_id,
        owner: admission.owner
      })

      try do
        fun.()
      after
        Process.delete(@document_progress_key)
      end
    else
      _ -> {:error, :invalid_document_admission}
    end
  end

  @doc false
  def document_verify(root, namespace, request, operation_id) do
    context = Process.get(@document_progress_key)

    with %{request: ^request, operation_id: ^operation_id} <- context,
         true <- request["op"] === "value.verify",
         internal =
           request
           |> Map.take(~w(key expected_revision byte_count sha256))
           |> Map.put("op", "progress.verify")
           |> Map.put("expected_generation", request["generation"]) do
      Profile.run(Profile.documents(), fn ->
        locked(root, namespace, internal, operation_id, :document_verify)
      end)
    else
      _ -> {:error, :invalid_document_admission}
    end
  rescue
    _ -> @error
  end

  @doc false
  def document_retire_empty(root, namespace, request, operation_id) do
    context = Process.get(@document_progress_key)

    with %{request: ^request, operation_id: ^operation_id} <- context,
         true <- request["op"] === "progress.retire",
         internal = %{"op" => "progress.retire", "expected_generation" => request["generation"]} do
      Profile.run(Profile.documents(), fn ->
        locked(root, namespace, internal, operation_id, :document_verify)
      end)
    else
      _ -> {:error, :invalid_document_admission}
    end
  rescue
    _ -> @error
  end

  @doc "Read only fixed-profile public document descriptors under the actual native owner."
  def document_index(root, project, request) do
    with false <- Process.get(@lock_key, false) != false,
         true <- Directory.document_index_request?(request) do
      Ipse.Session.Resources.file_effect(fn ->
        Profile.run(Profile.documents(), fn ->
          locked(root, project, request, nil, :document_index)
        end)
      end)
    else
      _ -> {:error, :invalid_collection_request}
    end
  rescue
    _ -> @error
  end

  @doc "Document publication checks its final locked decision before expiry; other timed profiles remain unavailable."
  def execute_profile_before(root, project, request, operation_id, profile, deadline) do
    if profile == Profile.documents() do
      if JSON.safe_uint?(deadline) and deadline > 0 do
        Profile.run(profile, fn ->
          execute_selected(root, project, request, operation_id, profile, deadline)
        end)
      else
        {:error, :invalid_collection_request}
      end
    else
      publication_deadline_admission(deadline)
    end
  end

  defp execute_selected(root, project, request, operation_id, profile, deadline \\ nil) do
    if Process.get(@lock_key) do
      {:error, :collection_lock_order}
    else
      with true <- valid_request?(request) and id?(operation_id),
           true <-
             profile == Profile.notes() or
               request["op"] in ~w(status snapshot get inspect scan commit) do
        Ipse.Session.Resources.file_effect(fn ->
          Profile.run(profile, fn ->
            before = Process.get(@switch_deadline_key)

            selected =
              case {before, deadline} do
                {nil, value} -> value
                {value, nil} -> value
                {left, right} -> min(left, right)
              end

            if is_nil(selected) or System.system_time(:millisecond) < selected do
              Process.put(@switch_deadline_key, selected)

              try do
                locked(root, project, request, operation_id)
              after
                if is_nil(before),
                  do: Process.delete(@switch_deadline_key),
                  else: Process.put(@switch_deadline_key, before)
              end
            else
              {:error, :collection_use_expired}
            end
          end)
        end)
      else
        _ -> {:error, :invalid_collection_request}
      end
    end
  rescue
    _ -> @error
  end

  @doc "Open a trusted fixed-profile read view; no worker profile selection is accepted."
  def open_view_profile(root, project, profile),
    do: Profile.run(profile, fn -> open_view(root, project) end)

  @doc "Open one bounded owner-task index cache after full protected validation; no authority is granted."
  def open_view(root, project), do: open_view(root, project, false)

  @doc false
  def open_view_classified(root, project), do: open_view(root, project, true)

  defp open_view(root, project, classified?) do
    with false <- Process.get(@lock_key, false) != false,
         true <- is_binary(root) and Path.type(root) == :absolute and JSON.sha256?(project),
         {:ok, view} <- if(classified?, do: ReadView.begin_classified(), else: ReadView.begin()) do
      install_view(root, project, view, classified?)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_collection_view_request}
    end
  rescue
    _ -> @error
  end

  defp install_view(root, project, view, classified?) do
    profile = Profile.selected()

    try do
      result =
        Ipse.Session.Resources.file_effect(fn ->
          Profile.run(profile, fn -> locked(root, project, nil, nil, :view_open) end)
        end)

      case result do
        {:ok, cache} ->
          installed =
            if classified?,
              do: ReadView.install_classified(view, cache),
              else: ReadView.install(view, cache)

          case installed do
            :ok ->
              {:ok, view}

            error ->
              ReadView.close(view)
              error
          end

        error ->
          ReadView.close(view)
          error
      end
    catch
      _, _ ->
        ReadView.close(view)
        {:error, :collection_view_unavailable}
    end
  end

  @doc "Read at most eight selected records after reacquiring the native owner and checking the exact current root."
  def view_read(view, request) do
    with false <- Process.get(@lock_key, false) != false,
         true <- ReadView.valid_request?(request),
         {:ok, token, cache} <- ReadView.borrow(view, request) do
      read_view(view, token, cache)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_collection_view_request}
    end
  rescue
    _ -> {:error, :collection_view_unavailable}
  end

  @doc "Select four neighboring metadata refs with no value IO after an exact native root recheck."
  def view_neighbors(view, request) do
    with false <- Process.get(@lock_key, false) != false,
         true <- Directory.neighbor_request?(request),
         {:ok, token, cache} <-
           ReadView.borrow(view, %{"op" => "neighbors", "request" => request}) do
      read_view(view, token, cache)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_collection_view_request}
    end
  rescue
    _ -> {:error, :collection_view_unavailable}
  end

  defp read_view(view, token, cache) do
    try do
      result =
        Ipse.Session.Resources.file_effect(fn ->
          Profile.run(Map.get(cache, "storage_profile", Profile.notes()), fn ->
            locked(cache["collection_root"], cache["project"], nil, nil, {:view_read, cache})
          end)
        end)

      finished =
        ReadView.finish(view, token, if(match?({:ok, _}, result), do: :ok, else: :invalid))

      if match?({:ok, _}, result) and finished != :ok,
        do: {:error, :collection_view_unavailable},
        else: result
    catch
      _, _ ->
        ReadView.finish(view, token, :invalid)
        {:error, :collection_view_unavailable}
    end
  end

  def close_view(view), do: ReadView.close(view)

  @doc """
  Retain one notes Collection owner for a trusted bounded read callback.

  The callback receives the actual root witness and the existing 32-unit
  managed read closure. Selected values are read by the same native owner;
  escaped or cross-process closures refuse. This grants no source, Identity,
  Consent, output or mutation authority. As with opening a view, absent storage
  can create protected directories and retained lock files, but no root or
  operation is published. Callers needing an existing record must authenticate
  its presence and exact metadata inside the callback.

  Native export/display coordination is a separate trusted caller obligation.
  A known result is returned only after checking and releasing the native lock.
  A trusted three-argument callback also receives a non-consuming lease check;
  it refuses after budget exhaustion, owner loss, or callback closure and does
  not authorize reading or publishing independently.
  """
  def with_managed_read(root, project, fun) when is_function(fun, 2) or is_function(fun, 3) do
    with false <- Process.get(@lock_key, false) != false do
      Ipse.Session.Resources.file_effect(fn ->
        Profile.run(Profile.notes(), fn ->
          locked(root, project, nil, nil, {:managed_read, fun})
        end)
      end)
    else
      _ -> {:error, :collection_lock_order}
    end
  rescue
    _ -> @error
  end

  def with_managed_read(_, _, _), do: {:error, :invalid_collection_request}

  @doc false
  def with_managed_acceptance_read(root, project, fun) when is_function(fun, 4) do
    with false <- Process.get(@lock_key, false) != false do
      Ipse.Session.Resources.file_effect(fn ->
        previous = Process.put(@acceptance_attempt_key, false)

        try do
          Profile.run(Profile.notes(), fn ->
            locked(root, project, nil, nil, {:acceptance_read, fun})
          end)
        after
          if is_nil(previous),
            do: Process.delete(@acceptance_attempt_key),
            else: Process.put(@acceptance_attempt_key, previous)
        end
      end)
    else
      _ -> {:error, :collection_lock_order}
    end
  rescue
    _ -> @error
  end

  def with_managed_acceptance_read(_, _, _), do: {:error, :invalid_collection_request}

  @doc """
  Retain the fixed document Collection for a trusted bounded read callback.

  The callback receives an actual root witness and a same-owner closure for
  at most 512 selected record reads, each bounded by the existing 64 KiB document
  value limit. It cannot mutate, cross processes or survive callback closure.
  Notes retain their separate 32-unit allowance. No source policy, inference
  permission or dispatch authority is supplied by this storage primitive.

  Use this for short source validation, releasing ownership before long IO.
  An admitted remote effect has its own lifetime and uncertainty contract.
  """
  def with_document_read(root, project, fun) when is_function(fun, 2) do
    with false <- Process.get(@lock_key, false) != false do
      Ipse.Session.Resources.file_effect(fn ->
        Profile.run(Profile.documents(), fn ->
          locked(root, project, nil, nil, {:document_read, fun})
        end)
      end)
    else
      _ -> {:error, :collection_lock_order}
    end
  rescue
    _ -> @error
  end

  def with_document_read(_, _, _), do: {:error, :invalid_collection_request}

  @doc "Host SDK scan: exclude reserved validity keys before selecting any values, under one lock."
  def scan_visible(root, project, request, operation_id) do
    with false <- Process.get(@lock_key, false) != false,
         true <- valid_request?(request) and request["op"] == "scan" and id?(operation_id),
         true <- is_nil(request["after"]) or not managed_key?(request["after"]) do
      Ipse.Session.Resources.file_effect(fn ->
        locked(root, project, request, operation_id, :visible_scan)
      end)
    else
      _ -> {:error, :invalid_collection_request}
    end
  rescue
    _ -> @error
  end

  @doc """
  Host-only atomic managed publication. This grants no policy or source authority.

  The trusted normalizer runs under the collection lock after original CAS and
  duplicate checks. Its bounded read closure is valid only in that process and
  invocation. It returns `{:ok, normalized_commit, normalization_receipt}` or an
  error. Original changes remain exact; additional writes belong exclusively to
  `host.validity.`. The owning adapter must reserve metadata costs, authenticate
  proofs and check consent before calling. No worker callback is accepted here.
  """
  def execute_managed(root, project, original, operation_id, recipe_sha256, normalizer)
      when is_function(normalizer, 2),
      do:
        execute_managed_version(
          root,
          project,
          original,
          operation_id,
          recipe_sha256,
          normalizer,
          2
        )

  def execute_managed(_, _, _, _, _, _), do: {:error, :invalid_managed_collection_request}

  @doc "Host-only v3 metadata publication: bounded authenticated-page replacements and one retained-revision deletion."
  def execute_managed_v3(root, project, original, operation_id, recipe_sha256, normalizer)
      when is_function(normalizer, 2),
      do:
        execute_managed_version(
          root,
          project,
          original,
          operation_id,
          recipe_sha256,
          normalizer,
          3
        )

  def execute_managed_v3(_, _, _, _, _, _), do: {:error, :invalid_managed_collection_request}

  @doc false
  def execute_managed_capture(
        root,
        project,
        original,
        operation_id,
        recipe_sha256,
        normalizer,
        held
      )
      when is_function(normalizer, 2) and is_map(held),
      do:
        execute_managed_version(
          root,
          project,
          original,
          operation_id,
          recipe_sha256,
          normalizer,
          {:capture, held}
        )

  @doc false
  def execute_managed_retention(
        root,
        project,
        original,
        operation_id,
        recipe_sha256,
        normalizer,
        owned,
        intent,
        permit
      )
      when is_function(normalizer, 2) and is_map(owned) and is_map(intent) do
    facts = intent["facts"]
    command = Ipse.Extension.Collection.ManagedRetention.command(facts["policy"])

    with true <-
           facts["kind"] in ~w(managed_literal_retention managed_accepted_decision_retention),
         true <- owned[:journal_owner] === self(),
         true <- intent["operation_id"] === operation_id,
         true <- get_in(facts, ["context", "namespace"]) === project,
         true <- get_in(facts, ["context", "session_id"]) === owned[:id],
         true <- facts["request_sha256"] === JSON.digest([original]),
         :ok <- Ipse.Runner.Review.check(permit, command, facts) do
      previous = Process.put(@acceptance_attempt_key, false)

      try do
        execute_managed_version(
          root,
          project,
          original,
          operation_id,
          recipe_sha256,
          normalizer,
          {:retention, owned, intent, permit}
        )
      after
        if is_nil(previous),
          do: Process.delete(@acceptance_attempt_key),
          else: Process.put(@acceptance_attempt_key, previous)
      end
    else
      _ -> {:error, :invalid_managed_collection_request}
    end
  rescue
    _ -> {:error, :invalid_managed_collection_request}
  end

  def execute_managed_retention(_, _, _, _, _, _, _, _, _),
    do: {:error, :invalid_managed_collection_request}

  @doc false
  def execute_managed_lineage_retention(
        root,
        project,
        original,
        operation_id,
        recipe_sha256,
        normalizer,
        owned,
        intent,
        permit,
        source_lease
      )
      when is_function(normalizer, 2) and is_map(owned) and is_map(intent) do
    facts = intent["facts"]
    command = Ipse.Extension.Collection.ManagedRetention.command(facts["policy"])

    with true <- facts["kind"] === "managed_literal_lineage_retention",
         true <- owned[:journal_owner] === self(),
         true <- intent["operation_id"] === operation_id,
         true <- get_in(facts, ["context", "namespace"]) === project,
         true <- get_in(facts, ["context", "session_id"]) === owned[:id],
         true <- facts["request_sha256"] === JSON.digest([original]),
         {:ok, _} <-
           Ipse.Session.StoredSources.share_verified_identity(source_lease, [
             facts["source_proof"]
           ]),
         :ok <- Ipse.Runner.Review.check(permit, command, facts) do
      previous = Process.put(@acceptance_attempt_key, false)

      try do
        execute_managed_version(
          root,
          project,
          original,
          operation_id,
          recipe_sha256,
          normalizer,
          {:lineage_retention, owned, intent, permit, source_lease}
        )
      after
        if is_nil(previous),
          do: Process.delete(@acceptance_attempt_key),
          else: Process.put(@acceptance_attempt_key, previous)
      end
    else
      _ -> {:error, :invalid_managed_collection_request}
    end
  rescue
    _ -> {:error, :invalid_managed_collection_request}
  end

  def execute_managed_lineage_retention(_, _, _, _, _, _, _, _, _, _),
    do: {:error, :invalid_managed_collection_request}

  @doc false
  def execute_pending_correction(
        root,
        project,
        original,
        operation_id,
        recipe_sha256,
        normalizer,
        owned,
        intent,
        permit,
        source_lease
      )
      when is_function(normalizer, 2) and is_map(owned) and is_map(intent) and
             is_reference(source_lease) do
    facts = intent["facts"]

    with true <- owned[:journal_owner] === self(),
         true <- intent["operation_id"] === operation_id,
         true <- get_in(facts, ["context", "namespace"]) === project,
         true <- get_in(facts, ["context", "session_id"]) === owned[:id],
         true <-
           Ipse.Session.PendingCorrection.current_review?(facts, System.system_time(:millisecond)),
         true <- facts["request"] === original,
         :ok <- Ipse.Runner.Review.check(permit, "correct", facts) do
      previous = Process.put(@acceptance_attempt_key, false)

      try do
        execute_managed_version(
          root,
          project,
          original,
          operation_id,
          recipe_sha256,
          normalizer,
          {:pending_correction, owned, intent, permit, source_lease}
        )
      after
        if is_nil(previous),
          do: Process.delete(@acceptance_attempt_key),
          else: Process.put(@acceptance_attempt_key, previous)
      end
    else
      _ -> {:error, :invalid_managed_collection_request}
    end
  rescue
    _ -> {:error, :invalid_managed_collection_request}
  end

  def execute_pending_correction(_, _, _, _, _, _, _, _, _, _),
    do: {:error, :invalid_managed_collection_request}

  @doc "Host-only atomic literal supersession; this does not widen the worker publication profile."
  def execute_managed_supersession(
        root,
        project,
        original,
        operation_id,
        recipe_sha256,
        normalizer
      )
      when is_function(normalizer, 2),
      do:
        execute_managed_version(
          root,
          project,
          original,
          operation_id,
          recipe_sha256,
          normalizer,
          :supersession
        )

  def execute_managed_supersession(_, _, _, _, _, _),
    do: {:error, :invalid_managed_collection_request}

  @doc false
  def execute_reviewed_supersession(
        root,
        project,
        original,
        operation_id,
        recipe_sha256,
        normalizer,
        review
      )
      when is_function(normalizer, 2) and is_map(review) do
    facts = review[:facts]
    command = if facts["mode"] == "ordinary", do: "correct", else: "supersede"

    with true <- is_map(review[:context]),
         true <- facts["operation_id"] === operation_id,
         true <- get_in(facts, ["context", "namespace"]) === project,
         true <- get_in(facts, ["context", "session_id"]) === review.context.session_id,
         true <- facts["request_sha256"] === JSON.digest([original]),
         :ok <- Ipse.Runner.Review.check(review[:permit], command, facts) do
      previous = Process.put(@acceptance_attempt_key, false)

      try do
        execute_managed_version(
          root,
          project,
          original,
          operation_id,
          recipe_sha256,
          normalizer,
          {:supersession, review}
        )
      after
        if is_nil(previous),
          do: Process.delete(@acceptance_attempt_key),
          else: Process.put(@acceptance_attempt_key, previous)
      end
    else
      _ -> {:error, :invalid_managed_collection_request}
    end
  rescue
    _ -> {:error, :invalid_managed_collection_request}
  end

  def execute_reviewed_supersession(_, _, _, _, _, _, _),
    do: {:error, :invalid_managed_collection_request}

  defp execute_managed_version(
         root,
         project,
         original,
         operation_id,
         recipe_sha256,
         normalizer,
         version
       )
       when is_function(normalizer, 2) do
    with false <- Process.get(@lock_key, false) != false,
         true <- valid_request?(original) and original["op"] == "commit",
         true <- original["advance_floor"] === true,
         true <- length(original["changes"]) <= 8 and id?(operation_id),
         true <- JSON.sha256?(recipe_sha256),
         true <- Enum.all?(original["changes"], &(not managed_key?(&1["key"]))) do
      Ipse.Session.Resources.file_effect(fn ->
        locked(root, project, original, operation_id, {recipe_sha256, normalizer, version})
      end)
    else
      _ -> {:error, :invalid_managed_collection_request}
    end
  rescue
    _ -> @error
  end

  def valid_request?(%{"op" => op} = r) when op in ~w(status snapshot), do: keys?(r, ["op"])
  def valid_request?(%{"op" => "get"} = r), do: keys?(r, ~w(op key)) and key?(r["key"])

  def valid_request?(%{"op" => "inspect"} = r),
    do: keys?(r, ~w(op operation_id)) and id?(r["operation_id"])

  def valid_request?(%{"op" => "scan"} = r) do
    keys?(r, ~w(op after generation limit)) and
      (is_nil(r["after"]) or key?(r["after"])) and uint?(r["generation"]) and
      is_integer(r["limit"]) and r["limit"] in 1..32
  end

  def valid_request?(%{"op" => op} = r) when op in ~w(commit import) do
    fields = ~w(op expected_generation changes advance_floor)
    fields = if op == "import", do: fields ++ ~w(project floor), else: fields

    keys?(r, fields) and uint?(r["expected_generation"]) and is_boolean(r["advance_floor"]) and
      (op != "import" or (JSON.sha256?(r["project"]) and uint?(r["floor"]))) and
      is_list(r["changes"]) and length(r["changes"]) in 1..128 and
      Enum.all?(r["changes"], &change?/1) and
      length(Enum.uniq_by(r["changes"], & &1["key"])) == length(r["changes"]) and
      (r["advance_floor"] or Enum.all?(r["changes"], &(not is_nil(&1["value"]))))
  rescue
    _ -> false
  end

  def valid_request?(request), do: Migration.request?(request)

  defp change?(c) do
    keys?(c, ~w(key expected_revision value)) and key?(c["key"]) and
      uint?(c["expected_revision"]) and (is_nil(c["value"]) or value?(c["value"]))
  end

  defp value?(v) do
    if Profile.selected() == Profile.documents() do
      case Ipse.Extension.ResultDocument.encode(v, %{"type" => "object"}) do
        {:ok, bytes} -> byte_size(bytes) <= Profile.limit(:value_bytes)
        _ -> false
      end
    else
      is_map(v) and :ok == JSON.validate_object(v) and
        byte_size(Jason.encode!(v)) <= Profile.limit(:value_bytes)
    end
  end

  defp locked(root, project, request, operation_id, managed \\ nil) do
    with true <- is_binary(root) and Path.type(root) == :absolute and JSON.sha256?(project),
         {:ok, uid} <- Ipse.Runner.protected_current_uid(),
         :ok <- directory(Path.dirname(root), uid, false),
         :ok <- directory(root, uid, true),
         path = Path.join(root, project),
         :ok <- directory(path, uid, true),
         :ok <- directory(Path.join(path, "objects"), uid, true),
         :ok <- directory(Path.join(path, "manifests"), uid, true),
         :ok <- safe_lock(Path.join(path, ".lock"), uid),
         {:ok, cap} <- Transaction.acquire(Path.join(path, ".lock"), cwd: Path.dirname(root)) do
      Process.put(@lock_key, cap)
      Process.put(@path_key, path)

      result =
        try do
          with :ok <- safe_lock(Path.join(path, ".lock"), uid),
               {:ok, state, manifest} <- load_for(path, project, uid, managed),
               :ok <- Transaction.check(cap),
               :ok <-
                 Transaction.quota(
                   cap,
                   :collection,
                   Profile.limit(:total_bytes) - Profile.limit(:reserved_bytes)
                 ) do
            case managed do
              nil ->
                apply_request(path, uid, state, manifest, request, operation_id)

              :document_snapshot ->
                result =
                  Map.put(
                    summary(state),
                    "document_maintenance",
                    DocumentMaintenance.metadata(state)
                  )

                result =
                  if DocumentMaintenance.metadata(state)["epoch"] > 0 do
                    result
                    |> Map.put("document_drafts", DocumentDraft.heads(state))
                    |> Map.put("document_available_slots", DocumentDraft.available_slots(state))
                  else
                    result
                  end

                {:ok, result}

              :document_verify ->
                apply_mutation(path, uid, state, manifest, request, operation_id, %{})

              {:document_maintenance, owner} ->
                apply_document_maintenance(
                  path,
                  uid,
                  state,
                  manifest,
                  request,
                  operation_id,
                  owner
                )

              {:document_migration, owner, input} ->
                apply_document_migration(
                  path,
                  uid,
                  state,
                  manifest,
                  request,
                  operation_id,
                  owner,
                  input
                )

              :visible_scan ->
                scan(path, uid, state, request, true)

              :unmanaged ->
                if Enum.any?(Map.keys(state["records"]), &managed_key?/1) do
                  {:error, :collection_managed_namespace}
                else
                  apply_request(path, uid, state, manifest, request, operation_id)
                end

              :view_open ->
                view_cache(root, path, project, uid, state, manifest)

              {kind, fun} when kind in [:managed_read, :document_read, :acceptance_read] ->
                limit = if kind == :document_read, do: 512, else: 32

                with_managed_reads(
                  path,
                  uid,
                  state,
                  manifest,
                  fn witness, read, check ->
                    witness =
                      if kind == :document_read,
                        do:
                          Map.put(
                            witness,
                            "document_maintenance",
                            DocumentMaintenance.metadata(state)
                          ),
                        else: witness

                    owner = self()
                    cap = Process.get(@lock_key)
                    {token, _, :open} = Process.get({__MODULE__, :managed_read})

                    alive = fn ->
                      with true <- self() == owner and Process.get(@lock_key) === cap,
                           {^token, _, :open} <- Process.get({__MODULE__, :managed_read}),
                           :ok <- Transaction.check(cap),
                           do: :ok,
                           else: (_ -> {:error, :managed_read_refused})
                    end

                    result =
                      if kind == :acceptance_read do
                        slot = {__MODULE__, make_ref()}
                        Process.put(slot, owner)

                        publish = fn event, intent, normalized, permit ->
                          if self() == owner and Process.delete(slot) == owner do
                            publish_acceptance(
                              path,
                              uid,
                              state,
                              manifest,
                              witness,
                              cap,
                              alive,
                              check,
                              event,
                              intent,
                              normalized,
                              permit
                            )
                          else
                            {:error, :pending_acceptance_refused}
                          end
                        end

                        try do
                          fun.(witness, read, alive, publish)
                        after
                          Process.delete(slot)
                        end
                      else
                        if is_function(fun, 3),
                          do: fun.(witness, read, alive),
                          else: fun.(witness, read)
                      end

                    case result do
                      {:ok, _} = result ->
                        result

                      {:error, _} when kind == :acceptance_read ->
                        if Process.get(@acceptance_attempt_key) == true,
                          do: {:unknown, :collection_publication_unconfirmed},
                          else: result

                      {:error, _} = result ->
                        result

                      {:unknown, _} = result ->
                        result

                      _ ->
                        {:error, :managed_read_refused}
                    end
                  end,
                  limit
                )

              :document_index ->
                if request["generation"] === state["generation"] do
                  :telemetry.execute(
                    [:ipse, :extension, :collection, :document_index],
                    %{value_reads: 0},
                    %{}
                  )

                  Directory.document_index(state["records"], summary(state), request)
                else
                  {:conflict, summary(state)}
                end

              {:view_read, %{"neighbors" => neighbors} = cache} when is_map(neighbors) ->
                view_neighbor_refs(cache)

              {:view_read, %{"metadata_only" => true} = cache} ->
                view_index(state, cache)

              {:view_read, cache} ->
                view_records(path, uid, state, cache)

              _ ->
                apply_managed(path, uid, state, manifest, request, operation_id, managed)
            end
          else
            {:error, :transaction_filesystem_unsupported} ->
              {:error, :collection_filesystem_unsupported}

            {:error, :transaction_capacity} ->
              {:failed, %{"code" => "collection_capacity"}}

            {:error, :collection_view_stale} = error ->
              error

            _ ->
              @error
          end
        rescue
          _ -> {:unknown, :collection_transaction_unconfirmed}
        catch
          _, _ -> {:unknown, :collection_transaction_unconfirmed}
        after
          Process.delete(@lock_key)
          Process.delete(@path_key)
        end

      checked = Transaction.check(cap)
      released = Transaction.release(cap)

      if checked == :ok and released == :ok,
        do: result,
        else: {:unknown, :collection_lock_lost}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp load_for(_path, project, _uid, {:view_read, cache}) do
    selected = Transaction.read_optional(publication_cap(), ".", "root.json", 1024)

    with true <- cache["project"] === project,
         true <- selected_root?(selected, cache) do
      {:ok, Map.put(cache["summary"], "records", cache["records"]), nil}
    else
      _ -> {:error, :collection_view_stale}
    end
  end

  defp load_for(path, project, uid, :view_open) do
    case Transaction.read_optional(publication_cap(), ".", "root.json", 1024) do
      :absent -> {:ok, empty(project), nil}
      {:ok, bytes} -> load_pointer(path, project, uid, bytes)
      _ -> @error
    end
  end

  defp load_for(path, project, uid, _), do: load(path, project, uid)

  defp selected_root?(:absent, %{"root_state" => "absent"}), do: true

  defp selected_root?({:ok, bytes}, %{"root_state" => "present"} = cache),
    do: bytes === cache["root_bytes"] and JSON.sha256(bytes) === cache["root_sha256"]

  defp selected_root?(_, _), do: false

  defp view_cache(root, _, project, _, state, nil) do
    with :absent <- Transaction.read_optional(publication_cap(), ".", "root.json", 1024),
         true <- state === empty(project) do
      {:ok,
       profile_cache(%{
         "version" => 2,
         "collection_root" => root,
         "project" => project,
         "root_state" => "absent",
         "root_bytes" => nil,
         "root_sha256" => nil,
         "manifest_sha256" => nil,
         "summary" => summary(state),
         "records" => %{}
       })}
    else
      _ -> @error
    end
  end

  defp view_cache(root, path, project, uid, state, manifest) do
    with {:ok, bytes} <- bounded_file(Path.join(path, "root.json"), uid, 1024),
         {:ok, pointer} <- JSON.decode_unique(bytes),
         {:ok, pointer} <- Profile.unfence(pointer, Profile.selected()),
         true <- pointer["version"] in [4, 5],
         true <- pointer["manifest"] === manifest.hash,
         true <- pointer |> Map.delete("manifest") |> Map.put("version", 3) == summary(state) do
      {:ok,
       profile_cache(%{
         "version" => 2,
         "collection_root" => root,
         "project" => project,
         "root_state" => "present",
         "root_bytes" => bytes,
         "root_sha256" => JSON.sha256(bytes),
         "manifest_sha256" => manifest.hash,
         "summary" => summary(state),
         "records" => state["records"]
       })}
    else
      false -> {:error, :collection_view_unsupported}
      _ -> @error
    end
  end

  defp profile_cache(cache) do
    if Profile.selected() == Profile.notes(),
      do: cache,
      else: Map.merge(cache, %{"version" => 3, "storage_profile" => Profile.selected()})
  end

  defp view_records(path, uid, state, cache) do
    :telemetry.execute(
      [:ipse, :extension, :collection, :view_read],
      %{records: length(cache["selected"])},
      %{}
    )

    with :ok <- view_generation(state, cache),
         {:ok, records} <- read_records(path, uid, state, cache["selected"]),
         {:ok, witness} <- view_witness(cache),
         result = %{
           "version" => 2,
           "summary" => cache["summary"],
           "witness" => witness,
           "keys" => cache["selected"],
           "records" => records,
           "next" => cache["next"]
         },
         true <- byte_size(Jason.encode!(result)) <= 65_536 do
      {:ok, result}
    else
      false -> {:error, :collection_view_reply_capacity}
      {:error, :collection_view_stale} = error -> error
      _ -> @error
    end
  end

  defp view_index(state, cache) do
    :telemetry.execute(
      [:ipse, :extension, :collection, :view_index],
      %{refs: length(cache["selected"]), value_reads: 0},
      %{}
    )

    with :ok <- view_generation(state, cache),
         {:ok, witness} <- view_witness(cache) do
      records =
        Enum.map(
          cache["selected"],
          &Map.take(cache["records"][&1], ~w(key revision bytes sha256))
        )

      {:ok,
       %{
         "version" => 2,
         "summary" => cache["summary"],
         "witness" => witness,
         "keys" => cache["selected"],
         "records" => records,
         "next" => cache["next"],
         "count" => cache["visible_count"]
       }}
    end
  end

  defp view_generation(state, cache) do
    if is_nil(cache["expected_generation"]) or
         cache["expected_generation"] === state["generation"],
       do: :ok,
       else: {:error, :collection_view_stale}
  end

  defp view_neighbor_refs(cache) do
    :telemetry.execute(
      [:ipse, :extension, :collection, :view_neighbors],
      %{refs: length(cache["selected"]), value_reads: 0},
      %{}
    )

    with {:ok, witness} <- view_witness(cache),
         neighbors = Map.delete(cache["neighbors"], "state"),
         result = %{
           "version" => 1,
           "summary" => cache["summary"],
           "witness" => witness,
           "directory" => cache["neighbor_request"],
           "state" => cache["neighbors"]["state"],
           "neighbors" => Map.new(neighbors, fn {slot, key} -> {slot, cache["records"][key]} end)
         },
         true <- byte_size(Jason.encode!(result)) <= 65_536 do
      {:ok, result}
    else
      false -> {:error, :collection_view_reply_capacity}
      _ -> @error
    end
  end

  defp view_witness(cache) do
    with {:ok, pointer} <- view_pointer(cache) do
      {:ok,
       %{
         "version" => 2,
         "root_state" => cache["root_state"],
         "root" => pointer,
         "root_sha256" => cache["root_sha256"],
         "manifest_sha256" => cache["manifest_sha256"]
       }}
    end
  end

  defp view_pointer(%{"root_state" => "absent", "root_bytes" => nil}), do: {:ok, nil}

  defp view_pointer(%{"root_state" => "present", "root_bytes" => bytes}),
    do: JSON.decode_unique(bytes)

  defp apply_request(path, uid, s, _, %{"op" => "status"}, _) do
    status(path, uid, s)
  end

  defp apply_request(_, _, s, _, %{"op" => "snapshot"}, _), do: {:ok, summary(s)}

  defp apply_request(_, _, s, _, %{"op" => "inspect", "operation_id" => id}, _),
    do: {:ok, Map.put(summary(s), "operation", Migration.known_operations(s)[id])}

  defp apply_request(path, uid, s, _, %{"op" => "get", "key" => key}, _) do
    with {:ok, record} <- read_record(path, uid, s, key),
         do: {:ok, Map.put(summary(s), "record", record)}
  end

  defp apply_request(path, uid, s, _, %{"op" => "scan"} = r, _),
    do: scan(path, uid, s, r, false)

  defp apply_request(path, uid, s, manifest, %{"op" => "export"} = r, id) do
    case apply_request(path, uid, s, manifest, %{r | "op" => "scan"}, id) do
      {:ok, page} -> {:ok, Map.put(page, "descriptor", Migration.descriptor(s))}
      other -> other
    end
  end

  defp apply_request(_, _, s, _, %{"op" => "export.plan", "generation" => generation}, _) do
    if generation == s["generation"],
      do:
        {:ok,
         Map.merge(summary(s), %{
           "descriptor" => Migration.descriptor(s),
           "plan" => Planning.export(s)
         })},
      else: {:conflict, summary(s)}
  end

  defp apply_request(_, _, s, _, %{"op" => "export.operations"} = r, _) do
    if r["generation"] == s["generation"] do
      keys =
        s
        |> Migration.operations()
        |> Map.keys()
        |> Enum.sort()
        |> Enum.filter(&(is_nil(r["after"]) or &1 > r["after"]))

      selected = Enum.take(keys, r["limit"])
      operations = Migration.operations(s)

      {:ok,
       Map.merge(summary(s), %{
         "descriptor" => Migration.descriptor(s),
         "operations" =>
           Enum.map(selected, &%{"operation_id" => &1, "receipt" => operations[&1]}),
         "next" => if(length(keys) > length(selected), do: List.last(selected))
       })}
    else
      {:conflict, summary(s)}
    end
  end

  defp apply_request(path, uid, s, manifest, r, id) do
    apply_mutation(path, uid, s, manifest, r, id, %{})
  end

  defp apply_document_maintenance(_, _, s, _, %{"op" => "maintenance.inspect"}, _, _) do
    {:ok, Map.put(summary(s), "document_maintenance", DocumentMaintenance.metadata(s))}
  end

  defp apply_document_maintenance(path, uid, s, manifest, request, id, owner) do
    request = Map.put(request, "owner", owner)
    known = Migration.known_operations(s)[id]

    if is_map(known) and known["request_sha256"] !== JSON.digest([request]) do
      {:failed, Map.put(summary(s), "code", "collection_operation_identity")}
    else
      apply_mutation(path, uid, s, manifest, request, id, %{})
    end
  end

  defp apply_document_migration(path, uid, s, manifest, r, id, owner, input) do
    if DocumentMigration.read?(r) do
      cond do
        r["generation"] !== s["generation"] ->
          {:conflict, summary(s)}

        DocumentMaintenance.metadata(s)["status"] !== "idle" or not is_nil(s["migration"]) or
            not DocumentMigration.quiescent?(s) ->
          {:failed, Map.put(summary(s), "code", "collection_writer_fenced")}

        r["op"] === "backup.describe" ->
          {:ok, %{"descriptor" => DocumentMigration.compact_descriptor(s)}}

        r["op"] === "backup.metadata" ->
          {:ok, DocumentMigration.metadata(s, r)}

        r["op"] === "backup.plan" ->
          {:ok, DocumentMigration.export_plan(s)}

        true ->
          keys =
            s["records"]
            |> Map.keys()
            |> Enum.sort()
            |> Enum.filter(&(is_nil(r["after"]) or &1 > r["after"]))

          selected = Enum.take(keys, r["limit"])

          with {:ok, rows} <- read_records(path, uid, s, selected),
               true <- Enum.all?(rows, &DocumentMigration.packed?(&1["value"])) do
            {:ok,
             %{
               "descriptor" => DocumentMigration.descriptor(s),
               "records" => rows,
               "next" => if(length(keys) > length(selected), do: List.last(selected))
             }}
          else
            _ -> {:error, :invalid_document_backup_value}
          end
      end
    else
      request_hash = JSON.digest([r, DocumentDraft.owner(owner)])
      known = Migration.known_operations(s)[id]
      m = DocumentMaintenance.metadata(s)

      cond do
        is_map(known) and known["request_sha256"] !== request_hash ->
          {:failed, Map.put(summary(s), "code", "collection_operation_identity")}

        is_map(known) ->
          {:existing, Map.put(summary(s), "operation", known)}

        r["expected_generation"] !== s["generation"] ->
          {:conflict, summary(s)}

        r["expected_epoch"] !== m["epoch"] ->
          {:failed, Map.put(summary(s), "code", "collection_document_epoch")}

        not uint?(s["generation"] + 1) ->
          capacity(s)

        true ->
          case DocumentMigration.prepare(s, r, id, owner, input) do
            {:ok, next, values, extra} ->
              receipt =
                Map.merge(
                  %{
                    "generation" => s["generation"] + 1,
                    "floor" => next["floor"],
                    "request_sha256" => request_hash
                  },
                  extra
                )

              next = %{
                next
                | "generation" => receipt["generation"],
                  "operations" => Map.put(s["operations"], id, receipt)
              }

              with :ok <- document_migration_guard() do
                publish(path, uid, s, next, manifest, values, receipt, r)
              else
                _ -> {:error, :document_migration_admission_refused}
              end

            {:failed, code} ->
              {:failed, Map.put(summary(s), "code", code)}
          end
      end
    end
  end

  defp document_migration_guard do
    case Process.get(@document_migration_key) do
      nil -> :ok
      %{guard: guard} when is_function(guard, 0) -> guard.()
      _ -> {:error, :document_migration_admission_refused}
    end
  end

  defp apply_managed(path, uid, s, manifest, original, id, {recipe, normalizer, version}) do
    cond do
      operation = Migration.known_operations(s)[id] ->
        {:existing, Map.put(summary(s), "operation", operation)}

      original["expected_generation"] != s["generation"] or
          Enum.any?(original["changes"], &(revision(s, &1["key"]) != &1["expected_revision"])) ->
        {:conflict, summary(s)}

      Migration.fenced?(s, "commit") ->
        {:failed, Map.put(summary(s), "code", "collection_writer_fenced")}

      true ->
        normalize_managed(path, uid, s, manifest, original, id, recipe, normalizer, version)
    end
  end

  defp normalize_managed(path, uid, s, manifest, original, id, recipe, normalizer, version) do
    result =
      with_managed_reads(path, uid, s, manifest, fn root, read, check ->
        normalize_managed(
          path,
          uid,
          s,
          manifest,
          original,
          id,
          recipe,
          normalizer,
          root,
          read,
          check,
          version
        )
      end)

    if result == {:error, :managed_read_refused},
      do: {:error, :managed_normalization_refused},
      else: result
  end

  defp with_managed_reads(path, uid, s, manifest, fun, limit \\ 32) do
    with {:ok, root} <- managed_root(s, manifest),
         {:ok, directory} <- Directory.index(s["records"] |> Map.keys() |> Enum.sort()) do
      with_managed_reads(path, uid, s, manifest, root, directory, fun, limit)
    else
      _ -> {:error, :managed_read_refused}
    end
  end

  defp with_managed_reads(path, uid, s, manifest, root, directory, fun, limit) do
    key = {__MODULE__, :managed_read}
    owner = self()
    token = make_ref()
    cap = Process.get(@lock_key)
    previous = Process.put(key, {token, 0, :open})

    check = fn ->
      case Process.get(key) do
        {^token, count, :open} ->
          Process.put(key, {token, count, :closed})
          :ok

        {^token, _, :closed} ->
          :ok

        _ ->
          {:error, :managed_read_refused}
      end
    end

    read = fn selected ->
      with true <- self() == owner and Process.get(@lock_key) === cap,
           true <- limit == 32 or is_binary(selected),
           {:ok, cost} <- managed_read_cost(selected),
           :ok <- debit_managed_read(key, token, cost, limit),
           :ok <- Transaction.check(cap) do
        result = managed_read(path, uid, s, directory, root, selected)
        if Transaction.check(cap) == :ok, do: result, else: {:error, :managed_read_refused}
      else
        _ -> {:error, :managed_read_refused}
      end
    end

    witness =
      Map.merge(root, %{
        "root" => summary(s),
        "manifest_sha256" => if(manifest, do: manifest.hash)
      })

    try do
      result = fun.(witness, read, check)

      case result do
        {:unknown, _} ->
          result

        _ ->
          with :ok <- check.(),
               :ok <- Transaction.check(cap) do
            result
          else
            _ ->
              if Process.get(@acceptance_attempt_key) == true,
                do: {:unknown, :collection_publication_unconfirmed},
                else: {:error, :managed_read_refused}
          end
      end
    after
      if is_nil(previous), do: Process.delete(key), else: Process.put(key, previous)
    end
  end

  defp normalize_managed(
         path,
         uid,
         s,
         manifest,
         original,
         id,
         recipe,
         normalizer,
         root,
         read,
         check,
         version
       ) do
    cap = Process.get(@lock_key)

    witness =
      Map.merge(root, %{
        "root" => summary(s),
        "manifest_sha256" => if(manifest, do: manifest.hash),
        "operation_id" => id,
        "original_request_sha256" => JSON.digest([original]),
        "recipe_sha256" => recipe
      })

    validation_version =
      cond do
        match?(
          {:retention, _, %{"facts" => %{"kind" => "managed_accepted_decision_retention"}}, _},
          version
        ) ->
          :accepted_retention

        match?({:retention, _, _, _}, version) ->
          3

        match?({:lineage_retention, _, _, _, _}, version) ->
          3

        match?({:supersession, _}, version) ->
          :supersession

        match?({:capture, _}, version) ->
          3

        match?({:pending_correction, _, _, _, _}, version) ->
          3

        true ->
          version
      end

    with {:ok, normalized, normalization} <- normalizer.(witness, read),
         :ok <- check.(),
         true <- normalized_managed?(original, normalized, s, root, validation_version),
         true <-
           validation_version == 2 or (is_map(normalization) and normalization["version"] === 3),
         true <-
           validation_version != :supersession or
             normalization["kind"] == "native_literal_supersession",
         :ok <- JSON.validate_object(normalization),
         true <- byte_size(Jason.encode!(normalization)) <= 2048,
         :ok <- Transaction.check(cap) do
      binding = %{
        "version" => 1,
        "original_request_sha256" => witness["original_request_sha256"],
        "recipe_sha256" => recipe,
        "normalization_sha256" => JSON.digest([normalization])
      }

      extra = %{"managed_binding_sha256" => JSON.digest([binding])}

      case managed_mutation(
             path,
             uid,
             s,
             manifest,
             original,
             normalized,
             id,
             extra,
             normalization,
             version,
             witness,
             cap
           ) do
        {:ok, receipt} ->
          {:ok,
           %{
             "version" => 1,
             "binding" => binding,
             "normalization" => normalization,
             "receipt" => receipt
           }}

        other ->
          other
      end
    else
      _ -> {:error, :managed_normalization_refused}
    end
  end

  defp managed_mutation(
         path,
         uid,
         state,
         manifest,
         _original,
         request,
         id,
         extra,
         normalization,
         {:capture, held},
         witness,
         cap
       ) do
    Ipse.Session.ManagedCapture.with_native_publication(cap, witness, held, fn ->
      with_capture_deadline(normalization, fn ->
        apply_mutation(path, uid, state, manifest, request, id, extra)
      end)
    end)
  end

  defp managed_mutation(
         path,
         uid,
         state,
         manifest,
         original,
         request,
         id,
         extra,
         normalization,
         {:supersession, review},
         witness,
         cap
       ) do
    alias Ipse.Runner.{Review, SessionSource}

    %{
      permit: permit,
      facts: facts,
      intent: intent,
      context: context,
      purpose_sha256: sha,
      source_leases: leases
    } = review

    with true <-
           facts["operation_id"] === id and
             get_in(facts, ["collection", "root_sha256"]) === witness["root_sha256"],
         {:ok, bound} <-
           Review.claim_supersession_effect(
             permit,
             facts,
             intent,
             original,
             request,
             normalization
           ) do
      SessionSource.with_supersession(cap, context, intent, sha, leases, fn ->
        with {:ok, ^bound} <-
               Review.claimed_supersession_effect(
                 permit,
                 facts,
                 intent,
                 original,
                 request,
                 normalization
               ) do
          with_notes_publication_deadline(bound.publish_before_ms, fn ->
            Process.put(@acceptance_attempt_key, true)
            apply_mutation(path, uid, state, manifest, request, id, extra)
          end)
        else
          _ -> {:error, :native_review_publication_fence_unavailable}
        end
      end)
    else
      _ -> {:error, :native_review_publication_fence_unavailable}
    end
  end

  defp managed_mutation(
         path,
         uid,
         state,
         manifest,
         original,
         request,
         id,
         extra,
         normalization,
         {:lineage_retention, owned, intent, permit, source_lease},
         witness,
         cap
       ) do
    alias Ipse.Runner.Review
    facts = intent["facts"]

    with true <- facts["kind"] === "managed_literal_lineage_retention",
         true <- normalization["kind"] === "native_literal_lineage_retention",
         true <- get_in(facts, ["collection", "root_sha256"]) === witness["root_sha256"],
         true <- facts["operation_id"] === id,
         {:ok, _} <-
           Ipse.Session.StoredSources.share_verified_identity(source_lease, [
             facts["source_proof"]
           ]),
         {:ok, bound} <-
           Review.claim_retention_effect(permit, facts, intent, original, request, normalization) do
      Transaction.with_lifecycle_journal_lease(cap, owned, intent, fn ->
        Transaction.with_source_lease(cap, source_lease, fn ->
          with :ok <- Transaction.lifecycle_guard(cap, intent),
               {:ok, ^bound} <-
                 Review.claimed_retention_effect(
                   permit,
                   facts,
                   intent,
                   original,
                   request,
                   normalization
                 ) do
            with_notes_publication_deadline(bound.publish_before_ms, fn ->
              Process.put(@acceptance_attempt_key, true)
              apply_mutation(path, uid, state, manifest, request, id, extra)
            end)
          else
            _ -> {:error, :native_review_publication_fence_unavailable}
          end
        end)
      end)
    else
      _ -> {:error, :native_review_publication_fence_unavailable}
    end
  end

  defp managed_mutation(
         path,
         uid,
         state,
         manifest,
         original,
         request,
         id,
         extra,
         normalization,
         {:retention, owned, intent, permit},
         witness,
         cap
       ) do
    alias Ipse.Runner.Review
    facts = intent["facts"]

    expected_kind =
      if facts["kind"] == "managed_accepted_decision_retention",
        do: "native_accepted_decision_retention",
        else: "native_literal_retention"

    with true <- normalization["kind"] === expected_kind,
         true <- get_in(facts, ["collection", "root_sha256"]) === witness["root_sha256"],
         true <- facts["operation_id"] === id,
         {:ok, bound} <-
           Review.claim_retention_effect(permit, facts, intent, original, request, normalization) do
      Transaction.with_lifecycle_journal_lease(cap, owned, intent, fn ->
        with :ok <- Transaction.lifecycle_guard(cap, intent),
             {:ok, ^bound} <-
               Review.claimed_retention_effect(
                 permit,
                 facts,
                 intent,
                 original,
                 request,
                 normalization
               ) do
          with_notes_publication_deadline(bound.publish_before_ms, fn ->
            Process.put(@acceptance_attempt_key, true)
            apply_mutation(path, uid, state, manifest, request, id, extra)
          end)
        else
          _ -> {:error, :native_review_publication_fence_unavailable}
        end
      end)
    else
      _ -> {:error, :native_review_publication_fence_unavailable}
    end
  end

  defp managed_mutation(
         path,
         uid,
         state,
         manifest,
         original,
         request,
         id,
         extra,
         normalization,
         {:pending_correction, owned, intent, permit, source_lease},
         witness,
         cap
       ) do
    alias Ipse.Runner.Review
    facts = intent["facts"]

    with true <- normalization["kind"] === "native_pending_correction",
         true <- get_in(facts, ["collection", "root_sha256"]) === witness["root_sha256"],
         true <- facts["operation_id"] === id,
         {:ok, bound} <-
           Review.claim_pending_correction_effect(
             permit,
             facts,
             intent,
             original,
             request,
             normalization
           ) do
      Transaction.with_pending_correction_journal_lease(cap, owned, intent, fn ->
        Transaction.with_source_lease(cap, source_lease, fn ->
          with :ok <- Transaction.pending_correction_guard(cap, intent),
               {:ok, ^bound} <-
                 Review.claimed_pending_correction_effect(
                   permit,
                   facts,
                   intent,
                   original,
                   request,
                   normalization
                 ) do
            with_notes_publication_deadline(bound.publish_before_ms, fn ->
              Process.put(@acceptance_attempt_key, true)
              apply_mutation(path, uid, state, manifest, request, id, extra)
            end)
          else
            _ -> {:error, :native_review_publication_fence_unavailable}
          end
        end)
      end)
    else
      _ -> {:error, :native_review_publication_fence_unavailable}
    end
  end

  defp managed_mutation(
         path,
         uid,
         state,
         manifest,
         _original,
         request,
         id,
         extra,
         normalization,
         _version,
         _witness,
         _cap
       ) do
    if normalization["kind"] in ~w(native_literal_retention native_literal_lineage_retention native_accepted_decision_retention native_literal_supersession native_pending_correction),
      do: {:error, :native_review_publication_fence_unavailable},
      else:
        with_capture_deadline(normalization, fn ->
          apply_mutation(path, uid, state, manifest, request, id, extra)
        end)
  end

  defp publish_acceptance(
         path,
         uid,
         state,
         manifest,
         witness,
         cap,
         alive,
         check,
         event,
         intent,
         request,
         permit
       ) do
    alias Ipse.Session.PendingAcceptance
    alias Ipse.Runner.Review

    with true <- notes_admission?(),
         deadline when is_integer(deadline) <- Process.get(@switch_deadline_key),
         true <- PendingAcceptance.valid_event?(event),
         facts = event["facts"],
         {:ok, ^intent} <- PendingAcceptance.effect_intent(event, intent["request"]),
         true <- PendingAcceptance.normalized_acceptance?(intent, request),
         [_, note, _] <- intent["request"]["changes"],
         note_deadline = note["value"]["valid_until_ms"],
         true <-
           deadline <= facts["valid_until_ms"] and
             (is_nil(note_deadline) or deadline <= note_deadline),
         true <-
           witness["root_sha256"] === facts["root_sha256"] and
             state["project"] === facts["namespace"],
         true <- normalized_managed?(intent["request"], request, state, witness, 3),
         {:ok, receipt} <- Review.claimed_acceptance_request(permit, facts, intent, request),
         true <- receipt === event["review"],
         :ok <- alive.(),
         :ok <- Transaction.acceptance_guard(cap, event, intent),
         :ok <- check.() do
      binding = JSON.digest(["pending_acceptance", 1, event, intent])
      Process.put(@acceptance_attempt_key, true)

      try do
        case apply_mutation(path, uid, state, manifest, request, facts["operation_id"], %{
               "managed_binding_sha256" => binding
             }) do
          {:ok, result} -> {:ok, result}
          {:unknown, _} = unknown -> unknown
          _ -> {:error, :pending_acceptance_refused}
        end
      rescue
        _ -> {:unknown, :collection_publication_unconfirmed}
      catch
        _, _ -> {:unknown, :collection_publication_unconfirmed}
      end
    else
      _ -> {:error, :pending_acceptance_refused}
    end
  rescue
    _ -> {:error, :pending_acceptance_refused}
  end

  defp with_capture_deadline(normalization, fun) do
    if notes_admission?() do
      deadline = normalization["valid_until_ms"]

      if normalization["version"] === 3 and not Map.has_key?(normalization, "kind") and
           Map.has_key?(normalization, "valid_until_ms") and
           (is_nil(deadline) or (JSON.safe_uint?(deadline) and deadline > 0)) do
        with_switch_deadline(deadline, fun)
      else
        {:error, :managed_normalization_refused}
      end
    else
      fun.()
    end
  end

  defp notes_admission? do
    case Process.get(@notes_admission_key) do
      {owner, token} when owner == self() and is_reference(token) -> true
      _ -> false
    end
  end

  defp with_switch_deadline(deadline, fun) do
    before = Process.get(@switch_deadline_key)

    selected =
      case {before, deadline} do
        {nil, value} -> value
        {value, nil} -> value
        {left, right} -> min(left, right)
      end

    if is_nil(selected) or System.system_time(:millisecond) < selected do
      Process.put(@switch_deadline_key, selected)

      try do
        fun.()
      after
        if is_nil(before),
          do: Process.delete(@switch_deadline_key),
          else: Process.put(@switch_deadline_key, before)
      end
    else
      {:error, :collection_use_expired}
    end
  end

  defp managed_root(s, nil) do
    with :absent <- Transaction.read_optional(publication_cap(), ".", "root.json", 1024),
         true <- s === empty(s["project"]) do
      {:ok,
       %{"version" => 2, "root_state" => "absent", "root_bytes" => nil, "root_sha256" => nil}}
    else
      _ -> @error
    end
  end

  defp managed_root(s, manifest) do
    with {:ok, bytes} <- Transaction.read_optional(publication_cap(), ".", "root.json", 1024),
         true <- is_binary(bytes) and byte_size(bytes) in 1..1024,
         {:ok, pointer} <- JSON.decode_unique(bytes),
         {:ok, pointer} <- Profile.unfence(pointer, Profile.selected()),
         true <- pointer["version"] in [2, 3, 4, 5],
         true <- pointer["manifest"] === manifest.hash,
         true <-
           pointer
           |> Map.delete("manifest")
           |> Map.put("version", 3)
           |> Map.put_new("floor_anchor", nil) == summary(s) do
      {:ok,
       %{
         "version" => 2,
         "root_state" => "present",
         "root_bytes" => bytes,
         "root_sha256" => JSON.sha256(bytes)
       }}
    else
      _ -> @error
    end
  end

  defp managed_read_cost(selected) when is_binary(selected), do: Directory.cost(selected)

  defp managed_read_cost(%{"op" => "neighbors"} = selected), do: Directory.cost(selected)
  defp managed_read_cost(%{"op" => "pending_summary"} = selected), do: Directory.cost(selected)
  defp managed_read_cost(_), do: :error

  defp debit_managed_read(key, token, cost, limit) do
    case Process.get(key) do
      {^token, count, :open} when count + cost <= limit ->
        Process.put(key, {token, count + cost, :open})
        :ok

      {^token, count, :open} ->
        Process.put(key, {token, count, :exceeded})
        :error

      _ ->
        :error
    end
  end

  defp managed_read(path, uid, s, _, _, key) when is_binary(key),
    do: read_record(path, uid, s, key)

  defp managed_read(_, _, s, directory, _, %{"op" => "pending_summary"}) do
    keys = Directory.pending_keys(directory)
    bytes = Enum.reduce(keys, 0, fn key, total -> total + s["records"][key]["bytes"] end)
    {:ok, %{"count" => length(keys), "bytes" => bytes}}
  end

  defp managed_read(_, _, s, directory, root, %{"op" => "neighbors", "request" => request} = r) do
    with {:ok, pointer} <- managed_pointer(root),
         true <- is_nil(pointer) or pointer["version"] in [4, 5],
         {:ok, _, nil, neighbors} <- Directory.select(directory, r, root["root_state"]),
         witness = %{
           "version" => 2,
           "root_state" => root["root_state"],
           "root" => pointer,
           "root_sha256" => root["root_sha256"],
           "manifest_sha256" => if(pointer, do: pointer["manifest"])
         },
         result = %{
           "version" => 1,
           "summary" => summary(s),
           "directory" => request,
           "state" => neighbors["state"],
           "neighbors" =>
             Map.new(Map.delete(neighbors, "state"), fn {slot, key} ->
               {slot, s["records"][key]}
             end),
           "witness" => witness
         },
         true <- byte_size(Jason.encode!(result)) <= 65_536 do
      {:ok, result}
    else
      _ -> {:error, :managed_read_refused}
    end
  end

  defp managed_pointer(%{"root_state" => "absent", "root_bytes" => nil}), do: {:ok, nil}

  defp managed_pointer(%{"root_state" => "present", "root_bytes" => bytes}),
    do: JSON.decode_unique(bytes)

  defp normalized_managed?(original, normalized, _, _, 2),
    do: normalized_managed?(original, normalized)

  defp normalized_managed?(original, normalized, state, root, :supersession) do
    with true <- valid_request?(normalized) and normalized["op"] == "commit",
         true <- normalized["expected_generation"] === original["expected_generation"],
         true <- normalized["advance_floor"] === true and original["advance_floor"] === true,
         [old, new] <- original["changes"],
         true <-
           String.starts_with?(old["key"], "note.") and String.starts_with?(new["key"], "note."),
         true <-
           old["key"] != new["key"] and old["expected_revision"] > 0 and
             new["expected_revision"] === 0,
         true <- is_map(old["value"]) and is_map(new["value"]),
         true <- Enum.all?(original["changes"], &(&1 in normalized["changes"])),
         extras = normalized["changes"] -- original["changes"],
         true <- length(extras) in 1..8,
         true <-
           Enum.all?(
             extras,
             &(v3_metadata_key?(&1["key"]) and &1["key"] != "host.validity.format" and
                 is_map(&1["value"]))
           ),
         true <-
           root["root_state"] == "present" and
             Map.has_key?(state["records"], "host.validity.format") do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp normalized_managed?(original, normalized, state, root, :accepted_retention) do
    with [target] <- original["changes"],
         true <- target["value"]["kind"] === "accepted_decision",
         true <-
           target["value"] |> Migration.encode() |> JSON.sha256() ==
             state["records"][target["key"]]["sha256"],
         true <- Enum.all?(normalized["changes"], &(&1["key"] != target["key"])),
         asserted = Map.update!(normalized, "changes", &(original["changes"] ++ &1)),
         do: normalized_managed?(original, asserted, state, root, 3),
         else: (_ -> false)
  rescue
    _ -> false
  end

  defp normalized_managed?(original, normalized, state, root, 3) do
    with true <- valid_request?(normalized) and normalized["op"] == "commit",
         true <- normalized["expected_generation"] === original["expected_generation"],
         true <- normalized["advance_floor"] === original["advance_floor"],
         true <- Enum.all?(original["changes"], &(&1 in normalized["changes"])),
         extras = normalized["changes"] -- original["changes"],
         true <- length(extras) in 1..5,
         {deleted, written} = Enum.split_with(extras, &is_nil(&1["value"])),
         true <- length(deleted) <= 1 and length(written) <= 4,
         true <- Enum.all?(extras, &v3_metadata_key?(&1["key"])),
         true <-
           Enum.all?(deleted, fn change ->
             change["key"] != "host.validity.format" and change["expected_revision"] > 0 and
               revision(state, change["key"]) === change["expected_revision"]
           end) do
      case root["root_state"] do
        "absent" ->
          deleted == [] and
            Enum.sort(Enum.map(extras, & &1["key"])) ==
              [
                "host.validity.a." <> String.duplicate("0", 64),
                "host.validity.format",
                "host.validity.l." <> String.duplicate("0", 66)
              ] and Enum.all?(extras, &(&1["expected_revision"] === 0))

        "present" ->
          Map.has_key?(state["records"], "host.validity.format") and
            Enum.all?(extras, &(&1["key"] != "host.validity.format"))

        _ ->
          false
      end
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp v3_metadata_key?("host.validity.format"), do: true

  defp v3_metadata_key?("host.validity.a." <> fence),
    do: JSON.sha256?(fence)

  defp v3_metadata_key?("host.validity.l." <> fence),
    do: Regex.match?(~r/\A0[0-2][0-9a-f]{64}\z/, fence)

  defp v3_metadata_key?(_), do: false

  defp normalized_managed?(original, normalized) do
    with true <- valid_request?(normalized) and normalized["op"] == "commit",
         true <- normalized["expected_generation"] === original["expected_generation"],
         true <- normalized["advance_floor"] === original["advance_floor"],
         true <- Enum.all?(original["changes"], &(&1 in normalized["changes"])),
         extras = normalized["changes"] -- original["changes"],
         true <- length(extras) in 1..16 do
      Enum.all?(extras, &(managed_key?(&1["key"]) and not is_nil(&1["value"])))
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp managed_key?(key), do: is_binary(key) and String.starts_with?(key, "host.validity.")

  defp apply_mutation(path, uid, s, manifest, r, id, extra_receipt) do
    known = Migration.known_operations(s)
    draft = document_draft_plan(s, r, id)

    cond do
      Map.has_key?(known, id) ->
        {:existing, Map.put(summary(s), "operation", known[id])}

      r["expected_generation"] != s["generation"] or
          Enum.any?(r["changes"] || [], &(revision(s, &1["key"]) != &1["expected_revision"])) ->
        {:conflict, summary(s)}

      Migration.fenced?(s, r["op"]) ->
        {:failed, Map.put(summary(s), "code", "collection_writer_fenced")}

      Profile.selected() === Profile.documents() and DocumentDraft.present?(s) and
          not DocumentDraft.physical?(s, &read_record(path, uid, s, &1)) ->
        {:failed, Map.put(summary(s), "code", "collection_document_draft_unconfirmed")}

      Profile.selected() === Profile.documents() and
          match?({:error, _}, draft) ->
        {:error, :document_store_refused}

      Profile.selected() === Profile.documents() and
          DocumentDraft.admission_error(s, r, draft_slots(draft)) !== nil ->
        {:failed,
         Map.put(summary(s), "code", DocumentDraft.admission_error(s, r, draft_slots(draft)))}

      document_admission_error(path, s, r, id) !== nil ->
        {:failed, Map.put(summary(s), "code", document_admission_error(path, s, r, id))}

      r["op"] == "import" and (r["project"] != s["project"] or r["floor"] != s["floor"]) ->
        {:failed, Map.put(summary(s), "code", "collection_import_floor")}

      map_size(known) >= Profile.limit(:operations) or not uint?(s["generation"] + 1) ->
        capacity(s)

      r["op"] == "import.open" and not Map.has_key?(r, "plan") and
          not import_fits?(path, uid, s, r["descriptor"]) ->
        capacity(s)

      true ->
        case prepare_with_document_draft(path, uid, s, r, id, draft) do
          {:ok, next, values, extra} ->
            receipt =
              Map.merge(
                %{
                  "generation" => s["generation"] + 1,
                  "floor" => next["floor"],
                  "request_sha256" => document_request_sha256(draft, r)
                },
                extra
              )
              |> Map.merge(extra_receipt)

            next = %{
              next
              | "generation" => receipt["generation"],
                "operations" => Map.put(s["operations"], id, receipt)
            }

            next =
              if r["advance_floor"] == true,
                do: Map.update!(next, "floor_lineage", &(&1 ++ [id])),
                else: next

            publish(path, uid, s, next, manifest, values, receipt, r)
            |> attach_document_progress(draft, next, s)

          {:failed, code} ->
            {:failed, Map.put(summary(s), "code", code)}
        end
    end
  end

  defp draft_slots({:ok, %{head: head}}), do: head["slots"]
  defp draft_slots(_), do: []

  defp document_request_sha256({:ok, %{request_sha256: sha256}}, _), do: sha256
  defp document_request_sha256(_, r), do: JSON.digest([r])

  defp attach_document_progress({:ok, receipt}, {:ok, %{head: previous, tag: tag}}, next, old) do
    current = DocumentDraft.heads(next)[previous["id"]]

    progress =
      DocumentDraft.receipt(
        previous,
        current,
        tag["action"],
        receipt["generation"],
        DocumentMaintenance.metadata(old)["epoch"]
      )

    {:ok, Map.put(receipt, "document_progress", progress)}
  end

  defp attach_document_progress(result, _, _, _), do: result

  defp document_draft_plan(s, r, id) do
    case Process.get(@document_progress_key) do
      nil ->
        {:ok, nil}

      %{request: request, request_sha256: sha256, operation_id: ^id, owner: owner} ->
        tag = request["progress"]

        with true <-
               Profile.selected() === Profile.documents() and
                 r["op"] in ~w(commit progress.verify progress.retire),
             true <- JSON.sha256?(sha256),
             {:ok, head} <-
               if(tag["action"] === "start",
                 do: DocumentDraft.first_head(s, tag, id, owner, request["slot"]),
                 else: DocumentDraft.authorize(s, tag, owner)
               ) do
          {:ok, %{head: head, tag: tag, request: request, request_sha256: sha256, owner: owner}}
        else
          _ -> {:error, :invalid_document_progress}
        end

      _ ->
        {:error, :invalid_document_progress}
    end
  rescue
    _ -> {:error, :invalid_document_progress}
  end

  defp prepare_with_document_draft(_path, _uid, s, r, id, {:ok, nil}),
    do: prepare(s, r, id)

  defp prepare_with_document_draft(
         path,
         uid,
         s,
         %{"op" => "progress.verify"} = r,
         _id,
         {:ok, plan}
       )
       when is_map(plan) do
    with {:ok, %{"value" => packed} = row} <- read_record(path, uid, s, r["key"]),
         true <- row["revision"] === r["expected_revision"],
         true <- packed["byte_count"] === r["byte_count"] and packed["sha256"] === r["sha256"],
         {:ok, _} <- Ipse.Extension.Collection.DocumentStage.decode_packed(packed),
         {:ok, head} <- DocumentDraft.verified_reuse(plan.head, plan.tag, s["generation"] + 1),
         next = put_document_draft(s, plan.head["id"], head) do
      {:ok, next, %{}, %{}}
    else
      _ -> {:failed, "collection_document_draft_unconfirmed"}
    end
  end

  defp prepare_with_document_draft(_path, _uid, s, %{"op" => "progress.retire"}, _id, {:ok, plan})
       when is_map(plan) do
    with {:ok, nil} <-
           DocumentDraft.retire(
             plan.head,
             plan.tag,
             plan.request,
             [],
             s["generation"] + 1,
             DocumentMaintenance.metadata(s)["epoch"]
           ) do
      {:ok, put_document_draft(s, plan.head["id"], nil), %{}, %{}}
    else
      _ -> {:failed, "collection_document_draft_unconfirmed"}
    end
  end

  defp prepare_with_document_draft(path, uid, s, r, id, {:ok, plan}) when is_map(plan) do
    with {:ok, next, values, extra} <- prepare(s, r, id),
         {:ok, head} <- document_draft_step(s, r, id, plan),
         next = put_document_draft(next, plan.head["id"], head),
         read = fn key -> changed_or_existing(path, uid, s, r["changes"], key) end,
         true <- DocumentDraft.physical?(next, read) do
      {:ok, next, values, extra}
    else
      {:failed, _} = failed -> failed
      _ -> {:failed, "collection_document_draft_unconfirmed"}
    end
  end

  defp document_draft_step(s, r, id, plan) do
    generation = s["generation"] + 1

    if plan.tag["action"] === "retire" do
      with {:ok, head} <-
             DocumentDraft.retire(
               plan.head,
               plan.tag,
               plan.request,
               r["changes"],
               generation,
               DocumentMaintenance.metadata(s)["epoch"]
             ) do
        DocumentDraft.bind_retirement(head, id, plan.owner["invocation_id"])
      end
    else
      DocumentDraft.step(plan.head, plan.tag, plan.request, r["changes"], generation)
    end
  end

  defp put_document_draft(state, id, nil) do
    remaining = Map.delete(DocumentDraft.heads(state), id)

    if map_size(remaining) == 0,
      do: Map.delete(state, "document_drafts"),
      else: Map.put(state, "document_drafts", remaining)
  end

  defp put_document_draft(state, id, head),
    do: Map.put(state, "document_drafts", Map.put(DocumentDraft.heads(state), id, head))

  defp changed_or_existing(path, uid, state, changes, key) do
    case Enum.find(changes, &(&1["key"] === key)) do
      nil -> read_record(path, uid, state, key)
      %{"value" => nil} -> {:ok, nil}
      %{"value" => value} -> {:ok, %{"value" => value}}
    end
  end

  defp document_admission_error(path, %{"project" => project} = s, r, id) do
    if Profile.selected() === Profile.documents() and
         r["op"] not in ~w(maintenance.open maintenance.close) do
      case Process.get(@document_epoch_key) do
        nil ->
          DocumentMaintenance.admission_error(s, id, nil)

        %{path: admitted_path, namespace: namespace, owner: owner, epoch: epoch, status: status}
        when namespace === project ->
          if admitted_path === Path.expand(path) and
               Ipse.Extension.Collection.DocumentStage.owner?(owner) do
            case DocumentMaintenance.admission_error(s, id, epoch) do
              nil when status === "idle" -> nil
              nil -> "collection_document_admission"
              error -> error
            end
          else
            "collection_document_admission"
          end

        _ ->
          "collection_document_admission"
      end
    end
  end

  defp import_fits?(path, uid, s, descriptor) do
    import_fits_quiescent?(path, uid, s, descriptor)
  end

  defp import_fits_quiescent?(path, uid, s, descriptor) do
    # Staging additionally checks exact allocation before every publication.
    extra_manifest =
      descriptor["records"] * 512 + div(descriptor["records"] + 31, 32) * 256 + 4096 +
        descriptor["operations"] * 384

    manifest_bound = byte_size(Encoding.encode(s)) + extra_manifest

    with true <- manifest_bound <= Profile.limit(:manifest_bytes),
         {:ok, disk} <- disk_bytes(path, uid),
         {:ok, allocation} <- allocation() do
      disk + descriptor["data_bytes"] + 2 * manifest_bound + Profile.limit(:reserved_bytes) <=
        Profile.limit(:total_bytes) and
        allocation["allocated_bytes"] + descriptor["data_bytes"] + 2 * manifest_bound +
          Profile.limit(:reserved_bytes) <= Profile.limit(:total_bytes)
    else
      _ -> false
    end
  end

  defp prepare(s, %{"op" => op} = r, id) when op in ~w(commit import) do
    {records, values} = changed_records(s, r["changes"], id)
    floor = if r["advance_floor"], do: max(s["generation"] + 1, s["floor"] + 1), else: s["floor"]

    next = %{
      s
      | "records" => records,
        "floor" => floor,
        "floor_anchor" => if(r["advance_floor"], do: id, else: s["floor_anchor"]),
        "checkpoint" => if(r["advance_floor"], do: nil, else: s["checkpoint"])
    }

    {:ok, next, values, %{}}
  end

  defp prepare(s, %{"op" => "import.open"} = r, id) do
    with {:ok, next, values, extra} <- Migration.prepare(s, r, id),
         true <-
           map_size(Migration.known_operations(next)) + Migration.reserved_operation_slots(next) +
             1 <= Profile.limit(:operations) do
      {:ok, next, values, extra}
    else
      false -> {:failed, "collection_capacity"}
      failed -> failed
    end
  end

  defp prepare(s, %{"op" => op} = r, id) when op in ~w(maintenance.open maintenance.close),
    do: DocumentMaintenance.prepare(s, r, id, Profile.limit(:operations))

  defp prepare(s, r, id), do: Migration.prepare(s, r, id)

  defp status(path, uid, s) do
    with {:ok, disk} <- disk_bytes(path, uid),
         {:ok, allocation} <- allocation() do
      {:ok,
       Map.merge(summary(s), %{
         "records" => map_size(s["records"]),
         "migration" => if(s["migration"], do: Map.drop(s["migration"], ["records"])),
         "checkpoint" => if(s["checkpoint"], do: Map.drop(s["checkpoint"], ["records"])),
         "staged_records" => map_size(get_in(s, ["migration", "records"]) || %{}),
         "staged_data_bytes" => Migration.bytes(get_in(s, ["migration", "records"]) || %{}),
         "checkpoint_records" => map_size(get_in(s, ["checkpoint", "records"]) || %{}),
         "checkpoint_data_bytes" => Migration.bytes(get_in(s, ["checkpoint", "records"]) || %{}),
         "operations" => map_size(Migration.operations(s)),
         "reserved_operation_slots" =>
           Migration.reserved_operation_slots(s) + DocumentMaintenance.reserved_slots(s),
         "data_bytes" => data_bytes(s),
         "envelope_data_bytes" => envelope_bytes(s),
         "disk_bytes" => disk,
         "accounted_total_bytes" => disk + Profile.limit(:reserved_bytes),
         "allocated_bytes" => allocation["allocated_bytes"],
         "accounted_allocated_bytes" =>
           allocation["allocated_bytes"] + Profile.limit(:reserved_bytes),
         "notice" =>
           if(
             envelope_bytes(s) >= div(Profile.limit(:data_bytes) * 4, 5) or
               disk + Profile.limit(:reserved_bytes) >= div(Profile.limit(:total_bytes) * 4, 5) or
               allocation["allocated_bytes"] + Profile.limit(:reserved_bytes) >=
                 div(Profile.limit(:total_bytes) * 4, 5) or
               map_size(s["records"]) >= div(Profile.limit(:records) * 4, 5) or
               map_size(Migration.operations(s)) >= div(Profile.limit(:operations) * 4, 5),
             do: "capacity_80_percent"
           ),
         "limits" => limits(Profile.selected())
       })}
    end
  end

  defp changed_records(s, changes, id) do
    Enum.reduce(changes, {s["records"], %{}}, fn c, {records, values} ->
      if is_nil(c["value"]) do
        {Map.delete(records, c["key"]), values}
      else
        bytes = Migration.encode(c["value"])
        hash = JSON.sha256(bytes)

        record = %{
          "key" => c["key"],
          "revision" => s["generation"] + 1,
          "sha256" => hash,
          "bytes" => byte_size(bytes),
          "operation_id" => id
        }

        {Map.put(records, c["key"], record), Map.put(values, hash, bytes)}
      end
    end)
  end

  defp publish(path, uid, old, next, manifest, values, receipt, request) do
    case Blocks.encode(next) do
      {:ok, bytes, blocks} ->
        publish_encoded(path, uid, old, next, manifest, values, receipt, request, bytes, blocks)

      _ ->
        capacity(old)
    end
  end

  defp publish_encoded(path, uid, old, next, manifest, values, receipt, request, bytes, blocks) do
    case DocumentDraft.cleanup_reserve(next, bytes, blocks) do
      {:ok, draft_reserve} ->
        publish_encoded_reserved(
          path,
          uid,
          old,
          next,
          manifest,
          values,
          receipt,
          request,
          bytes,
          blocks,
          draft_reserve
        )

      _ ->
        capacity(old)
    end
  end

  defp publish_encoded_reserved(
         path,
         uid,
         old,
         next,
         manifest,
         values,
         receipt,
         request,
         bytes,
         blocks,
         draft_reserve
       ) do
    terminal = terminal_reserve(next, blocks) ++ draft_reserve

    cond do
      not valid_state?(next, next["project"]) or
        map_size(next["records"]) > Profile.limit(:records) or
        data_bytes(next) > Profile.limit(:data_bytes) or
        byte_size(bytes) > Profile.limit(:manifest_bytes) or
          Enum.any?(terminal, &(&1 > Profile.limit(:manifest_bytes))) ->
        capacity(old)

      true ->
        hash = JSON.sha256(bytes)

        pointer =
          Jason.encode!(
            summary(next)
            |> Map.put("version", Blocks.version(next))
            |> Map.put("manifest", hash)
            |> Profile.fence()
          )

        with :ok <- collect(path, uid, old, manifest),
             {:ok, planned} <- full_import_plan(path, uid, old, next, request),
             {:ok, pending} <- prepare_values(path, uid, values),
             {:ok, pending_blocks} <- prepare_files(path, uid, blocks, "manifests", 64 * 1024),
             {:ok, disk} <- disk_bytes(path, uid),
             true <-
               disk + Profile.limit(:reserved_bytes) + byte_size(bytes) +
                 Enum.sum(Enum.map(pending, fn {_, _, v} -> byte_size(v) end)) +
                 Enum.sum(Enum.map(pending_blocks, fn {_, _, v} -> byte_size(v) end)) +
                 byte_size(pointer) + Enum.sum(terminal) <= Profile.limit(:total_bytes),
             :ok <-
               Transaction.preflight(
                 publication_cap(),
                 planned ++
                   terminal ++
                   [
                     byte_size(bytes),
                     byte_size(pointer)
                     | Enum.map(pending ++ pending_blocks, fn {_, _, value} ->
                         byte_size(value)
                       end)
                   ]
               ) do
          # Every failure after staging is an inspected unknown outcome. In
          # particular a failed final directory sync cannot justify replay.
          with :ok <- write_values(pending),
               :ok <- write_files(pending_blocks, "manifests"),
               :ok <- immutable(Path.join(path, "manifests"), hash, bytes, uid),
               :ok <-
                 publish_pointer_and_collect(
                   path,
                   uid,
                   pointer,
                   next,
                   %{hash: hash, blocks: MapSet.new(Map.keys(blocks))}
                 ) do
            {:ok, receipt}
          else
            _ -> {:unknown, :collection_publication_unconfirmed}
          end
        else
          false ->
            capacity(old)

          {:error, :transaction_capacity} ->
            capacity(old)

          {:error, :invalid_transaction_request} ->
            capacity(old)

          {:error, :transaction_filesystem_unsupported} ->
            {:error, :collection_filesystem_unsupported}

          _ ->
            @error
        end
    end
  end

  defp publish_pointer_and_collect(path, uid, bytes, state, manifest) do
    fun = fn ->
      with :ok <- publish_pointer(path, uid, bytes, state),
           do: collect(path, uid, state, manifest)
    end

    case Process.get(@document_retirement_owner_key) do
      {context, intent, authority} ->
        cap = publication_cap()

        Ipse.Runner.SessionSource.with_document_retirement(
          cap,
          context,
          intent,
          authority,
          fn wall ->
            Process.put(@document_retirement_wall_key, wall)

            try do
              fun.()
            after
              Process.delete(@document_retirement_wall_key)
            end
          end
        )

      nil ->
        fun.()
    end
  end

  defp publish_pointer(_path, _uid, bytes, state) do
    temporary = ".pending-" <> Ipse.Usage.id()

    with :ok <- Transaction.stage(publication_cap(), ".", [{temporary, bytes}]),
         {:ok, allocation} <- allocation(),
         :ok <- report_allocation(state, allocation),
         true <-
           allocation["allocated_bytes"] + Profile.limit(:reserved_bytes) <=
             Profile.limit(:total_bytes),
         :ok <- switch_pointer(temporary),
         do: :ok
  end

  defp switch_pointer(temporary) do
    with :ok <- document_migration_guard() do
      case Process.get(@document_retirement_wall_key) do
        wall when is_integer(wall) ->
          wall =
            case Process.get(@switch_deadline_key) do
              deadline when is_integer(deadline) -> min(wall, deadline)
              nil -> wall
            end

          Transaction.document_retirement_switch(publication_cap(), temporary, wall)

        nil ->
          switch_pointer_admitted(temporary)
      end
    end
  end

  defp switch_pointer_admitted(temporary) do
    case Process.get(@switch_deadline_key) do
      nil ->
        Transaction.switch(publication_cap(), temporary, "root.json")

      deadline ->
        if Profile.selected() == Profile.documents() or
             (Profile.selected() == Profile.notes() and notes_admission?()),
           do: Transaction.switch_before(publication_cap(), temporary, "root.json", deadline),
           else: publication_deadline_admission(deadline)
    end
  end

  defp allocation do
    case Transaction.allocation(publication_cap()) do
      {:ok, %{logical: logical, allocated: allocated, entries: entries}} ->
        {:ok, %{"logical_bytes" => logical, "allocated_bytes" => allocated, "entries" => entries}}

      error ->
        error
    end
  end

  defp report_allocation(state, allocation) do
    :telemetry.execute(
      [:ipse, :extension, :collection, :staged],
      %{
        allocated_bytes: allocation["allocated_bytes"],
        accounted_allocated_bytes: allocation["allocated_bytes"] + Profile.limit(:reserved_bytes),
        root_publication_reserved_bytes: 0
      },
      %{generation: state["generation"]}
    )

    :ok
  end

  defp prepare_values(path, uid, values) do
    prepare_files(path, uid, values, "objects", Profile.limit(:value_bytes))
  end

  defp prepare_files(path, uid, values, relative, limit) do
    dir = Path.join(path, relative)

    Enum.reduce_while(values, {:ok, []}, fn {hash, bytes}, {:ok, pending} ->
      target = Path.join(dir, hash <> ".json")

      case File.lstat(target) do
        {:error, :enoent} ->
          {:cont, {:ok, [{".pending-" <> Ipse.Usage.id(), target, bytes} | pending]}}

        {:ok, _} ->
          case bounded_file(target, uid, limit) do
            {:ok, ^bytes} -> {:cont, {:ok, pending}}
            _ -> {:halt, @error}
          end

        _ ->
          {:halt, @error}
      end
    end)
  end

  defp write_values(files), do: write_files(files, "objects")
  defp write_files([], _), do: :ok

  defp write_files(files, relative) do
    files
    |> Enum.chunk_every(128)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      with :ok <-
             Transaction.stage(
               publication_cap(),
               relative,
               Enum.map(chunk, fn {name, _, bytes} -> {name, bytes} end)
             ),
           :ok <-
             Enum.reduce_while(chunk, :ok, fn {name, target, _}, :ok ->
               case Transaction.install(publication_cap(), relative, name, Path.basename(target)) do
                 :ok -> {:cont, :ok}
                 error -> {:halt, error}
               end
             end) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp immutable(dir, hash, bytes, uid) do
    file = Path.join(dir, hash <> ".json")

    case File.lstat(file) do
      {:error, :enoent} ->
        replace(dir, hash <> ".json", bytes, uid)

      {:ok, _} ->
        with {:ok, ^bytes} <- bounded_file(file, uid, Profile.limit(:manifest_bytes)),
             do: :ok,
             else: (_ -> @error)

      _ ->
        @error
    end
  end

  defp replace(dir, name, bytes, _uid) do
    temporary = ".pending-" <> Ipse.Usage.id()
    relative = Path.basename(dir)

    with :ok <- Transaction.stage(publication_cap(), relative, [{temporary, bytes}]),
         do: Transaction.install(publication_cap(), relative, temporary, name)
  end

  defp load(path, project, uid) do
    case File.lstat(Path.join(path, "root.json")) do
      {:error, :enoent} ->
        {:ok, empty(project), nil}

      {:ok, _} ->
        with {:ok, bytes} <- bounded_file(Path.join(path, "root.json"), uid, 1024),
             do: load_pointer(path, project, uid, bytes)

      _ ->
        @error
    end
  end

  defp empty(project),
    do: %{
      "version" => 3,
      "project" => project,
      "generation" => 0,
      "floor" => 0,
      "floor_anchor" => nil,
      "floor_lineage" => [],
      "records" => %{},
      "operations" => %{},
      "imported_operations" => %{},
      "migration" => nil,
      "checkpoint" => nil
    }

  defp load_pointer(path, project, uid, bytes) do
    with {:ok, root} <- JSON.decode_unique(bytes),
         {:ok, root} <- Profile.unfence(root, Profile.selected()),
         true <-
           (keys?(root, ~w(version project generation floor manifest)) or
              keys?(root, ~w(version project generation floor floor_anchor manifest))) and
             root["version"] in [2, 3, 4, 5] and root["project"] == project and
             uint?(root["generation"]) and uint?(root["floor"]) and
             JSON.sha256?(root["manifest"]),
         {:ok, bytes} <-
           bounded_file(
             Path.join([path, "manifests", root["manifest"] <> ".json"]),
             uid,
             Profile.limit(:manifest_bytes)
           ),
         true <- JSON.sha256(bytes) == root["manifest"],
         {:ok, stored} <- JSON.decode_unique(bytes),
         true <- summary(stored) == Map.delete(root, "manifest"),
         {:ok, s, blocks} <- decode_manifest(stored, path, uid),
         true <- valid_state?(s, project) do
      {:ok, s, %{hash: root["manifest"], blocks: blocks}}
    else
      _ -> @error
    end
  end

  defp decode_manifest(%{"version" => version} = stored, path, uid) when version in [4, 5] do
    case Blocks.decode(stored, fn hash, bytes ->
           bounded_file(Path.join([path, "manifests", hash <> ".json"]), uid, bytes)
         end) do
      {:ok, state, hashes} -> {:ok, state, hashes}
      _ -> @error
    end
  end

  defp decode_manifest(stored, _, _) do
    case Encoding.decode(stored) do
      {:ok, state} -> {:ok, state, MapSet.new()}
      _ -> @error
    end
  end

  defp valid_state?(s, project) do
    keys?(
      s,
      ~w(version project generation floor floor_anchor floor_lineage records operations imported_operations migration checkpoint) ++
        if(Profile.selected() === Profile.documents() and DocumentMaintenance.present?(s),
          do: ["document_maintenance"],
          else: []
        ) ++
        if(Profile.selected() === Profile.documents() and DocumentDraft.present?(s),
          do: ["document_drafts"],
          else: []
        )
    ) and
      DocumentMaintenance.valid?(s) and
      DocumentDraft.valid_absent_or_present?(s) and
      s["version"] === 3 and
      s["project"] == project and uint?(s["generation"]) and uint?(s["floor"]) and
      is_map(s["records"]) and
      map_size(s["records"]) <= Profile.limit(:records) and
      is_map(s["operations"]) and map_size(s["operations"]) <= Profile.limit(:operations) and
      s["generation"] == map_size(s["operations"]) and
      valid_imported_operations?(s) and
      valid_floor_anchor?(s) and
      Migration.valid_lineage?(
        s["floor_lineage"],
        s["floor_anchor"],
        s["floor"],
        Migration.operations(s)
      ) and
      valid_records?(s["records"], s) and
      Migration.valid?(s, &valid_records?(&1, s)) and
      Enum.all?(s["operations"], fn {id, r} ->
        id?(id) and Migration.receipt?(r) and r["generation"] in 1..s["generation"]
      end) and
      length(Enum.uniq_by(Map.values(s["operations"]), & &1["generation"])) == s["generation"] and
      envelope_bytes(s) <= Profile.limit(:data_bytes)
  rescue
    _ -> false
  end

  defp valid_records?(records, s) do
    operations = Migration.operations(s)

    is_map(records) and map_size(records) <= Profile.limit(:records) and
      Enum.all?(records, fn {key, r} ->
        keys?(r, ~w(key revision sha256 bytes operation_id)) and key?(key) and r["key"] == key and
          uint?(r["revision"]) and r["revision"] in 1..s["generation"] and
          JSON.sha256?(r["sha256"]) and is_integer(r["bytes"]) and
          r["bytes"] in 2..Profile.limit(:value_bytes) and
          id?(r["operation_id"]) and
          get_in(operations, [r["operation_id"], "generation"]) == r["revision"]
      end)
  end

  defp valid_imported_operations?(s) do
    staged = get_in(s, ["migration", "imported_operations"]) || %{}
    imported = s["imported_operations"]

    is_map(imported) and is_map(staged) and
      map_size(s["operations"]) + map_size(imported) + map_size(staged) +
        Migration.reserved_operation_slots(s) + DocumentMaintenance.reserved_slots(s) +
        DocumentDraft.reserved_operations(s) <=
        Profile.limit(:operations) and
      Enum.all?(imported, fn {id, receipt} -> id?(id) and Migration.receipt?(receipt) end) and
      Enum.all?(Map.keys(imported), &(not Map.has_key?(s["operations"], &1))) and
      Enum.all?(
        Map.keys(staged),
        &(not Map.has_key?(s["operations"], &1) and not Map.has_key?(imported, &1))
      )
  end

  defp read_record(path, uid, s, key) do
    case s["records"][key] do
      nil ->
        {:ok, nil}

      r ->
        with {:ok, bytes} <-
               bounded_file(
                 Path.join([path, "objects", r["sha256"] <> ".json"]),
                 uid,
                 Profile.limit(:value_bytes)
               ),
             true <- byte_size(bytes) == r["bytes"] and JSON.sha256(bytes) == r["sha256"],
             {:ok, value} <- JSON.decode_unique(bytes),
             true <- value?(value) do
          {:ok, Map.put(r, "value", value)}
        else
          _ -> @error
        end
    end
  end

  defp read_records(path, uid, s, keys) do
    Enum.reduce_while(keys, {:ok, []}, fn key, {:ok, records} ->
      case read_record(path, uid, s, key) do
        {:ok, r} -> {:cont, {:ok, [r | records]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      error -> error
    end
  end

  # At most 512 orphan files are removed in one pass. Active objects and the
  # currently selected manifest are protected while the storage lock is held.
  defp collect(path, uid, s, manifest) do
    with :ok <- Transaction.check(publication_cap()),
         do: collect_quiescent(path, uid, s, manifest)
  end

  defp collect_quiescent(path, uid, s, manifest) do
    live =
      s
      |> Migration.collections()
      |> Enum.flat_map(fn records ->
        Enum.map(records, fn {_, r} -> r["sha256"] <> ".json" end)
      end)
      |> MapSet.new()
      |> MapSet.put(".writer.lock")

    with :ok <- collect_dir(Path.join(path, "objects"), uid, live),
         :ok <-
           collect_dir(
             Path.join(path, "manifests"),
             uid,
             if(manifest, do: manifest.blocks, else: MapSet.new())
             |> Enum.map(&(&1 <> ".json"))
             |> MapSet.new()
             |> MapSet.put(".writer.lock")
             |> then(fn live ->
               if manifest, do: MapSet.put(live, manifest.hash <> ".json"), else: live
             end)
           ),
         :ok <- collect_root_pending(path, uid),
         do: :ok
  end

  defp collect_root_pending(path, uid) do
    with {:ok, names} <- File.ls(path), true <- length(names) <= 1028 do
      reclaim_selected(path, ".", uid, names |> Enum.filter(&pending?/1) |> Enum.take(512))
    else
      _ -> @error
    end
  end

  defp collect_dir(dir, uid, live) do
    with {:ok, names} <- File.ls(dir),
         true <- length(names) <= Profile.limit(:records) * 2 + 1024 do
      reclaim_selected(
        dir,
        Path.basename(dir),
        uid,
        names |> Enum.reject(&MapSet.member?(live, &1)) |> Enum.take(512)
      )
    else
      _ -> @error
    end
  end

  defp reclaim_selected(path, relative, uid, names) do
    if Enum.all?(names, fn name ->
         with true <- artifact_name?(name),
              {:ok, stat} <- File.lstat(Path.join(path, name)),
              do: safe_file?(stat, uid),
              else: (_ -> false)
       end) do
      names
      |> Enum.chunk_every(64)
      |> Enum.reduce_while(:ok, fn chunk, :ok ->
        case Transaction.reclaim(publication_cap(), relative, chunk) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      @error
    end
  end

  defp disk_bytes(path, uid) do
    with {:ok, top} <- File.ls(path),
         true <-
           Enum.all?(
             top,
             &(&1 in ~w(.lock .writer.lock root.json objects manifests) or pending?(&1))
           ),
         {:ok, bytes} <- files_bytes(path, Enum.reject(top, &(&1 in ~w(objects manifests))), uid),
         {:ok, objects} <- File.ls(Path.join(path, "objects")),
         {:ok, manifests} <- File.ls(Path.join(path, "manifests")),
         true <-
           length(objects) <= Profile.limit(:records) * 2 + 1024 and length(manifests) <= 2048,
         {:ok, a} <- files_bytes(Path.join(path, "objects"), objects, uid),
         {:ok, b} <- files_bytes(Path.join(path, "manifests"), manifests, uid),
         true <- bytes + a + b + Profile.limit(:reserved_bytes) <= Profile.limit(:total_bytes) do
      {:ok, bytes + a + b}
    else
      _ -> @error
    end
  end

  defp files_bytes(dir, names, uid) do
    Enum.reduce_while(names, {:ok, 0}, fn name, {:ok, bytes} ->
      with true <- name in ~w(.lock .writer.lock root.json) or artifact_name?(name),
           {:ok, stat} <- File.lstat(Path.join(dir, name)),
           true <- safe_file?(stat, uid) do
        {:cont, {:ok, bytes + stat.size}}
      else
        _ -> {:halt, @error}
      end
    end)
  end

  defp bounded_file(path, uid, limit) do
    with {:ok, stat} <- File.lstat(path),
         true <- safe_file?(stat, uid) and stat.size <= limit,
         root when is_binary(root) <- Process.get(@path_key),
         directory = Path.relative_to(Path.dirname(path), root),
         true <- directory in [".", "objects", "manifests"],
         {:ok, bytes} <-
           Transaction.read(publication_cap(), directory, Path.basename(path), limit),
         true <- is_binary(bytes) and byte_size(bytes) <= limit do
      {:ok, bytes}
    else
      _ -> @error
    end
  end

  defp directory(path, uid, create) do
    case File.lstat(path) do
      {:error, :enoent} when create ->
        case File.mkdir(path) do
          :ok ->
            with :ok <- File.chmod(path, 0o700),
                 :ok <- Ipse.Runner.protected_sync_directory(Path.dirname(path)),
                 do: directory(path, uid, false)

          {:error, :eexist} ->
            directory(path, uid, false)

          _ ->
            @error
        end

      {:ok, %{type: :directory, uid: ^uid, mode: mode}} when band(mode, 0o077) == 0 ->
        case Ipse.Workspace.canonical_path(path) do
          {:ok, ^path} -> :ok
          _ -> @error
        end

      _ ->
        @error
    end
  end

  defp safe_lock(path, uid) do
    case File.lstat(path) do
      {:error, :enoent} -> :ok
      {:ok, stat} -> if safe_file?(stat, uid), do: :ok, else: @error
      _ -> @error
    end
  end

  defp publication_cap, do: Process.get(@lock_key)

  defp safe_file?(s, uid),
    do: s.type == :regular and s.uid == uid and s.links == 1 and band(s.mode, 0o077) == 0

  defp summary(s), do: Map.take(s, ~w(version project generation floor floor_anchor))

  defp valid_floor_anchor?(%{"floor" => 0, "floor_anchor" => nil}), do: true

  defp valid_floor_anchor?(s) do
    id?(s["floor_anchor"]) and
      get_in(Migration.operations(s), [s["floor_anchor"], "floor"]) === s["floor"]
  end

  defp envelope_bytes(s) do
    s
    |> Migration.collections()
    |> Enum.flat_map(&Map.to_list/1)
    |> Enum.uniq_by(fn {key, record} -> {key, record["sha256"]} end)
    |> Enum.reduce(0, fn {_, record}, total -> total + record["bytes"] end)
  end

  defp terminal_reserve(
         %{"migration" => nil, "checkpoint" => %{"document_owner" => _}} = s,
         staged_blocks
       ) do
    {:ok, manifest, _} = Blocks.encode(s)
    {:ok, _cleanup, additional} = DocumentDraft.cleanup_reserve(s, manifest, staged_blocks, 1)
    additional
  end

  defp terminal_reserve(%{"migration" => nil}, _), do: []

  defp terminal_reserve(%{"migration" => %{"version" => 1}} = s, staged_blocks) do
    m = s["migration"]
    owner = Map.put(m["owner"], "invocation_id", String.duplicate("0", 32))

    requests =
      Enum.map(~w(restore.abort restore.commit), fn op ->
        %{
          "op" => op,
          "migration_id" => m["id"],
          "expected_generation" => s["generation"],
          "expected_epoch" => m["epoch"],
          "plan_binding_sha256" => m["plan_binding_sha256"],
          "dependency_union_sha256" => m["dependency_union_sha256"]
        }
      end)

    document_terminal_vectors(s, staged_blocks, requests, owner)
  end

  defp terminal_reserve(s, staged_blocks) do
    # A valid nonterminal import reserves an additional complete abort publication.
    # Aliases survive abort; its extra receipt cannot consume the final identity.
    known = Migration.known_operations(s)

    id =
      Enum.find_value(0..Profile.limit(:operations), fn n ->
        candidate = n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")
        if not Map.has_key?(known, candidate), do: candidate
      end)

    {:ok, aborted, _, _} =
      Migration.prepare(
        s,
        %{
          "op" => "import.abort",
          "migration_id" => s["migration"]["id"]
        },
        id
      )

    receipt = %{
      "generation" => s["generation"] + 1,
      "floor" => s["floor"],
      "request_sha256" => String.duplicate("f", 64)
    }

    aborted = %{
      aborted
      | "generation" => receipt["generation"],
        "operations" => Map.put(s["operations"], id, receipt)
    }

    {:ok, bytes, aborted_blocks} = Blocks.encode(aborted)
    new_blocks = Map.drop(aborted_blocks, Map.keys(staged_blocks))
    [byte_size(bytes), 1024 | Enum.map(new_blocks, fn {_, bytes} -> byte_size(bytes) end)]
  end

  defp document_terminal_vectors(s, staged_blocks, requests, owner) do
    known = Migration.known_operations(s)

    id =
      Enum.find_value(0..Profile.limit(:operations), fn n ->
        candidate = Integer.to_string(n, 16) |> String.downcase() |> String.pad_leading(32, "0")
        if not Map.has_key?(known, candidate), do: candidate
      end)

    Enum.flat_map(requests, fn request ->
      case DocumentMigration.prepare(s, request, id, owner, nil) do
        {:ok, next, _, extra} ->
          receipt =
            Map.merge(
              %{
                "generation" => s["generation"] + 1,
                "floor" => next["floor"],
                "request_sha256" => JSON.digest([request, DocumentDraft.owner(owner)])
              },
              extra
            )

          next = %{
            next
            | "generation" => receipt["generation"],
              "operations" => Map.put(s["operations"], id, receipt)
          }

          {:ok, bytes, blocks} = Blocks.encode(next)

          [
            byte_size(bytes),
            1024
            | Enum.map(Map.drop(blocks, Map.keys(staged_blocks)), fn {_, value} ->
                byte_size(value)
              end)
          ] ++
            terminal_reserve(next, blocks)

        {:failed, _} ->
          []
      end
    end)
  end

  defp full_import_plan(path, uid, old, next, %{
         "op" => "import.open",
         "plan" => supplied,
         "descriptor" => descriptor
       }) do
    with {:ok, plan} <- Planning.validate(old, descriptor, supplied) do
      reserve_import_plan(path, uid, next, planned_generation(next, plan.records))
    end
  end

  defp full_import_plan(path, uid, _old, next, %{"op" => "restore.open"}) do
    reserve_import_plan(path, uid, next, DocumentMigration.forecast(next))
  rescue
    _ -> {:error, :transaction_capacity}
  end

  defp full_import_plan(_, _, _, _, _), do: {:ok, []}

  defp reserve_import_plan(path, uid, next, future) do
    with true <- envelope_bytes(future) <= Profile.limit(:data_bytes),
         {:ok, sizes} <- planned_object_sizes(path, uid, future["migration"]["records"]),
         {:ok, future_bytes, future_blocks} <- Blocks.encode(future),
         {:ok, new_blocks} <- prepare_files(path, uid, future_blocks, "manifests", 64 * 1024),
         block_sizes = Enum.map(new_blocks, fn {_, _, bytes} -> byte_size(bytes) end),
         stable = Blocks.import_stable_hashes(next),
         variable_sizes =
           new_blocks
           |> Enum.reject(fn {_, target, _} ->
             MapSet.member?(stable, Path.basename(target, ".json"))
           end)
           |> Enum.map(fn {_, _, bytes} -> byte_size(bytes) end),
         manifest_size = byte_size(future_bytes),
         true <- manifest_size <= Profile.limit(:manifest_bytes),
         terminal = terminal_reserve(future, future_blocks),
         true <- Enum.all?(terminal, &(&1 <= Profile.limit(:manifest_bytes))),
         # Immutable metadata reachable at successful open needs one set. A late
         # page can have both previous and next variable tails/staged indexes.
         # Keep two sets of those, plus the independently publishable abort; the
         # native two-times-rounded allowance still applies to every size here.
         sizes = [
           manifest_size,
           manifest_size,
           1024 | terminal ++ block_sizes ++ variable_sizes ++ sizes
         ],
         true <- length(sizes) <= 256,
         {:ok, disk} <- disk_bytes(path, uid),
         true <-
           disk + Profile.limit(:reserved_bytes) + Enum.sum(sizes) <= Profile.limit(:total_bytes),
         :ok <- report_import_plan(sizes),
         :ok <- Transaction.preflight(publication_cap(), sizes) do
      {:ok, []}
    else
      false -> {:error, :transaction_capacity}
      other -> other
    end
  end

  defp report_import_plan(sizes) do
    :telemetry.execute(
      [:ipse, :extension, :collection, :import_planned],
      %{files: length(sizes), logical_bytes: Enum.sum(sizes)},
      %{}
    )

    :ok
  end

  defp planned_generation(state, records) do
    pages = div(map_size(records) + 31, 32)
    known = Migration.known_operations(state)

    ids =
      0..Profile.limit(:operations)
      |> Enum.map(fn n ->
        n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")
      end)
      |> Enum.reject(&Map.has_key?(known, &1))
      |> Enum.take(pages)

    true = length(ids) == pages

    future =
      Enum.reduce(ids, state, fn id, state ->
        generation = state["generation"] + 1

        receipt = %{
          "generation" => generation,
          "floor" => state["floor"],
          "request_sha256" => String.duplicate("f", 64),
          "migration_id" => state["migration"]["id"]
        }

        %{
          state
          | "generation" => generation,
            "operations" => Map.put(state["operations"], id, receipt)
        }
      end)

    records =
      Map.new(records, fn {key, record} ->
        {key,
         Map.merge(record, %{
           "revision" => future["generation"],
           "operation_id" => List.last(ids) || state["migration"]["id"]
         })}
      end)

    future
    |> put_in(["migration", "records"], records)
    |> put_in(["migration", "after"], records |> Map.keys() |> Enum.sort() |> List.last())
  end

  defp planned_object_sizes(path, uid, records) do
    records
    |> Map.values()
    |> Enum.uniq_by(& &1["sha256"])
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, sizes} ->
      file = Path.join([path, "objects", record["sha256"] <> ".json"])

      case File.lstat(file) do
        {:error, :enoent} ->
          {:cont, {:ok, [record["bytes"] | sizes]}}

        {:ok, _} ->
          with {:ok, bytes} <- bounded_file(file, uid, Profile.limit(:value_bytes)),
               true <-
                 byte_size(bytes) == record["bytes"] and JSON.sha256(bytes) == record["sha256"] do
            {:cont, {:ok, sizes}}
          else
            _ -> {:halt, @error}
          end

        _ ->
          {:halt, @error}
      end
    end)
  end

  defp scan(path, uid, s, r, visible?) do
    if r["generation"] == s["generation"] do
      keys =
        s["records"]
        |> Map.keys()
        |> Enum.sort()
        |> Enum.reject(&(visible? and managed_key?(&1)))
        |> Enum.filter(&(is_nil(r["after"]) or &1 > r["after"]))

      selected = Enum.take(keys, r["limit"])

      with {:ok, records} <- read_records(path, uid, s, selected) do
        {:ok,
         Map.merge(summary(s), %{
           "records" => records,
           "next" => if(length(keys) > length(selected), do: List.last(selected))
         })}
      end
    else
      {:conflict, summary(s)}
    end
  end

  defp data_bytes(s), do: Enum.sum(Enum.map(s["records"], fn {_, r} -> r["bytes"] end))
  defp revision(s, key), do: if(s["records"][key], do: s["records"][key]["revision"], else: 0)
  defp capacity(s), do: {:failed, Map.put(summary(s), "code", "collection_capacity")}
  defp keys?(m, fields), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(fields)
  defp uint?(x), do: JSON.safe_uint?(x)
  defp id?(x), do: is_binary(x) and Regex.match?(~r/\A[a-f0-9]{32}\z/, x)
  defp key?(x), do: is_binary(x) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,95}\z/, x)
  defp pending?(name), do: Regex.match?(~r/\A\.pending-[a-f0-9]{32}\z/, name)
  defp artifact_name?(name), do: pending?(name) or Regex.match?(~r/\A[a-f0-9]{64}\.json\z/, name)
end
