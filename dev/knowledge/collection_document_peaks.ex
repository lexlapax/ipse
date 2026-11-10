defmodule Ipse.Development.CollectionDocumentPeaks do
  @moduledoc false

  # Measures Session journal and native Collection allocation peaks while a
  # synthetic document Collection is built and then rebuilt through the public
  # extension commands, under the product's unchanged limits.
  #
  # Facts use the result-backed route: `source` `fact_input` publish, assemble
  # and append. A complete group of eight sources with twenty facts each does
  # not fit one public request frame, so per-source publications assembled into
  # one group result are the only route that reaches the target geometry
  # (1,000 sources : 20 MiB evidence : 10,000 chunks : 5,000 entities : 20,000
  # assertions). `--sources N` scales that geometry per source.
  #
  # Nothing is maintained as a peak by the product, so every invocation is
  # followed by a sample of the Session journal, the Collection `status` and
  # the largest staged allocation reported while the invocation ran. A build
  # is split across Sessions only where no write is pending. A refusal, error
  # or unknown outcome anywhere else stops the run, and the summary then says
  # `complete: false` with its maxima marked partial.
  #
  # Embeddings come from a loopback fixture; no model service is contacted.

  alias Ipse.{JSON, Journal}

  @steps ~w(put_document lexical_index fact_publish fact_assemble job_begin vector_page fact_append finalize job_inspect)
  @collection_fields ~w(records operations reserved_operation_slots allocated_bytes accounted_allocated_bytes data_bytes envelope_data_bytes disk_bytes)
  @handoffs %{"planned" => :planned, "refusal" => :refusal, "group" => :group}

  # The documents-profile journal admission bound recorded in
  # docs/developer/collection-sdk.md. It only decides when a planned handoff is
  # taken before a unit starts; the Session still makes every admission
  # decision itself.
  @admission %{"bound_bytes" => 69_553_634, "bound_events" => 1_586}

  @route %{
    "route" => "source fact_input publish, assemble and append",
    "reason" =>
      "a complete eight-source group with twenty facts per source does not fit one public request frame, so per-source publications assembled into a group result are the only route that scales to the target geometry"
  }

  # `max_steps` is an operator setting, 30 by default and at most 100,000. A
  # Session spends one step on every embedding request, and its extension
  # commands never start a new turn, so the default admits thirty requests per
  # Session: fewer than the vector pages of one eight-source group need. The
  # harness therefore sets the setting explicitly and reports the value.
  @max_steps 100_000

  @usage "use --sources 1..1000 --out _build/NEW_DIRECTORY [--handoff planned|refusal|group] [--max-steps 1..100000] [--artifact BUILT_ARTIFACT] [--keep-home]"

  def steps, do: @steps
  def collection_fields, do: @collection_fields
  def usage, do: @usage

  ## Arguments

  def parse(argv) when is_list(argv) do
    {opts, rest, invalid} =
      OptionParser.parse(argv,
        strict: [
          sources: :integer,
          out: :string,
          handoff: :string,
          artifact: :string,
          keep_home: :boolean,
          max_steps: :integer
        ]
      )

    sources = opts[:sources]
    out = opts[:out]
    handoff = Map.get(@handoffs, Keyword.get(opts, :handoff, "planned"))
    build = Path.expand("_build")
    steps = Keyword.get(opts, :max_steps, @max_steps)

    # OptionParser keeps only the last value of a repeated option.
    flags =
      for "--" <> flag <- argv, do: flag |> String.split("=") |> hd() |> String.replace("_", "-")

    cond do
      rest != [] or invalid != [] ->
        {:error, "unrecognized arguments; " <> @usage}

      flags != Enum.uniq(flags) ->
        {:error, "an option was repeated; " <> @usage}

      not (is_integer(sources) and sources in 1..1000) ->
        {:error, "--sources must be an integer from 1 to 1000; " <> @usage}

      not (is_binary(out) and String.starts_with?(Path.expand(out), build <> "/")) ->
        {:error, "--out must name a new directory under _build/; " <> @usage}

      steps not in 1..100_000 ->
        {:error, "--max-steps must be an integer from 1 to 100000; " <> @usage}

      handoff == nil ->
        {:error, "--handoff must be planned, refusal or group; " <> @usage}

      true ->
        {:ok,
         %{
           sources: sources,
           out: Path.expand(out),
           handoff: handoff,
           artifact: if(opts[:artifact], do: Path.expand(opts[:artifact])),
           keep_home: Keyword.get(opts, :keep_home, false),
           max_steps: steps
         }}
    end
  end

  def gate(environment, probe) when is_function(probe, 0) do
    if environment == "1" do
      case probe.() do
        :ok -> :ok
        {:error, :transaction_filesystem_unsupported} -> {:not_run, :unsupported_storage_profile}
        other -> {:not_run, {:storage_probe_failed, other}}
      end
    else
      {:not_run, :native_storage_not_requested}
    end
  end

  def not_run_line(reason) do
    detail =
      case reason do
        :native_storage_not_requested ->
          "IPSE_TEST_NATIVE_STORAGE=1 is not set"

        :unsupported_storage_profile ->
          "the temporary directory is not a reviewed native storage profile on this host"

        {:storage_probe_failed, other} ->
          "the native storage probe failed: " <> inspect(other)
      end

    "NOT RUN: collection_document_peaks needs IPSE_TEST_NATIVE_STORAGE=1 on the supported native storage profile; " <>
      detail <> ". No Session or Collection was started and no evidence was written."
  end

  ## Geometry and fixtures

  def geometry(sources) when is_integer(sources) and sources in 1..1000 do
    large = div(sources * 252 + 500, 1000)

    %{
      "sources" => sources,
      "target_ratio" =>
        "1,000 sources : 20 MiB evidence : 10,000 chunks : 5,000 entities : 20,000 assertions",
      "chunks_per_source" => 10,
      "entities_per_source" => 5,
      "assertions_per_source" => 20,
      "chunks" => sources * 10,
      "entities" => sources * 5,
      "assertions" => sources * 20,
      "large_sources" => large,
      "large_source_text_bytes" => 20_979,
      "small_source_text_bytes" => 20_969,
      "evidence_bytes" => large * 20_979 + (sources - large) * 20_969,
      "target_evidence_bytes" => div(sources * 20_971_520, 1000),
      "sources_per_group" => 8
    }
  end

  def source_id(ordinal),
    do: "fixture:peaks:" <> String.pad_leading(Integer.to_string(ordinal), 4, "0")

  def document(ordinal, sources) do
    size = if ordinal < geometry(sources)["large_sources"], do: 2097, else: 2096
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    rel = "http://schemas.openxmlformats.org/package/2006/relationships"

    root =
      "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"

    types =
      "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"

    body =
      Enum.map_join(1..10, fn _ ->
        "<w:p><w:r><w:t>" <> String.duplicate("a", size) <> "</w:t></w:r></w:p>"
      end)

    {:ok, {_, bytes}} =
      :zip.create(
        ~c"capacity.docx",
        [
          {~c"_rels/.rels", root},
          {~c"[Content_Types].xml", types},
          {~c"word/document.xml",
           "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"}
        ],
        [:memory]
      )

    bytes
  end

  def put_arguments(ordinal, sources) do
    %{
      "store" => "local",
      "action" => "put_document",
      "args" => %{
        "source_id" => source_id(ordinal),
        "generation" => 1,
        "title" => "Document peaks supplied synthetic document",
        "uri" => "provided:capacity.docx",
        "observed_at_ms" => 10,
        "event_at_ms" => nil,
        "expires_at_ms" => nil,
        "expected_revision" => 0,
        "filename" => "capacity.docx",
        "bytes_base64" => Base.encode64(document(ordinal, sources))
      }
    }
  end

  def publish_arguments(ordinal, phase) do
    id = source_id(ordinal)

    rows =
      for n <- 0..19 do
        %{
          "subject" => id <> ":Entity#{rem(n, 5)}",
          "object" => id <> ":Entity#{rem(n + 1, 5)}",
          "predicate" => "relation#{n}" <> if(phase == "initial", do: "", else: "-replacement"),
          "polarity" => "positive",
          "inferred" => false,
          "valid_from_ms" => nil,
          "valid_to_ms" => nil,
          "spans" => [[0, 0, 32]]
        }
      end

    %{
      "store" => "local",
      "action" => "fact_input",
      "args" => %{
        "input" => %{
          "version" => 1,
          "mode" => "publish",
          "value" => %{
            "version" => 1,
            "kind" => "explicit_fact_group",
            "sources" => [%{"source_key" => JSON.sha256(id), "facts" => rows}]
          }
        }
      }
    }
  end

  ## Samples and summary

  def new_totals do
    %{
      "phases" => %{},
      "steps" => %{},
      "sessions" => 0,
      "handoffs" => %{"journal_refusal" => 0, "planned" => 0, "group" => 0, "role" => 0},
      "collection_limits" => nil
    }
  end

  @doc false
  def fold(totals, %{"record" => "invocation"} = row) do
    actions = row["host_actions"]["total"]

    totals
    |> update_in(["phases"], fn phases ->
      phase = Map.get(phases, row["phase"], new_phase())

      Map.put(phases, row["phase"], %{
        phase
        | "maxima" => maxima(phase["maxima"], row),
          "invocations" => phase["invocations"] + 1,
          "continuation_invocations" =>
            phase["continuation_invocations"] +
              if(row["invocation"] == "continuation", do: 1, else: 0),
          "host_actions" => %{
            "collection" =>
              phase["host_actions"]["collection"] + row["host_actions"]["collection"],
            "embedding" => phase["host_actions"]["embedding"] + row["host_actions"]["embedding"],
            "total" => phase["host_actions"]["total"] + actions
          },
          "wall_us" => phase["wall_us"] + row["wall_us"]
      })
    end)
    |> update_in(["steps"], fn steps ->
      step =
        Map.get(steps, row["step"], %{
          "invocations" => 0,
          "host_actions" => 0,
          "wall_us" => 0,
          "max_wall_us" => 0
        })

      Map.put(steps, row["step"], %{
        "invocations" => step["invocations"] + 1,
        "host_actions" => step["host_actions"] + actions,
        "wall_us" => step["wall_us"] + row["wall_us"],
        "max_wall_us" => max(step["max_wall_us"], row["wall_us"])
      })
    end)
    |> Map.update!("collection_limits", &(row["collection_limits"] || &1))
  end

  def fold(totals, %{"record" => "session_close"} = row) do
    update_in(totals, ["phases"], fn phases ->
      phase = Map.get(phases, row["phase"], new_phase())
      Map.put(phases, row["phase"], %{phase | "maxima" => maxima(phase["maxima"], row)})
    end)
  end

  def fold(totals, %{"record" => "session_open"}), do: Map.update!(totals, "sessions", &(&1 + 1))

  def fold(totals, %{"record" => "handoff", "reason" => reason}),
    do: update_in(totals, ["handoffs", reason], &(&1 + 1))

  def fold(totals, _), do: totals

  defp new_phase do
    %{
      "complete" => false,
      "maxima" => %{},
      "invocations" => 0,
      "continuation_invocations" => 0,
      "host_actions" => %{"collection" => 0, "embedding" => 0, "total" => 0},
      "wall_us" => 0
    }
  end

  @doc "Raise each measured maximum to the row's value, remembering the trace sequence that set it."
  def maxima(current, row) do
    Enum.reduce(measures(row), current, fn {field, value}, acc ->
      case acc[field] do
        %{"value" => held} when held >= value -> acc
        _ -> Map.put(acc, field, %{"value" => value, "seq" => row["seq"]})
      end
    end)
  end

  defp measures(row) do
    journal = row["journal"] || %{}
    collection = row["collection"] || %{}
    staged = row["staged"] || %{}

    [
      {"journal_bytes", journal["bytes"]},
      {"journal_events", journal["events"]},
      {"staged_allocated_bytes", staged["allocated_bytes"]},
      {"staged_accounted_allocated_bytes", staged["accounted_allocated_bytes"]}
    ]
    |> Kernel.++(Enum.map(@collection_fields, &{&1, collection[&1]}))
    |> Enum.filter(fn {_, value} -> is_integer(value) end)
  end

  def summary(options, totals, stop, journal) do
    phases =
      Map.new(~w(initial rebuild), fn name ->
        phase = Map.get(totals["phases"], name, new_phase())

        {name,
         Map.merge(phase, %{
           "maxima_are_partial" => not phase["complete"],
           "wall_us_per_host_action" => per(phase["wall_us"], phase["host_actions"]["total"])
         })}
      end)

    complete = stop == nil and Enum.all?(phases, fn {_, phase} -> phase["complete"] end)
    count = fn field -> Enum.sum(Enum.map(phases, fn {_, phase} -> phase[field] end)) end
    actions = fn kind -> Enum.sum(Enum.map(phases, fn {_, p} -> p["host_actions"][kind] end)) end
    wall = count.("wall_us")

    %{
      "tool" => "dev/knowledge/collection_document_peaks.exs",
      "version" => 1,
      "complete" => complete,
      "maxima_are_partial" => not complete,
      "fact_route" => @route,
      "geometry" => geometry(options.sources),
      "handoff_policy" => Atom.to_string(options.handoff),
      "operator_settings" => %{
        "max_steps" => options.max_steps,
        "max_steps_default" => 30,
        "note" =>
          "a Session spends one step per embedding request across all its extension commands; the default of 30 refuses the eighth vector page of one eight-source group with embedding_limit"
      },
      "phases" => phases,
      "counts" => %{
        "sessions" => totals["sessions"],
        "session_handoffs" => totals["handoffs"],
        "continuations" => totals["handoffs"]["journal_refusal"],
        "invocations" => count.("invocations"),
        "continuation_invocations" => count.("continuation_invocations"),
        "host_actions" => %{
          "collection" => actions.("collection"),
          "embedding" => actions.("embedding"),
          "total" => actions.("total")
        }
      },
      "wall" => %{
        "total_us" => wall,
        "per_host_action_us" => per(wall, actions.("total")),
        "steps" =>
          Map.new(totals["steps"], fn {step, row} ->
            {step,
             Map.put(row, "wall_us_per_host_action", per(row["wall_us"], row["host_actions"]))}
          end)
      },
      "first_stop" => stop,
      "limits" => %{
        "changed" => false,
        "journal" => journal,
        "collection" => totals["collection_limits"]
      }
    }
  end

  defp per(_, 0), do: nil
  defp per(total, count), do: div(total, count)

  ## Driver

  def journal_plan do
    Map.merge(@admission, %{
      "max_bytes" => Journal.limits()["max_bytes"],
      "max_events" => Journal.limits()["max_events"],
      "reserve_bytes" => Journal.reserve_bytes()
    })
  end

  @doc """
  Build and rebuild through `executor`, writing every trace row to `sink`.

  The executor owns Sessions and sampling; this function owns the command
  order, the handoff rule and the stop rule, so they can be exercised against a
  stub. Returns the summary.
  """
  def drive(options, executor, ctx, sink, journal \\ journal_plan()) do
    run = %{
      options: options,
      executor: executor,
      ctx: ctx,
      sink: sink,
      plan: journal,
      totals: new_totals(),
      seq: 0,
      phase: nil,
      role: nil,
      open: false,
      session: nil,
      session_index: 0,
      session_invocations: 0,
      journal: %{"bytes" => 0, "events" => 0},
      growth: %{},
      selection: nil,
      job: nil,
      stop: nil
    }

    run =
      Enum.reduce_while(~w(initial rebuild), run, fn name, run ->
        # A phase's last Session is closed, and its journal scanned, before the
        # next phase starts, so each close is counted in the phase that wrote it.
        with {:ok, run} <- phase(%{run | phase: name, job: nil}),
             {:ok, run} <- close(run) do
          phases = Map.put_new(run.totals["phases"], name, new_phase())
          totals = Map.put(run.totals, "phases", put_in(phases[name]["complete"], true))
          {:cont, %{run | totals: totals}}
        else
          {:stop, run} -> {:halt, run}
        end
      end)

    run =
      case close(run) do
        {:ok, run} -> run
        {:stop, run} -> run
      end

    {summary(options, run.totals, run.stop, journal), run.ctx}
  end

  defp phase(run) do
    with {:ok, run} <- ingest(run),
         {:ok, groups, run} <- groups(run),
         {:ok, refs, run} <- publish(run, groups),
         {:ok, group_refs, run} <- assemble(run, groups, refs) do
      job(run, group_refs)
    end
  end

  defp ingest(run) do
    with {:ok, run} <- role(run, "ingest"),
         {:ok, run} <- put_sources(run) do
      lexical = %{"store" => "local", "action" => "begin", "continuation" => nil}

      with {:ok, _, _, run} <- unit(run, "lexical_index", 0, "lexical_index", lexical),
           do: {:ok, run}
    end
  end

  # The rebuild keeps the stored sources and replaces the encoder selection and
  # every fact, as the recipe ledger's replacement variant does.
  defp put_sources(%{phase: "rebuild"} = run), do: {:ok, run}

  defp put_sources(run) do
    Enum.reduce_while(0..(run.options.sources - 1), {:ok, run}, fn ordinal, {:ok, run} ->
      arguments = put_arguments(ordinal, run.options.sources)

      case unit(run, "put_document", ordinal, "source", arguments) do
        {:ok, _, _, run} -> {:cont, {:ok, run}}
        {:stop, run} -> {:halt, {:stop, run}}
      end
    end)
  end

  defp groups(run) do
    with {:ok, run} <- close(run) do
      case run.executor.groups(run.ctx, run.options.sources) do
        {:ok, groups} ->
          if Enum.sort(List.flatten(groups)) == Enum.to_list(0..(run.options.sources - 1)) and
               Enum.all?(groups, &(length(&1) in 1..8)),
             do: {:ok, groups, run},
             else: stop(run, "unknown", "catalog group order does not cover the stored sources")

        {:error, detail} ->
          stop(run, "unknown", "catalog group order is unreadable: " <> text(detail))
      end
    end
  end

  defp publish(run, groups) do
    with {:ok, run} <- role(run, "publish") do
      Enum.reduce_while(List.flatten(groups), {:ok, %{}, run}, fn ordinal, {:ok, refs, run} ->
        arguments = publish_arguments(ordinal, run.phase)

        case unit(run, "fact_publish", ordinal, "source", arguments) do
          {:ok, _, ref, run} -> {:cont, {:ok, Map.put(refs, ordinal, ref), run}}
          {:stop, run} -> {:halt, {:stop, run}}
        end
      end)
    end
  end

  defp assemble(run, groups, refs) do
    with {:ok, run} <- role(run, "assemble") do
      Enum.with_index(groups)
      |> Enum.reduce_while({:ok, [], run}, fn {ordinals, group}, {:ok, done, run} ->
        arguments = %{
          "store" => "local",
          "action" => "fact_input",
          "data_inputs" => Enum.map(ordinals, &Map.fetch!(refs, &1)),
          "args" => %{"input" => %{"version" => 1, "mode" => "assemble"}}
        }

        case unit(run, "fact_assemble", group, "source", arguments) do
          {:ok, _, ref, run} -> {:cont, {:ok, done ++ [ref], run}}
          {:stop, run} -> {:halt, {:stop, run}}
        end
      end)
    end
  end

  defp job(run, group_refs) do
    with {:ok, run} <- role(run, "job") do
      selection = run.executor.selection(run.ctx, run.phase)
      extraction = %{"kind" => "explicit", "profile" => nil, "version" => 1}
      run = %{run | selection: {selection, extraction}}

      begin = %{
        "store" => "local",
        "action" => "fact_input",
        "args" => %{
          "input" => %{
            "version" => 1,
            "mode" => "begin",
            "vector_selection" => selection,
            "fact_selection" => extraction,
            "continuation" => nil
          }
        }
      }

      with {:ok, begun, _, run} <- unit(run, "job_begin", 0, "source", begin),
           {:ok, run} <- token(run, begun, "job_begin", 0),
           {:ok, run} <- append_groups(run, group_refs) do
        finalize = %{
          "store" => "local",
          "action" => "finalize_paged",
          "vector_selection" => selection,
          "fact_selection" => extraction,
          "continuation" => run.job,
          "response" => "compact_v1",
          "guard_sources" => true
        }

        with {:ok, _, _, run} <- unit(run, "finalize", 0, "generation_job", finalize),
             do: {:ok, %{run | job: nil}}
      end
    end
  end

  defp append_groups(run, group_refs) do
    {selection, extraction} = run.selection

    Enum.with_index(group_refs)
    |> Enum.reduce_while({:ok, run}, fn {ref, group}, {:ok, run} ->
      producer = %{
        "version" => 2,
        "action" => "page",
        "embedding" => "learned",
        "job_id" => run.job["id"],
        "job_revision" => run.job["job_revision"],
        "vector_selection" => selection,
        "fact_selection" => extraction,
        "vector_cursor" => 0,
        "previous_ready" => nil
      }

      page = Map.put(producer, "store", "local")

      append = %{
        "store" => "local",
        "action" => "fact_input",
        "result_input" => ref,
        "args" => %{
          "input" => %{
            "version" => 1,
            "mode" => "append",
            "producer" => producer,
            "continuation" => nil
          }
        }
      }

      with {:ok, _, _, run} <- unit(run, "vector_page", group, "generation_produce", page),
           {:ok, appended, _, run} <- unit(run, "fact_append", group, "source", append),
           {:ok, run} <- token(run, appended, "fact_append", group),
           {:ok, run} <- group_handoff(run) do
        {:cont, {:ok, run}}
      else
        {:stop, run} -> {:halt, {:stop, run}}
      end
    end)
  end

  defp token(run, value, step, item) do
    case get_in(value, ["coverage", "continuation"]) do
      %{"id" => id, "job_revision" => revision} = job
      when is_binary(id) and is_integer(revision) ->
        {:ok, %{run | job: job}}

      _ ->
        stop(
          run,
          "unknown",
          "#{step} #{item} completed without a Job continuation in coverage.continuation"
        )
    end
  end

  # The only real-Session-tested Job handoff: after a group append whose token
  # holds no stage and no write.
  defp group_handoff(%{options: %{handoff: :group}, job: job} = run) do
    if job["stages"] == [] and job["write"] == nil,
      do: handoff(run, "group"),
      else: stop(run, "unknown", "the Job continuation after an append still holds a stage")
  end

  defp group_handoff(run), do: {:ok, run}

  ## Units, invocations and Sessions

  # A unit is one fresh public command followed through its returned
  # continuations. No write is pending before it starts.
  defp unit(run, step, item, command, arguments) do
    with {:ok, run} <- planned(run, step) do
      before = {run.session_index, run.journal}

      with {:ok, value, ref, run} <- follow(run, step, item, command, arguments, "start") do
        {:ok, value, ref, grown(run, step, before)}
      end
    end
  end

  defp follow(run, step, item, command, arguments, kind) do
    position = %{
      "phase" => run.phase,
      "role" => run.role,
      "step" => step,
      "item" => item,
      "command" => command,
      "invocation" => kind
    }

    {result, observation, ctx} = run.executor.invoke(run.ctx, command, arguments)
    run = observed(%{run | ctx: ctx}, position, result, observation)

    case result do
      {:ok, %{"continuation" => %{"id" => next, "arguments" => next_arguments}}, _}
      when is_binary(next) and is_map(next_arguments) ->
        if next == command and next_arguments == arguments do
          stop(run, "unknown", "the continuation repeated its own arguments", position)
        else
          run =
            case {next, next_arguments["continuation"]} do
              {"generation_job", %{"id" => _, "job_revision" => _} = job} -> %{run | job: job}
              _ -> run
            end

          follow(run, step, item, next, next_arguments, "continuation")
        end

      {:ok, value, ref} ->
        if finished?(step, value, ref),
          do: {:ok, value, ref, run},
          else: stop(run, "refusal", text(value), position)

      {:journal_refusal, detail} ->
        cond do
          not stage_free?(kind, command, arguments) ->
            stop(run, "journal_capacity_insufficient_with_pending_write", detail, position)

          run.session_invocations <= 1 ->
            stop(run, "journal_capacity_insufficient_in_fresh_session", detail, position)

          true ->
            with {:ok, run} <- handoff(run, "journal_refusal"),
                 do: follow(run, step, item, command, arguments, kind)
        end

      {:error, detail} ->
        stop(run, "refusal", text(detail), position)

      {:unknown, detail} ->
        stop(run, "unknown", text(detail), position)
    end
  end

  defp finished?(step, value, ref) when step in ~w(fact_publish fact_assemble),
    do: is_map(ref) and is_map(value) and value["kind"] == "explicit_fact_group"

  defp finished?(_, value, _), do: is_map(value) and value["status"] == "ok"

  # A fresh command holds no stage. A returned command is stage-free only when
  # it carries a Job continuation that says so; Source and bound append
  # continuations belong to the Session that produced them.
  defp stage_free?("start", _, _), do: true

  defp stage_free?(_, "generation_job", %{"continuation" => %{"stages" => [], "write" => nil}}),
    do: true

  defp stage_free?(_, _, _), do: false

  defp observed(run, position, result, observation) do
    outcome =
      case result do
        {:ok, %{"status" => status}, _} when is_binary(status) -> status
        {:ok, _, ref} when is_map(ref) -> "published"
        {:ok, _, _} -> "unrecognized"
        {:journal_refusal, _} -> "journal_capacity_insufficient"
        {:error, _} -> "error"
        {:unknown, _} -> "unknown"
      end

    row =
      position
      |> Map.merge(observation)
      |> Map.merge(%{
        "record" => "invocation",
        "outcome" => outcome,
        "session_index" => run.session_index
      })

    run = emit(run, row)

    %{
      run
      | session_invocations: run.session_invocations + 1,
        journal: observation["journal"] || run.journal
    }
  end

  defp grown(run, step, {index, before}) do
    if index == run.session_index do
      {bytes, events} = Map.get(run.growth, step, {0, 0})

      grown =
        {max(bytes, run.journal["bytes"] - before["bytes"]),
         max(events, run.journal["events"] - before["events"])}

      %{run | growth: Map.put(run.growth, step, grown)}
    else
      run
    end
  end

  # Before a unit starts, leave the Session while it still has room for the
  # worst-case admission bound plus twice the largest journal growth that step
  # has needed so far, or half the usable journal when the step is new.
  defp planned(%{options: %{handoff: :refusal}} = run, _), do: {:ok, run}
  defp planned(%{session_invocations: 0} = run, _), do: {:ok, run}

  defp planned(run, step) do
    plan = run.plan
    usable_bytes = plan["max_bytes"] - plan["bound_bytes"] - plan["reserve_bytes"]
    usable_events = plan["max_events"] - plan["bound_events"]

    {need_bytes, need_events} =
      case run.growth[step] do
        nil -> {div(usable_bytes, 2), div(usable_events, 2)}
        {bytes, events} -> {2 * bytes, 2 * events}
      end

    if usable_bytes - run.journal["bytes"] < need_bytes or
         usable_events - run.journal["events"] < need_events,
       do: handoff(run, "planned"),
       else: {:ok, run}
  end

  defp role(run, role) do
    with {:ok, run} <- close(run),
         {:ok, run} <- open(%{run | role: role}) do
      {:ok, emit(run, %{"record" => "handoff", "reason" => "role", "role" => role})}
    end
  end

  # Close with confirmation and continue the same role in a new Session. A Job
  # continuation is inspected there before it is used again.
  defp handoff(run, reason) do
    with {:ok, run} <- close(run),
         {:ok, run} <- open(run) do
      run = emit(run, %{"record" => "handoff", "reason" => reason, "role" => run.role})
      if run.role == "job" and run.job != nil, do: inspect_job(run), else: {:ok, run}
    end
  end

  defp inspect_job(run) do
    {selection, extraction} = run.selection

    arguments = %{
      "store" => "local",
      "action" => "inspect",
      "continuation" => nil,
      "vector_selection" => selection,
      "fact_selection" => extraction,
      "response" => "compact_v1"
    }

    held = Map.take(run.job, ~w(id job_revision))

    with {:ok, value, _, run} <-
           follow(run, "job_inspect", 0, "generation_job", arguments, "start") do
      case get_in(value, ["coverage", "continuation"]) do
        %{} = seen ->
          if Map.take(seen, ~w(id job_revision)) == held,
            do: {:ok, run},
            else: stop(run, "unknown", "the inspected Job differs from the held continuation")

        _ ->
          stop(run, "unknown", "Job inspection returned no continuation")
      end
    end
  end

  defp open(run) do
    case run.executor.open(run.ctx, run.phase, run.role) do
      {:ok, session, ctx} ->
        run = %{
          run
          | ctx: ctx,
            open: true,
            session: session,
            session_index: run.session_index + 1,
            session_invocations: 0,
            journal: %{"bytes" => 0, "events" => 0}
        }

        {:ok, emit(run, %{"record" => "session_open", "session" => session})}

      {:error, detail, ctx} ->
        stop(%{run | ctx: ctx}, "unknown", "Session start failed: " <> text(detail))
    end
  end

  defp close(%{open: false} = run), do: {:ok, run}

  defp close(run) do
    case run.executor.close(run.ctx) do
      {:ok, journal, ctx} ->
        run = %{run | ctx: ctx, open: false}

        {:ok,
         emit(run, %{"record" => "session_close", "session" => run.session, "journal" => journal})}

      {:error, detail, ctx} ->
        stop(
          %{run | ctx: ctx, open: false},
          "unknown",
          "confirmed Session close or journal scan failed: " <> text(detail)
        )
    end
  end

  defp emit(run, row) do
    row =
      Map.merge(
        %{
          "seq" => run.seq,
          "phase" => run.phase,
          "role" => run.role,
          "session_index" => run.session_index
        },
        row
      )

    run.sink.(row)
    %{run | seq: run.seq + 1, totals: fold(run.totals, row)}
  end

  # Only the first stop is kept: it is the position the run could not pass.
  defp stop(run, kind, detail, position \\ %{}) do
    stop =
      Map.merge(
        %{
          "kind" => kind,
          "detail" => detail,
          "phase" => run.phase,
          "role" => run.role,
          "session" => run.session,
          "session_index" => run.session_index,
          "after_seq" => run.seq - 1
        },
        position
      )

    run = if run.stop, do: run, else: emit(%{run | stop: stop}, Map.put(stop, "record", "stop"))
    {:stop, run}
  end

  ## Entry

  def main(argv) do
    case parse(argv) do
      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(64)

      {:ok, options} ->
        code = run(options)
        __MODULE__.Native.cleanup()
        System.halt(code)
    end
  end

  defp run(options) do
    native = __MODULE__.Native

    case gate(System.get_env("IPSE_TEST_NATIVE_STORAGE"), &native.probe/0) do
      {:not_run, reason} ->
        IO.puts(not_run_line(reason))
        2

      :ok ->
        if File.exists?(options.out) do
          IO.puts(:stderr, "--out already exists; evidence is never mixed: " <> options.out)
          64
        else
          measure(options, native)
        end
    end
  end

  defp measure(options, native) do
    File.mkdir_p!(options.out)
    trace = File.open!(Path.join(options.out, "trace.jsonl"), [:write, :exclusive])
    sink = fn row -> IO.binwrite(trace, [Jason.encode_to_iodata!(row), "\n"]) end

    summary =
      try do
        ctx = native.start(options)
        {summary, ctx} = drive(options, native, ctx, sink)
        native.stop(ctx)
        summary
      rescue
        error -> failure(options, Exception.format(:error, error, __STACKTRACE__))
      catch
        kind, reason -> failure(options, Exception.format(kind, reason, __STACKTRACE__))
      end

    :ok = File.close(trace)
    summary = Map.put(summary, "host", native.host())

    File.write!(
      Path.join(options.out, "summary.json"),
      Jason.encode_to_iodata!(summary, pretty: true),
      [:exclusive]
    )

    Enum.each(report(summary, options.out), &IO.puts/1)
    if summary["complete"], do: 0, else: 1
  end

  # A harness fault is a stopped run too: it gets a summary that says so.
  defp failure(options, detail) do
    %{
      "tool" => "dev/knowledge/collection_document_peaks.exs",
      "version" => 1,
      "complete" => false,
      "maxima_are_partial" => true,
      "fact_route" => @route,
      "geometry" => geometry(options.sources),
      "phases" => %{},
      "first_stop" => %{"kind" => "harness_error", "detail" => text(detail)},
      "note" => "the harness failed; trace.jsonl holds every invocation it sampled"
    }
  end

  def report(summary, out) do
    geometry = summary["geometry"]

    head = [
      if(summary["complete"],
        do: "COMPLETE: initial build and rebuild finished",
        else: "INCOMPLETE: the run stopped; every maximum below is partial"
      ),
      "fact route: " <>
        summary["fact_route"]["route"] <> " (" <> summary["fact_route"]["reason"] <> ")",
      "geometry: #{geometry["sources"]} sources, #{geometry["evidence_bytes"]} evidence bytes; per source #{geometry["chunks_per_source"]} chunks, #{geometry["entities_per_source"]} entities, #{geometry["assertions_per_source"]} assertions"
    ]

    phases =
      for name <- ~w(initial rebuild), phase = summary["phases"][name], phase != nil do
        peaks =
          Enum.map_join(
            ~w(journal_bytes journal_events allocated_bytes staged_allocated_bytes records operations),
            ", ",
            &"#{&1}=#{get_in(phase, ["maxima", &1, "value"]) || "unsampled"}"
          )

        "#{name}: complete=#{phase["complete"]} invocations=#{phase["invocations"]} host_actions=#{phase["host_actions"]["total"]} wall_us=#{phase["wall_us"]} maxima: #{peaks}"
      end

    stop =
      case summary["first_stop"] do
        nil -> []
        stop -> ["first stop: " <> Jason.encode!(stop)]
      end

    head ++ phases ++ stop ++ ["evidence: " <> out]
  end

  defp text(detail) when is_binary(detail), do: String.slice(detail, 0, 2000)

  defp text(detail),
    do: detail |> inspect(limit: 40, printable_limit: 400) |> String.slice(0, 2000)
