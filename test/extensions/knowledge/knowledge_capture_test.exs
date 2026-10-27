defmodule IpseKnowledge.KnowledgeCaptureTest do
  use ExUnit.Case, async: false

  @suite ~S"""
  ExUnit.start(autorun: false)
  for path <- ~w(profiles notes knowledge/records knowledge/contracts knowledge),
    do: Code.require_file(Path.join("extensions/knowledge/src", path <> ".ex"))

  defmodule IpseKnowledge.KnowledgeCaptureSuite do
  use ExUnit.Case, async: true
  alias IpseKnowledge.Knowledge, as: K

  defp options,
    do:
      Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.put("version", 1)

  defp attrs(text \\ "Acme has owner Alex"),
    do: %{
      "text" => text,
      "category" => "ordinary",
      "reason" => "explicit observation",
      "event_at_ms" => nil,
      "source" => %{"handle" => "synthetic.handle", "quote" => "Acme has owner Alex"}
    }

  defp page(origin) do
    text = "Acme has owner Alex"
    ids = Map.new(~w(occurrence_id version_id chunk_id), &{&1, String.duplicate("1", 32)})

    Map.merge(ids, %{
      "version" => 1,
      "kind" => if(origin == "assistant_proposal", do: "answer.original", else: "input.original"),
      "origin" => origin,
      "coverage" => "available",
      "text" => text,
      "offset" => 0,
      "content_sha256" => Ipse.JSON.sha256(text),
      "handle" => "synthetic.handle",
      "next" => nil,
      "complete" => true,
      "original_bytes" => byte_size(text),
      "reason" => nil,
      "provenance" => %{"receipt_sha256" => Ipse.JSON.sha256("synthetic trusted-function input")},
      "window" => %{"version" => 1, "session_id" => String.duplicate("2", 32)}
    })
  end

  defp quote_receipt(page),
    do:
      Map.take(page, ~w(occurrence_id version_id chunk_id origin coverage content_sha256))
      |> Map.merge(%{
        "start_byte" => 0,
        "end_byte" => byte_size(page["text"]),
        "quote_sha256" => Ipse.JSON.sha256(page["text"])
      })

  defp respond(state, value),
    do: K.handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => value}}, state)

  defp request({:ok, %{"kind" => "host_call", "request" => request}, state}), do: {request, state}

  defp value({:ok, %Ipse.Extension.ResultPublication.Output{bytes: bytes}, state}),
    do: {JSON.decode!(bytes), state}

  defp value({:ok, %{"kind" => "result", "value" => value}, state}), do: {value, state}

  defp start(origin \\ "interactive_operator", args \\ attrs()) do
    {:ok, state} = K.init(options())

    {%{"op" => "source.read"}, state} =
      request(K.handle("invoke.tool", %{"id" => "capture", "arguments" => args}, state))

    page = page(origin)
    {%{"op" => "source.quote"}, state} = request(respond(state, page))

    {%{"op" => "collection.call", "request" => %{"op" => "get", "key" => "override." <> _}},
     state} = request(respond(state, quote_receipt(page)))

    state
  end

  test "native exact capture carries public stable proof into a create-only commit" do
    state = start()

    {%{"request" => %{"key" => "note." <> _}}, state} =
      request(respond(state, %{"record" => nil}))

    {commit, state} = request(respond(state, %{"record" => nil, "generation" => 7}))
    assert commit["request"]["expected_generation"] == 7
    assert commit["op"] == "collection.managed"
    assert commit["request"]["advance_floor"] == true
    assert {:ok, commit["recipe_sha256"]} ==
             Ipse.Extension.canonical_digest([IpseKnowledge.Knowledge.Contracts.recipe("note")])
    [change] = commit["request"]["changes"]
    assert change["expected_revision"] == 0

    assert change["value"]["evidence"]["sources"] |> hd() |> Map.fetch!("origin") ==
             "interactive_operator"

    assert commit["proofs"] == [
             %{"handle" => "synthetic.handle", "quote" => "Acme has owner Alex"}
           ]

    assert byte_size(IO.iodata_to_binary(JSON.encode!(commit))) <= 8192

    {%{"status" => "saved", "category" => "ordinary"}, %{phase: :idle}} =
      value(respond(state, %{"generation" => 8}))
  end

  test "duplicate capture never overwrites or renews an existing record" do
    state = start()
    {_, state} = request(respond(state, %{"record" => nil}))

    {%{"status" => "existing", "renewed" => false, "revision" => 3}, _} =
      value(respond(state, %{"record" => %{"revision" => 3}, "generation" => 9}))
  end

  test "saved session-only suppression stops paraphrases before any commit" do
    state = start("interactive_operator", attrs("Alex owns Acme"))

    override = %{
      "version" => 1,
      "lineage" => state.ctx.lineage,
      "policy" => %{"kind" => "session"},
      "reason" => "operator forgot this",
      "updated_at_ms" => 0
    }

    {:ok, stored} = IpseKnowledge.Knowledge.Records.override_record(override, state.ctx.proof)
    {%{"status" => "suppressed"}, _} =
      value(respond(state, %{"record" => %{"value" => stored}}))

    {%{"status" => "refused", "code" => "invalid_saved_override"}, _} =
      value(
        respond(state, %{
          "record" => %{"value" => %{stored | "lineage" => String.duplicate("f", 64)}}
        })
      )
  end

  test "assistant claims remain pending with bounded retained queue and no hidden pruning" do
    state = start("assistant_proposal")

    {%{"request" => %{"key" => "pending." <> _}}, state} =
      request(respond(state, %{"record" => nil}))

    {%{"request" => %{"op" => "scan", "after" => "pending.", "generation" => 5}}, state} =
      request(respond(state, %{"record" => nil, "generation" => 5}))

    {commit, _} = request(respond(state, %{"records" => [], "next" => nil}))
    assert commit["op"] == "collection.managed"
    assert {:ok, commit["recipe_sha256"]} ==
             Ipse.Extension.canonical_digest([IpseKnowledge.Knowledge.Contracts.recipe("pending")])
    [change] = commit["request"]["changes"]
    assert change["value"]["kind"] == "proposal"
    assert change["value"]["state"] == "pending"
    assert change["value"]["expires_at_ms"] - change["value"]["created_at_ms"] == 604_800_000

    rows =
      for n <- 1..4,
          do: %{
            "key" => "pending." <> Integer.to_string(n),
            "value" => %{"text" => "old proposal"}
          }

    state =
      Enum.reduce(1..15, state, fn _, state ->
        {_, state} = request(respond(state, %{"records" => rows, "next" => "pending.4"}))
        state
      end)

    {%{"status" => "refused", "code" => "proposal_capacity"}, _} =
      value(respond(state, %{"records" => rows, "next" => "pending.4"}))
  end

  test "conflict and unknown effects return terminal evidence without retrying" do
    state = start()
    {_, state} = request(respond(state, %{"record" => nil}))
    {_, state} = request(respond(state, %{"record" => nil, "generation" => 1}))

    for status <- ~w(conflict unknown failed) do
      {%{"status" => "interrupted", "outcome" => %{"status" => ^status}}, %{phase: :idle}} =
        value(
          K.handle("host.actions", %{"outcome" => %{"status" => status, "value" => %{}}}, state)
        )
    end
  end

  test "malformed invocations and source proof tampering cannot reach publication" do
    {:ok, state} = K.init(options())

    for args <- [
          Map.put(attrs(), "origin", "interactive_operator"),
          %{attrs() | "text" => String.duplicate("x", 2049)},
          %{attrs() | "category" => "pin"}
        ] do
      {%{"status" => "refused"}, _} =
        value(K.handle("invoke.tool", %{"id" => "capture", "arguments" => args}, state))
    end

    {_, state} =
      request(K.handle("invoke.tool", %{"id" => "capture", "arguments" => attrs()}, state))

    {_, state} = request(respond(state, page("interactive_operator")))

    {%{"status" => "refused", "code" => "source_refused"}, _} =
      value(
        respond(state, %{
          quote_receipt(page("interactive_operator"))
          | "quote_sha256" => Ipse.JSON.sha256("forged")
        })
      )
  end
  end
  result = ExUnit.run()
  if result.failures > 0, do: System.halt(1)
  """

  test "bounded capture continuations run in an independent VM" do
    sdk = Application.app_dir(:ipse, "ebin")
    paths = Path.wildcard(Path.join(Path.dirname(Path.dirname(sdk)), "*/ebin"))
    args = ["--erl", "+S 2:2"] ++ Enum.flat_map(paths, &["-pa", &1]) ++ ["-e", @suite]
    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "6 passed"
    refute :code.is_loaded(IpseKnowledge.Profiles)
    refute :code.is_loaded(IpseKnowledge.Knowledge)
  end
end
