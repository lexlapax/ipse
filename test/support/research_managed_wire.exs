unless Code.ensure_loaded?(Ipse.Test.ProviderFixture),
  do: Code.require_file("provider_fixture.ex", __DIR__)

defmodule ResearchMixedWire do
  @moduledoc false
  import ExUnit.Assertions

  def provided do
    %{
      "source_id" => "external:explicit-user",
      "title" => "Release",
      "text" => "Résumé 雪: Ada owns release after audit.",
      "uri" => "provided:explicit-user",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil
    }
  end

  def retain_args,
    do: %{"store" => "notes", "source" => provided(), "quote" => "Ada owns release after audit."}

  def query_args,
    do: %{
      "store" => "notes",
      "retrieval" => "words",
      "rerank" => nil,
      "query" => "release",
      "top_k" => 3,
      "as_of_ms" => 20
    }

  def negative_args do
    retain_args()
    |> put_in(["source", "source_id"], "external:model-tool")
    |> put_in(["source", "text"], "Different body: Bert owns release after review.")
    |> Map.put("quote", "Bert owns release after review.")
  end

  def operator(base) do
    %{
      "version" => 1,
      "settings" => %{"compact" => false},
      "profiles" => %{
        "mixed" => %{
          "provider" => "ollama",
          "model" => "synthetic",
          "base_url" => base,
          "timeout_ms" => 3000,
          "max_output_tokens" => 64
        }
      },
      "roles" => %{"main" => "mixed"},
      "inference_services" => %{"local" => %{"version" => 1, "origins" => [base]}}
    }
  end

  def start(root) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    base = "http://127.0.0.1:#{port}"
    route = Path.join(root, "mixed-route.json")
    File.write!(route, Jason.encode!(operator(base)), [:exclusive, :sync])
    File.chmod!(route, 0o600)
    log = Path.join(root, "mixed-wire.jsonl")
    File.write!(log, "", [:exclusive])
    File.chmod!(log, 0o600)
    task = Task.async(fn -> serve(listener, log, 0) end)
    %{listener: listener, task: task, route: route, base: base}
  end

  def finish(server) do
    :ok = :gen_tcp.close(server.listener)
    Task.await(server.task, 5000)
  end

  def requests(root) do
    root
    |> Path.join("mixed-wire.jsonl")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  def request(root, mode, index) do
    index = if mode == :negative, do: index + 3, else: index
    payload = requests(root) |> Enum.fetch!(index)
    {payload["messages"], payload["tools"] || []}
  end

  def count(root, :positive), do: length(requests(root))
  def count(root, :negative), do: max(length(requests(root)) - 3, 0)

  def message(0), do: final("MIXED_INITIAL_READY")
  def message(1), do: tool("ext__corpus__query", query_args())
  def message(2), do: final("MIXED_CITATION_VERIFIED")
  def message(3), do: tool("ext__research__retain", negative_args())
  def message(4), do: final("MIXED_RETAIN_UNAVAILABLE")

  defp final(text), do: %{"role" => "assistant", "content" => text}

  defp tool(name, args),
    do: %{
      "role" => "assistant",
      "content" => "",
      "tool_calls" => [%{"function" => %{"name" => name, "arguments" => args}}]
    }

  defp serve(listener, log, index) do
    case :gen_tcp.accept(listener, 60_000) do
      {:error, :closed} ->
        index

      {:ok, socket} ->
        try do
          {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
          request = Jason.decode!(bytes)
          assert request["model"] == "synthetic" and index < 5
          File.write!(log, Jason.encode!(request) <> "\n", [:append, :sync])

          body =
            Jason.encode!(%{
              "model" => "synthetic",
              "message" => message(index),
              "done" => true,
              "prompt_eval_count" => 1,
              "eval_count" => 1
            }) <> "\n"

          assert :ok =
                   :gen_tcp.send(
                     socket,
                     "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                       body
                   )
        after
          :gen_tcp.close(socket)
        end

        serve(listener, log, index + 1)
    end
  end
end
