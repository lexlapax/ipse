defmodule IpseSavedResultsExample.Proof do
  @moduledoc false
  alias Ipse.{Journal, Session}
  alias Ipse.Extensions.{Config, Invocation, Manifest, Registry, ResultReader, Store}

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("Saved-result proof unexpectedly called a model")
  end

  def run(artifact) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    unloaded!()
    root = Path.join(System.tmp_dir!(), "ipse-saved-results-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    Process.put(:saved_result_sessions, [])

    try do
      home = Path.join(root, "home")
      store = Path.join(home, "extensions/artifacts")
      load_marker = Path.join(home, "extensions/worker-loads.log")
      callback_marker = Path.join(root, "callbacks.log")
      {:ok, imported} = Store.import(Path.expand(artifact), store)
      false = File.exists?(load_marker)
      manifest = imported.manifest
      2 = manifest["sdk"]
      ~w(invoke.command invoke.result.pages) = manifest["capabilities"]

      source = %{
        scope: "operator",
        path: Path.join(root, "operator.json"),
        data: %{
          "extensions" => [
            %{
              "instance" => "saved",
              "artifact" => imported.digest,
              "enabled" => true,
              "options" => %{"callback_marker" => callback_marker},
              "order" => 0,
              "lifetime" => "persistent"
            }
          ],
          "extension_trust" => [
            %{
              "artifact" => imported.digest,
              "capabilities" => manifest["capabilities"],
              "allow_project" => false,
              "allow_children" => false
            }
          ]
        }
      }

      {:ok, selected} = Config.resolve([source], [])
      {:ok, entries} = Registry.prepare(selected, home)
      false = File.exists?(load_marker)

      config = %{
        provider: :demo,
        model: "unused",
        provider_module: NoModel,
        home: home,
        operator_home: nil,
        approval: :ask,
        compact: false,
        extensions: entries
      }

      cwd = Path.join(root, "workspace")
      File.mkdir!(cwd)
      state_dir = Path.join(root, "sessions")
      session = start(config, cwd, state_dir)
      false = File.exists?(load_marker)
      :ok = Session.invoke_export(session, :command, "ext__saved__publish", %{})
      wait(session, System.monotonic_time(:millisecond) + 60_000)
      info = Session.info(session)
      0 = info.accounting["request_count"]
      delivery = info.extension_result["delivery"]
      4_194_304 = delivery["byte_count"]
      {:ok, events} = Journal.load(state_dir, info.id)
      :ok = Invocation.validate_events(events)
      chunks = Enum.filter(events, &(&1["type"] == "extension_output_chunk"))
      1024 = length(chunks)
      true = Enum.all?(chunks, &(&1["byte_count"] == 4096))
      4_194_304 = List.last(chunks)["next"]
      1 = Enum.count(events, &(&1["type"] == "extension_output_seal"))
      [%{"version" => 2}] = Enum.filter(events, &(&1["type"] == "extension_invocation_result"))
      {:ok, original} = Session.materialize_result(session, delivery)
      "historical_receipt" = original.provenance
      4_194_304 = byte_size(original.bytes)
      true = Manifest.sha256(original.bytes) == delivery["sha256"]
      true = original.value["items"] == List.duplicate(String.duplicate("x", 8192), 511)
      true = String.trim(original.value["pad"], "y") == ""

      {:ok, view} =
        Session.read_saved_result(session, %{
          "output_id" => delivery["output_id"],
          "path" => ["items", 0]
        })

      :ok = Ipse.Extension.validate(view)
      true = byte_size(Jason.encode!(view)) <= 12_000 and view["historical_receipt"]
      false = view["complete"]
      :ok = Session.close_confirmed(session)
      loads = File.read!(load_marker)
      callbacks = File.read!(callback_marker)
      1 = length(String.split(loads, "\n", trim: true))
      1 = length(String.split(callbacks, "\n", trim: true))
      path = Path.join(state_dir, info.id <> ".jsonl")
      journal_sha = Manifest.sha256(File.read!(path))
      {:ok, ^original} = ResultReader.saved(state_dir, info.id, delivery["output_id"])
      resumed = start(config, cwd, state_dir, info.id)
      :idle = Session.info(resumed).phase
      0 = Session.info(resumed).accounting["request_count"]
      {:ok, ^original} = Session.materialize_result(resumed, delivery)

      {:ok, ^view} =
        Session.read_saved_result(resumed, %{
          "output_id" => delivery["output_id"],
          "path" => ["items", 0]
        })

      :ok = Session.close_confirmed(resumed)
      ^loads = File.read!(load_marker)
      ^callbacks = File.read!(callback_marker)
      ^journal_sha = Manifest.sha256(File.read!(path))
      unloaded!()

      %{
        "artifact_sha256" => imported.digest,
        "byte_count" => delivery["byte_count"],
        "fragment_count" => length(chunks),
        "sha256" => delivery["sha256"],
        "historical_reads_exact" => true,
        "resume_inert" => true,
        "journal_unchanged" => true,
        "worker_loads" => 1,
        "callbacks" => 1,
        "model_requests" => 0,
        "host_loaded_domain_modules" => false,
        "cleanup" => "confirmed"
      }
    after
      for session <- Process.get(:saved_result_sessions),
          Process.alive?(session),
          do: :ok = Session.close_confirmed(session)

      File.rm_rf!(root)
    end
  end

  defp start(config, cwd, state_dir, id \\ nil) do
    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config, cwd: cwd, state_dir: state_dir, id: id, subscriber: self(), owner: self()}
      )

    Process.put(:saved_result_sessions, [session | Process.get(:saved_result_sessions)])
    session
  end

  defp wait(session, deadline) do
    receive do
      {:ipse, ^session, {:done, :ok}} ->
        :ok

      {:ipse, ^session, {:done, status}} ->
        raise "Saved-result command failed: #{inspect(status)}"

      {:ipse, ^session, _} ->
        wait(session, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        raise "Saved-result proof deadline exceeded"
    end
  end

  defp unloaded!, do: false = :code.is_loaded(IpseSavedResultsExample.Worker)
end
