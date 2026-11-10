Code.require_file("../../../dev/knowledge/collection_document_peaks.ex", __DIR__)

defmodule Ipse.Development.CollectionDocumentPeaksTest do
  use ExUnit.Case, async: true
  @moduletag :document_peaks

  alias Ipse.Development.CollectionDocumentPeaks, as: Peaks

  # Stands in for real Sessions over native storage. Every invocation grows a
  # counted journal and answers the way the public commands are expected to;
  # `faults` replace the answer of the first invocation each one matches.
  defmodule Stub do
    def new(faults \\ [], grow \\ {1_000, 3}) do
      %{
        faults: faults,
        grow: grow,
        opened: 0,
        journal: %{"bytes" => 0, "events" => 0},
        job: nil,
        phase: nil,
        log: []
      }
    end

    def open(ctx, phase, role) do
      id = "session-#{ctx.opened + 1}"

      {:ok, id,
       %{
         ctx
         | opened: ctx.opened + 1,
           phase: phase,
           journal: %{"bytes" => 0, "events" => 0},
           log: [{:open, id, phase, role} | ctx.log]
       }}
    end

    def close(ctx), do: {:ok, ctx.journal, %{ctx | log: [:close | ctx.log]}}

    def groups(_, sources), do: {:ok, Enum.chunk_every(Enum.to_list(0..(sources - 1)), 8)}

    def selection(_, phase), do: %{"selection" => phase}

    def invoke(ctx, command, arguments) do
      ctx = %{ctx | log: [{:invoke, command, arguments} | ctx.log]}

      case Enum.split_while(ctx.faults, fn {match, _} -> not match.(command, arguments) end) do
        {kept, [{_, result} | rest]} ->
          {result, observation(ctx), %{ctx | faults: kept ++ rest}}

        {_, []} ->
          {bytes, events} = ctx.grow

          journal = %{
            "bytes" => ctx.journal["bytes"] + bytes,
            "events" => ctx.journal["events"] + events
          }

          {result, ctx} = answer(%{ctx | journal: journal}, command, arguments)
          {result, observation(ctx), ctx}
      end
    end

    defp observation(ctx) do
      calls = Enum.count(ctx.log, &match?({:invoke, _, _}, &1))

      %{
        "session" => "session-#{ctx.opened}",
        "wall_us" => 10,
        "approvals" => 1,
        "host_actions" => %{"collection" => 2, "embedding" => 1, "total" => 3},
        "journal" => ctx.journal,
        "collection" =>
          Map.new(Peaks.collection_fields(), &{&1, calls})
          |> Map.put("allocated_bytes", 4_096 * calls),
        "collection_limits" => %{"max_records" => 1},
        "staged" => %{"allocated_bytes" => 100 + calls, "accounted_allocated_bytes" => calls}
      }
    end

    defp token(ctx, revision) do
      %{
        "id" => "job-" <> ctx.phase,
        "job_revision" => revision,
        "stages" => [],
        "write" => nil
      }
    end

    defp done(ctx, job),
      do:
        {{:ok, %{"status" => "ok", "coverage" => %{"continuation" => job}}, nil},
         %{ctx | job: job}}

    defp answer(ctx, "source", %{"action" => "put_document"}),
      do: {{:ok, %{"status" => "ok"}, nil}, ctx}

    defp answer(ctx, "lexical_index", %{"continuation" => nil} = arguments) do
      next = %{"id" => "lexical_index", "arguments" => %{arguments | "continuation" => "page"}}
      {{:ok, %{"status" => "partial", "continuation" => next}, nil}, ctx}
    end

    defp answer(ctx, "lexical_index", _), do: {{:ok, %{"status" => "ok"}, nil}, ctx}

    defp answer(ctx, "source", %{"args" => %{"input" => %{"mode" => mode}}})
         when mode in ~w(publish assemble) do
      calls = Enum.count(ctx.log, &match?({:invoke, _, _}, &1))
      {{:ok, %{"kind" => "explicit_fact_group"}, %{"result" => "#{mode}-#{calls}"}}, ctx}
    end

    defp answer(ctx, "source", %{"args" => %{"input" => %{"mode" => "begin"}}}),
      do: done(ctx, token(ctx, 1))

    defp answer(ctx, "generation_produce", %{"action" => "page"}),
      do: {{:ok, %{"status" => "ok"}, nil}, ctx}

    # An append first returns its own bound continuation: a write is pending.
    defp answer(
           ctx,
           "source",
           %{"args" => %{"input" => %{"mode" => "append", "continuation" => nil} = input}} =
             arguments
         ) do
      next = %{
        "id" => "source",
        "arguments" => %{
          arguments
          | "args" => %{"input" => %{input | "continuation" => "bound"}}
        }
      }

      {{:ok, %{"status" => "partial", "continuation" => next}, nil}, ctx}
    end

    defp answer(ctx, "source", %{"args" => %{"input" => %{"mode" => "append"}}}),
      do: done(ctx, token(ctx, ctx.job["job_revision"] + 1))

    defp answer(ctx, "generation_job", %{"action" => "inspect"}), do: done(ctx, ctx.job)

    defp answer(ctx, "generation_job", %{"action" => "finalize_paged"}),
      do: {{:ok, %{"status" => "ok"}, nil}, ctx}
  end

  @refusal {:journal_refusal, "cannot hold another worst-case document Collection invocation"}

  defp options(sources, handoff \\ :refusal),
    do: %{
      sources: sources,
      out: "unused",
      handoff: handoff,
      artifact: nil,
      keep_home: false,
      max_steps: 100_000
    }

  defp drive(options, faults, plan \\ Peaks.journal_plan(), grow \\ {1_000, 3}) do
    {:ok, rows} = Agent.start_link(fn -> [] end)
    sink = fn row -> Agent.update(rows, &[row | &1]) end
    {summary, ctx} = Peaks.drive(options, Stub, Stub.new(faults, grow), sink, plan)
    trace = Enum.reverse(Agent.get(rows, & &1))
    Agent.stop(rows)
    {summary, trace, Enum.reverse(ctx.log)}
  end

  defp mode?(arguments, mode), do: get_in(arguments, ["args", "input", "mode"]) == mode

  defp invocations(trace, step),
    do: Enum.filter(trace, &(&1["record"] == "invocation" and &1["step"] == step))

  describe "arguments" do
    test "accepts the ladder sizes and expands the evidence directory" do
      assert {:ok, parsed} = Peaks.parse(~w(--sources 64 --out _build/document-peaks-64))

      assert parsed == %{
               sources: 64,
               out: Path.expand("_build/document-peaks-64"),
               handoff: :planned,
               artifact: nil,
               keep_home: false,
               max_steps: 100_000
             }

      assert {:ok, %{sources: 1}} = Peaks.parse(~w(--sources 1 --out _build/a))

      assert {:ok, %{sources: 1000, handoff: :group, keep_home: true}} =
               Peaks.parse(~w(--sources 1000 --out _build/a --handoff group --keep-home))
    end

    test "refuses sizes, directories and options outside the contract" do
      for argv <- [
            ~w(--out _build/a),
            ~w(--sources 0 --out _build/a),
            ~w(--sources 1001 --out _build/a),
            ~w(--sources many --out _build/a),
            ~w(--sources 8),
            ~w(--sources 8 --out /tmp/a),
            ~w(--sources 8 --out _build),
            ~w(--sources 8 --out _build/../a),
            ~w(--sources 8 --out _build/a --handoff never),
            ~w(--sources 8 --out _build/a --max-steps 0),
            ~w(--sources 8 --out _build/a --max-steps 100001),
            ~w(--sources 8 --sources 9 --out _build/a),
            ~w(--sources 8 --out _build/a extra),
            ~w(--sources 8 --out _build/a --limit 9)
          ] do
        assert {:error, message} = Peaks.parse(argv)
        assert message =~ Peaks.usage()
      end
    end
  end

  describe "native storage gate" do
    test "never probes unless native storage was requested" do
      probe = fn -> flunk("probed without IPSE_TEST_NATIVE_STORAGE=1") end
      assert Peaks.gate(nil, probe) == {:not_run, :native_storage_not_requested}
      assert Peaks.gate("0", probe) == {:not_run, :native_storage_not_requested}
    end

    test "runs only on the supported profile" do
      assert Peaks.gate("1", fn -> :ok end) == :ok

      assert Peaks.gate("1", fn -> {:error, :transaction_filesystem_unsupported} end) ==
               {:not_run, :unsupported_storage_profile}

      assert Peaks.gate("1", fn -> {:error, :enoent} end) ==
               {:not_run, {:storage_probe_failed, {:error, :enoent}}}
    end

    test "every refusal prints a NOT RUN line" do
      for reason <- [
            :native_storage_not_requested,
            :unsupported_storage_profile,
            {:storage_probe_failed, {:error, :enoent}}
          ] do
        line = Peaks.not_run_line(reason)
        assert String.starts_with?(line, "NOT RUN: ")
        assert line =~ "IPSE_TEST_NATIVE_STORAGE=1"
        assert line =~ "no evidence was written"
        refute line =~ "\n"
      end
    end
  end

  describe "geometry" do
    test "the full size is the recorded target" do
      assert %{
               "evidence_bytes" => 20_971_520,
               "target_evidence_bytes" => 20_971_520,
               "chunks" => 10_000,
               "entities" => 5_000,
               "assertions" => 20_000
             } = Peaks.geometry(1000)
    end

    test "ladder sizes keep the per-source figures" do
      for sources <- [8, 64, 250] do
        geometry = Peaks.geometry(sources)
        assert geometry["chunks_per_source"] == 10
        assert geometry["entities_per_source"] == 5
        assert geometry["assertions_per_source"] == 20
        assert geometry["chunks"] == sources * 10
        assert abs(geometry["evidence_bytes"] - geometry["target_evidence_bytes"]) < 10
      end

      assert %{"large_sources" => 2, "evidence_bytes" => 167_772} = Peaks.geometry(8)
    end

    test "a source is ten paragraphs of the stated size and twenty facts" do
      for {ordinal, size} <- [{0, 2097}, {1, 2097}, {2, 2096}, {7, 2096}] do
        assert {:ok, files} = :zip.unzip(Peaks.document(ordinal, 8), [:memory])
        {_, xml} = List.keyfind(files, ~c"word/document.xml", 0)
        paragraphs = Regex.scan(~r/<w:t>(a+)<\/w:t>/, xml, capture: :all_but_first)
        assert Enum.map(paragraphs, fn [text] -> byte_size(text) end) == List.duplicate(size, 10)
      end

      for phase <- ~w(initial rebuild) do
        [source] = get_in(Peaks.publish_arguments(3, phase), ~w(args input value sources))
        assert length(source["facts"]) == 20
        assert length(Enum.uniq_by(source["facts"], & &1["predicate"])) == 20
        entities = Enum.flat_map(source["facts"], &[&1["subject"], &1["object"]])
        assert length(Enum.uniq(entities)) == 5

        assert Enum.all?(source["facts"], &String.ends_with?(&1["predicate"], "-replacement")) ==
                 (phase == "rebuild")
      end
    end
  end

  describe "maxima" do
    test "keep the largest value and the row that set it" do
      rows = [
        %{
          "seq" => 4,
          "journal" => %{"bytes" => 10, "events" => 2},
          "collection" => %{"allocated_bytes" => 9, "records" => 1},
          "staged" => %{"allocated_bytes" => 30}
        },
        %{
          "seq" => 5,
          "journal" => %{"bytes" => 8, "events" => 3},
          "collection" => %{"allocated_bytes" => 9, "records" => nil},
          "staged" => %{}
        }
      ]

      assert Enum.reduce(rows, %{}, &Peaks.maxima(&2, &1)) == %{
               "journal_bytes" => %{"value" => 10, "seq" => 4},
               "journal_events" => %{"value" => 3, "seq" => 5},
               "allocated_bytes" => %{"value" => 9, "seq" => 4},
               "records" => %{"value" => 1, "seq" => 4},
               "staged_allocated_bytes" => %{"value" => 30, "seq" => 4}
             }
    end

    test "an unsampled invocation changes nothing" do
      held = %{"journal_bytes" => %{"value" => 10, "seq" => 4}}
      assert Peaks.maxima(held, %{"seq" => 9, "collection_status_error" => "busy"}) == held
    end

    test "the confirmed close scan can raise a journal maximum" do
      totals =
        Peaks.new_totals()
        |> Peaks.fold(%{
          "record" => "invocation",
          "seq" => 1,
          "phase" => "initial",
          "step" => "put_document",
          "invocation" => "start",
          "wall_us" => 5,
          "host_actions" => %{"collection" => 1, "embedding" => 0, "total" => 1},
          "journal" => %{"bytes" => 10, "events" => 2}
        })
        |> Peaks.fold(%{
          "record" => "session_close",
          "seq" => 2,
          "phase" => "initial",
          "journal" => %{"bytes" => 12, "events" => 2}
        })

      assert totals["phases"]["initial"]["maxima"] == %{
               "journal_bytes" => %{"value" => 12, "seq" => 2},
               "journal_events" => %{"value" => 2, "seq" => 1}
             }
    end
  end

  describe "a complete run" do
    setup do
      {summary, trace, log} = drive(options(9), [])
      %{summary: summary, trace: trace, log: log}
    end

    test "is reported as complete with per-phase maxima", %{summary: summary} do
      assert summary["complete"]
      refute summary["maxima_are_partial"]
      assert summary["first_stop"] == nil
      assert summary["fact_route"]["route"] == "source fact_input publish, assemble and append"
      assert summary["geometry"] == Peaks.geometry(9)
      assert summary["handoff_policy"] == "refusal"
      assert summary["limits"]["changed"] == false
      assert summary["limits"]["journal"] == Peaks.journal_plan()
      assert summary["limits"]["collection"] == %{"max_records" => 1}

      # 9 puts, 2 lexical, 9 publications, 2 assemblies, 1 begin, 2 pages,
      # 4 appends and 1 finalize; the rebuild stores no source again.
      assert %{"initial" => initial, "rebuild" => rebuild} = summary["phases"]
      assert initial["complete"] and rebuild["complete"]
      refute initial["maxima_are_partial"] or rebuild["maxima_are_partial"]
      assert initial["invocations"] == 30
      assert rebuild["invocations"] == 21
      assert initial["continuation_invocations"] == 3
      assert initial["host_actions"] == %{"collection" => 60, "embedding" => 30, "total" => 90}
      assert initial["wall_us"] == 300
      assert initial["wall_us_per_host_action"] == 3

      for phase <- [initial, rebuild],
          field <-
            ~w(journal_bytes journal_events staged_allocated_bytes staged_accounted_allocated_bytes) ++
              Peaks.collection_fields() do
        assert %{"value" => value, "seq" => seq} = phase["maxima"][field]
        assert is_integer(value) and is_integer(seq)
      end

      assert initial["maxima"]["journal_bytes"]["value"] == 11_000
      assert rebuild["maxima"]["allocated_bytes"]["value"] == 4_096 * 51

      assert summary["counts"] == %{
               "sessions" => 8,
               "session_handoffs" => %{
                 "journal_refusal" => 0,
                 "planned" => 0,
                 "group" => 0,
                 "role" => 8
               },
               "continuations" => 0,
               "invocations" => 51,
               "continuation_invocations" => 6,
               "host_actions" => %{"collection" => 102, "embedding" => 51, "total" => 153}
             }

      assert summary["wall"]["total_us"] == 510
      assert summary["wall"]["per_host_action_us"] == 3

      assert Map.keys(summary["wall"]["steps"]) |> Enum.sort() ==
               Enum.sort(Peaks.steps() -- ["job_inspect"])

      assert summary["wall"]["steps"]["fact_append"] == %{
               "invocations" => 8,
               "host_actions" => 24,
               "wall_us" => 80,
               "max_wall_us" => 10,
               "wall_us_per_host_action" => 3
             }

      assert hd(Peaks.report(summary, "_build/a")) =~ "COMPLETE"
      assert Jason.decode!(Jason.encode!(summary)) == summary
    end

    test "traces every invocation in order with its samples", %{trace: trace} do
      assert Enum.map(trace, & &1["seq"]) == Enum.to_list(0..(length(trace) - 1))
      refute Enum.any?(trace, &(&1["record"] == "stop"))

      for row <- trace, row["record"] == "invocation" do
        assert row["phase"] in ~w(initial rebuild)
        assert row["step"] in Peaks.steps()
        assert row["invocation"] in ~w(start continuation)
        assert is_integer(row["wall_us"])

        assert Map.keys(row["collection"]) |> Enum.sort() ==
                 Enum.sort(Peaks.collection_fields())

        assert %{"bytes" => _, "events" => _} = row["journal"]
        assert %{"allocated_bytes" => _} = row["staged"]
      end

      assert Enum.count(trace, &(&1["record"] == "session_open")) == 8
      assert Enum.count(trace, &(&1["record"] == "session_close")) == 8

      opened =
        for %{"record" => "session_open"} = row <- trace, do: {row["session"], row["phase"]}

      closed =
        for %{"record" => "session_close"} = row <- trace, do: {row["session"], row["phase"]}

      assert closed == opened
    end

    test "publishes per source, assembles per group and appends in one Job Session", %{log: log} do
      roles = for {:open, _, phase, role} <- log, do: {phase, role}

      expected =
        for phase <- ~w(initial rebuild), role <- ~w(ingest publish assemble job) do
          {phase, role}
        end

      assert roles == expected

      puts = for {:invoke, "source", %{"action" => "put_document"} = put} <- log, do: put
      assert length(puts) == 9

      assembled =
        for {:invoke, "source", %{"data_inputs" => inputs} = arguments} <- log,
            mode?(arguments, "assemble"),
            do: length(inputs)

      assert assembled == [8, 1, 8, 1]

      # Each group embeds its page before its facts are appended, and the
      # append carries the Job token the previous step returned.
      appends =
        for {:invoke, "source", arguments} <- log,
            mode?(arguments, "append"),
            get_in(arguments, ~w(args input continuation)) == nil,
            do: get_in(arguments, ~w(args input producer job_revision))

      assert appends == [1, 2, 1, 2]

      selections =
        for {:invoke, "generation_job", %{"action" => "finalize_paged"} = finalize} <- log,
            do: {finalize["vector_selection"], finalize["continuation"]["job_revision"]}

      assert selections == [{%{"selection" => "initial"}, 3}, {%{"selection" => "rebuild"}, 3}]
    end
  end

  describe "a refusal where a write is pending" do
    setup do
      pending = fn command, arguments ->
        command == "source" and mode?(arguments, "append") and
          get_in(arguments, ~w(args input continuation)) == "bound" and
          get_in(arguments, ~w(args input producer job_revision)) == 2
      end

      {summary, trace, log} = drive(options(9), [{pending, @refusal}])
      %{summary: summary, trace: trace, log: log}
    end

    test "stops at the exact position without a handoff", %{summary: summary, log: log} do
      refute summary["complete"]
      assert summary["maxima_are_partial"]

      assert %{
               "kind" => "journal_capacity_insufficient_with_pending_write",
               "phase" => "initial",
               "role" => "job",
               "step" => "fact_append",
               "item" => 1,
               "command" => "source",
               "invocation" => "continuation",
               "session" => "session-4",
               "session_index" => 4
             } = summary["first_stop"]

      assert summary["first_stop"]["detail"] =~ "worst-case"
      assert summary["counts"]["sessions"] == 4
      assert summary["counts"]["session_handoffs"]["journal_refusal"] == 0

      # The refused continuation is the last command: nothing is retried, no
      # Session is opened for it, and the open Session is still closed.
      assert [{:invoke, "source", refused}, :close] = Enum.take(log, -2)
      assert get_in(refused, ~w(args input continuation)) == "bound"
    end

    test "never looks like a successful run", %{summary: summary, trace: trace} do
      assert %{"initial" => initial, "rebuild" => rebuild} = summary["phases"]
      refute initial["complete"]
      assert initial["maxima_are_partial"]
      assert initial["invocations"] == 29
      assert initial["maxima"]["journal_bytes"]["value"] > 0
      refute rebuild["complete"]
      assert rebuild["invocations"] == 0
      assert rebuild["maxima"] == %{}

      assert [stop] = Enum.filter(trace, &(&1["record"] == "stop"))
      assert stop["kind"] == summary["first_stop"]["kind"]

      assert List.last(invocations(trace, "fact_append"))["outcome"] ==
               "journal_capacity_insufficient"

      [head | rest] = Peaks.report(summary, "_build/a")
      assert head =~ "INCOMPLETE"
      assert head =~ "partial"
      assert Enum.any?(rest, &(&1 =~ "journal_capacity_insufficient_with_pending_write"))
    end
  end

  describe "a refusal where no write is pending" do
    test "moves a fresh command to a new Session and repeats it" do
      fifth = fn command, arguments ->
        command == "source" and
          get_in(arguments, ~w(args source_id)) == Peaks.source_id(4)
      end

      {summary, trace, log} = drive(options(9), [{fifth, @refusal}])
      assert summary["complete"]
      assert summary["first_stop"] == nil
      assert summary["counts"]["sessions"] == 9
      assert summary["counts"]["continuations"] == 1
      assert summary["counts"]["session_handoffs"]["journal_refusal"] == 1
      assert summary["phases"]["initial"]["invocations"] == 31

      puts =
        for {:invoke, "source", %{"action" => "put_document"} = put} <- log,
            do: put["args"]["source_id"]

      assert Enum.count(puts, &(&1 == Peaks.source_id(4))) == 2
      assert length(puts) == 10

      assert [%{"reason" => "journal_refusal", "role" => "ingest"}] =
               Enum.filter(trace, &(&1["record"] == "handoff" and &1["reason"] != "role"))
    end

    test "inspects the held Job before using it in the new Session" do
      second_page = fn command, arguments ->
        command == "generation_produce" and arguments["job_revision"] == 2
      end

      {summary, trace, log} = drive(options(9), [{second_page, @refusal}])
      assert summary["complete"]
      assert summary["counts"]["session_handoffs"]["journal_refusal"] == 1
      assert summary["wall"]["steps"]["job_inspect"]["invocations"] == 1

      commands = for {:invoke, command, arguments} <- log, do: {command, arguments["action"]}
      refused = Enum.find_index(commands, &(&1 == {"generation_produce", "page"})) + 3

      assert Enum.slice(commands, refused, 3) == [
               {"generation_produce", "page"},
               {"generation_job", "inspect"},
               {"generation_produce", "page"}
             ]

      assert [
               %{"item" => 0, "session_index" => 4},
               %{"item" => 1, "session_index" => 4, "outcome" => "journal_capacity_insufficient"},
               %{"item" => 1, "session_index" => 5, "outcome" => "ok"}
             ] = Enum.filter(invocations(trace, "vector_page"), &(&1["phase"] == "initial"))
    end

    test "stops when a new Session refuses its first command" do
      fifth = fn command, arguments ->
        command == "source" and
          get_in(arguments, ~w(args source_id)) == Peaks.source_id(4)
      end

      {summary, _, _} = drive(options(9), [{fifth, @refusal}, {fifth, @refusal}])
      refute summary["complete"]

      assert %{
               "kind" => "journal_capacity_insufficient_in_fresh_session",
               "step" => "put_document",
               "item" => 4,
               "session_index" => 2
             } = summary["first_stop"]
    end
  end

  describe "other outcomes" do
    test "an error stops the run as a refusal" do
      publish = fn _, arguments -> mode?(arguments, "publish") end

      {summary, _, log} = drive(options(9), [{publish, {:error, :extension_admission_refused}}])

      refute summary["complete"]

      assert %{"kind" => "refusal", "step" => "fact_publish", "item" => 0} =
               summary["first_stop"]

      assert summary["first_stop"]["detail"] =~ "extension_admission_refused"
      assert Enum.count(log, &match?({:invoke, _, _}, &1)) == 12
    end

    test "a result that is not a success stops the run as a refusal" do
      begin = fn _, arguments -> mode?(arguments, "begin") end
      refused = {:ok, %{"status" => "refused", "reason" => "source_use_refused"}, nil}
      {summary, _, _} = drive(options(9), [{begin, refused}])
      refute summary["complete"]
      assert %{"kind" => "refusal", "step" => "job_begin"} = summary["first_stop"]
      assert summary["first_stop"]["detail"] =~ "source_use_refused"
    end

    test "an unknown outcome stops the run and is never replayed" do
      finalize = fn command, _ -> command == "generation_job" end
      {summary, _, log} = drive(options(9), [{finalize, {:unknown, :timeout}}])
      refute summary["complete"]
      assert %{"kind" => "unknown", "step" => "finalize"} = summary["first_stop"]
      assert Enum.count(log, &match?({:invoke, "generation_job", _}, &1)) == 1
      refute summary["phases"]["initial"]["complete"]
    end

    test "a continuation that repeats itself is an unknown outcome" do
      lexical = fn command, _ -> command == "lexical_index" end

      loop =
        {:ok,
         %{
           "status" => "partial",
           "continuation" => %{
             "id" => "lexical_index",
             "arguments" => %{"store" => "local", "action" => "begin", "continuation" => nil}
           }
         }, nil}

      {summary, _, _} = drive(options(9), [{lexical, loop}])
      refute summary["complete"]
      assert %{"kind" => "unknown", "step" => "lexical_index"} = summary["first_stop"]
    end

    test "a Job token without a revision is an unknown outcome" do
      begin = fn _, arguments -> mode?(arguments, "begin") end
      {summary, _, _} = drive(options(9), [{begin, {:ok, %{"status" => "ok"}, nil}}])
      refute summary["complete"]
      assert %{"kind" => "unknown"} = summary["first_stop"]
      assert summary["first_stop"]["detail"] =~ "without a Job continuation"
    end
  end

  describe "handoff policies" do
    # Room for 100 journal bytes beyond the admission bound and the reserve.
    @small %{
      "max_bytes" => 10_000,
      "max_events" => 1_000,
      "bound_bytes" => 3_900,
      "bound_events" => 100,
      "reserve_bytes" => 100
    }

    test "planned handoffs leave a Session before a unit could be refused" do
      {summary, trace, _} = drive(options(9, :planned), [], @small)
      assert summary["complete"]
      assert summary["handoff_policy"] == "planned"
      assert summary["counts"]["session_handoffs"]["planned"] > 0
      assert summary["counts"]["session_handoffs"]["journal_refusal"] == 0
      assert summary["wall"]["steps"]["job_inspect"]["invocations"] > 0

      # No unit starts in a Session whose journal is past the usable size.
      for row <- trace, row["record"] == "invocation", row["invocation"] == "start" do
        assert row["journal"]["bytes"] <= 6_000
      end

      {unplanned, _, _} = drive(options(9, :refusal), [], @small)
      assert unplanned["complete"]
      assert unplanned["counts"]["session_handoffs"]["planned"] == 0
    end

    test "group handoffs change Session after every stage-free append" do
      {summary, _, log} = drive(options(9, :group), [])
      assert summary["complete"]
      assert summary["counts"]["session_handoffs"]["group"] == 4
      assert summary["counts"]["sessions"] == 12
      assert summary["wall"]["steps"]["job_inspect"]["invocations"] == 4
      assert Enum.count(log, &match?({:open, _, _, "job"}, &1)) == 6
    end
  end
end
