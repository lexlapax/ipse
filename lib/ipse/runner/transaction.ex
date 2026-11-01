defmodule Ipse.Runner.Transaction do
  @moduledoc """
  Internal owner-bound protected file transactions, with at most three locks.

  The same native process holds every logical lock and performs staging,
  immutable installation, reclamation and the final durable file switch. Policy,
  CAS, content hashes and orphan selection remain with the trusted host. A
  supported API call from a different worker is refused; JSON cannot reconstruct
  a capability. Controllers and callers are trusted core BEAM code. Do not expose
  capability/Port terms to untrusted code in the same VM: ordinary BEAM messages
  do not authenticate an adversarial raw-message sender.
  Call inside `Resources.file_effect/1`; nested effects execute inline. Lock
  order is ProjectIdentity, Consent, then Collection. Domain entry guards must
  reject reverse acquisition before starting an effect worker.
  The controller monitors both the capability caller and the original file-effect
  owner, and registers in that owner's propagated resource scope. Losing either
  owner or cancelling the scope stops the native transaction even while the
  effect callback is paused. Legacy file-effect workers still finish their own
  pending IO; their survival cannot retain or reuse this transaction.

  `check/1` detects observed lease loss; it does not fence arbitrary Elixir IO.
  Return read data only after a successful final check and release. After an
  unknown effect, inspect durable state in a new explicitly initiated transaction;
  never retry the effect automatically. This is a trusted same-user host boundary,
  not containment of arbitrary code able to mutate protected operator state.
  """
  alias __MODULE__.Controller
  @key {__MODULE__, :controller}
  @acceptance_key {__MODULE__, :acceptance_journal}
  @lifecycle_key {__MODULE__, :lifecycle_journal}
  @pending ~r/\A\.pending-[0-9a-f]{32}\z/
  @state_pending ~r/\A\.state-pending-[0-9a-f]{32}\z/
  @immutable ~r/\A[0-9a-f]{64}\.json\z/
  @bytes 8 * 1024 * 1024

  defmodule Capability do
    @moduledoc false
    @enforce_keys [:owner, :controller, :port, :depth, :generation]
    defstruct @enforce_keys

    defimpl Inspect do
      def inspect(_, _), do: "#Transaction.Capability<private>"
    end
  end

  @doc "Acquire one protected .lock; a nested acquire shares the native owner."
  def acquire(path, opts \\ []) do
    with true <- valid_path?(path) and Keyword.keyword?(opts),
         true <- Keyword.keys(opts) -- [:cwd, :timeout_ms] == [],
         true <- length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))),
         timeout = Keyword.get(opts, :timeout_ms, 120_000),
         true <- is_integer(timeout) and timeout in 1..120_000 do
      case Process.get(@key) do
        nil -> start(path, Keyword.get(opts, :cwd, Path.dirname(path)), timeout)
        controller -> call(controller, {:acquire, path})
      end
    else
      _ -> {:error, :invalid_transaction_request}
    end
  rescue
    _ -> {:error, :invalid_transaction_request}
  end

  @doc "Observe retained lock and directory identities; no arbitrary-IO fencing."
  def check(cap), do: operation(cap, :check)

  @doc false
  def acceptance_guard(cap), do: operation(cap, :acceptance_guard)

  @doc false
  def acceptance_guard(cap, event, intent) do
    with {owner, ^cap, event_sha, intent_sha} <- Process.get(@acceptance_key),
         true <- owner == self(),
         true <- event_sha === Ipse.JSON.digest([event]),
         true <- intent_sha === Ipse.JSON.digest([intent]),
         do: acceptance_guard(cap),
         else: (_ -> {:error, :invalid_transaction_capability})
  rescue
    _ -> {:error, :invalid_transaction_capability}
  end

  @doc false
  # This only checks a live owner and the exact last synced intent. It is not a
  # one-use permit or a final-switch fence; the effect owner must supply both.
  def lifecycle_guard(cap, intent) do
    with {owner, ^cap, digest} <- Process.get(@lifecycle_key),
         true <- owner == self() and digest === Ipse.JSON.digest([intent]),
         facts = intent["facts"],
         command = Ipse.Extension.Collection.ManagedRetention.command(facts["policy"]),
         true <-
           Ipse.Session.ManagedLifecycle.retention_review?(
             command,
             facts,
             System.system_time(:millisecond)
           ),
         do: check(cap),
         else: (_ -> {:error, :invalid_transaction_capability})
  rescue
    _ -> {:error, :invalid_transaction_capability}
  end

  @doc "Check an exact same-owner retained stack member without granting operations below the top capability."
  def check_retained(cap), do: operation(cap, :check_retained)

  # Private candidate only. An identity response describes the lock already
  # held by the native owner; it is not an output or publication admission.
  @doc false
  def retained_share_identity(cap), do: operation(cap, :retained_share_identity)

  # Only trusted same-owner code already inside all three ordered callbacks can
  # obtain these opaque capabilities; this does not attest their domain roles.
  @doc false
  def retained_share_stack do
    case Process.get(@key) do
      controller when is_pid(controller) -> call(controller, :retained_share_stack)
      _ -> {:error, :invalid_transaction_capability}
    end
  end

  @doc false
  def retained_share_export(cap, operation_id, recipient, deadline)
      when is_binary(operation_id) and byte_size(operation_id) == 16 and
             operation_id != <<0::128>> and is_binary(recipient) and
             byte_size(recipient) == 68 and is_integer(deadline),
      do: operation(cap, {:retained_share_export, operation_id, recipient, deadline})

  def retained_share_export(_, _, _, _), do: {:error, :invalid_transaction_request}

  @doc false
  def retained_share_settle(cap, operation_id, deadline)
      when is_binary(operation_id) and byte_size(operation_id) == 16 and
             operation_id != <<0::128>> and is_integer(deadline),
      do: operation(cap, {:retained_share_settle, operation_id, deadline})

  def retained_share_settle(_, _, _), do: {:error, :invalid_transaction_request}

  @doc false
  def with_source_lease(cap, token, fun),
    do: with_shared_source(cap, token, fun, Ipse.Session.StoredSources, :source)

  @doc false
  def with_source_leases(cap, tokens, fun) when is_list(tokens) and is_function(fun, 0) do
    with true <- length(tokens) in 1..128,
         true <- Enum.all?(tokens, &is_reference/1),
         true <- length(Enum.uniq(tokens)) == length(tokens),
         true <-
           Enum.all?(tokens, &match?({:ok, _}, Ipse.Session.StoredSources.share_identity(&1))) do
      retain_sources(cap, tokens, fun)
    else
      _ -> {:error, :invalid_transaction_request}
    end
  end

  def with_source_leases(_, _, _), do: {:error, :invalid_transaction_request}

  defp retain_sources(_, [], fun), do: fun.()

  defp retain_sources(cap, [token | rest], fun),
    do: with_source_lease(cap, token, fn -> retain_sources(cap, rest, fun) end)

  @doc false
  def with_inactive_acceptance_journal_lease(cap, token, fun),
    do: with_shared_source(cap, token, fun, Ipse.Session.PendingAcceptance, :journal)

  defp with_shared_source(
         %Capability{owner: owner, controller: controller, depth: 3} = cap,
         token,
         fun,
         module,
         kind
       )
       when owner == self() and is_reference(token) and is_function(fun, 0) do
    {identity_fun, export_fun, settle_fun} =
      if kind == :source,
        do: {:share_identity, :share_export, :share_settle},
        else: {:journal_share_identity, :journal_share_export, :journal_share_settle}

    with true <- Process.get(@key) == controller,
         {:ok, identity} <- apply(module, identity_fun, [token]),
         {:ok, %{pid: pid}} when is_integer(pid) and pid > 0 <- retained_share_identity(cap) do
      operation = :crypto.strong_rand_bytes(16)
      name = :crypto.strong_rand_bytes(16)
      secret = :crypto.strong_rand_bytes(32)

      entry =
        <<identity.pid::32, name::binary, secret::binary, identity.device::64,
          identity.inode::64>>

      recipient =
        <<pid::32, name::binary, secret::binary, identity.device::64, identity.inode::64>>

      deadline = System.monotonic_time(:millisecond) + 5_000

      request =
        :gen_server.send_request(controller, {:source_import, cap, operation, entry, deadline})

      with :ok <- apply(module, export_fun, [token, operation, recipient, deadline]),
           {:reply, :ok} <-
             :gen_server.receive_response(
               request,
               max(deadline - System.monotonic_time(:millisecond), 0)
             ) do
        result =
          try do
            fun.()
          rescue
            _ -> {:unknown, :transaction_source_unconfirmed}
          catch
            _, _ -> {:unknown, :transaction_source_unconfirmed}
          end

        deadline = System.monotonic_time(:millisecond) + 5_000
        closing = :gen_server.send_request(controller, {:source_close, cap, operation, deadline})

        with :ok <- apply(module, settle_fun, [token, operation, deadline]),
             {:reply, :ok} <-
               :gen_server.receive_response(
                 closing,
                 max(deadline - System.monotonic_time(:millisecond), 0)
               ) do
          result
        else
          _ -> abort_source(controller)
        end
      else
        _ -> abort_source(controller)
      end
    else
      _ -> {:error, :invalid_transaction_capability}
    end
  rescue
    _ -> abort_source(controller)
  catch
    :exit, _ -> abort_source(controller)
  end

  defp with_shared_source(_, _, _, _, _), do: {:error, :invalid_transaction_request}

  @doc false
  def with_journal_lease(cap, owned, fun), do: with_journal_lease(cap, owned, :any, fun)

  @doc false
  def with_acceptance_journal_lease(cap, owned, event, intent, fun) when is_function(fun, 0) do
    with %Capability{owner: owner, depth: 3} <- cap,
         true <- owner == self() and is_nil(Process.get(@acceptance_key)),
         true <- Ipse.Session.PendingAcceptance.valid_event?(event),
         true <- is_map(owned) and event["facts"]["journal_id"] === owned[:id],
         {:ok, ^intent} <- Ipse.Session.PendingAcceptance.effect_intent(event, intent["request"]) do
      hashes = [Ipse.JSON.digest([event]), Ipse.JSON.digest([intent])]
      [event_sha, intent_sha] = hashes

      with_journal_lease(cap, owned, hashes, fn ->
        Process.put(@acceptance_key, {self(), cap, event_sha, intent_sha})

        try do
          fun.()
        after
          Process.delete(@acceptance_key)
        end
      end)
    else
      _ -> {:error, :invalid_transaction_request}
    end
  rescue
    _ -> {:error, :invalid_transaction_request}
  end

  def with_acceptance_journal_lease(_, _, _, _, _), do: {:error, :invalid_transaction_request}

  @doc false
  def with_lifecycle_journal_lease(cap, owned, intent, fun) when is_function(fun, 0) do
    facts = intent["facts"]
    command = Ipse.Extension.Collection.ManagedRetention.command(facts["policy"])

    with %Capability{owner: owner, depth: 3} <- cap,
         true <- owner == self() and is_nil(Process.get(@lifecycle_key)),
         true <- is_map(owned) and get_in(facts, ["context", "session_id"]) === owned[:id],
         true <- Enum.sort(Map.keys(intent)) === ~w(facts operation_id type version),
         true <- intent["type"] === "managed_lifecycle_intent" and intent["version"] === 1,
         true <- intent["operation_id"] === facts["operation_id"],
         true <-
           Ipse.Session.ManagedLifecycle.retention_review?(
             command,
             facts,
             System.system_time(:millisecond)
           ),
         digest = Ipse.JSON.digest([intent]) do
      with_journal_lease(cap, owned, {:lifecycle, digest}, fn ->
        Process.put(@lifecycle_key, {self(), cap, digest})

        try do
          fun.()
        after
          Process.delete(@lifecycle_key)
        end
      end)
    else
      _ -> {:error, :invalid_transaction_request}
    end
  rescue
    _ -> {:error, :invalid_transaction_request}
  end

  def with_lifecycle_journal_lease(_, _, _, _), do: {:error, :invalid_transaction_request}

  defp with_journal_lease(
         %Capability{owner: owner, controller: controller, depth: 3} = cap,
         owned,
         expected,
         fun
       )
       when owner == self() and is_map(owned) and is_function(fun, 0) do
    alias Ipse.Journal.Writer
    alias Ipse.Session.Lock

    operation = :crypto.strong_rand_bytes(16)
    deadline = System.monotonic_time(:millisecond) + 5_000
    job = make_ref()
    generation = make_ref()

    with true <- Process.get(@key) == controller and owned[:journal_owner] == self(),
         {:ok, %{pid: pid}} <- retained_share_identity(cap),
         {:reply, {:ok, token, snapshot}} <-
           response(
             Writer.request_share_barrier(owned.writer, operation, job, generation),
             deadline
           ),
         true <-
           snapshot.session_id == owned.id and snapshot.job_ref == job and
             snapshot.owner_generation == generation and
             journal_expected?(snapshot, expected),
         {:reply, {:ok, control}} <-
           response(
             Writer.request_share_control_open(owned.writer, token, operation, deadline),
             deadline
           ),
         :ok <-
           import_writer_control(
             controller,
             cap,
             owned.writer,
             token,
             operation,
             pid,
             control,
             deadline
           ),
         {:reply, {:ok, transport}} <-
           response(Lock.request_share_arm(owned.guard, owned.writer, token, operation), deadline),
         {:reply, {:ok, identity}} <-
           response(
             Lock.request_share_identity(owned.guard, token, operation, deadline),
             deadline
           ) do
      name = :crypto.strong_rand_bytes(16)
      secret = :crypto.strong_rand_bytes(32)

      entry =
        <<identity.pid::32, name::binary, secret::binary, identity.device::64,
          identity.inode::64>>

      recipient =
        <<pid::32, name::binary, secret::binary, identity.device::64, identity.inode::64>>

      request =
        :gen_server.send_request(controller, {:source_import, cap, transport, entry, deadline})

      with {:reply, :ok} <-
             response(
               Lock.request_share_export(owned.guard, token, operation, recipient, deadline),
               deadline
             ),
           {:reply, :ok} <- response(request, deadline) do
        result =
          try do
            fun.()
          rescue
            _ -> {:unknown, :transaction_journal_unconfirmed}
          catch
            _, _ -> {:unknown, :transaction_journal_unconfirmed}
          end

        deadline = System.monotonic_time(:millisecond) + 5_000
        closing = :gen_server.send_request(controller, {:source_close, cap, transport, deadline})

        with {:reply, :ok} <-
               response(
                 Lock.request_share_settle(owned.guard, token, operation, deadline),
                 deadline
               ),
             {:reply, :ok} <- response(closing, deadline),
             {:reply, :ok} <-
               response(
                 Writer.request_share_control_prepare_close(owned.writer, token, operation),
                 deadline
               ),
             :ok <- call(controller, {:writer_control_close, cap, deadline}),
             {:reply, :ok} <-
               response(
                 Writer.request_share_control_close(owned.writer, token, operation),
                 deadline
               ),
             :ok <- Writer.thaw_share_barrier(owned.writer, token, operation) do
          result
        else
          _ -> abort_source(controller)
        end
      else
        _ -> abort_source(controller)
      end
    else
      _ -> abort_source(controller)
    end
  rescue
    _ -> abort_source(controller)
  catch
    :exit, _ -> abort_source(controller)
  end

  defp with_journal_lease(_, _, _, _), do: {:error, :invalid_transaction_request}

  defp journal_expected?(_, :any), do: true

  defp journal_expected?(snapshot, {:lifecycle, digest}),
    do: snapshot.recent_lifecycle_intent === digest

  defp journal_expected?(snapshot, expected), do: snapshot.recent_acceptance === expected

  defp import_writer_control(controller, cap, writer, token, operation, pid, identity, deadline) do
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    entry =
      <<identity.pid::32, name::binary, secret::binary, identity.device::64, identity.inode::64>>

    request =
      :gen_server.send_request(
        controller,
        {:writer_control_import, cap, operation, entry, deadline}
      )

    with {:reply, :ok} <-
           response(
             Ipse.Journal.Writer.request_share_control_transfer(
               writer,
               token,
               operation,
               pid,
               name,
               secret,
               deadline
             ),
             deadline
           ),
         {:reply, :ok} <- response(request, deadline),
         do: :ok,
         else: (_ -> {:error, :writer_control_unconfirmed})
  end

  defp response(request, deadline),
    do:
      :gen_server.receive_response(
        request,
        max(deadline - System.monotonic_time(:millisecond), 0)
      )

  defp abort_source(controller) do
    call(controller, :abort)
    Process.delete(@key)
    {:unknown, :transaction_source_unconfirmed}
  end

  @doc false
  def abort_owned(%Capability{owner: owner, controller: controller}) when owner == self() do
    if Process.get(@key) == controller,
      do: abort_source(controller),
      else: {:error, :invalid_transaction_capability}
  end

  def abort_owned(_), do: {:error, :invalid_transaction_capability}

  @doc "Release exactly the top capability; root release proves native cleanup."
  def release(cap), do: operation(cap, :release)

  @doc false
  def state_begin(cap, mutating) when is_boolean(mutating),
    do: operation(cap, {:state_begin, mutating})

  @doc false
  def state_stage(cap, name, bytes)
      when is_binary(name) and is_binary(bytes) and byte_size(bytes) in 1..1_048_576 do
    if Regex.match?(@state_pending, name),
      do: operation(cap, {:stage, 0, [{name, bytes}]}),
      else: {:error, :invalid_transaction_request}
  end

  def state_stage(_, _, _), do: {:error, :invalid_transaction_request}

  @doc false
  def state_read(cap), do: operation(cap, {:read_optional, 0, "state.json", 1_048_576})

  @doc false
  def state_commit(cap, deadline) when is_nil(deadline) or deadline in 0..9_007_199_254_740_991,
    do: operation(cap, {:state_commit, deadline})

  def state_commit(_, _), do: {:error, :invalid_transaction_request}

  @doc false
  def state_decision_reply(deadline, <<committed, checked_at::64>>)
      when committed in 0..1 and checked_at <= 9_007_199_254_740_991 and
             (is_nil(deadline) or
                (is_integer(deadline) and deadline in 0..9_007_199_254_740_991)) do
    cond do
      committed == 1 and is_nil(deadline) -> :ok
      committed == 1 and is_integer(deadline) and checked_at < deadline -> :ok
      committed == 0 and is_integer(deadline) and checked_at >= deadline -> {:elapsed, checked_at}
      true -> {:unknown, :transaction_protocol}
    end
  end

  def state_decision_reply(_, _), do: {:unknown, :transaction_protocol}

  def switch(cap, pending, target) do
    if pending?(pending) and target in ~w(index.json control.json root.json),
      do: operation(cap, {:switch, pending, target}),
      else: {:error, :invalid_transaction_request}
  end

  @doc "Check a wall deadline before rename; scheduling between that check and the syscall can still permit a late rename. Strict-deadline host publication must refuse."
  def switch_before(cap, pending, "root.json", deadline)
      when is_integer(deadline) and deadline in 1..9_007_199_254_740_991 do
    if pending?(pending),
      do: operation(cap, {:switch_before, pending, deadline}),
      else: {:error, :invalid_transaction_request}
  end

  def switch_before(_, _, _, _), do: {:error, :invalid_transaction_request}

  def reclaim(cap, directory, names) do
    if selector(directory) != nil and is_list(names) and length(names) in 1..64 and
         Enum.all?(names, &(pending?(&1) or immutable?(&1))) and
         length(Enum.uniq(names)) == length(names),
       do: operation(cap, {:reclaim, selector(directory), names}),
       else: {:error, :invalid_transaction_request}
  end

  def install(cap, directory, pending, target) do
    if selector(directory) != nil and pending?(pending) and immutable?(target),
      do: operation(cap, {:install, selector(directory), pending, target}),
      else: {:error, :invalid_transaction_request}
  end

  def stage(cap, directory, entries) do
    if selector(directory) != nil and is_list(entries) and length(entries) in 1..128 and
         Enum.all?(entries, fn
           {name, bytes} -> pending?(name) and is_binary(bytes) and byte_size(bytes) in 1..@bytes
           _ -> false
         end) and length(Enum.uniq_by(entries, &elem(&1, 0))) == length(entries) and
         Enum.reduce(entries, 0, fn {_, bytes}, n -> n + byte_size(bytes) end) <= @bytes,
       do: operation(cap, {:stage, selector(directory), entries}),
       else: {:error, :invalid_transaction_request}
  end

  @doc "Read bounded protected bytes through the retained native owner; no host data-file FD survives its lock."
  def read(cap, directory, name, maximum) do
    read_operation(cap, directory, name, maximum, :read)
  end

  @doc "Read protected bytes or return :absent only for a validated native missing basename; final check/release remain required."
  def read_optional(cap, directory, name, maximum) do
    read_operation(cap, directory, name, maximum, :read_optional)
  end

  defp read_operation(cap, directory, name, maximum, kind) do
    if selector(directory) != nil and is_binary(name) and
         (name in ~w(index.json control.json root.json) or immutable?(name)) and
         is_integer(maximum) and maximum in 1..@bytes,
       do: operation(cap, {kind, selector(directory), name, maximum}),
       else: {:error, :invalid_transaction_request}
  end

  @doc "Sync retained staging files and measure under this owner's writer leases; a failed sync refuses."
  def allocation(cap, mode \\ :collection)

  def allocation(cap, mode) when mode in [:flat, :collection],
    do: operation(cap, {:allocation, mode})

  def allocation(_, _), do: {:error, :invalid_transaction_request}

  @doc "Set or narrow this lock's native staging budget; unsupported filesystems refuse."
  def quota(cap, mode, ceiling)
      when mode in [:flat, :collection] and is_integer(ceiling) and ceiling in 1..201_326_592,
      do: operation(cap, {:quota, mode, ceiling})

  def quota(_, _, _), do: {:error, :invalid_transaction_request}

  @doc "Check a bounded complete file plan before any staged payload is admitted."
  def preflight(cap, sizes) do
    if is_list(sizes) and length(sizes) <= 256 and
         Enum.all?(sizes, &(is_integer(&1) and &1 in 1..@bytes)) and
         Enum.sum(sizes) <= 67_108_864 do
      operation(cap, {:preflight, sizes})
    else
      {:error, :invalid_transaction_request}
    end
  end

  defp operation(
         %Capability{
           owner: owner,
           controller: controller,
           port: port,
           depth: depth,
           generation: generation
         } = cap,
         op
       )
       when owner == self() and is_pid(controller) and is_port(port) and depth in 1..3 and
              is_reference(generation) do
    if Process.get(@key) == controller,
      do: call(controller, {:operation, cap, op}),
      else: {:error, :invalid_transaction_capability}
  end

  defp operation(_, _), do: {:error, :invalid_transaction_capability}

  defp start(path, cwd, timeout) do
    with true <- valid_path?(cwd),
         {:ok, helper} <- Ipse.Runner.protected_helper(cwd),
         {:ok, controller} <-
           GenServer.start(
             Controller,
             {self(), Ipse.Session.Resources.file_effect_owner(),
              Ipse.Session.Resources.current(), helper, cwd, timeout}
           ) do
      Process.put(@key, controller)

      case call(controller, {:acquire, path}) do
        {:ok, _} = ok ->
          ok

        error ->
          call(controller, :abort)
          Process.delete(@key)
          error
      end
    else
      _ -> {:error, :transaction_unavailable}
    end
  end

  defp call(controller, request) do
    result = GenServer.call(controller, request, 125_000)

    if match?({:unknown, _}, result) or request |> released_root?(result),
      do: Process.delete(@key)

    result
  catch
    :exit, _ ->
      Process.delete(@key)
      {:unknown, :transaction_unavailable}
  end

  defp released_root?({:operation, %Capability{depth: 1}, :release}, :ok), do: true
  defp released_root?(_, _), do: false

  defp valid_path?(p),
    do:
      is_binary(p) and byte_size(p) in 1..4096 and String.valid?(p) and
        Path.type(p) == :absolute and not String.contains?(p, <<0>>)

  defp pending?(s), do: is_binary(s) and Regex.match?(@pending, s)
  defp immutable?(s), do: is_binary(s) and Regex.match?(@immutable, s)
  defp selector("."), do: 0
  defp selector("objects"), do: 1
  defp selector("manifests"), do: 2
  defp selector(_), do: nil

  defmodule Controller do
    @moduledoc false
    use GenServer
    alias Ipse.Runner.Transaction.Capability
    @impl true
    def init({owner, upstream, scope, helper, cwd, timeout}) do
      Process.flag(:trap_exit, true)
      monitor = Process.monitor(owner)
      upstream_monitor = if upstream != owner, do: Process.monitor(upstream)

      with {:ok, ticket} <- Ipse.Session.Resources.register(:lock, scope) do
        case Ipse.Runner.open_protected_stdio(
               helper,
               ["--transaction-lock", Integer.to_string(timeout)],
               cwd,
               %{},
               timeout + 1_000,
               cleanup_ticket: ticket
             ) do
          {:ok, port} ->
            {:ok,
             %{
               owner: owner,
               monitor: monitor,
               upstream: upstream,
               upstream_monitor: upstream_monitor,
               ticket: ticket,
               port: port,
               caps: [],
               seq: 0,
               outer: <<>>,
               inner: <<>>,
               replies: [],
               finished: false,
               deadline: now() + timeout,
               retained_share: nil,
               source_operations: [],
               writer_control: false,
               session_control: false,
               cleanup: nil
             }}

          error ->
            cleanup =
              if match?({:error, {:cleanup_unconfirmed, _}}, error),
                do: {:error, :cleanup_unconfirmed},
                else: :ok

            Ipse.Session.Resources.closed(ticket, cleanup)
            {:stop, :transaction_unavailable}
        end
      else
        _ -> {:stop, :transaction_unavailable}
      end
    end

    @impl true
    def handle_call(
          {:writer_control_import, cap, operation, entry, deadline},
          {owner, _},
          %{
            owner: owner,
            caps: [cap | _],
            source_operations: [],
            writer_control: false,
            retained_share: nil
          } = s
        ) do
      if cap.depth == 3 and deadline > now() and deadline <= now() + 5_000 do
        case command(s, ?O, operation <> entry, length(s.caps), deadline) do
          {:ok, s, <<>>} -> {:reply, :ok, %{s | writer_control: true}}
          _ -> fail(s)
        end
      else
        {:reply, {:error, :invalid_transaction_capability}, s}
      end
    end

    def handle_call(
          {:writer_control_close, cap, deadline},
          {owner, _},
          %{
            owner: owner,
            caps: [cap | _],
            source_operations: [],
            writer_control: true,
            session_control: false
          } = s
        ) do
      if deadline > now() and deadline <= now() + 5_000 do
        case command(s, ?o, <<>>, length(s.caps), deadline) do
          {:ok, s, <<>>} -> {:reply, :ok, %{s | writer_control: false}}
          _ -> fail(s)
        end
      else
        {:reply, {:error, :invalid_transaction_capability}, s}
      end
    end

    def handle_call(
          {:session_control_import, cap, operation, entry, deadline},
          {owner, _},
          %{
            owner: owner,
            caps: [cap | _],
            writer_control: true,
            session_control: false,
            retained_share: nil
          } = s
        ) do
      if cap.depth == 3 and deadline > now() and deadline <= now() + 5_000 do
        case command(s, ?c, operation <> entry, length(s.caps), deadline) do
          {:ok, s, <<>>} -> {:reply, :ok, %{s | session_control: true}}
          _ -> fail(s)
        end
      else
        {:reply, {:error, :invalid_transaction_capability}, s}
      end
    end

    def handle_call(
          {:session_control_close, cap, deadline},
          {owner, _},
          %{owner: owner, caps: [cap | _], source_operations: [], session_control: true} = s
        ) do
      if deadline > now() and deadline <= now() + 5_000 do
        case command(s, ?d, <<>>, length(s.caps), deadline) do
          {:ok, s, <<>>} -> {:reply, :ok, %{s | session_control: false}}
          _ -> fail(s)
        end
      else
        {:reply, {:error, :invalid_transaction_capability}, s}
      end
    end

    def handle_call(
          {:source_import, cap, operation, entry, deadline},
          {owner, _},
          %{owner: owner, caps: [cap | _], source_operations: operations, retained_share: nil} = s
        ) do
      if cap.depth == 3 and length(operations) < 129 and deadline > now() and
           deadline <= now() + 5_000 do
        case command(s, ?Z, operation <> entry, length(s.caps), deadline) do
          {:ok, s, <<>>} -> {:reply, :ok, %{s | source_operations: [operation | operations]}}
          _ -> fail(s)
        end
      else
        {:reply, {:error, :invalid_transaction_capability}, s}
      end
    end

    def handle_call(
          {:source_close, cap, operation, deadline},
          {owner, _},
          %{owner: owner, caps: [cap | _], source_operations: [operation | remaining]} = s
        )
        when not is_nil(operation) do
      if deadline > now() and deadline <= now() + 5_000 do
        case command(s, ?z, operation, length(s.caps), deadline) do
          {:ok, s, <<>>} -> {:reply, :ok, %{s | source_operations: remaining}}
          _ -> fail(s)
        end
      else
        {:reply, {:error, :invalid_transaction_capability}, s}
      end
    end

    def handle_call(
          :retained_share_stack,
          {owner, _},
          %{owner: owner, retained_share: nil, caps: [third, second, first]} = s
        ) do
      {:reply, {:ok, [first, second, third]}, s}
    end

    def handle_call(:retained_share_stack, _, s),
      do: {:reply, {:error, :invalid_transaction_capability}, s}

    def handle_call({:acquire, _path}, {owner, _}, %{owner: owner, retained_share: share} = s)
        when not is_nil(share),
        do: {:reply, {:error, :transaction_share_frozen}, s}

    def handle_call({:acquire, path}, {owner, _}, %{owner: owner} = s) do
      case command(s, ?A, path, length(s.caps) + 1) do
        {:ok, s, _} ->
          cap = %Capability{
            owner: owner,
            controller: self(),
            port: s.port,
            depth: length(s.caps) + 1,
            generation: make_ref()
          }

          {:reply, {:ok, cap}, %{s | caps: [cap | s.caps]}}

        {:error, code, s} ->
          {:reply, {:error, code}, s}

        {:unknown, s} ->
          fail(s)
      end
    end

    def handle_call(
          {:operation, cap, :retained_share_identity},
          {owner, _},
          %{owner: owner, retained_share: nil} = s
        ) do
      if cap in s.caps do
        index = cap.depth - 1

        case command(s, ?I, <<index>>, length(s.caps)) do
          {:ok, s, <<^index, pid::32, dev::64, ino::64>>} when pid > 0 ->
            {:reply, {:ok, %{slot: index, pid: pid, device: dev, inode: ino}}, s}

          _ ->
            fail(s)
        end
      else
        {:reply, {:error, :invalid_transaction_capability}, s}
      end
    end

    def handle_call(
          {:operation, cap, {:retained_share_export, operation, recipient, deadline}},
          {owner, _},
          %{owner: owner} = s
        ) do
      index = cap.depth - 1
      share = s.retained_share

      valid_share =
        is_nil(share) or
          (share.operation == operation and share.deadline == deadline and not share.closing and
             index not in share.slots)

      if cap in s.caps and valid_share and deadline > now() and deadline <= now() + 5_000 do
        case command(
               s,
               ?Y,
               <<index, operation::binary, recipient::binary>>,
               length(s.caps),
               deadline
             ) do
          {:ok, s, <<^index, ^operation::binary-size(16)>>} ->
            share =
              share || %{operation: operation, deadline: deadline, slots: [], closing: false}

            {:reply, :ok, %{s | retained_share: %{share | slots: share.slots ++ [index]}}}

          _ ->
            fail(s)
        end
      else
        {:reply, {:error, :invalid_transaction_capability}, s}
      end
    end

    def handle_call(
          {:operation, cap, {:retained_share_settle, operation, deadline}},
          {owner, _},
          %{owner: owner, retained_share: share} = s
        )
        when not is_nil(share) do
      index = cap.depth - 1

      if cap in s.caps and share.operation == operation and share.deadline == deadline and
           match?([^index | _], share.slots) and deadline > now() do
        case command(s, ?K, <<index, operation::binary>>, length(s.caps), deadline) do
          {:ok, s, <<^index, ^operation::binary-size(16)>>} ->
            remaining = tl(share.slots)
            next = if remaining == [], do: nil, else: %{share | slots: remaining, closing: true}
            {:reply, :ok, %{s | retained_share: next}}

          _ ->
            fail(s)
        end
      else
        {:reply, {:error, :invalid_transaction_capability}, s}
      end
    end

    def handle_call(
          {:operation, _cap, _op},
          {owner, _},
          %{owner: owner, retained_share: share} = s
        )
        when not is_nil(share),
        do: {:reply, {:error, :transaction_share_frozen}, s}

    def handle_call({:operation, cap, :check_retained}, {owner, _}, %{owner: owner} = s) do
      if cap in s.caps,
        do: operate(:check, s),
        else: {:reply, {:error, :invalid_transaction_capability}, s}
    end

    def handle_call({:operation, cap, op}, {owner, _}, %{owner: owner, caps: [cap | _]} = s) do
      operate(op, s)
    end

    def handle_call(:abort, {owner, _}, %{owner: owner} = s),
      do: {:stop, :normal, :ok, cleanup(s)}

    def handle_call(_, _, s), do: {:reply, {:error, :invalid_transaction_capability}, s}

    defp operate(:release, s) do
      case command(s, ?R, <<>>, length(s.caps) - 1) do
        {:ok, s, _} ->
          if length(s.caps) == 1 do
            case await_finished(s, min(s.deadline, now() + 2_000)) do
              {:ok, s} ->
                s = cleanup(s)

                result =
                  if s.cleanup == :ok, do: :ok, else: {:unknown, :transaction_cleanup_unconfirmed}

                {:stop, :normal, result, s}

              _ ->
                fail(s)
            end
          else
            {:reply, :ok, %{s | caps: tl(s.caps)}}
          end

        _ ->
          fail(s)
      end
    end

    defp operate({:stage, dir, entries}, s) do
      metadata =
        IO.iodata_to_binary([
          <<dir, length(entries)>>
          | Enum.map(entries, fn {name, bytes} ->
              [name, <<byte_size(bytes)::unsigned-big-32>>]
            end)
        ])

      case command(s, ?W, metadata, length(s.caps)) do
        {:ok, s, _} ->
          bytes = entries |> Enum.map(&elem(&1, 1)) |> IO.iodata_to_binary()

          case chunks(s, bytes) do
            {:ok, s} -> {:reply, :ok, s}
            _ -> fail(s)
          end

        {:error, code, s} ->
          {:reply, {:error, code}, s}

        _ ->
          fail(s)
      end
    end

    defp operate({kind, directory, name, maximum}, s) when kind in [:read, :read_optional] do
      case read_chunks(s, kind, directory, name, maximum, 0, nil, []) do
        {:ok, bytes, s} -> {:reply, {:ok, bytes}, s}
        {:absent, s} -> {:reply, :absent, s}
        {:error, code, s} -> {:reply, {:error, code}, s}
        _ -> fail(s)
      end
    end

    defp operate(op, s) do
      {tag, payload} =
        case op do
          :check ->
            {?P, <<>>}

          :acceptance_guard ->
            {?j, <<>>}

          {:state_begin, mutating} ->
            {?J, <<if(mutating, do: 1, else: 0)>>}

          {:state_commit, deadline} ->
            {?V, <<if(is_nil(deadline), do: 0, else: 1), deadline || 0::64>>}

          {:allocation, mode} ->
            {?M, if(mode == :flat, do: <<0>>, else: <<1>>)}

          {:quota, mode, ceiling} ->
            {?B, <<if(mode == :flat, do: 0, else: 1), ceiling::64>>}

          {:preflight, sizes} ->
            {?F, IO.iodata_to_binary([<<length(sizes)::16>> | Enum.map(sizes, &<<&1::32>>)])}

          {:switch, stage, target} ->
            {?S, stage <> target}

          {:switch_before, stage, deadline} ->
            {?T, <<deadline::64>> <> stage <> "root.json"}

          {:install, dir, stage, target} ->
            {?N, <<dir>> <> stage <> target}

          {:reclaim, dir, names} ->
            {?Q,
             IO.iodata_to_binary([
               <<dir, length(names)>> | Enum.map(names, &[<<byte_size(&1)>>, &1])
             ])}
        end

      case command(s, tag, payload, length(s.caps)) do
        {:ok, s, payload} ->
          result =
            case {op, payload} do
              {{:state_commit, deadline}, payload} ->
                Ipse.Runner.Transaction.state_decision_reply(deadline, payload)

              {{:allocation, _}, <<logical::64, allocated::64, entries::64>>} ->
                {:ok, %{logical: logical, allocated: allocated, entries: entries}}

              {{:allocation, _}, _} ->
                {:unknown, :transaction_protocol}

              {_, <<>>} ->
                :ok

              _ ->
                {:unknown, :transaction_protocol}
            end

          if match?({:unknown, _}, result), do: fail(s), else: {:reply, result, s}

        {:error, code, s} ->
          {:reply, {:error, code}, s}

        _ ->
          fail(s)
      end
    end

    defp read_chunks(s, kind, directory, name, maximum, offset, identity, chunks) do
      payload = <<directory, byte_size(name), name::binary, offset::32, maximum::32>>

      {tag, payload} =
        if kind == :read_optional, do: {?H, <<1, payload::binary>>}, else: {?G, payload}

      reply =
        case command(s, tag, payload, length(s.caps)) do
          {:ok, s, <<1, 1, bytes::binary>>} when kind == :read_optional -> {:ok, s, bytes}
          {:ok, s, <<1, 0>>} when kind == :read_optional -> {:absent, s}
          {:ok, _, _} when kind == :read_optional -> :unknown
          result -> result
        end

      case reply do
        {:ok, s, <<total::32, ^offset::32, device::64, inode::64, bytes::binary>>}
        when total <= maximum and offset <= total ->
          actual = {total, device, inode}

          if (identity == nil or identity == actual) and
               byte_size(bytes) == min(16_384, total - offset) do
            chunks = [bytes | chunks]
            next = offset + byte_size(bytes)

            if next == total do
              {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary(), s}
            else
              read_chunks(s, kind, directory, name, maximum, next, actual, chunks)
            end
          else
            :unknown
          end

        {:absent, s} when offset == 0 and identity == nil and chunks == [] ->
          {:absent, s}

        {:error, code, s} ->
          {:error, code, s}

        _ ->
          :unknown
      end
    end

    defp chunks(s, <<>>), do: {:ok, s}

    defp chunks(s, bytes) do
      size = min(byte_size(bytes), 16_384)
      <<chunk::binary-size(^size), tail::binary>> = bytes

      case command(s, ?D, chunk, length(s.caps)) do
        {:ok, s, <<>>} -> chunks(s, tail)
        _ -> :unknown
      end
    end

    defp command(s, tag, payload, expected_depth, limit \\ nil) do
      seq = s.seq + 1
      body = <<seq::64, length(s.caps), payload::binary>>
      frame = <<tag, byte_size(body)::32, body::binary>>
      s = %{s | seq: seq}

      deadline = min(s.deadline, limit || now() + 5_000)

      if idle_framing?(s) and owners_alive?(s) and now() < deadline and
           Ipse.Runner.send_stdio(s.port, frame) == :ok do
        case await_reply(s, deadline, {tag, seq, expected_depth}) do
          {:ok, kind, <<^seq::64, depth, rest::binary>>, s} ->
            cond do
              kind == tag and depth == expected_depth ->
                {:ok, s, rest}

              kind == ?E and depth == length(s.caps) and byte_size(rest) == 1 ->
                <<code>> = rest
                if code in 1..8, do: {:error, reason(code), s}, else: {:unknown, s}

              true ->
                {:unknown, s}
            end

          _ ->
            {:unknown, s}
        end
      else
        {:unknown, s}
      end
    end

    defp reason(1), do: :transaction_busy
    defp reason(2), do: :transaction_unsafe
    defp reason(3), do: :invalid_transaction_request
    defp reason(4), do: :transaction_io
    defp reason(5), do: :transaction_exists
    defp reason(6), do: :transaction_capacity
    defp reason(7), do: :transaction_filesystem_unsupported
    defp reason(8), do: :transaction_write_deadline_elapsed

    defp idle_framing?(s),
      do: s.inner == <<>> and s.outer == <<>> and s.replies == [] and not s.finished

    defp root_release_reply?(?R, <<seq::64, 0>>, {?R, seq, 0}), do: true
    defp root_release_reply?(_, _, _), do: false

    defp terminal_prefix?(<<?X, size::32, bytes::binary>>),
      do: size <= 128 and byte_size(bytes) < size

    defp terminal_prefix?(<<?X, _::binary>> = bytes), do: byte_size(bytes) < 5
    defp terminal_prefix?(_), do: false

    defp await_reply(%{replies: [{kind, bytes}]} = s, deadline, expected) do
      release? = root_release_reply?(kind, bytes, expected)

      cond do
        not owners_alive?(s) or now() >= deadline or s.inner != <<>> ->
          :unknown

        s.outer != <<>> ->
          if release? and not s.finished and terminal_prefix?(s.outer),
            do: receive_reply(s, deadline, expected),
            else: :unknown

        s.finished and not release? ->
          :unknown

        true ->
          {:ok, kind, bytes, %{s | replies: []}}
      end
    end

    defp await_reply(%{replies: [], finished: false} = s, deadline, expected),
      do: receive_reply(s, deadline, expected)

    defp await_reply(_, _, _), do: :unknown

    defp receive_reply(s, deadline, expected) do
      case receive_data(s, deadline) do
        {:ok, s} -> await_reply(s, deadline, expected)
        _ -> :unknown
      end
    end

    defp await_finished(%{finished: true, inner: <<>>, outer: <<>>, replies: []} = s, deadline),
      do: if(owners_alive?(s) and now() < deadline, do: {:ok, s}, else: :unknown)

    defp await_finished(%{finished: false, inner: <<>>, replies: []} = s, deadline) do
      if s.outer == <<>> or terminal_prefix?(s.outer) do
        case receive_data(s, deadline) do
          {:ok, s} -> await_finished(s, deadline)
          _ -> :unknown
        end
      else
        :unknown
      end
    end

    defp await_finished(_, _), do: :unknown

    defp receive_data(s, deadline) do
      port = s.port
      monitor = s.monitor
      upstream_monitor = s.upstream_monitor
      ticket = s.ticket

      receive do
        {^port, {:data, bytes}} -> outer(%{s | outer: s.outer <> bytes})
        {:DOWN, ^monitor, :process, _, _} -> :unknown
        {:DOWN, ^upstream_monitor, :process, _, _} -> :unknown
        {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id -> :unknown
        {^port, {:exit_status, _}} -> :unknown
        {:EXIT, ^port, _} -> :unknown
      after
        max(0, deadline - now()) -> :unknown
      end
    end

    defp outer(%{finished: true, outer: bytes}) when bytes != <<>>, do: :unknown
    defp outer(%{outer: bytes}) when byte_size(bytes) > 131_072, do: :unknown

    defp outer(%{outer: <<tag, size::32, bytes::binary>>} = s) do
      cond do
        size > 65_536 ->
          :unknown

        byte_size(bytes) < size ->
          {:ok, s}

        true ->
          <<payload::binary-size(^size), tail::binary>> = bytes
          s = %{s | outer: tail}

          case tag do
            ?O ->
              case inner(%{s | inner: s.inner <> payload}) do
                {:ok, s} -> outer(s)
                _ -> :unknown
              end

            ?X ->
              case Ipse.JSON.decode_bounded(payload, 128) do
                {:ok, %{"exit_code" => 0, "timed_out" => false} = x} when map_size(x) == 2 ->
                  outer(%{s | finished: true})

                _ ->
                  :unknown
              end

            _ ->
              :unknown
          end
      end
    end

    defp outer(s), do: {:ok, s}

    defp inner(%{inner: bytes}) when byte_size(bytes) > 32_768, do: :unknown

    defp inner(%{inner: <<tag, size::32, bytes::binary>>} = s) do
      maximum =
        case tag do
          ?G -> 16_417
          ?H -> 16_419
          _ -> 64
        end

      cond do
        tag not in [
          ?A,
          ?P,
          ?R,
          ?S,
          ?T,
          ?E,
          ?U,
          ?Q,
          ?N,
          ?W,
          ?D,
          ?M,
          ?B,
          ?F,
          ?G,
          ?H,
          ?J,
          ?V,
          ?I,
          ?Y,
          ?K,
          ?Z,
          ?z,
          ?O,
          ?o,
          ?c,
          ?d,
          ?j
        ] or
            size > maximum ->
          :unknown

        byte_size(bytes) < size ->
          {:ok, s}

        s.replies != [] ->
          :unknown

        true ->
          <<payload::binary-size(^size), tail::binary>> = bytes
          inner(%{s | inner: tail, replies: [{tag, payload}]})
      end
    end

    defp inner(s), do: {:ok, s}

    defp fail(s), do: {:stop, :normal, {:unknown, :transaction_lost}, cleanup(s)}
    defp cleanup(%{cleanup: result} = s) when result != nil, do: s

    defp cleanup(s) do
      result = Ipse.Runner.close_stdio(s.port, if(s.finished, do: :completed, else: :cancel))
      Ipse.Session.Resources.closed(s.ticket, result)
      %{s | cleanup: result, port: nil}
    end

    @impl true
    def handle_info(_, s), do: {:stop, :normal, cleanup(s)}
    @impl true
    def terminate(_, s), do: cleanup(s)
    @impl true
    def format_status(%{state: _} = status) do
      Map.new(status, fn
        {key, _} when key in [:state, :message, :reason] -> {key, :redacted}
        {:log, _} -> {:log, []}
        pair -> pair
      end)
    end

    defp now, do: System.monotonic_time(:millisecond)
    defp owners_alive?(s), do: Process.alive?(s.owner) and Process.alive?(s.upstream)
  end
end
