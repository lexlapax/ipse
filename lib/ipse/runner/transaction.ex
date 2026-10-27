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
  @pending ~r/\A\.pending-[0-9a-f]{32}\z/
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
  @doc "Release exactly the top capability; root release proves native cleanup."
  def release(cap), do: operation(cap, :release)

  def switch(cap, pending, target) do
    if pending?(pending) and target in ~w(index.json control.json root.json),
      do: operation(cap, {:switch, pending, target}),
      else: {:error, :invalid_transaction_request}
  end

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
    if selector(directory) != nil and is_binary(name) and
         (name in ~w(index.json control.json root.json) or immutable?(name)) and
         is_integer(maximum) and maximum in 1..@bytes,
       do: operation(cap, {:read, selector(directory), name, maximum}),
       else: {:error, :invalid_transaction_request}
  end

  def allocation(cap, mode \\ :collection)

  def allocation(cap, mode) when mode in [:flat, :collection],
    do: operation(cap, {:allocation, mode})

  def allocation(_, _), do: {:error, :invalid_transaction_request}

  @doc "Set or narrow this lock's native staging budget; unsupported filesystems refuse."
  def quota(cap, mode, ceiling)
      when mode in [:flat, :collection] and is_integer(ceiling) and ceiling in 1..67_108_864,
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

    defp operate({:read, directory, name, maximum}, s) do
      case read_chunks(s, directory, name, maximum, 0, nil, []) do
        {:ok, bytes, s} -> {:reply, {:ok, bytes}, s}
        {:error, code, s} -> {:reply, {:error, code}, s}
        _ -> fail(s)
      end
    end

    defp operate(op, s) do
      {tag, payload} =
        case op do
          :check ->
            {?P, <<>>}

          {:allocation, mode} ->
            {?M, if(mode == :flat, do: <<0>>, else: <<1>>)}

          {:quota, mode, ceiling} ->
            {?B, <<if(mode == :flat, do: 0, else: 1), ceiling::64>>}

          {:preflight, sizes} ->
            {?F, IO.iodata_to_binary([<<length(sizes)::16>> | Enum.map(sizes, &<<&1::32>>)])}

          {:switch, stage, target} ->
            {?S, stage <> target}

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

    defp read_chunks(s, directory, name, maximum, offset, identity, chunks) do
      payload = <<directory, byte_size(name), name::binary, offset::32, maximum::32>>

      case command(s, ?G, payload, length(s.caps)) do
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
              read_chunks(s, directory, name, maximum, next, actual, chunks)
            end
          else
            :unknown
          end

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

    defp command(s, tag, payload, expected_depth) do
      seq = s.seq + 1
      body = <<seq::64, length(s.caps), payload::binary>>
      frame = <<tag, byte_size(body)::32, body::binary>>
      s = %{s | seq: seq}

      if owners_alive?(s) and now() < s.deadline and Ipse.Runner.send_stdio(s.port, frame) == :ok do
        case await_reply(s, min(s.deadline, now() + 5_000)) do
          {:ok, kind, <<^seq::64, depth, rest::binary>>, s} ->
            cond do
              kind == tag and depth == expected_depth ->
                {:ok, s, rest}

              kind == ?E and depth == length(s.caps) and byte_size(rest) == 1 ->
                <<code>> = rest
                if code in 1..7, do: {:error, reason(code), s}, else: {:unknown, s}

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

    defp await_reply(%{replies: [{kind, bytes} | tail]} = s, _) do
      if owners_alive?(s), do: {:ok, kind, bytes, %{s | replies: tail}}, else: :unknown
    end

    defp await_reply(s, deadline) do
      case receive_data(s, deadline) do
        {:ok, s} -> await_reply(s, deadline)
        _ -> :unknown
      end
    end

    defp await_finished(%{finished: true} = s, _), do: {:ok, s}

    defp await_finished(s, deadline) do
      case receive_data(s, deadline) do
        {:ok, s} -> await_finished(s, deadline)
        _ -> :unknown
      end
    end

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
      cond do
        tag not in [?A, ?P, ?R, ?S, ?E, ?U, ?Q, ?N, ?W, ?D, ?M, ?B, ?F, ?G] or
            size > if(tag == ?G, do: 16_417, else: 64) ->
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
