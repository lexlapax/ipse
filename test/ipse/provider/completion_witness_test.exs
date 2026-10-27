Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Provider.CompletionWitnessTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider.{CompletionWitness, Decision.Transport, Embedding}
  alias Ipse.Test.ProviderFixture

  test "a native terminal stream and the actual isolated HTTP cleanup both witness completion" do
    body =
      Jason.encode!(%{
        "model" => "fixture",
        "message" => %{"role" => "assistant", "content" => "complete"},
        "done" => true,
        "done_reason" => "stop",
        "prompt_eval_count" => 1,
        "eval_count" => 1
      }) <> "\n"

    {base, server} = ProviderFixture.start(body, 200, "", :whole)
    runtime = %{provider: :ollama, model: "fixture", base_url: base, timeout_ms: 2000}

    assert {{:ok, %{"content" => "complete"}, _}, true} =
             CompletionWitness.capture(runtime, :text, base <> "/api/chat", fn ->
               Ipse.Provider.complete(
                 runtime,
                 [%{"role" => "user", "content" => "fixture"}],
                 [],
                 fn _ -> :ok end
               )
             end)

    assert Ipse.HTTP.finch_guardian(self()) == nil
    assert {headers, _} = Task.await(server)
    assert headers =~ "POST /api/chat HTTP/1.1"
  end

  test "bounded nonstreaming embedding and decision responses require their typed native parsers" do
    embedding = Jason.encode!(%{"model" => "fixture", "embeddings" => [[1.0, 0.5]]})
    {base, server} = ProviderFixture.start(embedding, 200, "", :whole)

    runtime = %{
      provider: :ollama,
      model: "fixture",
      base_url: base,
      timeout_ms: 2000,
      dimensions: 2,
      dimension_mode: "native"
    }

    assert {{:ok, _, _}, true} =
             CompletionWitness.capture(runtime, :embedding, base <> "/api/embed", fn ->
               Embedding.embed(runtime, ["input"], fn _ -> :ok end)
             end)

    Task.await(server)

    request = %{
      "version" => 1,
      "profile" => "fixture",
      "input" => "fixture",
      "questions" => [%{"id" => "p", "type" => "predicate", "instructions" => "fixture"}]
    }

    body =
      Jason.encode!(%{
        "model" => "fixture",
        "answers" => %{"p" => %{"type" => "noul", "noul" => 0.8}},
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      })

    {base, server} = ProviderFixture.start(body, 200, "", :whole)

    runtime = %{
      provider: :system_one_compatible,
      model: "fixture",
      base_url: base,
      timeout_ms: 2000
    }

    assert {{:ok, _, _}, true} =
             CompletionWitness.capture(runtime, :decision, base <> "/systemone", fn ->
               Transport.request(runtime, request, fn _ -> :ok end)
             end)

    Task.await(server)
  end

  test "full HTTP errors, malformed native bodies and incomplete streams do not witness terminal success" do
    for {body, status} <- [
          {"private fixture body", 500},
          {"not json\n", 200},
          {Jason.encode!(%{"message" => %{"content" => "partial"}, "done" => false}) <> "\n", 200}
        ] do
      {base, server} = ProviderFixture.start(body, status, "", :whole)
      runtime = %{provider: :ollama, model: "fixture", base_url: base, timeout_ms: 2000}

      assert {{:error, _}, false} =
               CompletionWitness.capture(runtime, :text, base <> "/api/chat", fn ->
                 Ipse.Provider.complete(
                   runtime,
                   [%{"role" => "user", "content" => "fixture"}],
                   [],
                   fn _ -> :ok end
                 )
               end)

      Task.await(server)
    end
  end

  test "success-shaped callbacks, other owners, wrong targets and unconfirmed cleanup cannot forge the conjunction" do
    runtime = %{provider: :ollama, model: "fixture"}
    target = "http://127.0.0.1:11434/api/chat"

    assert {{:ok, %{}, %{}}, false} =
             CompletionWitness.capture(runtime, :text, target, fn -> {:ok, %{}, %{}} end)

    for mutation <- [:other_owner, :wrong_target, :wrong_ref, :failed_cleanup] do
      assert {:fixture, false} =
               CompletionWitness.capture(runtime, :text, target, fn ->
                 ref = make_ref()

                 mark = fn ->
                   CompletionWitness.http_started(
                     if(mutation == :wrong_target, do: target <> "/other", else: target)
                   )

                   CompletionWitness.borrowed(ref)
                   CompletionWitness.http_complete(target, 200)

                   CompletionWitness.cleaned(
                     if(mutation == :wrong_ref, do: make_ref(), else: ref),
                     if(mutation == :failed_cleanup,
                       do: {:error, :cleanup_unconfirmed},
                       else: :ok
                     )
                   )

                   CompletionWitness.native_complete(runtime, :text)
                 end

                 if mutation == :other_owner, do: Task.await(Task.async(mark)), else: mark.()
                 :fixture
               end)
    end
  end
end
