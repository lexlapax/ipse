{:ok, _} = Application.ensure_all_started(:ipse)
config = %{
  provider: :ollama,
  model: "qwen3-embedding:0.6b-q8_0",
  dimensions: 1024,
  dimension_mode: "native",
  base_url: "http://127.0.0.1:11434",
  timeout_ms: 60_000
}
inputs = ["Synthetic local embedding transport control."]
started = System.monotonic_time(:millisecond)
case Ipse.Provider.Embedding.embed(config, inputs, fn _ -> :ok end) do
  {:ok, result, usage} ->
    true = Ipse.Provider.Embedding.valid_data?(Map.take(result, ~w(encoding dimensions vectors)), inputs, 1024)
    IO.puts(JSON.encode!(%{
      status: "ok", model: result["reported_model"], dimensions: result["dimensions"],
      vector_count: length(result["vectors"]), response_sha256: result["provider_response_sha256"],
      elapsed_ms: System.monotonic_time(:millisecond) - started,
      prompt_eval_count: usage["prompt_eval_count"]
    }))
  _ ->
    IO.puts(JSON.encode!(%{status: "failed", elapsed_ms: System.monotonic_time(:millisecond) - started}))
    System.halt(1)
end
