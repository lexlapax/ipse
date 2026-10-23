defmodule Ipse.Development.Verification.Memory do
  @moduledoc "Fixed synthetic lexical-memory experiment, independent of command-line output."
  alias Ipse.{Session, Journal}
  alias Ipse.Extension.{Config, Registry, State}
  alias Ipse.Builtins.Memory.Records

  def run(corpus_path) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    corpus_bytes = File.read!(corpus_path)
    corpus = Jason.decode!(corpus_bytes)
    1 = corpus["version"]
    100 = length(corpus["records"])
    100 = length(corpus["questions"])
    root = Path.join(System.tmp_dir!(), "ipse-memory-measure-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    home = Path.join(root, "home")
    File.mkdir_p!(home)

    operator = %{
      scope: "operator",
      path: Path.join(root, "operator.json"),
      data: %{
        "extensions" => [
          %{
            "instance" => "notes",
            "artifact" => "builtin:persistent-memory:1",
            "enabled" => true,
            "options" => %{"scope" => "project", "retention_seconds" => 3600},
            "order" => 1,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => "builtin:persistent-memory:1",
            "capabilities" => Ipse.Builtins.Memory.describe()["capabilities"],
            "allow_project" => false,
            "allow_children" => false,
            "state_bindings" => [
              %{
                "version" => 1,
                "instance" => "notes",
                "id" => "measurement",
                "scopes" => ["project"]
              }
            ]
          }
        ]
      }
    }

    {:ok, catalog} = Config.resolve([operator], [])
    {:ok, entries} = Registry.prepare(catalog, home)

    sessions =
      for project <- ~w(alpha beta), n <- 0..2, into: %{} do
        cwd = Path.join(root, project)
        File.mkdir_p!(cwd)

        config = %{
          provider: :demo,
          model: "no-inference",
          provider_module: __MODULE__,
          home: home,
          operator_home: nil,
          extensions: entries,
          approval: :allow,
          compact: false
        }

        {:ok, pid} =
          DynamicSupervisor.start_child(
            Ipse.Sessions,
            {Session,
             config: config,
             cwd: cwd,
             state_dir: Path.join(root, "sessions"),
             subscriber: self(),
             owner: self()}
          )

        {{project, n}, pid}
      end

    try do
      for record <- corpus["records"] do
        pid = sessions[{record["project"], 0}]
        args = Map.drop(record, ~w(project mode))
        result = command(pid, "remember", args)
        "stored" = result["status"]

        case record["mode"] do
          "updated" ->
            "stored" =
              command(pid, "remember", %{
                args
                | "source_generation" => 2,
                  "expected_revision" => 1,
                  "text" =>
                    args["text"] <> " Updated with a conflict-resolved operator statement."
              })["status"]

          "forgotten" ->
            "stored" =
              command(
                pid,
                "forget",
                Map.take(args, ["source"]) |> Map.put("expected_revision", 1)
              )["status"]

          "expired" ->
            [entry] = entries

            {:ok, namespace} =
              State.namespace(
                entry.identity,
                "project",
                Session.info(pid).cwd,
                Session.info(pid).id
              )

            {:ok, note} = Records.build(args, nil, 1000, 60)

            {:ok, _} =
              State.execute(
                Path.join(home, "extension-state-v1"),
                namespace,
                %{
                  "op" => "state.put",
                  "scope" => "project",
                  "key" => Records.key(args["source"]),
                  "expected_revision" => 1,
                  "value" => note
                },
                Ipse.Usage.id()
              )

          _ ->
            :ok
        end
      end

      observations =
        for q <- corpus["questions"] do
          pid = sessions[{q["project"], q["session"]}]
          before_memory = :erlang.memory(:total)
          started = System.monotonic_time(:microsecond)
          result = command(pid, "recall", %{"query" => q["query"], "limit" => 5})
          elapsed = System.monotonic_time(:microsecond) - started
          "recalled" = result["status"]
          matches = result["matches"]
          wanted = q["expected_sources"]
          actual = Enum.map(matches, & &1["source"])

          exact =
            Enum.all?(matches, fn match ->
              source = Enum.find(corpus["records"], &(&1["source"] == match["source"]))

              text =
                source["text"] <>
                  if(source["mode"] == "updated",
                    do: " Updated with a conflict-resolved operator statement.",
                    else: ""
                  )

              match["text_sha256"] == Ipse.JSON.sha256(text) and
                binary_part(
                  text,
                  match["span"]["start_byte"],
                  match["span"]["end_byte"] - match["span"]["start_byte"]
                ) == match["excerpt"]
            end)

          %{
            "id" => q["id"],
            "latency_us" => elapsed,
            "pass" => actual == wanted and exact,
            "recall_at_5" =>
              if(wanted == [],
                do: nil,
                else: length(Enum.filter(wanted, &(&1 in actual))) / length(wanted)
              ),
            "citation_count" => length(matches),
            "exact_citations" => if(exact, do: length(matches), else: 0),
            "observed_vm_bytes" => max(before_memory, :erlang.memory(:total))
          }
        end

      true = Enum.all?(observations, & &1["pass"])

      requests =
        Enum.sum(for {_, pid} <- sessions, do: Session.info(pid).accounting["request_count"])

      0 = requests

      state_bytes =
        Path.wildcard(Path.join(home, "extension-state-v1/*/state.json"))
        |> Enum.map(&File.stat!(&1).size)
        |> Enum.sum()

      for {_, pid} <- sessions do
        id = Session.info(pid).id
        :ok = Session.close(pid)
        {:ok, events} = Journal.load(Path.join(root, "sessions"), id)
        {:ok, _} = Session.restore_context(events)
      end

      latencies = observations |> Enum.map(& &1["latency_us"]) |> Enum.sort()
      citations = Enum.sum(Enum.map(observations, & &1["citation_count"]))

      report = %{
        "version" => 1,
        "kind" => "synthetic_lexical_fixture_not_semantic_model_benchmark",
        "corpus_sha256" => Ipse.JSON.sha256(corpus_bytes),
        "records" => 100,
        "questions" => 100,
        "projects" => 2,
        "sessions" => 6,
        "passed" => true,
        "correct_retrieval_or_abstention" => 1.0,
        "recall_at_5" =>
          Enum.map(observations, & &1["recall_at_5"])
          |> Enum.reject(&is_nil/1)
          |> then(&(Enum.sum(&1) / length(&1))),
        "exact_span_precision" =>
          Enum.sum(Enum.map(observations, & &1["exact_citations"])) / max(citations, 1),
        "p50_us" => Enum.at(latencies, 49),
        "p95_us" => Enum.at(latencies, 94),
        "observed_vm_bytes" => Enum.max(Enum.map(observations, & &1["observed_vm_bytes"])),
        "state_bytes" => state_bytes,
        "model_calls" => requests,
        "model_cost" => "none_no_model_dispatch",
        "encoder_calls" => 0,
        "ndcg_at_10" => "not_measured_tool_returns_at_most_5",
        "runtime" => %{
          "elixir" => System.version(),
          "otp" => System.otp_release(),
          "schedulers" => System.schedulers_online(),
          "architecture" => to_string(:erlang.system_info(:system_architecture))
        },
        "limits" =>
          "Synthetic exact-token retrieval; no semantic answer or human citation assessment; VM samples are not a peak-memory proof."
      }

      report
    after
      for {_, pid} <- sessions, Process.alive?(pid), do: Session.close(pid)
      File.rm_rf!(root)
    end
  end

  def complete(_, _, _, _), do: raise("Memory measurement must not dispatch inference")

  defp command(pid, id, args) do
    :ok = Session.invoke_export(pid, :command, "ext__notes__" <> id, args)
    await(pid, nil)
  end

  defp await(pid, result) do
    receive do
      {:ipse, ^pid, {:extension_result, %{"value" => value}}} -> await(pid, value)
      {:ipse, ^pid, {:done, :ok}} when is_map(result) -> result
      {:ipse, ^pid, {:done, _}} -> raise("Memory fixture command failed")
      {:ipse, ^pid, _} -> await(pid, result)
    after
      15_000 -> raise("Memory fixture command timed out")
    end
  end
end
