defmodule Ipse.Runner.Operator do
  @moduledoc false
  @input_limit 1_048_576
  @display_limit 16_777_216

  def input_limit, do: @input_limit
  def display_limit, do: @display_limit

  def probe(helper) do
    port =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :nouse_stdio,
        :hide,
        args: ["--operator-input", "1000", "v2-probe"]
      ])

    try do
      probe_reply(port, <<>>, System.monotonic_time(:millisecond) + 2_000)
    after
      if Port.info(port), do: Port.close(port)
    end
  rescue
    _ -> {:error, :operator_input_unavailable}
  end

  defp probe_reply(port, bytes, deadline) do
    receive do
      {^port, {:data, data}} when byte_size(bytes) + byte_size(data) <= 32 ->
        probe_reply(port, bytes <> data, deadline)

      {^port, {:exit_status, 0}} ->
        case bytes do
          <<?t, 8::32, "terminal">> -> {:ok, :native}
          <<?n, 11::32, "nonterminal">> -> {:ok, :pipe}
          _ -> {:error, :operator_input_unavailable}
        end

      {^port, _} ->
        {:error, :operator_input_unavailable}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        {:error, :operator_input_unavailable}
    end
  end

  def run(helper, display, timeout) do
    owner = self()
    scope = Ipse.Session.Resources.current()
    call = make_ref()

    {controller, monitor} =
      spawn_monitor(fn ->
        Process.flag(:trap_exit, true)
        Ipse.Session.Resources.bind(scope)
        owner_ref = Process.monitor(owner)
        result = control(helper, display, timeout, owner_ref)
        send(owner, {call, result})
      end)

    await(controller, monitor, call)
  end

  @doc false
  def run_guarded(helper, display, timeout, guard) when is_function(guard, 1) do
    case Ipse.Session.Resources.register(:lock) do
      {:ok, ticket} ->
        {result, cleanup} = port_guarded(helper, display, timeout, ticket, guard)
        Ipse.Session.Resources.closed(ticket, cleanup)
        result

      _ ->
        {:error, :operator_input_unavailable}
    end
  end

  def run_guarded(_, _, _, _), do: {:error, :operator_input_unavailable}

  # The lease owner owns the native Port itself. Its death closes the control
  # pipe without relying on a separate BEAM controller to handle a monitor.
  defp port_guarded(helper, display, timeout, ticket, guard) do
    owner = self()

    port =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :nouse_stdio,
        :hide,
        args: ["--operator-input", Integer.to_string(timeout), "v2"]
      ])

    nonce = :crypto.strong_rand_bytes(16)
    used = :atomics.new(1, [])
    key = {__MODULE__, make_ref()}
    overall = System.monotonic_time(:millisecond) + timeout + 2_000

    initial = %{
      nonce: nonce,
      phase: :initial,
      text: nil,
      error: nil,
      restored: false,
      exited: false,
      cancelled: false,
      cancel_sent: false,
      buffer: <<>>,
      request: <<>>,
      deadline: overall,
      cancel_deadline: nil,
      owner_ref: make_ref(),
      ticket: ticket,
      guarded: :direct,
      guarded_stop: true
    }

    Process.put(key, initial)

    send_display = fn wall ->
      cond do
        self() != owner ->
          :atomics.put(used, 1, 3)
          {:error, :operator_input_unavailable}

        :atomics.compare_exchange(used, 1, 0, 1) != :ok ->
          :atomics.put(used, 1, 3)
          {:error, :operator_input_unavailable}

        not Ipse.JSON.safe_uint?(wall) or System.system_time(:millisecond) >= wall ->
          {:error, :operator_input_unavailable}

        true ->
          remaining = max(wall - System.system_time(:millisecond), 0)
          body = <<nonce::binary, wall::unsigned-big-64, display::binary>>
          current = Process.get(key)

          next = %{
            current
            | request: <<?D, byte_size(body)::unsigned-big-32, body::binary>>,
              deadline: min(overall, System.monotonic_time(:millisecond) + remaining)
          }

          next = loop(port, next)
          Process.put(key, %{next | deadline: overall})

          if next.phase in [:displayed, :input, :eof] and not next.cancelled and
               is_nil(next.error) and System.system_time(:millisecond) < wall and
               :atomics.compare_exchange(used, 1, 1, 2) == :ok do
            :ok
          else
            {:error, :operator_input_unavailable}
          end
      end
    end

    try do
      guarded =
        try do
          guard.(send_display)
        rescue
          _ -> {:error, :operator_input_unavailable}
        catch
          _, _ -> {:error, :operator_input_unavailable}
        end

      accepted = guarded === :ok and :atomics.get(used, 1) == 2
      state = Process.delete(key)
      state = %{state | guarded_stop: false}

      # A cancellation queued while the guard unwound must win over release;
      # otherwise already-buffered terminal input could be consumed first.
      cancelled =
        receive do
          :ipse_cancel_operator_input -> true
          :cancel -> true
          {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id -> true
        after
          0 -> false
        end

      # The helper cannot begin terminal input until the guard has returned and
      # its source/policy leases have unwound in this same owner process.
      accepted = accepted and not cancelled and Port.command(port, <<?U, 0::32>>, [:nosuspend])

      state =
        if accepted do
          loop(port, state)
        else
          :atomics.put(used, 1, 3)
          loop(port, cancel(port, state))
        end

      {result, cleanup} = operator_result(state, display)
      if accepted, do: {result, cleanup}, else: {{:error, :operator_input_unavailable}, cleanup}
    after
      Process.delete(key)
      if Port.info(port), do: Port.close(port)
    end
  rescue
    _ -> {{:error, :operator_cleanup_unconfirmed}, {:error, :cleanup_unconfirmed}}
  catch
    _, _ -> {{:error, :operator_cleanup_unconfirmed}, {:error, :cleanup_unconfirmed}}
  end

  defp await(controller, monitor, call) do
    receive do
      {^call, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^controller, _} ->
        {:error, :operator_cleanup_unconfirmed}

      :ipse_cancel_operator_input ->
        send(controller, :cancel)
        await(controller, monitor, call)
    end
  end

  defp control(helper, display, timeout, owner_ref) do
    case Ipse.Session.Resources.register(:lock) do
      {:ok, ticket} ->
        {result, cleanup} = port_run(helper, display, timeout, owner_ref, ticket)
        Ipse.Session.Resources.closed(ticket, cleanup)
        result

      _ ->
        {:error, :operator_input_unavailable}
    end
  end

  defp port_run(helper, display, timeout, owner_ref, ticket) do
    port =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :nouse_stdio,
        :hide,
        args: ["--operator-input", Integer.to_string(timeout), "v2"]
      ])

    nonce = :crypto.strong_rand_bytes(16)
    body = nonce <> display

    state = %{
      nonce: nonce,
      phase: :initial,
      text: nil,
      error: nil,
      restored: false,
      exited: false,
      cancelled: false,
      cancel_sent: false,
      buffer: <<>>,
      request: <<?d, byte_size(body)::unsigned-big-32, body::binary>>,
      guarded: nil,
      deadline: System.monotonic_time(:millisecond) + timeout + 2_000,
      cancel_deadline: nil,
      owner_ref: owner_ref,
      ticket: ticket
    }

    try do
      state = loop(port, state)
      operator_result(state, display)
    after
      if Port.info(port), do: Port.close(port)
    end
  rescue
    _ -> {{:error, :operator_cleanup_unconfirmed}, {:error, :cleanup_unconfirmed}}
  end

  defp operator_result(state, display) do
    cleanup =
      if state.exited and state.buffer == <<>> and
           (state.restored or state.phase == :nonterminal),
         do: :ok,
         else: {:error, :cleanup_unconfirmed}

    result =
      cond do
        cleanup != :ok ->
          {:error, :operator_cleanup_unconfirmed}

        state.phase == :nonterminal ->
          {:error, :operator_nonterminal}

        state.error != nil ->
          {:error, state.error}

        state.cancelled ->
          {:error, :operator_input_cancelled}

        state.phase == :eof ->
          {:error, :operator_input_eof}

        state.phase == :input ->
          {:ok,
           %{
             "version" => 2,
             "event_id" => Base.encode16(state.nonce, case: :lower),
             "text" => state.text,
             "text_sha256" => Ipse.JSON.sha256(state.text),
             "display_sha256" => Ipse.JSON.sha256(display),
             "input_limit" => @input_limit,
             "display_limit" => @display_limit
           }}

        true ->
          {:error, :operator_input_unavailable}
      end

    {result, cleanup}
  end

  @doc false
  def validate_transcript(bytes, nonce)
      when is_binary(bytes) and is_binary(nonce) and byte_size(nonce) == 16 and
             byte_size(bytes) <= @input_limit + 128 do
    state = %{
      buffer: bytes,
      nonce: nonce,
      phase: :initial,
      restored: false,
      text: nil,
      error: nil,
      cancelled: false,
      cancel_deadline: nil,
      request: <<>>
    }

    with {:ok, result} <- frames(state),
         true <- result.buffer == <<>>,
         true <- result.restored or result.phase == :nonterminal,
         true <- result.phase in [:input, :eof, :nonterminal] or result.cancelled,
         true <- result.error == nil do
      {:ok, Map.take(result, [:phase, :text, :restored, :cancelled])}
    else
      _ -> {:error, :invalid_operator_protocol}
    end
  end

  def validate_transcript(_, _), do: {:error, :invalid_operator_protocol}

  defp loop(_port, %{exited: true} = state), do: state

  defp loop(_port, %{guarded_stop: true, phase: phase} = state)
       when phase in [:displayed, :input, :eof],
       do: state

  defp loop(port, state) do
    state = flush_request(port, state)
    now = System.monotonic_time(:millisecond)

    state =
      if now >= state.deadline and state.cancel_deadline == nil,
        do: cancel(port, state),
        else: state

    if state.cancel_deadline != nil and now >= state.cancel_deadline do
      %{state | error: :operator_cleanup_unconfirmed}
    else
      receive do
        {^port, {:data, data}}
        when byte_size(state.buffer) + byte_size(data) <= @input_limit + 128 ->
          case frames(%{state | buffer: state.buffer <> data}) do
            {:ok, next} -> loop(port, next)
            :error -> loop(port, cancel(port, %{state | error: :operator_input_unavailable}))
          end

        {^port, {:data, _}} ->
          loop(port, cancel(port, %{state | buffer: <<>>, error: :operator_input_unavailable}))

        {^port, {:exit_status, 0}} ->
          %{state | exited: true}

        {^port, {:exit_status, _}} ->
          %{state | exited: true, error: :operator_input_unavailable}

        {:DOWN, ref, :process, _, _} when ref == state.owner_ref ->
          loop(port, cancel(port, state))

        {:ipse_cancel_resource, id} when state.ticket != nil and state.ticket.id == id ->
          loop(port, cancel(port, state))

        :cancel ->
          loop(port, cancel(port, state))

        :ipse_cancel_operator_input ->
          loop(port, cancel(port, state))

        {:EXIT, ^port, _} ->
          loop(port, state)
      after
        if(state.request == <<>>, do: 5, else: 0) -> loop(port, state)
      end
    end
  end

  defp flush_request(port, %{request: <<>>, cancelled: true, cancel_sent: false} = s) do
    if Port.command(port, <<?C, 0::32>>, [:nosuspend]), do: %{s | cancel_sent: true}, else: s
  rescue
    _ -> s
  end

  defp flush_request(_port, %{request: <<>>} = s), do: s

  defp flush_request(port, s) do
    size = min(byte_size(s.request), 4096)
    part = binary_part(s.request, 0, size)
    rest = binary_part(s.request, size, byte_size(s.request) - size)
    if Port.command(port, part, [:nosuspend]), do: %{s | request: rest}, else: s
  rescue
    _ -> %{s | request: <<>>, error: :operator_input_unavailable}
  end

  defp cancel(_port, %{cancel_deadline: deadline} = s) when is_integer(deadline), do: s

  defp cancel(port, %{guarded: guarded, phase: phase} = s)
       when not is_nil(guarded) and phase in [:initial, :ready] do
    # Do not finish an authority-bearing display frame after its owner or
    # resource scope is lost. Closing the control port interrupts the helper;
    # without its restoration receipt cleanup remains unconfirmed.
    if Port.info(port), do: Port.close(port)
    %{s | cancelled: true, exited: true, request: <<>>, error: :operator_cleanup_unconfirmed}
  rescue
    _ -> %{s | cancelled: true, exited: true, request: <<>>, error: :operator_cleanup_unconfirmed}
  end

  defp cancel(port, s) do
    # Finish the original display frame so cancellation cannot become its body.
    next = %{
      s
      | cancelled: true,
        cancel_deadline: System.monotonic_time(:millisecond) + 2_000
    }

    flush_request(port, next)
  rescue
    _ ->
      %{
        s
        | cancelled: true,
          cancel_deadline: System.monotonic_time(:millisecond) + 2_000
      }
  end

  defp frames(%{restored: true, buffer: buffer}) when buffer != <<>>, do: :error

  defp frames(%{buffer: <<kind, count::unsigned-big-32, rest::binary>>} = s) do
    cond do
      count > @input_limit + 16 ->
        :error

      byte_size(rest) < count ->
        {:ok, s}

      true ->
        body = binary_part(rest, 0, count)
        tail = binary_part(rest, count, byte_size(rest) - count)

        case frame(s, kind, body) do
          {:ok, next} -> frames(%{next | buffer: tail})
          :error -> :error
        end
    end
  end

  defp frames(s), do: {:ok, s}

  defp frame(%{phase: :initial, restored: false} = s, ?n, "nonterminal"),
    do: {:ok, %{s | phase: :nonterminal, request: <<>>}}

  defp frame(
         %{phase: :initial, nonce: nonce} = s,
         ?g,
         <<nonce::binary-size(16), reader::unsigned-big-32, guardian::unsigned-big-32>>
       )
       when reader > 1 and guardian > 1 and reader != guardian,
       do: {:ok, %{s | phase: :ready}}

  defp frame(%{phase: :ready, nonce: nonce} = s, ?y, nonce),
    do: {:ok, %{s | phase: :displayed}}

  defp frame(%{phase: :displayed, nonce: nonce} = s, ?i, <<nonce::binary-size(16), text::binary>>)
       when byte_size(text) <= @input_limit do
    if String.valid?(text), do: {:ok, %{s | phase: :input, text: text}}, else: :error
  end

  defp frame(%{phase: :displayed, nonce: nonce} = s, ?f, nonce),
    do: {:ok, %{s | phase: :eof}}

  defp frame(%{nonce: nonce, restored: false} = s, ?c, nonce),
    do:
      {:ok,
       %{
         s
         | cancelled: true,
           cancel_deadline: s.cancel_deadline || System.monotonic_time(:millisecond) + 2_000
       }}

  defp frame(%{nonce: nonce, restored: false} = s, ?R, nonce)
       when s.phase in [:ready, :displayed, :input, :eof] or s.cancelled,
       do: {:ok, %{s | restored: true}}

  defp frame(%{restored: false} = s, ?e, reason) when byte_size(reason) <= 256 do
    error =
      case reason do
        "operator line exceeds 1 MiB" -> :operator_input_too_large
        "invalid operator input UTF-8" -> :operator_input_invalid_utf8
        "operator input interrupted" -> :operator_input_interrupted
        _ -> :operator_input_unavailable
      end

    if String.valid?(reason), do: {:ok, %{s | error: error}}, else: :error
  end

  defp frame(_, _, _), do: :error
end
