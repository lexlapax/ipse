defmodule Ipse.Provider.EgressGate do
  @moduledoc """
  One-use, caller-local admission at an inference transport boundary.

  This is a host-private capability, not a policy decision or worker grant. The
  owner supplies the actual route, deadline and current-authority callback; the
  transport supplies the exact target and serialized body immediately before
  dispatch. Direct low-level provider calls outside a Session have no gate.
  """

  alias Ipse.JSON
  @key {__MODULE__, :active}

  @doc false
  def capture(expected, verify, fun)
      when is_map(expected) and is_function(verify, 1) and is_function(fun, 0) do
    if Process.get(@key) != nil or not expected?(expected),
      do: raise(ArgumentError, "Inference egress gate is unavailable.")

    ref = make_ref()

    Process.put(@key, %{
      owner: self(),
      ref: ref,
      expected: expected,
      verify: verify,
      status: :pending
    })

    try do
      result = fun.()
      state = Process.get(@key)

      status =
        if is_map(state) and state.ref === ref and state.owner === self(),
          do: state.status,
          else: :unknown

      {result, status}
    after
      Process.delete(@key)
    end
  end

  @doc false
  def before_dispatch(kind, target, body) do
    case Process.get(@key) do
      nil ->
        :ok

      %{owner: owner, ref: ref, expected: expected, verify: verify, status: :pending} = state
      when owner == self() and is_reference(ref) ->
        Process.put(@key, %{state | status: :checking})

        allowed =
          with true <- valid_wire?(kind, target, body, expected),
               facts = %{
                 "kind" => kind,
                 "target_sha256" => JSON.sha256(target),
                 "body_sha256" => JSON.sha256(body)
               },
               :ok <- checked_verify(verify, facts),
               %{owner: ^owner, ref: ^ref, status: :checking} <- Process.get(@key),
               true <- alive?(expected) do
            true
          else
            _ -> false
          end

        Process.put(@key, %{state | status: if(allowed, do: :authorized, else: :denied)})
        if allowed, do: :ok, else: {:error, :inference_egress_refused}

      %{owner: owner, status: status} = state
      when owner == self() and status in [:authorized, :checking] ->
        Process.put(@key, %{state | status: :invalid})
        {:error, :inference_egress_refused}

      _ ->
        {:error, :inference_egress_refused}
    end
  rescue
    _ -> {:error, :inference_egress_refused}
  catch
    _, _ -> {:error, :inference_egress_refused}
  end

  defp checked_verify(verify, facts) do
    verify.(facts)
  rescue
    _ -> {:error, :inference_egress_refused}
  catch
    _, _ -> {:error, :inference_egress_refused}
  end

  defp expected?(e),
    do:
      Enum.sort(Map.keys(e)) == ~w(body_sha256 deadline_ms kind target_sha256 upstream)a and
        e.kind in ~w(text embedding decision custom) and JSON.sha256?(e.target_sha256) and
        JSON.sha256?(e.body_sha256) and
        is_integer(e.deadline_ms) and is_pid(e.upstream)

  defp valid_wire?(kind, target, body, e),
    do:
      is_binary(target) and is_binary(body) and kind == e.kind and
        JSON.sha256(target) == e.target_sha256 and JSON.sha256(body) == e.body_sha256 and
        alive?(e)

  defp alive?(e),
    do: Process.alive?(e.upstream) and System.monotonic_time(:millisecond) < e.deadline_ms
end
