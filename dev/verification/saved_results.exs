defmodule IpseSavedResultsExample.Proof do
  @moduledoc false
  alias Ipse.{Journal, Session}
  alias Ipse.Extension.{Config, Invocation, Registry, ResultSource, Artifact}

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
      {:ok, imported} = Artifact.import(Path.expand(artifact), store)
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
      true = Ipse.JSON.sha256(original.bytes) == delivery["sha256"]
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
      journal_before = File.read!(path)
      {:ok, events_before} = Journal.load(state_dir, info.id)
      {:ok, ^original} = ResultSource.read_saved(state_dir, info.id, delivery["output_id"])
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
      journal_after = File.read!(path)
      {:ok, events_after} = Journal.load(state_dir, info.id)

      {:ok, release_mode} =
        validate_idle_resume(journal_before, journal_after, events_before, events_after, info.id)

      {:ok, release_status} =
        validate_release_status(release_mode, fn ->
          Ipse.Session.ReleaseReceipt.inspect_current(state_dir, info.id)
        end)

      unloaded!()

      %{
        "artifact_sha256" => imported.digest,
        "byte_count" => delivery["byte_count"],
        "fragment_count" => length(chunks),
        "sha256" => delivery["sha256"],
        "historical_reads_exact" => true,
        "resume_inert" => true,
        "journal_prefix_preserved" => true,
        "resume_release_status" => release_status,
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

  @doc false
  def validate_idle_resume(before, after_bytes, before_events, after_events, session)
      when is_binary(before) and is_binary(after_bytes) and is_list(before_events) and
             is_list(after_events) and is_binary(session) do
    count = length(before_events)

    with true <- byte_size(after_bytes) >= byte_size(before),
         true <- binary_part(after_bytes, 0, byte_size(before)) == before,
         true <- Enum.take(after_events, count) === before_events,
         suffix = Enum.drop(after_events, count),
         {:ok, mode} <- validate_idle_suffix(before_events, after_events, suffix, session) do
      {:ok, mode}
    else
      _ -> {:error, :unexpected_resume_journal}
    end
  rescue
    _ -> {:error, :unexpected_resume_journal}
  end

  def validate_idle_resume(_, _, _, _, _), do: {:error, :unexpected_resume_journal}

  defp validate_idle_suffix(before_events, after_events, suffix, session) do
    case get_in(hd(before_events), ["metadata", "release_receipt_layout"]) do
      nil ->
        if suffix === [], do: {:ok, :legacy_unchanged}, else: {:error, :unexpected_resume_journal}

      layout ->
        with true <- layout == Ipse.Session.ReleaseReceipt.layout(),
             [owner, intent] <- suffix,
             true <- Ipse.Session.ReleaseReceipt.valid_owner_marker?(owner, session),
             true <- intent["type"] == "session_release_intent",
             true <- intent["owner_id"] == owner["owner_id"],
             true <- is_nil(intent["epoch_id"]) and is_nil(intent["closure_sha256"]),
             {:ok, ^intent} <- Ipse.Session.ReleaseReceipt.current_intent(after_events, session) do
          {:ok, :signed_release_required}
        else
          _ -> {:error, :unexpected_resume_journal}
        end
    end
  end

  @doc false
  def validate_release_status(:legacy_unchanged, _inspect), do: {:ok, "legacy_unchanged"}

  def validate_release_status(:signed_release_required, inspect) when is_function(inspect, 0) do
    if inspect.() == :signed_release_claim,
      do: {:ok, "signed_release_claim"},
      else: {:error, :release_claim_unconfirmed}
  rescue
    _ -> {:error, :release_claim_unconfirmed}
  end

  def validate_release_status(_, _), do: {:error, :release_claim_unconfirmed}

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
