Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Provider.CompletionWitnessTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider.{CompletionWitness, Decision.Transport, Embedding}
  alias Ipse.Test.ProviderFixture

  defmodule SyntheticMain do
    def complete(config, messages, tools, emit),
      do: Ipse.Provider.complete(Map.put(config, :provider, :ollama), messages, tools, emit)
  end

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

  test "a completed authentication HTTP request neither witnesses nor invalidates the later inference" do
    {auth_base, auth_server} = ProviderFixture.start("{}", 200, "", :whole)

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
    target = base <> "/api/chat"

    assert {{:ok, %{"content" => "complete"}, _}, true} =
             CompletionWitness.capture(runtime, :text, target, fn ->
               assert {:ok, 200, "{}"} =
                        CompletionWitness.during_auth(fn ->
                          request =
                            Finch.build(:post, auth_base <> "/oauth/token", [], "{}")

                          Ipse.HTTP.bounded_request(request, 1024, 2000)
                        end)

               Ipse.Provider.complete(
                 runtime,
                 [%{"role" => "user", "content" => "fixture"}],
                 [],
                 fn _ -> :ok end
               )
             end)

    assert {auth_headers, _} = Task.await(auth_server)
    assert auth_headers =~ "POST /oauth/token HTTP/1.1"
    assert {headers, _} = Task.await(server)
    assert headers =~ "POST /api/chat HTTP/1.1"
  end

  test "authentication cannot forge a completion and its witness is restored after failure" do
    runtime = %{provider: :ollama, model: "fixture"}
    target = "http://127.0.0.1:11434/api/chat"

    assert {:fixture, false} =
             CompletionWitness.capture(runtime, :text, target, fn ->
               assert_raise RuntimeError, "fixture", fn ->
                 CompletionWitness.during_auth(fn ->
                   assert_raise ArgumentError, fn ->
                     CompletionWitness.capture(runtime, :text, target, fn -> :ok end)
                   end

                   CompletionWitness.http_started(target)
                   CompletionWitness.native_complete(runtime, :text)
                   raise "fixture"
                 end)
               end

               :fixture
             end)
  end

  test "authentication cannot conceal another HTTP request after inference has started" do
    runtime = %{provider: :ollama, model: "fixture"}
    target = "http://127.0.0.1:11434/api/chat"

    assert {:fixture, false} =
             CompletionWitness.capture(runtime, :text, target, fn ->
               ref = make_ref()
               CompletionWitness.http_started(target)
               CompletionWitness.borrowed(ref)

               CompletionWitness.during_auth(fn ->
                 CompletionWitness.http_started("http://127.0.0.1:11434/oauth/token")
               end)

               CompletionWitness.http_complete(target, 200)
               CompletionWitness.cleaned(ref, :ok)
               CompletionWitness.native_complete(runtime, :text)
               :fixture
             end)
  end

  test "the main request isolates actual credential refresh HTTP from inference completion" do
    dir = Path.join(System.tmp_dir!(), "ipse-witness-auth-" <> Ipse.Usage.id())
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)
    on_exit(fn -> File.rm_rf!(dir) end)

    record = %{
      "access_token" => "synthetic-access",
      "refresh_token" => "synthetic-refresh",
      "client_id" => "synthetic-client",
      "subject" => "synthetic-subject",
      "issuer" => "https://auth.openai.com",
      "email" => "fixture@example.test",
      "expires_at" => 0,
      "scopes" => ["chatgpt.tokens.use.direct"]
    }

    assert :ok = Ipse.Auth.write_credentials(dir, record)

    response =
      Jason.encode!(%{
        "access_token" => "rotated-synthetic",
        "refresh_token" => "rotated-refresh",
        "expires_in" => 3600,
        "token_type" => "Bearer"
      })

    {auth_base, auth_server} = ProviderFixture.start(response, 200, "", :whole)

    stream =
      Jason.encode!(%{
        "model" => "fixture",
        "message" => %{"role" => "assistant", "content" => "complete"},
        "done" => true,
        "done_reason" => "stop",
        "prompt_eval_count" => 1,
        "eval_count" => 1
      }) <> "\n"

    {base, server} = ProviderFixture.start(stream, 200, "", :whole)

    config = %{
      provider: :chatgpt,
      model: "fixture",
      auth_dir: dir,
      provider_module: SyntheticMain,
      base_url: base,
      timeout_ms: 2000
    }

    witness_runtime = %{provider: :ollama, model: "fixture"}

    transport = fn :post, "https://auth.openai.com/api/accounts/oauth/token", fields ->
      assert fields["grant_type"] == "refresh_token"

      request =
        Finch.build(:post, auth_base <> "/oauth/token", [], Jason.encode!(%{"fixture" => true}))

      assert {:ok, 200, body} = Ipse.HTTP.bounded_request(request, 1024, 2000)
      {:ok, Jason.decode!(body)}
    end

    assert {{:ok, %{"content" => "complete"}, _}, true} =
             CompletionWitness.capture(witness_runtime, :text, base <> "/api/chat", fn ->
               Ipse.Auth.with_auth_transport(transport, fn ->
                 Ipse.Provider.request_complete(
                   config,
                   [%{"role" => "user", "content" => "fixture"}],
                   [],
                   fn _ -> :ok end
                 )
               end)
             end)

    assert {:ok, %{"access_token" => "rotated-synthetic"}} = Ipse.Auth.read_credentials(dir)
    assert {_, %{"fixture" => true}} = Task.await(auth_server)
    assert {_, _} = Task.await(server)
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