end

defmodule Ipse.Development.CollectionDocumentPeaks.Native do
  @moduledoc false

  # The real executor: public commands in real Sessions over native storage,
  # with the samples the driver records after each one.

  alias Ipse.{JSON, Journal, Session, Usage}
  alias Ipse.Development.CollectionDocumentPeaks, as: Peaks
  alias Ipse.Extension.{Artifact, Collection, CollectionStore, Config, ProjectIdentity, Registry}
  alias Ipse.Extension.Collection.DocumentStage

  @wait_ms 120_000
  @journal_refusal "cannot hold another worst-case document Collection invocation"
  @approvals ~w(extension:collection.store extension:embedding.create)

  defmodule NoConversation do
    def complete(_, _, _, _), do: raise("document peaks fixture called the conversation model")
  end

  ## Host

  # Mirrors test/test_helper.exs: physical temporary paths and an operator home
  # that hides installed skills and credentials, set before the application
  # starts. The probe asks the pinned helper whether that directory qualifies.
  def probe do
    {:ok, temporary} = Ipse.Workspace.canonical_path(System.tmp_dir!())
    System.put_env("TMPDIR", temporary)
    operator = Path.join(temporary, "ipse-document-peaks-operator-#{System.pid()}")
    File.mkdir_p!(operator)
    rustup = Path.join(Ipse.Workspace.operator_home(), ".rustup")

    if is_nil(System.get_env("RUSTUP_HOME")) and File.dir?(rustup),
      do: System.put_env("RUSTUP_HOME", rustup)

    System.put_env("HOME", operator)
    System.put_env("IPSE_HOME", Path.join(operator, ".ipse"))
    :persistent_term.put({__MODULE__, :operator}, operator)
    {:ok, _} = Application.ensure_all_started(:ipse)
    directory = Path.join(temporary, "ipse-document-peaks-probe-#{System.pid()}")
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)

    Task.async(fn ->
      try do
        Ipse.Session.Resources.file_effect(fn ->
          with {:ok, cap} <- Ipse.Runner.Transaction.acquire(Path.join(directory, ".lock")) do
            result = Ipse.Runner.Transaction.quota(cap, :flat, 65_536)
            :ok = Ipse.Runner.Transaction.release(cap)
            result
          end
        end)
      after
        File.rm_rf!(directory)
      end
    end)
    |> Task.await(30_000)
  end

  def cleanup do
    case :persistent_term.get({__MODULE__, :operator}, nil) do
      nil -> :ok
      operator -> File.rm_rf!(operator)
    end

    :ok
  end

  def host do
    %{
      "os" => :os.type() |> Tuple.to_list() |> Enum.map_join("/", &Atom.to_string/1),
      "otp" => List.to_string(:erlang.system_info(:otp_release)),
      "elixir" => System.version(),
      "native_storage_profile" => "supported",
      "embeddings" => "loopback fixture"
    }
  end

  ## Setup

  def start(options) do
    root = Path.join(System.fetch_env!("TMPDIR"), "ipse-document-peaks-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "workspace")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)

    built =
      if options.artifact,
        do: nil,
        else: Path.expand("_build/document-peaks-artifact-" <> Usage.id())

    try do
      setup(options, root, home, cwd, built)
    rescue
      error ->
        File.rm_rf!(root)
        if built, do: File.rm_rf!(built)
        reraise error, __STACKTRACE__
    end
  end

  defp setup(options, root, home, cwd, built) do
    source = if built, do: build(built), else: options.artifact
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    server = spawn(fn -> http(listener) end)
    {:ok, artifact} = Artifact.import(source, Path.join(home, "extensions/artifacts"))

    extension =
      Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.merge(%{
        "version" => 1,
        "stores" => %{
          "local" => %{"kind" => "collection", "scope" => "project", "partition" => "notes"}
        },
        "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
        "embedding" => %{"learned" => %{"kind" => "embedding", "profile" => "encoder"}}
      })

    # The result-backed fact route needs the version 3 operator binding.
    operator = %{
      "version" => 3,
      "instance" => "documents",
      "id" => "documents",
      "scope" => "project",
      "profile" => "document_graph_v1",
      "source_use" => "shared_producer_v1",
      "input_validation" => %{
        "command_id" => "source",
        "action" => "restore_validate_page",
        "export_action" => "backup_page",
        "plan_action" => "backup_plan"
      }
    }

    data = %{
      "extensions" => [
        %{
          "instance" => "documents",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => extension,
          "order" => 0,
          "lifetime" => "session"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false,
          "collection_bindings" => [operator]
        }
      ]
    }

    {:ok, selected} =
      Config.resolve([%{scope: "operator", path: "/fixture/document-peaks.json", data: data}], [])

    {:ok, entries} = Registry.prepare(selected, home)
    {:ok, project} = ProjectIdentity.admit(home, cwd, :folder)
    peak = :atomics.new(2, signed: false)
    telemetry = "document-peaks-" <> Usage.id()

    :ok =
      :telemetry.attach(
        telemetry,
        [:ipse, :extension, :collection, :staged],
        &__MODULE__.staged/4,
        peak
      )

    %{
      root: root,
      home: home,
      cwd: cwd,
      dir: Path.join(home, "sessions"),
      built: built,
      keep: options.keep_home,
      max_steps: options.max_steps,
      listener: listener,
      server: server,
      port: port,
      entries: entries,
      store: CollectionStore.root(home),
      namespace: CollectionStore.namespace(project["project_id"]),
      peak: peak,
      telemetry: telemetry,
      pid: nil,
      monitor: nil,
      id: nil,
      offset: 0,
      events: 0
    }
  end

  def stop(ctx) do
    if ctx.pid && Process.alive?(ctx.pid), do: Session.close_confirmed(ctx.pid)
    :telemetry.detach(ctx.telemetry)
    :gen_tcp.close(ctx.listener)
    Process.exit(ctx.server, :kill)
    if ctx.built, do: File.rm_rf!(ctx.built)

    if ctx.keep,
      do: IO.puts("native home retained for inspection: " <> ctx.root),
      else: File.rm_rf!(ctx.root)

    :ok
  end

  defp build(root) do
    package = Path.join(root, "package/extensions/knowledge")
    File.mkdir_p!(Path.dirname(package))
    {:ok, _} = File.cp_r("extensions/knowledge", package)
    File.cp!("LICENSE", Path.join(root, "package/LICENSE"))
    output = Path.join(root, "artifact")
    sdk = :code.which(Ipse.Extension) |> List.to_string() |> Path.dirname()

    {log, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "--erl",
          "+S 2:2",
          Path.join(package, "build.exs"),
          "--sdk",
          sdk,
          "--output",
          output,
          "--package",
          "corpus",
          "--preset",
          "collection-dense"
        ],
        stderr_to_stdout: true
      )

    if status != 0, do: raise("corpus artifact build failed: " <> log)
    output
  end

  @doc false
  def staged(_, measurements, _, peak) do
    raise_peak(peak, 1, measurements[:allocated_bytes])
    raise_peak(peak, 2, measurements[:accounted_allocated_bytes])
  end

  defp raise_peak(peak, index, value) when is_integer(value) and value >= 0 do
    held = :atomics.get(peak, index)

    if value > held and :atomics.compare_exchange(peak, index, held, value) != :ok,
      do: raise_peak(peak, index, value),
      else: :ok
  end

  defp raise_peak(_, _, _), do: :ok

  ## Executor

  # The rebuild selects a different encoder, so its selection digest and
  # vectors differ while the stored sources stay as they are.
  defp model("initial"), do: "fixture-model"
  defp model(_), do: "fixture-model-rebuild"

  defp config(ctx, phase) do
    %{
      provider: :ollama,
      provider_module: NoConversation,
      model: "unused",
      home: ctx.home,
      extensions: ctx.entries,
      approval: :ask,
      max_steps: ctx.max_steps,
      approval_origin: :interactive,
      headless: false,
      compact: false,
      inference_services: %{
        "local" => %{"version" => 1, "origins" => ["http://127.0.0.1:#{ctx.port}"]}
      },
      embedding_profiles: %{
        "encoder" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => model(phase),
          "dimensions" => 1024,
          "dimension_mode" => "native",
          "base_url" => "http://127.0.0.1:#{ctx.port}",
          "timeout_ms" => 5000
        }
      }
    }
  end

  def selection(ctx, phase) do
    request = %{"op" => "embedding.profile", "version" => 1, "profile" => "encoder"}

    scope = %{
      "embedding_profiles" => Ipse.Config.Profiles.embedding_snapshot(config(ctx, phase))
    }

    {:ok, binding} = Ipse.Extension.EmbeddingCall.profile_binding(scope, request)

    %{
      "selection_sha256" => binding["selection_sha256"],
      "profile" => "encoder",
      "model" => model(phase),
      "dimensions" => 1024,
      "encoding" => "float32le"
    }
  end

  def open(ctx, phase, _role) do
    opts = [config: config(ctx, phase), cwd: ctx.cwd, state_dir: ctx.dir, subscriber: self()]

    case DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts}) do
      {:ok, pid} ->
        id = Session.info(pid).id
        {:ok, id, %{ctx | pid: pid, monitor: Process.monitor(pid), id: id, offset: 0, events: 0}}

      other ->
        {:error, other, ctx}
    end
  end

  # The scan after confirmed close is the authoritative journal figure for the
  # Session; the per-invocation samples read the same file as it grows.
  def close(ctx) do
    Process.demonitor(ctx.monitor, [:flush])

    with :ok <- Session.close_confirmed(ctx.pid),
         {:ok, scan} <- Journal.read_path(journal(ctx), nil, :validate) do
      {:ok, %{"bytes" => scan.bytes, "events" => scan.count, "tail" => Atom.to_string(scan.tail)},
       %{ctx | pid: nil}}
    else
      other -> {:error, other, %{ctx | pid: nil}}
    end
  end

  def invoke(ctx, command, arguments) do
    :atomics.put(ctx.peak, 1, 0)
    :atomics.put(ctx.peak, 2, 0)
    started = System.monotonic_time(:microsecond)

    {approvals, result} =
      case Session.invoke_export(ctx.pid, :command, "ext__documents__" <> command, arguments) do
        :ok -> wait(ctx, %{approvals: 0, error: nil})
        {:error, :journal_capacity_insufficient} -> {0, {:journal_refusal, @journal_refusal}}
        {:error, reason} -> {0, {:error, reason}}
      end

    wall = System.monotonic_time(:microsecond) - started
    staged = {:atomics.get(ctx.peak, 1), :atomics.get(ctx.peak, 2)}
    {types, ctx} = tail(ctx)
    status = status(ctx)

    observation = %{
      "session" => ctx.id,
      "wall_us" => wall,
      "approvals" => approvals,
      "host_actions" => %{
        "collection" => Map.get(types, "extension_action_intent", 0),
        "embedding" => Map.get(types, "extension_embedding_request", 0),
        "total" =>
          Map.get(types, "extension_action_intent", 0) +
            Map.get(types, "extension_embedding_request", 0)
      },
      "journal" => %{"bytes" => ctx.offset, "events" => ctx.events},
      "collection" =>
        if(is_map(status), do: Map.take(status, Peaks.collection_fields()), else: nil),
      "collection_limits" => if(is_map(status), do: status["limits"], else: nil),
      "collection_status_error" => if(is_map(status), do: nil, else: inspect(status)),
      "staged" =>
        if(staged == {0, 0},
          do: nil,
          else: %{
            "allocated_bytes" => elem(staged, 0),
            "accounted_allocated_bytes" => elem(staged, 1)
          }
        )
    }

    {result, observation, ctx}
  end

  defp wait(ctx, acc) do
    pid = ctx.pid

    receive do
      {:ipse, ^pid, {:approval, ref, kind, _}} when kind in @approvals ->
        case Session.approve(pid, ref, true) do
          :ok -> wait(ctx, %{acc | approvals: acc.approvals + 1})
          other -> {acc.approvals, {:unknown, {:approval_failed, kind, other}}}
        end

      # Any approval this fixture does not expect is denied rather than granted.
      {:ipse, ^pid, {:approval, ref, kind, _}} ->
        Session.approve(pid, ref, false)
        wait(ctx, %{acc | error: acc.error || "unexpected approval request: " <> inspect(kind)})

      {:ipse, ^pid, {:error, error}} ->
        wait(ctx, %{acc | error: acc.error || error})

      {:ipse, ^pid, {:done, :ok}} when acc.error == nil ->
        {acc.approvals, result(ctx)}

      {:ipse, ^pid, {:done, _}} ->
        error = acc.error || "the invocation ended without a result"

        if is_binary(error) and String.contains?(error, @journal_refusal),
          do: {acc.approvals, {:journal_refusal, error}},
          else: {acc.approvals, {:error, error}}

      {:ipse, ^pid, _} ->
        wait(ctx, acc)

      {:DOWN, _, :process, ^pid, reason} ->
        {acc.approvals, {:unknown, {:session_down, reason}}}
    after
      @wait_ms ->
        {acc.approvals,
         {:unknown, acc.error || "no completion within #{@wait_ms} ms; the outcome is unknown"}}
    end
  end

  defp result(ctx) do
    display = Session.info(ctx.pid).extension_result

    cond do
      not is_map(display) ->
        {:unknown, "the Session reported completion without an extension result"}

      delivery = display["delivery"] ->
        case Session.materialize_result(ctx.pid, delivery) do
          {:ok, materialized} ->
            {:ok, materialized.value,
             %{"version" => 1, "session_id" => ctx.id, "delivery" => delivery}}

          other ->
            {:unknown, {:saved_result_unreadable, other}}
        end

      true ->
        {:ok, display["value"], nil}
    end
  end

  defp journal(ctx), do: Path.join(ctx.dir, ctx.id <> ".jsonl")

  # Count the complete records appended since the previous sample.
  defp tail(ctx) do
    with {:ok, file} <- :file.open(String.to_charlist(journal(ctx)), [:read, :binary, :raw]) do
      bytes = read(file, ctx.offset, [])
      :file.close(file)

      case :binary.matches(bytes, "\n") do
        [] ->
          {%{}, ctx}

        matches ->
          {last, 1} = List.last(matches)
          lines = :binary.split(binary_part(bytes, 0, last), "\n", [:global])
          types = Enum.frequencies_by(lines, &event_type/1)
          {types, %{ctx | offset: ctx.offset + last + 1, events: ctx.events + length(lines)}}
      end
    else
      _ -> {%{}, ctx}
    end
  end

  defp read(file, offset, parts) do
    case :file.pread(file, offset, 1_048_576) do
      {:ok, bytes} -> read(file, offset + byte_size(bytes), [bytes | parts])
      _ -> IO.iodata_to_binary(Enum.reverse(parts))
    end
  end

  defp event_type(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => type}} when is_binary(type) -> type
      _ -> "unreadable"
    end
  end

  defp status(ctx) do
    case Collection.execute_profile(
           ctx.store,
           ctx.namespace,
           %{"op" => "status"},
           Usage.id(),
           "document_graph_v1"
         ) do
      {:ok, status} -> status
      other -> other
    end
  end

  # Groups follow the catalog pages, not insertion order: the Job captures
  # each group from them, and a selected fact group must name those sources in
  # that order.
  def groups(ctx, sources) do
    ordinals = Map.new(0..(sources - 1), &{JSON.sha256(Peaks.source_id(&1)), &1})

    Collection.with_document_read(ctx.store, ctx.namespace, fn _, read ->
      with {:ok, %{"value" => %{"pages" => pages}}} when is_list(pages) <-
             DocumentStage.read_value(read, "catalog.notes") do
        Enum.reduce_while(pages, {:ok, []}, fn ref, {:ok, groups} ->
          case DocumentStage.read_value(read, ref["key"]) do
            {:ok, %{"value" => %{"rows" => rows}}} when is_list(rows) ->
              page = Enum.map(rows, &Map.get(ordinals, &1["source_key"]))

              if Enum.all?(page, &is_integer/1),
                do: {:cont, {:ok, groups ++ Enum.chunk_every(page, 8)}},
                else: {:halt, {:error, :unknown_catalog_source}}

            other ->
              {:halt, {:error, {:catalog_page_unreadable, ref["key"], other}}}
          end
        end)
      else
        other -> {:error, {:catalog_unreadable, other}}
      end
    end)
    |> case do
      {:ok, groups} when is_list(groups) -> {:ok, groups}
      {:ok, {:ok, groups}} when is_list(groups) -> {:ok, groups}
      {:ok, {:error, detail}} -> {:error, detail}
      other -> {:error, other}
    end
  end

  ## Loopback embedding fixture

  defp http(listener) do
    case :gen_tcp.accept(listener, 120_000) do
      {:ok, socket} ->
        wire = Jason.decode!(read_http(socket, ""))
        base = if wire["model"] == "fixture-model", do: 1.0, else: 1.5
        vector = for i <- 1..1024, do: base + rem(i, 17) / 17

        body =
          Jason.encode!(%{
            "model" => wire["model"],
            "embeddings" => Enum.map(wire["input"], fn _ -> vector end),
            "prompt_eval_count" => 2
          })

        :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
          body
        ])

        :gen_tcp.close(socket)
        http(listener)

      {:error, :timeout} ->
        http(listener)

      _ ->
        :ok
    end
  end

  defp read_http(socket, bytes) do
    case :binary.split(bytes, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
        read_body(socket, body, String.to_integer(size))

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 10_000)
        read_http(socket, bytes <> more)
    end
  end

  defp read_body(_, bytes, size) when byte_size(bytes) >= size, do: binary_part(bytes, 0, size)

  defp read_body(socket, bytes, size) do
    {:ok, more} = :gen_tcp.recv(socket, 0, 10_000)
    read_body(socket, bytes <> more, size)
  end
end
