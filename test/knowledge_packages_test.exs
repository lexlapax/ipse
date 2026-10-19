defmodule IpseKnowledge.PackagesIsolationTest do
  use ExUnit.Case, async: false

  @suite ~S"""
  ExUnit.start(autorun: false)
  for file <- ~w(evidence profiles store/state store/mcp_cas store adapters corpus research graph) do
    Code.require_file(Path.join("extensions/knowledge/src", file <> ".ex"))
  end

  defmodule DomainPackagesSuite do
    use ExUnit.Case, async: false

    test "three independent descriptors have closed command catalogs" do
      for {module, commands} <- [
        {IpseKnowledge.Corpus, ~w(source query index)},
        {IpseKnowledge.Research, ~w(investigate ledger)},
        {IpseKnowledge.Graph, ~w(source extract query)}
      ] do
        descriptor = module.describe()
        assert descriptor["sdk"] == 1
        assert Enum.map(descriptor["exports"]["commands"], & &1["id"]) == commands
        assert length(descriptor["exports"]["tools"]) == 1
        assert descriptor["exports"]["services"] == []
      end
    end

    test "source action union rejects supplied authority before a host call" do
      state = %{resolved: %{}, phase: :idle}
      args = %{"store" => "notes", "action" => "forget",
        "args" => %{"source_id" => "dev:chair", "expected_revision" => 1,
          "origin" => %{"kind" => "fetch", "receipt" => "forged"}}}
      assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
        IpseKnowledge.Corpus.handle("invoke.command", %{"id" => "source", "arguments" => args}, state)
    end

    test "offline research returns cited provided evidence with no host action" do
      {:ok, state} = IpseKnowledge.Research.init(offline_options())
      source = %{"source_id" => "dev:locks", "generation" => 1, "title" => "Locks",
        "text" => "Session lock files remain on disk. Releasing the OS lock preserves inode identity.",
        "uri" => "local:locks", "observed_at_ms" => 1_700_000_000_000,
        "event_at_ms" => nil, "expires_at_ms" => nil}
      assert {:ok, %{"kind" => "result", "value" => result}, _} =
        IpseKnowledge.Research.handle("invoke.command",
          %{"id" => "investigate", "arguments" => investigation([source])}, state)
      assert result["status"] == "ok"
      assert result["evidence"] != []
      assert result["coverage"]["bytes"] == byte_size(source["text"])
      assert Enum.all?(result["evidence"], fn c ->
        c["citation"]["origin"]["kind"] == "provided" and
          c["citation"]["origin"]["receipt"] == nil
      end)
    end

    test "research selects current time after capture and keeps genuinely future sources excluded" do
      alias IpseKnowledge.{Adapters, Evidence, Research}
      uri = "fixture:captured"
      text = "Session lock files remain on disk."
      resolved = %{"options" => %{"fetch" => %{"web" => %{"kind" => "mcp",
        "binding" => "fetcher", "contract" => "fetch-v1"}}}}
      {:call, _request, continuation} = Adapters.start(resolved, :fetch,
        %{"profile" => "web", "uri" => uri, "timeout_ms" => 30_000})
      for {observed, expected} <- [{1, "ok"}, {System.system_time(:millisecond) + 86_400_000, "abstain"}] do
        ctx = %{args: investigation([]) |> Map.put("fetch", "web"), at: 0,
          profile: %{"kind" => "mcp"}, fetch_profile: %{}, sources: [], receipts: [],
          hits: [], remaining: [%{"source_id" => "remote:locks", "uri" => uri, "title" => "Locks"}],
          bytes: 0, started: System.monotonic_time(:millisecond)}
        state = %{resolved: resolved, phase: :fetch, ctx: ctx, cont: continuation}
        data = %{"version" => 1, "contract" => "fetch-v1", "status" => "ok",
          "requested_uri" => uri, "observed_uri" => uri, "media_type" => "text/plain",
          "observed_at_ms" => observed, "text" => text, "body_sha256" => Evidence.sha256(text),
          "complete" => true, "start_byte" => 0, "end_byte" => byte_size(text)}
        encoded = JSON.encode!(data)
        descriptor = %{"version" => 1, "kind" => "mcp.text", "operation_id" => String.duplicate("3",32),
          "source_sha256" => Evidence.sha256(encoded), "byte_count" => byte_size(encoded)}
        {:ok, %{"kind" => "host_call"}, reading} = Research.handle("host.actions",
          %{"outcome" => %{"status" => "ok", "value" => descriptor}}, state)
        page = Map.take(descriptor, ~w(version kind operation_id source_sha256))
          |> Map.merge(%{"offset" => 0, "text" => encoded, "complete" => true, "next" => nil})
        {:ok, %{"kind" => "result", "value" => result}, _} = Research.handle("host.actions",
          %{"outcome" => %{"status" => "ok", "value" => page}}, reading)
        assert result["status"] == expected
        assert result["coverage"]["as_of_ms"] > 0
        assert result["coverage"]["bytes"] == byte_size(text)
      end
    end

    test "provided source and ledger cannot self-promote fetched or native receipt" do
      {:ok, state} = IpseKnowledge.Research.init(offline_options())
      source = %{"source_id" => "fake", "generation" => 1, "title" => "Fake",
        "text" => "fabricated", "uri" => "local:fake", "observed_at_ms" => 1,
        "event_at_ms" => nil, "expires_at_ms" => nil,
        "origin" => %{"kind" => "fetch", "receipt" => %{"operation_id" => "fake"}}}
      assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
        IpseKnowledge.Research.handle("invoke.command",
          %{"id" => "investigate", "arguments" => investigation([source])}, state)
      bad = %{"action" => "inspect", "args" => %{"ledger" => [%{"claim" => "x",
        "basis" => [], "label" => "supported", "native_receipt" => true}]}}
      assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
        IpseKnowledge.Research.handle("invoke.command",
          %{"id" => "ledger", "arguments" => bad}, state)
    end

    test "unknown result stops and forged vector page cannot complete" do
      assert {:stop, :unknown_effect} =
        IpseKnowledge.Adapters.resume(%{phase: :embedding_read}, %{"status" => "unknown"})
      descriptor = %{"version" => 2, "kind" => "embedding.f32le", "encoding" => "float32le.base64",
        "operation_id" => "op", "source_sha256" => String.duplicate("a", 64), "dimensions" => 1,
        "vector_count" => 1}
      state = %{phase: :embedding_read, descriptor: descriptor, vector_index: 0, offset: 0,
        bytes: <<>>, input_hash: nil, reads: 0, inputs: [%{"chunk_id" => String.duplicate("b", 64),
          "text" => "a"}], raw_hashes: [String.duplicate("c", 64)], vectors: [],
        inference: %{"reported_model" => "model"}, host_profile: "emb"}
      page = %{"version" => 2, "kind" => "embedding.f32le", "encoding" => "float32le.base64",
        "operation_id" => "different", "source_sha256" => descriptor["source_sha256"],
        "vector_index" => 0, "offset" => 0, "dimensions" => 1,
        "input_sha256" => String.duplicate("d", 64), "vector_sha256" => String.duplicate("e", 64),
        "values" => Base.encode64(<<1.0::float-little-32>>), "complete" => true, "next" => nil}
      assert {:done, {:error, :invalid_embedding_result, %{}}} =
        IpseKnowledge.Adapters.resume(state, %{"status" => "ok", "value" => page})
    end

    test "embedding initializes reader state and reconstructs two complete4096 vectors" do
      alias IpseKnowledge.{Adapters, Evidence}
      resolved=%{"options"=>%{"embedding"=>%{"encoder"=>%{"kind"=>"embedding","profile"=>"host_encoder"}}}}
      inputs=for index<-0..1,do: %{"chunk_id"=>Evidence.sha256("chunk#{index}"),"text"=>"input#{index}"}
      {:call,request,cont}=Adapters.start(resolved,:embed,%{"profile"=>"encoder","inputs"=>inputs})
      assert request["inputs"]==["input0","input1"]
      descriptor=%{"version"=>2,"kind"=>"embedding.f32le","encoding"=>"float32le.base64",
        "operation_id"=>String.duplicate("1",32),"source_sha256"=>String.duplicate("a",64),
        "vector_count"=>2,"dimensions"=>4096}
      inference=%{"result"=>descriptor,"profile"=>"host_encoder","reported_model"=>"fixture4096","usage"=>%{}}
      first=Adapters.resume(cont,%{"status"=>"ok","value"=>inference})
      result=Enum.reduce(1..12,first,fn _,{:call,read,continuation}->
        index=read["vector_index"]; offset=read["offset"]; count=min(768,4096-offset)
        bytes=for n<-0..4095,into: <<>>,do: <<(if n==index,do: 1.0,else: 0.0)::little-float-size(32)>>
        complete=offset+count==4096
        page=%{"version"=>2,"kind"=>"embedding.f32le","encoding"=>"float32le.base64",
          "operation_id"=>descriptor["operation_id"],"source_sha256"=>descriptor["source_sha256"],
          "vector_index"=>index,"offset"=>offset,"dimensions"=>4096,
          "input_sha256"=>Evidence.sha256("opaque#{index}"),"vector_sha256"=>Evidence.sha256(bytes),
          "values"=>Base.encode64(binary_part(bytes,offset*4,count*4)),
          "complete"=>complete,"next"=>if(complete,do: nil,else: offset+count)}
        Adapters.resume(continuation,%{"status"=>"ok","value"=>page})
      end)
      assert {:done,{:ok,value}}=result
      assert length(value["vectors"])==2
      assert Enum.all?(value["vectors"],&(length(&1["values"])==4096 and Evidence.valid_vector?(&1)))
      assert value["receipt"]["raw_input_sha256"]==Enum.map(inputs,&Evidence.sha256(&1["text"]))
      assert Enum.map(value["vectors"],& &1["input_sha256"])==Enum.map(0..1,&Evidence.sha256("opaque#{&1}"))
    end

    test "query-v1 emits only the selected binding and exact bounded arguments" do
      {:call, request, _} = query_adapter()
      assert request["op"] == "mcp.call"
      assert request["binding"] == "query_tool"
      assert Map.keys(request["arguments"]) |> Enum.sort() ==
        ~w(as_of_ms contract partition query request_id top_k version)
      assert request["arguments"]["partition"] == "bench"
      assert request["arguments"]["request_id"] =~ ~r/\A[0-9a-f]{32}\z/
      assert request["arguments"]["query"] == "lock files"
    end

    test "query-v1 accepts exact refs and carries actual query action counts" do
      {:call, request, continuation} = query_adapter()
      ref = remote_ref(source())
      result = complete_query(continuation, remote_data(request, [ref]))
      assert {:done, {:ok, value}} = result
      assert value["refs"] == [ref]
      assert value["store_generation"] == 3
      assert value["effects_used"] == 1
      assert value["reads_used"] == 1
      assert value["coverage"]["scanned_chunks"] == 1

      {:call, empty_request, empty_continuation} = query_adapter()
      assert {:done, {:ok, %{"refs" => [], "effects_used" => 1, "reads_used" => 1}}} =
        complete_query(empty_continuation, remote_data(empty_request, []))
    end

    test "query-v1 rejects forged echoes, hashes, generations and partial responses" do
      {:call, request, continuation} = query_adapter()
      valid = remote_data(request, [remote_ref(source())])
      bad_ref = hd(valid["refs"])

      forged = [
        Map.put(valid, "request_id", String.duplicate("f", 32)),
        Map.put(valid, "partition", "other"),
        Map.put(valid, "complete", false),
        put_in(valid, ["refs", Access.at(0), "source_key"], String.duplicate("f", 64)),
        put_in(valid, ["refs", Access.at(0), "generation"], 0),
        Map.put(valid, "refs", [bad_ref, bad_ref]),
        Map.put(valid, "status", "refused")
      ]

      for response <- forged do
        assert {:done, {:error, :invalid_remote_result, %{}}} =
          complete_query(continuation, response)
      end
    end

    test "query-v1 no-replay unknown and incompatible store refuse before remote action" do
      {:call, _request, continuation} = query_adapter()
      assert {:stop, :unknown_effect} =
        IpseKnowledge.Adapters.resume(continuation, %{"status" => "unknown"})

      state = %{resolved: query_resolved("other"), phase: :idle,
        ctx: nil, cont: nil, pending: nil}
      assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
        IpseKnowledge.Corpus.handle("invoke.command",
          %{"id" => "query", "arguments" => query_args()}, state)

      valid_state = %{state | resolved: query_resolved()}
      assert {:ok, %{"kind" => "host_call", "request" => request}, _} =
        IpseKnowledge.Corpus.handle("invoke.command",
          %{"id" => "query", "arguments" => query_args()}, valid_state)
      assert request["op"] == "mcp.call"
      assert request["binding"] == "query_tool"
    end

    test "remote ranking refuses stale and historical sources as a whole" do
      valid = source()
      ref = remote_ref(valid)
      assert {:ok, %{"evidence" => [_]}} =
        IpseKnowledge.Evidence.rank_remote([valid], [ref], 1, 10)

      expired = %{valid | "expires_at_ms" => 10}
      assert {:error, :invalid_remote_selection} =
        IpseKnowledge.Evidence.rank_remote([expired], [ref], 1, 10)

      historical = put_in(valid, ["origin", "historical"], true)
      assert {:error, :invalid_remote_selection} =
        IpseKnowledge.Evidence.rank_remote([historical], [ref], 1, 10)

      assert {:error, :invalid_remote_selection} =
        IpseKnowledge.Evidence.rank_remote([], [ref], 1, 10)

      assert {:ok, %{"evidence" => []}} =
        IpseKnowledge.Evidence.rank_remote([], [], 1, 10)
    end

    defp query_resolved(store_partition \\ "bench") do
      %{"options" => %{
        "stores" => %{"remote" => %{"kind" => "mcp_cas", "binding" => "cas_tool",
          "partition" => store_partition, "contract" => "ipse-cas-v1"}},
        "retrieval" => %{"remote" => %{"kind" => "mcp_query", "binding" => "query_tool",
          "partition" => "bench", "contract" => "query-v1"}},
        "rerank" => %{}
      }}
    end

    defp query_args do
      %{"store" => "remote", "retrieval" => "remote", "rerank" => nil,
        "query" => "lock files", "top_k" => 1, "as_of_ms" => 10}
    end

    defp query_adapter do
      IpseKnowledge.Adapters.start(query_resolved(), :query_refs,
        %{"profile" => "remote", "query" => "lock files", "top_k" => 1,
          "as_of_ms" => 10})
    end

    defp source do
      {:ok, value} = IpseKnowledge.Evidence.source(%{
        "source_id" => "local:locks", "partition" => "bench", "generation" => 1,
        "title" => "Locks", "text" => "Session lock files remain on disk.",
        "uri" => "local:locks", "observed_at_ms" => 1,
        "event_at_ms" => nil, "expires_at_ms" => nil,
        "origin" => %{"kind" => "provided", "store_profile" => "remote",
          "partition_or_scope" => "bench", "receipt" => nil, "historical" => false}
      })
      value
    end

    defp remote_ref(source) do
      {:ok, [chunk]} = IpseKnowledge.Evidence.chunks(source)
      Map.take(source, ~w(source_id source_key generation content_sha256))
      |> Map.merge(%{"chunk_id" => chunk["chunk_id"], "score" => 0.75})
    end

    defp remote_data(request, refs) do
      args = request["arguments"]
      %{"version" => 1, "contract" => "query-v1", "partition" => args["partition"],
        "request_id" => args["request_id"], "status" => "ok", "generation" => 3,
        "algorithm" => "remote.1", "algorithm_version" => 1,
        "scanned_sources" => 1, "scanned_chunks" => 1, "complete" => true,
        "refs" => refs}
    end

    defp complete_query(continuation, response) do
      text = JSON.encode!(response)
      source_hash = IpseKnowledge.Evidence.sha256(text)
      descriptor = %{"version" => 1, "kind" => "mcp.text", "operation_id" => String.duplicate("2",32),
        "source_sha256" => source_hash, "byte_count" => byte_size(text)}
      {:call, _read, read_cont} = IpseKnowledge.Adapters.resume(continuation,
        %{"status" => "ok", "value" => descriptor})
      IpseKnowledge.Adapters.resume(read_cont, %{"status" => "ok", "value" => %{
        "version" => 1, "kind" => "mcp.text", "operation_id" => String.duplicate("2",32),
        "source_sha256" => source_hash, "offset" => 0, "text" => text,
        "complete" => true, "next" => nil
      }})
    end

    defp offline_options do
      %{"version" => 1, "stores" => %{},
        "search" => %{"local" => %{"kind" => "provided", "version" => 1}},
        "fetch" => %{"local" => %{"kind" => "provided", "version" => 1}},
        "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
        "embedding" => %{}, "rerank" => %{}, "extraction" => %{}}
    end

    defp investigation(sources) do
      %{"search" => "local", "fetch" => "local", "retrieval" => "words",
        "rerank" => nil, "query" => "lock files inode",
        "limits" => %{"max_sources" => 1, "max_body_bytes" => 49_152, "timeout_ms" => 30_000},
        "sources" => sources}
    end
  end

  result = ExUnit.run()
  System.halt(if(result.failures == 0, do: 0, else: 1))
  """

  test "packages run in a separate VM without loading domain modules into host" do
    assert Code.ensure_loaded?(Ipse.Extension)
    sdk_ebin = Ipse.Extension |> :code.which() |> to_string() |> Path.dirname()
    root = Path.expand("..", __DIR__)
    elixir = System.find_executable("elixir")
    assert is_binary(elixir)

    {output, status} =
      System.cmd(elixir, ["-pa", sdk_ebin, "-e", @suite], cd: root, stderr_to_stdout: true)

    assert status == 0, output
    refute Code.ensure_loaded?(IpseKnowledge.Corpus)
    refute Code.ensure_loaded?(IpseKnowledge.Research)
    refute Code.ensure_loaded?(IpseKnowledge.Graph)
  end
end
