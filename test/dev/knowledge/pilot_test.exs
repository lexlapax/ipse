Code.require_file("../../../dev/knowledge/pilot.exs", __DIR__)

defmodule Ipse.Development.Knowledge.PilotTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Knowledge.Pilot

  test "finite sessions use the selected main route and perform no task effects" do
    request = fn config, messages, tools, emit ->
      assert config.provider == :chatgpt
      assert config.max_output_tokens == nil
      assert tools == Pilot.tool()
      refute Enum.any?(tools, &(get_in(&1, ["function", "name"]) == "shell"))
      assert List.last(messages)["role"] == "user"
      emit.({:text, "acknowledged"})
      {:ok, %{"role" => "assistant", "content" => "acknowledged"}, %{}}
    end

    assert {:ok, records, 60} = Pilot.run(%{provider: :chatgpt, max_output_tokens: nil}, request)
    assert length(records) == 60
    assert Enum.all?(records, &(&1.published == 0 and is_integer(&1.ttft_us)))
    assert Enum.frequencies_by(records, & &1.session) == %{1 => 20, 2 => 20, 3 => 20}
  end

  test "capture is source-bound and at most one continuation is attempted per turn" do
    request = fn _, messages, _, _ ->
      case List.last(messages)["role"] do
        "user" ->
          source = JSON.decode!(List.last(messages)["content"])

          args = %{
            "items" => [
              %{
                "source_id" => source["source_id"],
                "quote" => source["text"],
                "text" => source["text"],
                "category" => "automatic"
              }
            ]
          }

          {:ok,
           %{
             "role" => "assistant",
             "tool_calls" => [
               %{
                 "id" => "call",
                 "type" => "function",
                 "function" => %{"name" => "knowledge_capture", "arguments" => JSON.encode!(args)}
               }
             ]
           }, %{}}

        "tool" ->
          assert JSON.decode!(List.last(messages)["content"])["published"] == 0
          {:ok, %{"role" => "assistant", "content" => "done"}, %{}}
      end
    end

    assert {:ok, records, 120} = Pilot.run(%{provider: :chatgpt}, request)
    assert Enum.count(records, & &1.continuation) == 60
    assert Enum.all?(records, &is_nil(&1.ttft_us))

    assert Enum.all?(Enum.reject(records, & &1.continuation), fn r ->
             assert [%{valid_source: true}] = r.proposals
           end)
  end

  test "an unselected tool stops before any simulated continuation" do
    request = fn _, _, _, _ ->
      {:ok,
       %{
         "role" => "assistant",
         "tool_calls" => [
           %{
             "id" => "call",
             "type" => "function",
             "function" => %{"name" => "shell", "arguments" => "{}"}
           }
         ]
       }, %{}}
    end

    assert {:error, :pilot_call_contract_refused, [first], 1} =
             Pilot.run(%{provider: :chatgpt}, request)

    assert first.proposals == [%{valid_source: false, reason: "invalid_capture_call"}]
  end

  test "multiple batches, duplicate JSON keys and malformed selected calls stop after one request" do
    call = %{
      "id" => "call",
      "type" => "function",
      "function" => %{"name" => "knowledge_capture", "arguments" => "{\"items\":[]}"}
    }

    for calls <- [
          [call, %{call | "id" => "second"}],
          [put_in(call, ["function", "arguments"], "{\"items\":[],\"items\":[]}")],
          [
            put_in(
              call,
              ["function", "arguments"],
              "{\"items\":" <>
                String.duplicate("[", 17) <> "0" <> String.duplicate("]", 17) <> "}"
            )
          ],
          [Map.put(call, "id", "")],
          [put_in(call, ["function", "extra"], true)],
          [
            put_in(
              call,
              ["function", "arguments"],
              JSON.encode!(%{"items" => List.duplicate(%{}, 9)})
            )
          ],
          %{"not" => "a list"}
        ] do
      request = fn _, _, _, _ -> {:ok, %{"role" => "assistant", "tool_calls" => calls}, %{}} end

      assert {:error, :pilot_call_contract_refused, [_], 1} =
               Pilot.run(%{provider: :chatgpt}, request)
    end
  end

  test "a repeated selected capture is not executed as a second continuation" do
    call = %{
      "id" => "call",
      "type" => "function",
      "function" => %{"name" => "knowledge_capture", "arguments" => "{\"items\":[]}"}
    }

    request = fn _, _, _, _ -> {:ok, %{"role" => "assistant", "tool_calls" => [call]}, %{}} end

    assert {:error, :extra_continuation_refused, [_, _], 2} =
             Pilot.run(%{provider: :chatgpt}, request)
  end

  test "false tool-call fields are malformed in initial and continuation responses" do
    first = fn _, _, _, _ -> {:ok, %{"role" => "assistant", "tool_calls" => false}, %{}} end

    assert {:error, :pilot_call_contract_refused, [_], 1} =
             Pilot.run(%{provider: :chatgpt}, first)

    next = fn _, messages, _, _ ->
      if List.last(messages)["role"] == "user" do
        call = %{
          "id" => "call",
          "type" => "function",
          "function" => %{"name" => "knowledge_capture", "arguments" => "{\"items\":[]}"}
        }

        {:ok, %{"role" => "assistant", "tool_calls" => [call]}, %{}}
      else
        {:ok, %{"role" => "assistant", "tool_calls" => false}, %{}}
      end
    end

    assert {:error, :extra_continuation_refused, [_, _], 2} =
             Pilot.run(%{provider: :chatgpt}, next)
  end

  test "selected tighter request limits survive and invalid limits cause zero dispatch" do
    request = fn config, _, _, _ ->
      assert config.timeout_ms == 5_000
      assert config.max_response_bytes == 16_384
      {:ok, %{"role" => "assistant", "content" => "done"}, %{}}
    end

    assert {:ok, _, 60} =
             Pilot.run(
               %{provider: :chatgpt, timeout_ms: 5_000, max_response_bytes: 16_384},
               request
             )

    never = fn _, _, _, _ -> flunk("must refuse before dispatch") end

    for extra <- [%{timeout_ms: 0}, %{timeout_ms: "60000"}, %{max_response_bytes: -1}] do
      assert {:error, :pilot_configuration_refused, [], 0} =
               Pilot.run(Map.merge(%{provider: :chatgpt}, extra), never)
    end
  end

  test "local history refusal charges no nonexistent request" do
    request = fn _, _, _, _ ->
      {:ok, %{"role" => "assistant", "content" => String.duplicate("x", 100_000)}, %{}}
    end

    assert {:error, :pilot_limit, records, count} = Pilot.run(%{provider: :chatgpt}, request)
    assert count == 4
    assert length(records) == count

    assert {:error, :provider_request_failed, [], 1} =
             Pilot.run(%{provider: :chatgpt}, fn _, _, _, _ -> {:error, :failed} end)
  end

  test "provider or budget mismatch causes zero dispatch" do
    request = fn _, _, _, _ -> flunk("no request authorized") end

    for config <- [
          %{provider: :openai},
          %{provider: :chatgpt, budget: %{}},
          %{provider: :chatgpt, max_output_tokens: 1}
        ] do
      assert {:error, :pilot_configuration_refused, [], 0} = Pilot.run(config, request)
    end
  end

  test "optional audit retains exact synthetic candidates without widening public progress" do
    candidate_text = "PRIVATE_SYNTHETIC_CANDIDATE"
    request = audit_request(candidate_text)
    owner = self()

    audit = fn event ->
      send(owner, {:candidate_audit, event})
      :ok
    end

    assert {:ok, records, 120} =
             Pilot.run(%{provider: :chatgpt}, request, fn _ -> :ok end, audit)

    refute inspect(records) =~ candidate_text
    assert_receive {:candidate_audit, first}
    assert first["session"] == 1 and first["request"] == 1
    assert first["source"] == hd(Pilot.cases())
    assert [%{"text" => ^candidate_text} = item] = first["candidates"]
    assert item["quote"] == first["source"]["text"]
    assert first["published"] == 0
    refute inspect(first) =~ "UNRELATED_ASSISTANT_CONTENT"

    rest =
      for _ <- 1..59,
          do:
            (
              assert_receive {:candidate_audit, event}
              event
            )

    assert length(rest) == 59
    refute_receive {:candidate_audit, _}
  end

  test "audit failure stops after the observed request without continuation or replay" do
    for audit <- [
          fn _ -> {:error, :disk_full} end,
          fn _ -> raise "synthetic audit failure" end,
          fn _ -> throw(:audit_stopped) end
        ] do
      assert {:error, :pilot_audit_failed, [record], 1} =
               Pilot.run(
                 %{provider: :chatgpt},
                 audit_request("candidate"),
                 fn _ -> :ok end,
                 audit
               )

      assert record.request == 1 and not record.continuation
    end

    never = fn _, _, _, _ -> flunk("invalid audit must refuse before dispatch") end

    assert {:error, :pilot_configuration_refused, [], 0} =
             Pilot.run(%{provider: :chatgpt}, never, fn _ -> :ok end, :invalid)
  end

  test "audit records omissions but never retains a source-invalid candidate" do
    owner = self()
    empty = fn _, _, _, _ -> {:ok, %{"role" => "assistant", "content" => "done"}, %{}} end

    audit = fn event ->
      send(owner, {:empty_audit, event})
      :ok
    end

    assert {:ok, _, 60} = Pilot.run(%{provider: :chatgpt}, empty, fn _ -> :ok end, audit)

    for _ <- 1..60 do
      assert_receive {:empty_audit, %{"candidates" => []}}
    end

    valid = audit_request("candidate")

    invalid = fn config, messages, tools, emit ->
      {:ok, assistant, usage} = valid.(config, messages, tools, emit)
      [call] = assistant["tool_calls"]
      args = JSON.decode!(call["function"]["arguments"])
      args = put_in(args, ["items", Access.at(0), "source_id"], "unrelated-source")
      call = put_in(call, ["function", "arguments"], JSON.encode!(args))
      {:ok, %{assistant | "tool_calls" => [call]}, usage}
    end

    assert {:error, :pilot_call_contract_refused, [_], 1} =
             Pilot.run(%{provider: :chatgpt}, invalid, fn _ -> :ok end, fn _ ->
               flunk("invalid candidate must not reach the audit sink")
             end)
  end

  test "rejected model category values cannot escape through public progress" do
    marker = "PRIVATE_SYNTHETIC_INVALID_CATEGORY"
    valid = audit_request("candidate")
    owner = self()

    for category <- [marker, %{"text" => marker}] do
      invalid = fn config, messages, tools, emit ->
        {:ok, assistant, usage} = valid.(config, messages, tools, emit)
        [call] = assistant["tool_calls"]
        args = JSON.decode!(call["function"]["arguments"])
        args = put_in(args, ["items", Access.at(0), "category"], category)
        call = put_in(call, ["function", "arguments"], JSON.encode!(args))
        {:ok, %{assistant | "tool_calls" => [call]}, usage}
      end

      assert {:error, :pilot_call_contract_refused, [record], 1} =
               Pilot.run(%{provider: :chatgpt}, invalid, fn row ->
                 send(owner, {:progress, row})
               end)

      assert_receive {:progress, ^record}
      assert [%{valid_source: false, category: nil}] = record.proposals
      refute inspect(record) =~ marker
    end
  end

  test "audit files use a new private directory and reject overwrite and oversized records" do
    directory = Path.join(System.tmp_dir!(), "ipse-pilot-audit-" <> Ipse.Usage.id())
    on_exit(fn -> File.rm_rf!(directory) end)
    assert {:ok, nil} = Pilot.open_audit(nil)
    assert {:ok, file} = Pilot.open_audit(directory)

    try do
      path = Path.join(directory, "candidates.jsonl")
      assert Bitwise.band(File.stat!(directory).mode, 0o777) == 0o700
      assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
      assert {:error, :pilot_audit_unavailable} = Pilot.open_audit(directory)
      assert :ok = Pilot.write_audit(file, %{"kind" => "synthetic", "published" => 0})
      before = File.read!(path)

      assert Jason.decode!(String.trim_trailing(before)) == %{
               "kind" => "synthetic",
               "published" => 0
             }

      assert {:error, :pilot_audit_failed} =
               Pilot.write_audit(file, %{"text" => String.duplicate("x", 65_537)})

      assert File.read!(path) == before
    after
      File.close(file)
    end
  end

  defp audit_request(text) do
    fn _, messages, _, _ ->
      if List.last(messages)["role"] == "tool" do
        {:ok, %{"role" => "assistant", "content" => "done"}, %{}}
      else
        source = JSON.decode!(List.last(messages)["content"])

        {:ok,
         %{
           "role" => "assistant",
           "content" => "UNRELATED_ASSISTANT_CONTENT",
           "tool_calls" => [
             %{
               "id" => "audit-capture",
               "type" => "function",
               "function" => %{
                 "name" => "knowledge_capture",
                 "arguments" =>
                   JSON.encode!(%{
                     "items" => [
                       %{
                         "source_id" => source["source_id"],
                         "quote" => source["text"],
                         "text" => text,
                         "category" => "automatic"
                       }
                     ]
                   })
               }
             }
           ]
         }, %{}}
      end
    end
  end
end
