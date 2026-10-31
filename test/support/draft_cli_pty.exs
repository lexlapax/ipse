ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
root = List.last(System.argv())
multi = "multi" in System.argv()
question = "question" in System.argv()
mcp = "mcp" in System.argv()
cancel = "cancel" in System.argv()
inline_replace = "inline" in System.argv()
transport = System.get_env("IPSE_TEST_DRAFT_TRANSPORT") == "1"

original =
  if multi or question or mcp,
    do: "private initial request",
    else: "/enhance private initial request"

expected =
  cond do
    multi -> "first replacement line\nsecond replacement line"
    question or mcp -> "suggested request"
    true -> "accepted replacement"
  end

defmodule DraftCLIProvider do
  def complete(config, messages, _, _) do
    draft =
      Enum.any?(messages, fn m ->
        is_binary(m["content"]) and String.contains?(m["content"], "Draft a clearer version")
      end)

    answered =
      Enum.any?(messages, &(&1["role"] == "tool" and &1["tool_call_id"] == "draft-question-1"))

    effect_completed =
      Enum.any?(messages, &(&1["role"] == "tool" and &1["tool_call_id"] == "accepted-write"))

    cond do
      config[:draft_mcp] and draft and
          not Enum.any?(
            messages,
            &(&1["role"] == "tool" and &1["tool_call_id"] == "draft-lookup")
          ) ->
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "draft-lookup",
               "type" => "function",
               "function" => %{
                 "name" => "mcp__notes__lookup",
                 "arguments" => Jason.encode!(%{"query" => "public"})
               }
             }
           ]
         }, %{}}

      config[:draft_question] and draft and not answered ->
        args = %{
          "questions" => [%{"id" => "detail", "kind" => "text", "prompt" => "What detail?"}]
        }

        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "draft-question-1",
               "type" => "function",
               "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(args)}
             }
           ]
         }, %{}}

      config[:draft_question] and not draft and not effect_completed ->
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "accepted-write",
               "type" => "function",
               "function" => %{
                 "name" => "write",
                 "arguments" =>
                   Jason.encode!(%{"path" => "question-effect.txt", "content" => "approved"})
               }
             }
           ]
         }, %{}}

      true ->
        {:ok, %{"role" => "assistant", "content" => "suggested request"}, %{}}
    end
  end
end

{servers, reads, configuration} =
  if mcp do
    document = %{
      "servers" => [
        %{
          "id" => "notes",
          "command" => System.find_executable("elixir"),
          "args" => [
            "--erl",
            "+S 2:2",
            "-pa",
            Path.dirname(to_string(:code.which(Jason))),
            Path.expand("test/support/mcp_server.exs"),
            "planning_read"
          ],
          "tools" => ["lookup"],
          "env" => %{"PATH" => Path.join(to_string(:code.root_dir()), "bin") <> ":/usr/bin:/bin"},
          "timeout_ms" => 10_000
        }
      ]
    }

    path = Path.join(root, "mcp.json")
    File.write!(path, Jason.encode!(document))
    {:ok, servers} = Ipse.MCP.Config.load(path)
    [server] = servers
    {:ok, [tool]} = Ipse.MCP.discover(servers, root)

    reads = %{
      tool.tool_id => %{
        "version" => 1,
        "server_id" => server.id,
        "tool" => tool.name,
        "endpoint_sha256" => server.fingerprint,
        "descriptor_sha256" => tool.digest
      }
    }

    {servers, reads,
     %{fingerprint: Ipse.JSON.digest([reads]), planning_mcp_reads: reads, sources: []}}
  else
    {[], %{}, nil}
  end

{provider_config, transport_server} =
  if transport do
    Code.require_file(Path.expand("test/support/provider_fixture.ex"))
    fixture = Ipse.Test.ProviderFixture

    reply = fn id, text, private ->
      output =
        if(private,
          do: [
            %{
              "type" => "reasoning",
              "id" => "rs_private",
              "summary" => [],
              "encrypted_content" => "private encrypted canary"
            }
          ],
          else: []
        ) ++
          [
            %{
              "type" => "message",
              "id" => id,
              "role" => "assistant",
              "status" => "completed",
              "content" => [%{"type" => "output_text", "text" => text, "annotations" => []}]
            }
          ]

      fixture.sse(%{
        "type" => "response.completed",
        "response" => %{
          "status" => "completed",
          "model" => "fixture-model",
          "output" => output,
          "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
        }
      })
    end

    receiver = self()
    capture = Path.join(root, "transport-capture.json")

    spawn_link(fn ->
      {base_url, server} =
        fixture.sequence([
          reply.("msg_private", "suggested request", true),
          reply.("msg_accepted", "accepted response", false),
          reply.("msg_resumed", "resumed response", false)
        ])

      send(receiver, {:fixture_url, base_url})
      requests = Task.await(server, 30_000) |> Enum.map(&elem(&1, 1))
      File.write!(capture, Jason.encode!(requests))
      send(receiver, :fixture_capture_complete)
    end)

    base_url = receive do: ({:fixture_url, url} -> url)
    auth = Path.join(root, "transport-auth")

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

    :ok =
      Ipse.Auth.with_credential_lock(auth, fn -> Ipse.Auth.write_credentials(auth, record) end)

    {%{
       provider: :chatgpt,
       provider_module: Ipse.Provider.OpenAI,
       auth_dir: auth,
       base_url: base_url,
       max_output_tokens: nil
     }, capture}
  else
    {%{provider: :demo, provider_module: DraftCLIProvider}, nil}
  end

