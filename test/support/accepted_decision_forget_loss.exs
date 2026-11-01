# Test-only pause after the actual native durable root switch, before cleanup.
defmodule Ipse.Test.AcceptedDecisionForgetLoss do
  import ExUnit.Assertions
  alias Ipse.{JSON, Runner.Transaction}

  def install(root, collection, namespace, key) do
    source = File.read!(Path.expand("../../lib/ipse/extension/collection.ex", __DIR__))
    anchor = ":ok <- publish_pointer(path, uid, pointer, next),"
    assert length(:binary.matches(source, anchor)) == 1

    replacement =
      ":ok <- Ipse.Test.AcceptedDecisionForgetLoss.after_publication(" <>
        "publish_pointer(path, uid, pointer, next), path, request),"

    instrumented = String.replace(source, anchor, replacement, global: false)
    IO.puts("ACCEPTED_FORGET_LOSS_SOURCE_SHA256=" <> JSON.sha256(instrumented))

    [{module, beam}] =
      Code.compile_string(instrumented, "accepted-forget-after-effect-control.ex")

    path = Path.join(root, "Elixir.Ipse.Extension.Collection.beam")
    File.write!(path, beam)
    assert {:module, ^module} = :code.load_binary(module, String.to_charlist(path), beam)
    owner = self()

    watcher =
      Task.async(fn ->
        true = Process.register(self(), :ipse_accepted_forget_loss)
        send(owner, :accepted_forget_loss_ready)

        receive do
          {:accepted_forget_published, effect, controller, actual_path, request} ->
            assert actual_path == Path.join(collection, namespace)
            assert Enum.any?(request["changes"], &(&1["key"] == key and is_nil(&1["value"])))
            pointer = actual_path |> Path.join("root.json") |> File.read!() |> Jason.decode!()
            assert pointer["generation"] == request["expected_generation"] + 1
            assert Process.alive?(effect) and Process.alive?(controller)
            monitor = Process.monitor(controller)
            %{port: port} = :sys.get_state(controller)
            assert {:os_pid, native} = Port.info(port, :os_pid)

            assert {_, 0} =
                     System.cmd("/bin/kill", ["-KILL", Integer.to_string(native)],
                       stderr_to_stdout: true
                     )

            assert_receive {:DOWN, ^monitor, :process, ^controller, :normal}, 5_000
            assert Port.info(port) == nil
            send(effect, :accepted_forget_loss_released)
            %{"published_generation" => pointer["generation"], "native_owner_stopped" => true}
        after
          30_000 -> flunk("accepted forgetting never reached the durable publication boundary")
        end
      end)

    assert_receive :accepted_forget_loss_ready, 1_000
    watcher
  end

  def after_publication(:ok, path, request) do
    controller = Process.get({Transaction, :controller})
    assert is_pid(controller)

    send(
      Process.whereis(:ipse_accepted_forget_loss),
      {:accepted_forget_published, self(), controller, path, request}
    )

    receive do
      :accepted_forget_loss_released -> :ok
    after
      10_000 -> flunk("accepted forget loss controller did not release the effect")
    end
  end

  def after_publication(result, _, _), do: result
end
