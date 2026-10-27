defmodule Ipse.Extension.SubscriptionsTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extension.{Config, Registry, Artifact, Subscriptions}
  alias Ipse.Journal

  defmodule Model do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, {:subscription_model, messages})

      if config[:native_question] == true and
           not Enum.any?(messages, &(&1["role"] == "assistant")) do
        arguments = %{
          "questions" => [
            %{"id" => "choice", "prompt" => "Choose synthetic continuation", "kind" => "text"}
          ]
        }

        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "native_fixture_question",
               "type" => "function",
               "function" => %{
                 "name" => "ask_operator",
                 "arguments" => Jason.encode!(arguments)
               }
             }
           ]
         }, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => Map.get(config, :answer_text, "answer"),
           "provider_data" => %{"native" => "synthetic-native-secret"}
         }, %{}}
      end
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-subscription-artifacts-#{Ipse.Usage.id()}")

    artifacts =
      for {kind, private, required, family} <- [
            {:private, true, true, :prompt},
            {:optional, true, false, :prompt},
            {:metadata, false, true, :prompt},
            {:answer, true, true, :answer},
            {:answer_optional, true, false, :answer},
            {:answer_metadata, false, true, :answer}
          ],
          into: %{} do
        declarations =
          for {id, event, view} <-
                if(family == :prompt,
                  do: [
                    {"original", "prompt.received", "prompt.original"},
                    {"effective", "prompt.effective_committed", "prompt.effective"}
                  ],
                  else: [
                    {"original", "answer.committed", "answer.original"},
                    {"presented", "answer.committed", "answer.presented"}
                  ]
                ),
              do:
                Map.merge(
                  %{
                    "id" => id,
                    "event" => event,
                    "view" => if(private, do: view, else: "metadata"),
                    "event_version" => 1,
                    "mode" => "notify",
                    "required" => required
                  },
                  if(family == :answer, do: %{"schedule" => "after_turn"}, else: %{})
                )

        capabilities =
          if private,
            do:
              if(family == :answer,
                do: ~w(event.notify event.answer.original event.answer.presented),
                else: ~w(event.notify event.prompt.original event.prompt.effective)
              ),
            else: ["event.notify"]

        directory = Path.join(root, Atom.to_string(kind))
        File.mkdir_p!(Path.join(directory, "ebin"))
        module = "Independent.Subscription#{System.unique_integer([:positive])}"

        code = """
        defmodule #{module} do
          @behaviour Ipse.Extension
          def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "subscriptions" => #{inspect(declarations)}}
          def init(options) do
            File.write!(options["trace"], Jason.encode!(%{"initialized" => true}) <> "\n", [:append])
            {:ok, options}
          end
          def handle("event.notify", payload, state) do
            File.write!(state["trace"], Jason.encode!(payload) <> "\n", [:append])
            if state["mode"] == "hang" do
              File.write!(state["pid"] <> ".ready-" <> System.pid(), System.pid())
              File.rename!(state["pid"] <> ".ready-" <> System.pid(), state["pid"])
              Process.sleep(:infinity)
            end
            reply = if state["mode"] == "host_call" do
              %{"api_version" => 1, "kind" => "host_call", "request" => %{"op" => "state.put", "key" => "unapproved", "value" => %{"text" => "no"}, "expected_revision" => 0}}
            else
              %{"api_version" => 1, "kind" => "ack", "delivery_id" => payload["delivery_id"], "event_id" => payload["event"]["event_id"]}
            end
            {:ok, reply, state}
          end
        end
        """

        file = Path.join(directory, "fixture.ex")
        File.write!(file, code)

        {output, status} =
          System.cmd(
            System.find_executable("elixirc"),
            ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(directory, "ebin"), file],
            stderr_to_stdout: true
          )

        assert status == 0, output
        File.write!(Path.join(directory, "LICENSE"), "MIT synthetic fixture")

        manifest = %{
          "format" => 1,
          "id" => "fixture/subscription",
          "version" => "0.1.0",
          "sdk" => 1,
          "protocol" => 1,
          "backend" => "elixir_worker",
          "entrypoint" => module,
          "license_file" => "LICENSE",
          "capabilities" => capabilities,
          "subscriptions" => declarations,
          "options_schema" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(trace pid mode),
            "properties" => Map.new(~w(trace pid mode), &{&1, %{"type" => "string"}})
          },
          "runtime" => %{
            "elixir" => ">= 1.18.0",
            "otp" => [String.to_integer(System.otp_release())],
            "platforms" => [to_string(:erlang.system_info(:system_architecture))]
          },
          "files" =>
            Enum.map(["LICENSE", "ebin/Elixir.#{module}.beam"], fn path ->
              bytes = File.read!(Path.join(directory, path))
              %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
            end)
        }

        File.write!(Path.join(directory, "extension.json"), Jason.encode!(manifest))
        {kind, %{directory: directory, manifest: manifest}}
      end

    on_exit(fn -> File.rm_rf!(root) end)
    %{artifacts: artifacts}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-event-notify-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      home: Path.join(root, "home"),
      dir: Path.join(root, "sessions"),
      trace: Path.join(root, "trace.jsonl"),
      pid_file: Path.join(root, "worker.pid")
    }
  end

  defp config(c, kind, mode \\ "record", enabled \\ true, instance \\ "subscriber") do
    {:ok, artifact} =
      Artifact.import(c.artifacts[kind].directory, Path.join(c.home, "extensions/artifacts"))

    data = %{
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false
        }
      ],
      "extensions" => [
        %{
          "instance" => instance,
          "artifact" => artifact.digest,
          "enabled" => enabled,
          "options" => %{"trace" => c.trace, "pid" => c.pid_file, "mode" => mode},
          "order" => 1,
          "lifetime" => "session"
        }
      ]
    }

    {:ok, catalog} =
      Config.resolve([%{scope: "operator", path: "/synthetic/operator.json", data: data}], [])

    {:ok, entries} = Registry.prepare(catalog, c.home)

    %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      test_pid: self(),
      home: c.home,
      approval: :deny,
      extensions: entries,
      context_bytes: 65_536,
      max_steps: 3
    }
  end

  defp start(c, config, id \\ nil),
    do:
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, [config: config, cwd: c.root, state_dir: c.dir, subscriber: self(), id: id]}
      )

  defp trace(c),
    do: c.trace |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

  defp done(session, status), do: assert_receive({:ipse, ^session, {:done, ^status}}, 15_000)
  defp eventually(fun, attempts \\ 200)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if not fun.(),
      do:
        (
          Process.sleep(10)
          eventually(fun, attempts - 1)
        )
  end

  defp alive?(pid), do: elem(System.cmd("kill", ["-0", pid], stderr_to_stdout: true), 1) == 0

  test "native clarification resume retains answer delivery without rerunning prompt notifications",
       c do
    config = config(c, :answer, "record", true, "answers") |> Map.put(:native_question, true)
    prompt_config = config(c, :metadata)

    config = %{
      config
      | extensions:
          Enum.sort_by(
            config.extensions ++ prompt_config.extensions,
            &{&1.identity["order"], &1.identity["instance"]}
          )
    }

    {:ok, session} = start(c, config)
    :ok = Session.prompt(session, "Question before answer")
    assert_receive {:ipse, ^session, {:question, question, _}}, 10_000
    before = trace(c)
    assert Enum.count(before, &Map.has_key?(&1, "event")) == 2
    id = Session.info(session).id
    Process.exit(session, :kill)
    eventually(fn -> not Process.alive?(session) end)
    {:ok, resumed} = start(c, config, id)
    assert_receive {:ipse, ^resumed, {:question, ^question, _}}, 1000
    assert trace(c) == before
    :ok = Session.answer(resumed, question, %{"choice" => "continue"})
    done(resumed, :ok)
    assert Enum.count(trace(c), &Map.has_key?(&1, "event")) == 4
    {:ok, events} = Journal.load(c.dir, id)
    assert Enum.count(events, &(&1["type"] == "lifecycle_prompt_received")) == 1
    assert Enum.count(events, &(&1["type"] == "request_admitted")) == 2
    assert Subscriptions.validate_events(events) == :ok
    assert match?({:ok, _}, Session.restore_context(events))
    checkpoint = Enum.find(events, &(&1["type"] == "lifecycle_question_sources"))
    assert checkpoint["question_id"] == question
    effective = Enum.find(events, &(&1["type"] == "lifecycle_prompt_committed"))
    {:ok, forged_source} = Journal.source(id, 0, effective)

    forged =
      Enum.map(events, fn e ->
        if e == checkpoint, do: Map.put(e, "effective_source", forged_source), else: e
      end)

    assert Subscriptions.validate_events(forged) == :ok

    assert Subscriptions.validate_sources(c.dir, id, forged) ==
             {:error, :invalid_extension_subscription}

    :ok = Session.close(resumed)
  end

  test "answer views retain native-visible and final presented text with shared source identity",
       c do
    config = config(c, :answer)

    formatter = %{
      "instance" => "formatter",
      "artifact" => "builtin:answer-format:1",
      "enabled" => true,
      "options" => %{"prefix" => "<answer>", "suffix" => "</answer>"},
      "order" => 0,
      "lifetime" => "session"
    }

    trust = %{
      "artifact" => formatter["artifact"],
      "capabilities" => ["transform.presentation"],
      "allow_project" => false,
      "allow_children" => false
    }

    {:ok, catalog} =
      Config.resolve(
        [
          %{
            scope: "operator",
            path: "/synthetic/formatter.json",
            data: %{"extensions" => [formatter], "extension_trust" => [trust]}
          }
        ],
        []
      )

    {:ok, [entry]} = Registry.prepare(catalog, c.home)
    config = %{config | extensions: [entry | config.extensions]}
    {:ok, session} = start(c, config)
    :ok = Session.prompt(session, "synthetic private prompt")
    done(session, :ok)
    [_, original, _, presented] = trace(c)
    assert original["event"]["data"]["text"] == "answer"
    assert presented["event"]["data"]["text"] == "<answer>answer</answer>"
    assert original["event"]["event_id"] == presented["event"]["event_id"]
    refute Jason.encode!(trace(c)) =~ "synthetic-native-secret"
    refute Jason.encode!(trace(c)) =~ "synthetic private prompt"
    id = Session.info(session).id
    {:ok, events} = Journal.load(c.dir, id)
    answer = Enum.find(events, &(&1["type"] == "lifecycle_answer_committed"))
    assert answer["presented"] == Session.info(session).final
    request = Enum.find(events, &(&1["type"] == "request_admitted"))
    assert original["event"]["correlations"]["request_id"] == request["request_id"]
    assert Subscriptions.validate_events(events) == :ok
    assert Subscriptions.validate_sources(c.dir, id, events) == :ok
    assert match?({:ok, _}, Session.restore_context(events))

    changed =
      Enum.map(events, fn e ->
        if e == answer do
          e
          |> Map.put("presented", "forged")
          |> Map.put("presented_bytes", 6)
          |> Map.put("presented_sha256", Ipse.JSON.sha256("forged"))
        else
          e
        end
      end)

    assert Subscriptions.validate_events(changed) == {:error, :invalid_extension_subscription}
    :ok = Session.close(session)
    bytes = File.read!(Path.join(c.dir, id <> ".jsonl"))
    before = trace(c)
    {:ok, resumed} = start(c, config, id)
    assert File.read!(Path.join(c.dir, id <> ".jsonl")) == bytes
    assert trace(c) == before
    :ok = Session.close(resumed)
  end

  test "answer metadata and disabled instances never receive private output", c do
    {:ok, session} = start(c, config(c, :answer_metadata))
    :ok = Session.prompt(session, "private prompt")
    done(session, :ok)
    entries = for row <- trace(c), row["event"], do: row["event"]
    assert length(entries) == 2
    assert Enum.all?(entries, &(&1["data"] == %{"original_bytes" => 6, "presented_bytes" => 6}))
    refute Jason.encode!(entries) =~ "\"text\""
    refute Jason.encode!(entries) =~ "record_sha256"
    :ok = Session.close(session)
    File.rm!(c.trace)
    {:ok, session} = start(c, config(c, :answer, "record", false))
    :ok = Session.prompt(session, "private prompt")
    done(session, :ok)
    refute File.exists?(c.trace)
    {:ok, events} = Journal.load(c.dir, Session.info(session).id)
    refute Enum.any?(events, &(&1["type"] == "lifecycle_answer_committed"))
    :ok = Session.close(session)
  end

  test "oversized private answers refuse without truncating native history or initializing workers",
       c do
    for {kind, status} <- [{:answer_optional, :ok}, {:answer, :error}] do
      config = config(c, kind) |> Map.put(:answer_text, String.duplicate("a", 8193))
      {:ok, session} = start(c, config)
      :ok = Session.prompt(session, "bounded answer fixture")
      done(session, status)
      refute File.exists?(c.trace)
      {:ok, events} = Journal.load(c.dir, Session.info(session).id)
      answer = Enum.find(events, &(&1["type"] == "lifecycle_answer_committed"))
      assert answer["original"] == nil and answer["presented"] == nil
      assert answer["original_bytes"] == 8193
      assert byte_size(Session.info(session).final) == 8193
      assert Subscriptions.validate_events(events) == :ok

      assert Enum.all?(
               Enum.filter(events, &(&1["type"] == "extension_event_result")),
               &(&1["outcome"] == "not_started")
             )

      :ok = Session.close(session)
    end
  end

  test "answer notifications cannot turn acknowledgments into mutations or undo the saved answer",
       c do
    {:ok, session} = start(c, config(c, :answer, "host_call"))
    :ok = Session.prompt(session, "answer first")
    done(session, :error)
    assert Session.info(session).final == "answer"
    {:ok, events} = Journal.load(c.dir, Session.info(session).id)
    assert Enum.count(events, &(&1["type"] == "request_admitted")) == 1
    refute Enum.any?(events, &(&1["type"] == "extension_action_intent"))
    assert Subscriptions.validate_events(events) == :ok
    :ok = Session.close(session)
  end

  test "answer capabilities and after-turn timing are explicit, not inferred from prompt access",
       c do
    declaration = c.artifacts.answer.manifest["subscriptions"] |> hd()
    assert Subscriptions.validate([declaration], ~w(event.notify event.answer.original)) == :ok

    assert {:error, :invalid_extension_subscription} =
             Subscriptions.validate([declaration], ~w(event.notify event.prompt.original))

    assert {:error, :invalid_extension_subscription} =
             Subscriptions.validate(
               [Map.put(declaration, "schedule", "before_request")],
               ~w(event.notify event.answer.original)
             )

    assert {:error, :invalid_extension_subscription} =
             Subscriptions.validate(
               [Map.delete(declaration, "schedule")],
               ~w(event.notify event.answer.original)
             )
  end

  test "private declarations deliver original then final effective prompt with synced receipts",
       c do
    config = config(c, :private)

    annotation = %{
      "instance" => "annotation",
      "artifact" => "builtin:prompt-annotation:1",
      "enabled" => true,
      "options" => %{"text" => "synthetic annotation"},
      "order" => 0,
      "lifetime" => "session"
    }

    trust = %{
      "artifact" => annotation["artifact"],
      "capabilities" => ["transform.prompt"],
      "allow_project" => false,
      "allow_children" => false
    }

    {:ok, catalog} =
      Config.resolve(
        [
          %{
            scope: "operator",
            path: "/synthetic/annotation.json",
            data: %{"extensions" => [annotation], "extension_trust" => [trust]}
          }
        ],
        []
      )

    {:ok, [entry]} = Registry.prepare(catalog, c.home)
    config = %{config | extensions: [entry | config.extensions]}
    {:ok, session} = start(c, config)
    :ok = Session.prompt(session, "synthetic original")
    done(session, :ok)
    assert_receive {:subscription_model, [_system, _reference, user, selection]}
    assert Ipse.Session.Reference.reference?(selection)
    [_, original, _, effective] = trace(c)
    assert original["event"]["data"]["text"] == "synthetic original"
    assert effective["event"]["data"]["text"] == user["content"]
    assert String.contains?(user["content"], "synthetic annotation")
    refute original["event"]["event_id"] == effective["event"]["event_id"]
    refute String.contains?(Jason.encode!(trace(c)), "synthetic-native-secret")
    id = Session.info(session).id
    {:ok, events} = Journal.load(c.dir, id)
    assert Subscriptions.validate_events(events) == :ok
    assert Subscriptions.validate_sources(c.dir, id, events) == :ok
    first_request = Enum.find_index(events, &(&1["type"] == "request_admitted"))

    assert events
           |> Enum.take(first_request)
           |> Enum.count(&(&1["type"] == "extension_event_result")) == 2

    :ok = Session.close(session)
  end

  test "metadata-only and disabled selections never acquire private text or implicit startup",
       c do
    {:ok, session} = start(c, config(c, :metadata))
    :ok = Session.prompt(session, "synthetic-secret-to-exclude")
    done(session, :ok)

    for delivery <- trace(c), Map.has_key?(delivery, "event") do
      assert delivery["event"]["view"] == "metadata"
      refute Map.has_key?(delivery["event"]["source"], "record_sha256")
    end

    refute String.contains?(File.read!(c.trace), "synthetic-secret-to-exclude")
    :ok = Session.close(session)
    File.rm!(c.trace)
    {:ok, disabled} = start(c, config(c, :private, "record", false))
    :ok = Session.prompt(disabled, "disabled")
    done(disabled, :ok)
    refute File.exists?(c.trace)
    :ok = Session.close(disabled)
  end

  test "host-call replies grant no effects; required failure blocks inference and optional failure is recorded",
       c do
    {:ok, required} = start(c, config(c, :private, "host_call"))
    :ok = Session.prompt(required, "required")
    done(required, :error)
    refute_receive {:subscription_model, _}, 100
    {:ok, events} = Journal.load(c.dir, Session.info(required).id)

    assert [%{"outcome" => "unknown", "cleanup_confirmed" => true}] =
             Enum.filter(events, &(&1["type"] == "extension_event_result"))

    refute Enum.any?(events, &(&1["type"] == "extension_action_intent"))
    :ok = Session.close(required)
    {:ok, optional} = start(c, config(c, :optional, "host_call"))
    :ok = Session.prompt(optional, "optional")
    done(optional, :ok)
    assert_receive {:subscription_model, _}
    {:ok, events} = Journal.load(c.dir, Session.info(optional).id)
    assert Subscriptions.validate_events(events) == :ok

    assert Enum.count(
             events,
             &(&1["type"] == "extension_event_result" and &1["outcome"] == "unknown")
           ) == 2

    :ok = Session.close(optional)
  end

  test "oversized private input refuses before initializer, without truncation or inference", c do
    {:ok, session} = start(c, config(c, :private))
    :ok = Session.prompt(session, String.duplicate("a", 8193))
    done(session, :error)
    refute File.exists?(c.trace)
    refute_receive {:subscription_model, _}, 100
    {:ok, events} = Journal.load(c.dir, Session.info(session).id)

    assert [%{"payload_sha256" => nil}] =
             Enum.filter(events, &(&1["type"] == "extension_event_intent"))

    assert [%{"outcome" => "not_started"}] =
             Enum.filter(events, &(&1["type"] == "extension_event_result"))

    assert Subscriptions.validate_events(events) == :ok
    :ok = Session.close(session)
  end

  test "idle resume never replays delivery; explicit identical input gets new occurrence IDs",
       c do
    config = config(c, :private)
    {:ok, session} = start(c, config)
    :ok = Session.prompt(session, "same prompt")
    done(session, :ok)
    id = Session.info(session).id
    :ok = Session.close(session)
    path = Path.join(c.dir, id <> ".jsonl")
    bytes = File.read!(path)
    old_trace = trace(c)
    {:ok, resumed} = start(c, config, id)
    assert Session.info(resumed).id == id
    assert File.read!(path) == bytes
    assert trace(c) == old_trace
    :ok = Session.prompt(resumed, "same prompt")
    done(resumed, :ok)

    ids =
      for delivery <- trace(c), Map.has_key?(delivery, "event"), do: delivery["event"]["event_id"]

    assert length(ids) == 4 and length(Enum.uniq(ids)) == 4
    :ok = Session.close(resumed)
  end

  test "cancel and untrappable owner death stop actual worker VMs without resume callbacks", c do
    for {kind, stop} <- [
          {:private, :cancel},
          {:private, :kill},
          {:answer, :cancel},
          {:answer, :kill}
        ] do
      config = config(c, kind, "hang")
      File.rm(c.pid_file)
      {:ok, session} = start(c, config)
      :ok = Session.prompt(session, "blocked callback")
      eventually(fn -> File.exists?(c.pid_file) end)
      pid = File.read!(c.pid_file)
      assert alive?(pid)
      id = Session.info(session).id

      if stop == :cancel,
        do: assert(:ok == Session.cancel(session)),
        else: Process.exit(session, :kill)

      eventually(fn -> not alive?(pid) end)
      if stop == :cancel, do: assert(:ok == Session.close(session))
      bytes = File.read!(Path.join(c.dir, id <> ".jsonl"))
      entries = trace(c)
      eventually(fn -> match?({:ok, _}, Journal.load(c.dir, id)) end)
      {:ok, resumed} = start(c, config, id)
      assert Session.info(resumed).id == id
      assert Session.info(resumed).phase == :idle
      assert File.read!(Path.join(c.dir, id <> ".jsonl")) == bytes
      assert trace(c) == entries
      :ok = Session.close(resumed)
    end
  end

  test "unknown versions, modes, views and widened read capabilities refuse inert admission", c do
    manifest = c.artifacts.private.manifest
    [declaration | rest] = manifest["subscriptions"]

    for changed <- [
          Map.put(declaration, "mode", "job"),
          Map.put(declaration, "event_version", 2),
          Map.put(declaration, "view", "prompt.effective"),
          Map.put(declaration, "event", "*"),
          Map.put(declaration, "filter", "executable")
        ] do
      assert {:error, _} =
               Artifact.decode(
                 Jason.encode!(Map.put(manifest, "subscriptions", [changed | rest]))
               )
    end

    assert {:error, _} =
             Artifact.decode(Jason.encode!(Map.put(manifest, "capabilities", ["event.notify"])))
  end

  test "large source input and excessive selections refuse before executable admission", c do
    config = config(c, :metadata)
    {:ok, session} = start(c, config)
    path = Path.join(c.dir, Session.info(session).id <> ".jsonl")
    before = File.read!(path)

    assert {:error, :subscription_prompt_too_large_or_invalid} =
             Session.prompt(session, String.duplicate("a", Journal.source_record_bytes()))

    assert Session.info(session).phase == :idle
    assert File.read!(path) == before
    refute File.exists?(c.trace)
    :ok = Session.close(session)
    [entry] = config.extensions
    entries = for instance <- ~w(a b c d e), do: put_in(entry, [:identity, "instance"], instance)
    refute Registry.valid_entries?(%{extensions: entries})
    assert Registry.child_entries(config) == []
  end

  test "callback timeout records an unknown delivery and closes its actual VM", c do
    {:ok, session} = start(c, config(c, :private, "hang"))
    :ok = Session.prompt(session, "bounded timeout")
    done(session, :error)
    assert File.exists?(c.pid_file)
    eventually(fn -> not alive?(File.read!(c.pid_file)) end)
    refute_receive {:subscription_model, _}, 100
    {:ok, events} = Journal.load(c.dir, Session.info(session).id)

    assert [%{"outcome" => "unknown", "cleanup_confirmed" => false}] =
             Enum.filter(events, &(&1["type"] == "extension_event_result"))

    assert Subscriptions.validate_events(events) == :ok
    assert {:error, :cleanup_unconfirmed} = Session.close(session)
  end

  test "coherently forged physical references and missing receipts refuse before tail repair",
       c do
    config = config(c, :private)
    {:ok, session} = start(c, config)
    :ok = Session.prompt(session, "source binding fixture")
    done(session, :ok)
    id = Session.info(session).id
    :ok = Session.close(session)
    path = Path.join(c.dir, id <> ".jsonl")
    {:ok, %{records: records, next: nil}} = Journal.source_page(c.dir, id, 0, 64)
    events = Enum.map(records, & &1.record)
    received = Enum.find(records, &(&1.record["type"] == "lifecycle_prompt_received"))
    {:ok, forged} = Journal.source(id, received.source["byte_offset"] + 1, received.record)
    marker = Enum.find(records, &(&1.record["type"] == "lifecycle_prompt_committed"))
    changed_marker = Map.put(marker.record, "received_source", forged)

    {:ok, changed_marker_source} =
      Journal.source(id, marker.source["byte_offset"], changed_marker)

    {altered, _} =
      Enum.map_reduce(events, %{}, fn event, intents ->
        case event["type"] do
          "lifecycle_prompt_committed" ->
            {changed_marker, intents}

          "extension_event_intent" ->
            original? = event["declaration"]["event"] == "prompt.received"
            source = if original?, do: forged, else: changed_marker_source
            record = if original?, do: received.record, else: changed_marker
            changed = Map.put(event, "source", source)
            payload = Subscriptions.payload(changed, record)
            changed = Map.put(changed, "payload_sha256", Ipse.JSON.digest([payload]))
            {changed, Map.put(intents, changed["delivery_id"], changed)}

          "extension_event_result" ->
            {Subscriptions.result(
               intents[event["delivery_id"]],
               event["outcome"],
               event["cleanup_confirmed"]
             ), intents}

          _ ->
            {event, intents}
        end
      end)

    assert Subscriptions.validate_events(altered) == :ok
    assert {:ok, _} = Session.restore_context(altered)

    for corruption <- [altered, Enum.reject(events, &(&1["type"] == "extension_event_result"))] do
      bytes = Enum.map_join(corruption, "\n", &Jason.encode!/1) <> "\n{\"interrupted\":"
      File.write!(path, bytes)
      assert {:error, _} = Ipse.Session.Saved.inspect_saved(c.dir, id)
      assert {:error, _} = start(c, config, id)
      assert File.read!(path) == bytes
    end
  end
end
