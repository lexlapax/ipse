Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Session.DraftResponseLimitsTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session, Usage}
  alias Ipse.Test.ProviderFixture

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-draft-response-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    auth = Path.join(root, "auth")

    record = %{
      "access_token" => "fixture-access",
      "refresh_token" => "fixture-refresh",
      "id_token" => "fixture-id",
      "client_id" => "oaiapp_fixture",
      "ext_agent_host_id" => "urn:uuid:00112233-4455-4677-8899-aabbccddeeff",
      "subject" => "fixture",
      "issuer" => "https://auth.openai.com",
      "email" => "fixture@example.test",
      "expires_at" => System.system_time(:second) + 3600,
      "scopes" => ["chatgpt.tokens.use.direct"]
    }

    assert :ok =
             Ipse.Auth.with_credential_lock(auth, fn ->
               Ipse.Auth.write_credentials(auth, record)
             end)

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, auth: auth, dir: Path.join(root, "sessions")}
  end

  defp response(text, fragmented?) do
    fragments =
      if fragmented? do
        for {point, index} <- text |> String.codepoints() |> Enum.with_index() do
          %{
            "type" => "response.output_text.delta",
            "item_id" => "msg_draft",
            "output_index" => 0,
            "content_index" => 0,
            "sequence_number" => index,
            "delta" => point
          }
        end
      else
        []
      end

    ProviderFixture.sse(
      fragments ++
        [
          %{
            "type" => "response.completed",
            "response" => %{
              "status" => "completed",
              "model" => "fixture",
              "output" => [
                %{
                  "type" => "message",
                  "id" => "msg_draft",
                  "role" => "assistant",
                  "status" => "completed",
                  "content" => [%{"type" => "output_text", "text" => text, "annotations" => []}]
                }
              ],
              "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
            }
          }
        ]
    )
  end

  defp start(c, body, extra \\ %{}) do
    {url, server} = ProviderFixture.sequence([body])

    config =
      Map.merge(
        %{
          provider: :chatgpt,
          model: "fixture",
          auth_dir: c.auth,
          home: Path.join(c.root, "home"),
          base_url: url,
          max_output_tokens: nil,
          approval: :deny,
          headless: true,
          compact: false,
          budget: %{"version" => 1, "max_requests" => 1}
        },
        extra
      )

    assert {:ok, pid} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: c.root, state_dir: c.dir, subscriber: self()}
             )

    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)
    {pid, server}
  end

  defp saved(c, pid) do
    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)
    assert {:ok, events} = Journal.load(c.dir, id)
    assert {:ok, restored} = Session.Saved.restore(events, id)
    assert Enum.count(events, &(&1["type"] == "request_admitted")) == 1
    refute Enum.any?(events, &(&1["type"] in ~w(tool_started draft_accepted draft_consumed)))
    {events, restored}
  end

  test "short proposal survives SSE framing larger than 64 KiB", c do
    text = String.duplicate("A résumé proposal. ", 64)
    body = response(text, true)
    assert byte_size(text) < 2048
    assert byte_size(body) > 65_536 and byte_size(body) < 8_388_608
    {pid, server} = start(c, body)
    assert :ok = Session.start_draft(pid, "Draft this bounded request")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    assert {:ok, %{status: :completed, proposal: ^text}} = Session.draft(pid)
    assert [{_, request}] = Task.await(server, 5_000)
    assert Enum.any?(request["input"], &(&1["type"] == "additional_tools"))
    assert :ok = Session.cancel_draft(pid)
    {events, restored} = saved(c, pid)
    assert restored.draft.status == :cancelled
    assert Enum.count(events, &(&1["type"] == "draft_completed")) == 1
  end

  test "a tighter inherited transport limit still refuses before draft completion", c do
    body = response(String.duplicate("bounded proposal ", 64), true)
    {pid, server} = start(c, body, %{max_response_bytes: 32_768})
    assert :ok = Session.start_draft(pid, "Draft this bounded request")
    assert_receive {:ipse, ^pid, {:error, error}}, 10_000
    assert error =~ "byte limit"
    assert_receive {:ipse, ^pid, {:done, :error}}, 5_000
    assert {:ok, %{status: :pending}} = Session.draft(pid)
    assert [{_, _}] = Task.await(server, 5_000)
    id = Session.info(pid).id
    {events, _} = saved(c, pid)
    refute Enum.any?(events, &(&1["type"] == "draft_completed"))

    assert [%{"finality" => "partial", "outcome" => "failed"}] =
             Enum.filter(events, &(&1["type"] == "request_finished"))

    assert {:ok, %{"unknown_liability_count" => 1, "request_count" => 1}} =
             Ipse.Usage.Budget.saved(c.dir, id)
  end

  test "oversized final proposal reports failure without admitting a completed draft", c do
    text = String.duplicate("é", 16_385)
    assert byte_size(text) == 32_770
    {pid, server} = start(c, response(text, false))
    assert :ok = Session.start_draft(pid, "Draft this bounded request")
    assert_receive {:ipse, ^pid, {:error, error}}, 10_000
    assert error =~ "32768"
    assert error =~ "Cancel this draft"
    assert_receive {:ipse, ^pid, {:done, :error}}, 5_000
    assert {:ok, %{status: :pending} = draft} = Session.draft(pid)

    assert {:error, :stale_draft} =
             Session.replace_draft(pid, draft.id, draft.revision, "replacement")

    assert :ok = Session.cancel_draft(pid)
    assert [{_, _}] = Task.await(server, 5_000)
    id = Session.info(pid).id
    {events, restored} = saved(c, pid)
    assert restored.draft.status == :cancelled
    refute Enum.any?(events, &(&1["type"] == "draft_completed"))
    assert Enum.any?(events, &(get_in(&1, ["message", "content"]) == text))

    assert [%{"finality" => "final", "outcome" => "completed"}] =
             Enum.filter(events, &(&1["type"] == "request_finished"))

    assert {:ok, %{"unknown_liability_count" => 0, "request_count" => 1}} =
             Ipse.Usage.Budget.saved(c.dir, id)
  end

  test "the complete 32768-byte UTF-8 proposal remains admissible", c do
    text = String.duplicate("é", 16_384)
    assert byte_size(text) == 32_768
    {pid, server} = start(c, response(text, false))
    assert :ok = Session.start_draft(pid, "Draft this bounded request")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    assert {:ok, %{status: :completed, proposal: ^text}} = Session.draft(pid)
    assert [{_, _}] = Task.await(server, 5_000)
    {events, restored} = saved(c, pid)
    assert restored.draft.status == :completed
    assert Enum.count(events, &(&1["type"] == "draft_completed")) == 1
  end

  test "draft config preserves selected transport and token settings" do
    for extra <- [%{}, %{max_response_bytes: 8192}, %{max_response_bytes: 1_048_576}] do
      config =
        Map.merge(
          %{
            provider: :chatgpt,
            max_output_tokens: nil,
            reasoning_effort: "medium",
            max_steps: 30,
            approval: :deny,
            headless: true
          },
          extra
        )

      draft = Ipse.Session.Draft.draft_config(config)
      assert Map.fetch(draft, :max_response_bytes) == Map.fetch(config, :max_response_bytes)
      assert draft.max_output_tokens == config.max_output_tokens
      assert draft.reasoning_effort == config.reasoning_effort
      assert draft.max_steps == 3
      assert draft.execution_mode == :draft
    end
  end
end