session_config =
  Map.merge(
    %{
      model: "synthetic",
      owner: self(),
      home: Path.join(root, "home"),
      approval: if(mcp, do: :ask, else: if(question, do: :allow, else: :deny)),
      operator_questions: true,
      draft_question: question,
      draft_mcp: mcp,
      mcp_servers: servers,
      planning_mcp_reads: reads,
      configuration: configuration,
      compact: false
    },
    provider_config
  )

{:ok, session} =
  Ipse.Session.start_link(
    config: session_config,
    cwd: root,
    state_dir: Path.join(root, "state"),
    subscriber: self()
  )

id = Ipse.Session.info(session).id
monitor = Process.monitor(session)
assert 0 == Ipse.CLI.Terminal.interact(session, monitor, true, nil, root)
{:ok, events} = Ipse.Journal.load(Path.join(root, "state"), id)

assert Enum.any?(
         events,
         &(&1["type"] == "input_received" and &1["origin"] == "interactive_operator" and
             &1["text"] == original)
       )

input = Enum.find(events, &(&1["type"] == "input_received" and &1["text"] == original))
assert input["observation"]["text_sha256"] == Ipse.JSON.sha256(original)
assert input["effective_sha256"] == Ipse.JSON.sha256(Ipse.Session.Draft.effective(original))

assert Ipse.Session.Draft.effective(original) ==
         Ipse.Session.Draft.effective("private initial request")

if cancel do
  assert Enum.count(events, &(&1["type"] == "draft_started")) == 1
  refute Enum.any?(events, &(&1["type"] in ~w(draft_replaced draft_accepted draft_consumed)))
  assert Enum.any?(events, &(&1["type"] == "draft_cancelled"))
  assert %{draft: %{status: :cancelled, revision: 1}} = Ipse.Session.info(session)

  assert {:ok, %{draft: cancelled, messages: messages}} = Ipse.Session.Saved.restore(events, id)

  assert {:ok, projected} =
           Ipse.Session.Draft.project(
             cancelled,
             messages,
             Ipse.Session.Reference.occurrences(events)
           )

  refute Jason.encode!(projected) =~ "private initial request"
  assert Enum.any?(projected, &(&1["content"] == "ordinary before draft"))
  assert Enum.any?(projected, &(&1["content"] == "ordinary after cancellation"))
  assert :ok = Ipse.Session.close_confirmed(session)
  IO.puts("SYNTHETIC_ENHANCE_CANCEL_PASSED")
  System.halt(0)
end

if not question and not mcp do
  replacement_version = if inline_replace, do: 4, else: if(multi, do: 3, else: 2)

  assert Enum.any?(
           events,
           &(&1["type"] == "draft_replaced" and &1["version"] == replacement_version and
               &1["text"] == expected)
         )
end

if mcp do
  assert File.read!(Path.join(root, "calls.log")) == "lookup\n"
  accepted = Enum.find(events, &(&1["type"] == "draft_accepted"))
  assert [source] = accepted["tool_evidence"]

  assert {:ok, %{records: [%{source: ^source, record: result}]}} =
           Ipse.Journal.source_page(Path.join(root, "state"), id, source["byte_offset"], 1)

  assert get_in(result, ["message", "content"]) =~ "Synthetic lookup result"
  inference = Enum.find(events, &(&1["type"] == "draft_inference_intent"))
  assert [lineage] = inference["possible_source_lineages"]
  assert lineage["tool_evidence"] == [source]

  forged =
    Enum.map(events, fn event ->
      if event == accepted, do: Map.put(event, "tool_evidence", []), else: event
    end)

  assert {:error, _} = Ipse.Session.Saved.restore(forged, id)
end

