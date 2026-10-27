defmodule Ipse.Session.ObservationOwnerDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Journal, Usage}
  alias Ipse.Session.{ObservationAdmission, Resources}
  alias Ipse.Extension.Collection.ObservedRead

  defmodule Owner do
    use GenServer
    def start(args), do: GenServer.start(__MODULE__, args)
    @impl true
    def init(args) do
      {:ok, id} = Journal.create(args.dir, %{})
      {:ok, writer} = Journal.Writer.start(args.dir, id, self())
      {:ok, scope} = Resources.start(self())
      {:ok, Map.merge(args, %{id: id, writer: writer, scope: scope, status: nil})}
    end

    @impl true
    def handle_call(:start, _, state) do
      owner = self()

      worker =
        spawn(fn ->
          receive do
            {:start, job, token} ->
              Resources.bind(state.scope)

              Resources.file_effect(fn ->
                {:ok, observation} =
                  ObservedRead.read(
                    state.root,
                    state.namespace,
                    state.intent["request"]["request"]
                  )

                reply = GenServer.call(owner, {:observation, job, token, observation}, 5000)
                send(state.test, {:worker_reply, reply})
              end)

              send(state.test, :worker_finished)
              receive do: (:stop -> :ok)
          end
        end)

      :ok = Resources.attach(state.scope, worker)
      job = make_ref()

      {:ok, admission, token} =
        ObservationAdmission.start(
          job,
          worker,
          state.intent,
          state.identity,
          state.identity["artifact_sha256"],
          state.writer
        )

      send(worker, {:start, job, token})
      {:reply, :ok, Map.merge(state, %{worker: worker, admission: admission, job: job})}
    end

    def handle_call({:observation, job, token, observation}, {caller, _}, state) do
      case ObservationAdmission.admit(state.admission, caller, job, token, observation) do
        {:ok, admission} ->
          {:reply, {:error, :not_exposed}, %{state | admission: admission, status: :recorded}}

        {:error, admission} ->
          {:reply, {:error, :refused}, %{state | admission: admission, status: :failed}}
      end
    end

    def handle_call(:close, _, state) do
      :ok = Resources.finish(state.scope)
      send(state.worker, :stop)
      :ok = Resources.close(state.scope)
      :ok = Journal.Writer.close(state.writer)
      {:stop, :normal, {:ok, state.id, state.status}, state}
    end
  end

  defp setup_intent(namespace) do
    identity = %{
      "instance" => "synthetic",
      "artifact_sha256" => JSON.sha256("reviewed-synthetic")
    }

    request = %{"op" => "collection.call", "request" => %{"op" => "get", "key" => "note.absent"}}

    pin = %{
      "version" => 1,
      "session_id" => Usage.id(),
      "project_id" => JSON.sha256("project"),
      "worktree_id" => JSON.sha256("worktree"),
      "binding_sha256" => JSON.sha256("binding"),
      "epoch" => 1,
      "policy_sha256" => JSON.sha256("policy"),
      "identity_sha256" => JSON.digest([identity]),
      "namespace" => namespace,
      "routes_sha256" => JSON.sha256("routes"),
      "source_sha256" => JSON.sha256("source")
    }

    binding = %{
      "kind" => "collection",
      "version" => 1,
      "namespace" => namespace,
      "pin" => pin,
      "inner_op" => "get",
      "request_sha256" => JSON.digest([request["request"]])
    }

    intent = %{
      "type" => "extension_action_intent",
      "version" => 2,
      "parent_invocation_id" => Usage.id(),
      "operation_id" => Usage.id(),
      "step" => 1,
      "identity_sha256" => JSON.digest([identity]),
      "namespace" => namespace,
      "context_sha256" => nil,
      "service" => nil,
      "request" => request,
      "request_sha256" => JSON.digest([request]),
      "approval" => "not_required",
      "effect_binding" => binding
    }

    {intent, identity}
  end

  test "GenServer-owned callback uses the actual effect caller and returns no value" do
    base = Path.join(System.tmp_dir!(), "ipse-observation-owner-" <> Usage.id())
    File.mkdir_p!(base)
    File.chmod!(base, 0o700)
    on_exit(fn -> File.rm_rf!(base) end)
    dir = Path.join(base, "journal")
    File.mkdir_p!(dir)
    namespace = JSON.sha256("namespace")
    {intent, identity} = setup_intent(namespace)

    {:ok, owner} =
      Owner.start(%{
        dir: dir,
        root: Path.join(base, "collections"),
        namespace: namespace,
        intent: intent,
        identity: identity,
        test: self()
      })

    assert :ok = GenServer.call(owner, :start)
    assert_receive {:worker_reply, {:error, :not_exposed}}, 5000
    assert_receive :worker_finished, 5000
    assert {:ok, id, :recorded} = GenServer.call(owner, :close)
    assert {:ok, [_header, marker, result, receipt]} = Journal.load(dir, id)

    assert {:ok, _} =
             ObservationAdmission.replay_stream([intent, marker, result, receipt], [intent])
  end
end
