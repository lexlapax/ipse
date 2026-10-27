defmodule Ipse.Provider.CompletionWitness do
  @moduledoc false
  @key {__MODULE__, :active}

  # This is a trusted host observation in the actual provider caller. It never
  # enters configuration, wire payloads, worker outcomes or durable records.
  def capture(runtime, kind, target, fun) when is_function(fun, 0) do
    if Process.get(@key) != nil do
      raise ArgumentError, "Nested provider completion observation is unavailable."
    end

    Process.put(@key, %{
      owner: self(),
      ref: make_ref(),
      provider: runtime.provider,
      model: runtime.model,
      kind: kind,
      target: target_hash(target),
      started: false,
      http_ref: nil,
      eof: false,
      cleanup: false,
      native: false,
      invalid: false
    })

    try do
      result = fun.()
      state = Process.get(@key)

      complete =
        is_map(state) and state.owner == self() and is_reference(state.ref) and
          not state.invalid and state.started and state.eof and state.cleanup and state.native

      {result, complete}
    after
      Process.delete(@key)
    end
  end

  def http_started(target) do
    update(fn state ->
      if not state.started and state.target == target_hash(target),
        do: %{state | started: true},
        else: %{state | invalid: true}
    end)
  end

  def borrowed(reference) when is_reference(reference) do
    update(fn state ->
      if state.started and is_nil(state.http_ref),
        do: %{state | http_ref: reference},
        else: state
    end)
  end

  def http_complete(target, status) do
    update(fn state ->
      if state.started and state.target == target_hash(target) and status in 200..299,
        do: %{state | eof: true},
        else: %{state | invalid: true}
    end)
  end

  def cleaned(reference, result) when is_reference(reference) do
    update(fn state ->
      if state.http_ref === reference,
        do: %{state | cleanup: result == :ok},
        else: state
    end)
  end

  def native_complete(runtime, kind) do
    update(fn state ->
      if state.provider == runtime.provider and state.model == runtime.model and
           state.kind == kind,
         do: %{state | native: true},
         else: %{state | invalid: true}
    end)
  end

  defp update(fun) do
    case Process.get(@key) do
      %{owner: owner} = state when owner == self() -> Process.put(@key, fun.(state))
      _ -> :ok
    end

    :ok
  end

  defp target_hash(target), do: target |> URI.new!() |> URI.to_string() |> Ipse.JSON.sha256()
end
