Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Provider.EgressGateTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Provider.EgressGate}

  defp expected(target \\ "https://fixture.example/v1", changes \\ %{}) do
    Map.merge(
      %{
        kind: "text",
        target_sha256: JSON.sha256(target),
        body_sha256: JSON.sha256("body"),
        upstream: self(),
        deadline_ms: System.monotonic_time(:millisecond) + 5000
      },
      changes
    )
  end

  test "one actual target and body digest are reported to the verifier" do
    target = "https://fixture.example/v1"
    owner = self()

    verify = fn facts ->
      send(owner, {:verified, facts})
      :ok
    end

    assert {:sent, :authorized} =
             EgressGate.capture(
               expected("https://fixture.example/v1", %{body_sha256: JSON.sha256("wire bytes")}),
               verify,
               fn ->
                 assert :ok == EgressGate.before_dispatch("text", target, "wire bytes")
                 :sent
               end
             )

    assert_receive {:verified,
                    %{
                      "kind" => "text",
                      "target_sha256" => target_hash,
                      "body_sha256" => body_hash
                    }}

    assert target_hash == JSON.sha256(target) and body_hash == JSON.sha256("wire bytes")
  end

  test "wrong target, kind, body, expired deadline or dead owner refuse before the callback" do
    target = "https://fixture.example/v1"
    dead = spawn(fn -> :ok end)
    monitor = Process.monitor(dead)
    assert_receive {:DOWN, ^monitor, :process, ^dead, _}

    for {expected, kind, actual} <- [
          {expected(), "text", target <> "/other"},
          {expected(), "embedding", target},
          {expected(target, %{body_sha256: JSON.sha256("other")}), "text", target},
          {expected(target, %{deadline_ms: System.monotonic_time(:millisecond) - 1}), "text",
           target},
          {expected(target, %{upstream: dead}), "text", target}
        ] do
      assert {{:error, :inference_egress_refused}, :denied} =
               EgressGate.capture(
                 expected,
                 fn _ -> flunk("wrong request entered verifier") end,
                 fn ->
                   EgressGate.before_dispatch(kind, actual, "body")
                 end
               )
    end
  end

  test "refusal, exceptions, reentry and a second use cannot authorize a dispatch" do
    target = "https://fixture.example/v1"

    for verifier <- [
          fn _ -> :deny end,
          fn _ -> raise "fixture" end,
          fn _ -> EgressGate.before_dispatch("text", target, "nested") end
        ] do
      assert {{:error, :inference_egress_refused}, :denied} =
               EgressGate.capture(expected(), verifier, fn ->
                 EgressGate.before_dispatch("text", target, "body")
               end)
    end

    assert {:checked, :invalid} =
             EgressGate.capture(expected(), fn _ -> :ok end, fn ->
               assert :ok == EgressGate.before_dispatch("text", target, "body")

               assert {:error, :inference_egress_refused} ==
                        EgressGate.before_dispatch("text", target, "body")

               :checked
             end)
  end

  test "scope cleanup and nested capture do not replace an active admission" do
    target = "https://fixture.example/v1"

    assert_raise RuntimeError, "fixture", fn ->
      EgressGate.capture(expected(), fn _ -> :ok end, fn ->
        assert_raise ArgumentError, fn ->
          EgressGate.capture(expected(), fn _ -> :ok end, fn -> :ok end)
        end

        raise "fixture"
      end)
    end

    assert :ok == EgressGate.before_dispatch("text", target, "direct low-level request")
  end

  test "denial after HTTP profile setup sends no text inference request" do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    server =
      Task.async(fn ->
        result = :gen_tcp.accept(listener, 1500)
        :gen_tcp.close(listener)
        result
      end)

    base = "http://127.0.0.1:#{port}"
    runtime = %{provider: :ollama, model: "fixture", base_url: base, timeout_ms: 2000}
    target = base <> "/api/chat"
    owner = self()
    messages = [%{"role" => "user", "content" => "fixture"}]

    body_sha256 =
      JSON.sha256(Jason.encode!(Ipse.Provider.Ollama.request_body(runtime, messages, [])))

    assert {{:error, _}, :denied} =
             EgressGate.capture(
               expected(target, %{body_sha256: body_sha256}),
               fn facts ->
                 send(owner, {:attempted, facts})
                 :deny
               end,
               fn ->
                 Ipse.Provider.complete(
                   runtime,
                   messages,
                   [],
                   fn _ -> :ok end
                 )
               end
             )

    assert_receive {:attempted,
                    %{
                      "kind" => "text",
                      "target_sha256" => target_hash,
                      "body_sha256" => body_hash
                    }}

    assert target_hash == JSON.sha256(target) and JSON.sha256?(body_hash)
    assert {:error, :timeout} == Task.await(server, 3000)
  end

  test "diagnostic: a policy change during TLS setup occurs after the prototype gate" do
    root = Path.join(System.tmp_dir!(), "ipse-egress-tls-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)

    certificate =
      :public_key.pkix_test_data(%{
        root: [digest: :sha256, key: {:rsa, 2048, 65537}],
        peer: [
          digest: :sha256,
          key: {:rsa, 2048, 65537},
          extensions: [{:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]}]
        ]
      })

    original =
      Enum.map(:public_key.cacerts_get(), fn
        {:cert, der, _} -> der
        der when is_binary(der) -> der
      end)

    pem = fn certs ->
      :public_key.pem_encode(Enum.map(certs, &{:Certificate, &1, :not_encrypted}))
    end

    saved = Path.join(root, "original.pem")
    trusted = Path.join(root, "fixture.pem")
    File.write!(saved, pem.(original))
    File.write!(trusted, pem.(certificate[:cacerts]))

    try do
      :ok = :public_key.cacerts_load(trusted)

      {:ok, listener} =
        :ssl.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}] ++ certificate)

      {:ok, {_, port}} = :ssl.sockname(listener)
      target = "https://localhost:#{port}/fixture"
      parent = self()
      policy = :atomics.new(1, [])
      :atomics.put(policy, 1, 1)

      server =
        Task.async(fn ->
          {:ok, socket} = :ssl.transport_accept(listener, 5000)
          send(parent, :connected_before_handshake)
          receive do: (:continue_handshake -> :ok)
          {:ok, tls} = :ssl.handshake(socket, 5000)
          bytes = receive_fixture(tls, "")

          :ok =
            :ssl.send(tls, "HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: close\r\n\r\nok")

          :ssl.close(tls)
          :ssl.close(listener)
          bytes
        end)

      request =
        Task.async(fn ->
          EgressGate.capture(
            expected(target, %{
              upstream: parent,
              body_sha256: JSON.sha256(Jason.encode!(%{"input" => "stale fixture"}))
            }),
            fn _ ->
              send(parent, :gate_checked)
              if :atomics.get(policy, 1) == 1, do: :ok, else: :deny
            end,
            fn ->
              Ipse.Provider.Transport.stream(
                target,
                [],
                %{"input" => "stale fixture"},
                %{provider: :ollama, timeout_ms: 5000},
                "",
                fn acc, bytes -> {:ok, acc <> bytes} end
              )
            end
          )
        end)

      assert_receive :gate_checked, 5000
      assert_receive :connected_before_handshake, 5000
      :atomics.put(policy, 1, 0)
      send(server.pid, :continue_handshake)
      assert {{:ok, "ok"}, :authorized} = Task.await(request, 8000)
      assert Task.await(server, 8000) =~ "stale fixture"
    after
      :ok = :public_key.cacerts_load(saved)
      File.rm_rf!(root)
    end
  end

  defp receive_fixture(socket, bytes) when byte_size(bytes) < 16_384 do
    if String.contains?(bytes, "stale fixture") do
      bytes
    else
      {:ok, next} = :ssl.recv(socket, 0, 5000)
      receive_fixture(socket, bytes <> next)
    end
  end

  test "embedding and decision requests check their actual serialized body and destination" do
    response = Jason.encode!(%{"model" => "fixture", "embeddings" => [[1.0, 0.5]]})
    {base, server} = Ipse.Test.ProviderFixture.start(response, 200, "", :whole)

    runtime = %{
      provider: :ollama,
      model: "fixture",
      base_url: base,
      timeout_ms: 2000,
      dimensions: 2,
      dimension_mode: "native"
    }

    target = base <> "/api/embed"
    owner = self()
    {:ok, embedding_body} = Ipse.Provider.Embedding.request_body(runtime, ["fixture"])

    assert {{:ok, _, _}, :authorized} =
             EgressGate.capture(
               expected(target, %{
                 kind: "embedding",
                 body_sha256: JSON.sha256(Jason.encode!(embedding_body))
               }),
               fn facts ->
                 send(owner, {:embedding, facts})
                 :ok
               end,
               fn -> Ipse.Provider.Embedding.embed(runtime, ["fixture"], fn _ -> :ok end) end
             )

    assert_receive {:embedding, %{"target_sha256" => target_hash, "body_sha256" => body_hash}}
    assert target_hash == JSON.sha256(target)
    assert {_, body} = Task.await(server)
    assert body_hash == JSON.sha256(Jason.encode!(body))

    request = %{
      "version" => 1,
      "profile" => "fixture",
      "input" => "fixture",
      "questions" => [%{"id" => "p", "type" => "predicate", "instructions" => "fixture"}]
    }

    response =
      Jason.encode!(%{
        "model" => "fixture",
        "answers" => %{"p" => %{"type" => "noul", "noul" => 0.8}},
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      })

    {base, server} = Ipse.Test.ProviderFixture.start(response, 200, "", :whole)

    runtime = %{
      provider: :system_one_compatible,
      model: "fixture",
      base_url: base,
      timeout_ms: 2000
    }

    target = base <> "/systemone"
    {:ok, decision_body} = Ipse.Provider.Decision.encode(:system_one, request, runtime.model)

    assert {{:ok, _, _}, :authorized} =
             EgressGate.capture(
               expected(target, %{
                 kind: "decision",
                 body_sha256: JSON.sha256(Jason.encode!(decision_body))
               }),
               fn facts ->
                 send(owner, {:decision, facts})
                 :ok
               end,
               fn ->
                 Ipse.Provider.Decision.Transport.request(runtime, request, fn _ -> :ok end)
               end
             )

    assert_receive {:decision, %{"target_sha256" => target_hash, "body_sha256" => body_hash}}
    assert target_hash == JSON.sha256(target)
    assert {_, body} = Task.await(server)
    assert body_hash == JSON.sha256(Jason.encode!(body))
  end
end