if inline_replace do
  replacement = Enum.find(events, &(&1["type"] == "draft_replaced"))
  command = "/enhance replace  accepted replacement  "
  assert replacement["command"] == command
  assert replacement["observation"]["text_sha256"] == Ipse.JSON.sha256(command)

  assert {:error, :duplicate_operator_observation} =
           Ipse.Session.DraftAcceptance.validate_observation_uniqueness([
             replacement,
             replacement
           ])

  reused_input = Map.put(input, "observation", replacement["observation"])

  assert {:error, :duplicate_operator_observation} =
           Ipse.Session.DraftAcceptance.validate_observation_uniqueness([
             reused_input,
             replacement
           ])

  for changed <- [
        Map.put(replacement, "command", "/enhance replace changed"),
        Map.put(replacement, "command", "/enhance replace accepted replacement"),
        Map.put(replacement, "text", "changed"),
        Map.put(replacement, "revision", replacement["revision"] + 1),
        put_in(replacement, ["observation", "text_sha256"], String.duplicate("0", 64)),
        Map.put(replacement, "unexpected", true)
      ] do
    tampered = Enum.map(events, fn event -> if event == replacement, do: changed, else: event end)
    assert {:error, _} = Ipse.Session.Saved.restore(tampered, id)
  end
end

assert Enum.any?(events, &(&1["type"] == "draft_accepted" and &1["version"] == 2))

if question do
  answer = Enum.find(events, &(&1["type"] == "operator_answer" and &1["version"] == 2))
  accepted = Enum.find(events, &(&1["type"] == "draft_accepted"))

  original =
    Enum.find(
      events,
      &(&1["type"] == "input_received" and &1["text"] == "private initial request")
    )

  assert accepted["question_ids"] == ["draft-question-1"]
  assert accepted["answer_source_ids"] == [answer["origin"]["source_id"]]
  assert accepted["input_source_id"] == original["source_id"]

  effect =
    Enum.find(
      events,
      &(&1["type"] == "draft_effect_intent" and &1["call_id"] == "accepted-write")
    )

  assert [lineage] = effect["possible_source_lineages"]
  assert lineage["question_ids"] == accepted["question_ids"]
  assert lineage["answer_source_ids"] == accepted["answer_source_ids"]
  assert lineage["input_source_id"] == accepted["input_source_id"]
  assert File.read!(Path.join(root, "question-effect.txt")) == "approved"

  forged =
    Enum.map(events, fn event ->
      if event == accepted, do: Map.put(event, "question_ids", []), else: event
    end)

  assert {:error, _} = Ipse.Session.Saved.restore(forged, id)
end

assert {:ok, %{draft: %{status: :consumed} = draft, messages: messages}} =
         Ipse.Session.Saved.restore(events, id)

assert {:ok, final} =
         Ipse.Session.Draft.project(
           draft,
           messages,
           Ipse.Session.Reference.occurrences(events),
           if(transport, do: :chatgpt, else: :none)
         )

assert Enum.any?(final, &(&1["content"] == expected))
refute Jason.encode!(final) =~ "private initial request"
refute Jason.encode!(final) =~ "private answer canary"
{:ok, page} = Ipse.Session.sources(session, "source.list", %{"limit" => 32})

for row <- page["sources"] do
  {:ok, source} = Ipse.Session.sources(session, "source.read", %{"handle" => row["read_handle"]})
  refute Jason.encode!(source) =~ "private initial request"
  refute Jason.encode!(source) =~ "private answer canary"
end

assert :ok = Ipse.Session.close_confirmed(session)

if transport do
  {:ok, resumed} =
    Ipse.Session.start_link(
      config: session_config,
      cwd: root,
      state_dir: Path.join(root, "state"),
      subscriber: self(),
      id: id
    )

  assert :ok = Ipse.Session.prompt(resumed, "later resumed task")
  assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
  assert :ok = Ipse.Session.close_confirmed(resumed)
  assert_receive :fixture_capture_complete, 5_000
  [first, second, third] = transport_server |> File.read!() |> Jason.decode!()
  assert Jason.encode!(first) =~ "private initial request"
  assert Jason.encode!(second) =~ "accepted replacement"
  assert Jason.encode!(third) =~ "later resumed task"
  assert Jason.encode!(third) =~ "msg_accepted"
  assert Jason.encode!(third) =~ "accepted response"

  for canary <- [
        "private initial request",
        "suggested request",
        "private encrypted canary",
        "rs_private",
        "msg_private"
      ] do
    for request <- [second, third], do: refute(Jason.encode!(request) =~ canary)
  end

  IO.puts("DRAFT_NATIVE_TRANSPORT_PASSED")
end

IO.puts("SYNTHETIC_DRAFT_CLI_PASSED")
