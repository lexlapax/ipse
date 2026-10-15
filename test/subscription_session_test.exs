defmodule Ipse.SubscriptionSessionTest do
  use ExUnit.Case, async: false

  alias Ipse.Auth.Store
  alias Ipse.Session

  test "actual ChatGPT sessions surface eligibility and usage limits without fallback or replay" do
    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-subscription-session-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    original_api_key = System.get_env("OPENAI_API_KEY")
    System.put_env("OPENAI_API_KEY", "api-billing-trap")

    on_exit(fn ->
      if original_api_key,
        do: System.put_env("OPENAI_API_KEY", original_api_key),
        else: System.delete_env("OPENAI_API_KEY")

      File.rm_rf!(root)
    end)

    for {status, code, hint} <- [
          {403, "subscription_sharing_user_not_eligible", "Check eligibility"},
          {429, "subscription_sharing_usage_limit_exceeded", "Pause plan requests"}
        ] do
      case_root = Path.join(root, Integer.to_string(status))
      File.mkdir_p!(case_root)
      auth_dir = Path.join(case_root, "auth")
      state_dir = Path.join(case_root, "sessions")
      home = Path.join(case_root, "ipse-home")
      token = subscription_token()
      assert :ok = Store.with_lock(auth_dir, fn -> Store.write(auth_dir, token) end)
      body = Jason.encode!(%{"error" => %{"code" => code, "message" => "private provider prose"}})
      request_id = "req-session-#{status}"
      {base_url, server} = fixture(body, status, request_id)

      config = %{
        provider: :chatgpt,
        model: "fixture-model",
        base_url: base_url,
        auth_dir: auth_dir,
        home: home,
        timeout_ms: 5_000,
        approval: :ask
      }

      session = start_session(case_root, state_dir, config)
      session_id = Session.info(session).id
      assert :ok = Session.prompt(session, "Inspect the current project safely.")

      assert_receive {:ipse, ^session, {:error, error}}, 5_000
      assert_receive {:ipse, ^session, {:done, :error}}, 5_000
      assert error =~ code
      assert error =~ request_id
      assert error =~ hint
      refute error =~ "private provider prose"
      refute error =~ "api-billing-trap"
      assert Session.info(session).phase == :idle

      {headers, request, extra_request} = Task.await(server, 5_000)
      assert extra_request == :none
      assert headers =~ "POST /responses HTTP/1.1"
      assert String.downcase(headers) =~ "authorization: bearer subscription-fixture-token"
      refute headers =~ "api-billing-trap"
      assert request["model"] == "fixture-model"
      assert request["store"] == false
      assert request["stream"] == true
      assert Enum.any?(request["input"], &(&1["role"] == "developer"))

      assert Enum.any?(request["input"], fn item ->
               item["type"] == "additional_tools" and item["role"] == "developer" and
                 item["tools"] != []
             end)

      assert {:ok, ^token} = Store.read(auth_dir)
      {:ok, events} = Ipse.Journal.load(state_dir, session_id)

      assert Enum.any?(events, fn event ->
               get_in(event, ["message", "role"]) == "user" and
                 get_in(event, ["message", "content"]) =~ "Inspect the current project"
             end)

      refute Enum.any?(events, &(&1["type"] == "tool_started"))
      terminate_session(session)

      resumed = start_session(case_root, state_dir, config, session_id)
      assert Session.info(resumed).phase == :idle
      refute_receive {:ipse, ^resumed, {:status, "Thinking"}}, 100
      assert {:ok, ^token} = Store.read(auth_dir)
      terminate_session(resumed)
    end
  end

  defp start_session(root, state_dir, config, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: root, state_dir: state_dir, id: id, subscriber: self()}
      )

    on_exit(fn -> terminate_session(pid) end)
    pid
  end

  defp terminate_session(pid) do
    if Process.alive?(pid), do: DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
  end

  defp subscription_token do
    %{
      "access_token" => "subscription-fixture-token",
      "refresh_token" => "subscription-fixture-refresh",
      "id_token" => "subscription-fixture-id",
      "client_id" => "oaiapp_subscription_fixture",
      "ext_agent_host_id" => "urn:uuid:00112233-4455-4677-8899-aabbccddeeff",
      "subject" => "subscription-fixture-account",
      "email" => "subscription@example.test",
      "issuer" => "https://auth.openai.com",
      "token_type" => "Bearer",
      "expires_in" => 3600,
      "expires_at" => System.system_time(:second) + 3600,
      "saved_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "scopes" => ["openid", "offline_access", "chatgpt.tokens.use.direct"]
    }
  end

  defp fixture(body, status, request_id) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listener, 5_000)
          {headers, payload} = request(socket, "")

          response =
            "HTTP/1.1 #{status} Fixture\r\n" <>
              "content-type: application/json\r\n" <>
              "content-length: #{byte_size(body)}\r\n" <>
              "x-request-id: #{request_id}\r\n" <>
              "connection: close\r\n\r\n"

          :ok = :gen_tcp.send(socket, response <> body)
          :gen_tcp.close(socket)

          extra_request =
            case :gen_tcp.accept(listener, 200) do
              {:ok, extra_socket} ->
                :gen_tcp.close(extra_socket)
                :received

              {:error, :timeout} ->
                :none
            end

          {headers, Jason.decode!(payload), extra_request}
        after
          :gen_tcp.close(listener)
        end
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  defp request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
        {headers, rest(socket, body, String.to_integer(size))}

      [_] ->
        {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
        request(socket, buffer <> chunk)
    end
  end

  defp rest(_socket, body, size) when byte_size(body) >= size, do: body

  defp rest(socket, body, size) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
    rest(socket, body <> chunk, size)
  end
end
