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
      invalid: false,
      owned_child: nil
    })

    try do
      result = fun.()
      state = Process.get(@key)

      complete =
        is_map(state) and state.owner == self() and is_reference(state.ref) and
          not state.invalid and state.started and state.eof and state.cleanup and state.native and
          state.owned_child in [nil, :consumed]

      {result, complete}
    after
      Process.delete(@key)
    end
  end

  # Authentication may use the same owned HTTP client before inference starts.
  # Its request is not the selected inference request and cannot witness it.
  # Keep a sentinel so a nested capture cannot replace the original witness.
  def during_auth(fun) when is_function(fun, 0) do
    case Process.get(@key) do
      %{owner: owner, started: false, invalid: false} = state when owner == self() ->
        Process.put(@key, :authentication)

        try do
          fun.()
        after
          Process.put(@key, state)
        end

      _ ->
        fun.()
    end
  end

  def http_started(target) do
    update(fn state ->
      if not state.started and is_nil(state.owned_child) and state.target == target_hash(target),
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

  # Trusted host only. This reference correlates a single child with its outer
  # witness; it does not prove a child ran or authenticate a same-BEAM caller.
  # The host must call completion only after confirmed child cleanup and native
  # parsing. It is not an extension or JSON receipt.
  @doc false
  def reserve_owned_child(runtime, kind, target) do
    case Process.get(@key) do
      nil ->
        {:ok, :unobserved}

      %{owner: owner} = state when owner == self() ->
        if not state.invalid and not state.started and is_nil(state.http_ref) and
             is_nil(state.owned_child) and
             state.provider == runtime.provider and state.model == runtime.model and
             state.kind == kind and state.target == target_hash(target) do
          capability = make_ref()
          Process.put(@key, %{state | owned_child: capability})
          {:ok, capability}
        else
          Process.put(@key, %{state | invalid: true})
          {:error, :inference_witness_refused}
        end

      _ ->
        {:error, :inference_witness_refused}
    end
  end

  @doc false
  def complete_owned_child(runtime, kind, target, capability) do
    case Process.get(@key) do
      nil when capability == :unobserved ->
        :ok

      %{owner: owner} = state when owner == self() ->
        if is_reference(capability) and state.owned_child === capability and
             not state.invalid and not state.started and is_nil(state.http_ref) and
             state.provider == runtime.provider and state.model == runtime.model and
             state.kind == kind and state.target == target_hash(target) do
          Process.put(@key, %{
            state
            | started: true,
              http_ref: make_ref(),
              eof: true,
              cleanup: true,
              native: true,
              owned_child: :consumed
          })

          :ok
        else
          Process.put(@key, %{state | invalid: true})
          {:error, :inference_witness_refused}
        end

      _ ->
        {:error, :inference_witness_refused}
    end
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
