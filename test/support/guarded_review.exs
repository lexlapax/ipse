[root, mode] = System.argv()
{:ok, _} = Application.ensure_all_started(:ipse)
alias Ipse.Runner
alias Ipse.Runner.Review

facts = %{"target" => "SYNTHETIC_GUARDED_REVIEW", "reason" => "fixture"}
lock = Path.join(root, "display.lock")
refused = {:error, :native_review_refused}

case mode do
  "valid" ->
    observer =
      Task.async(fn ->
        receive do
          :verify_unlocked ->
            {:ok, port} = Runner.protected_lock(lock)
            :ok = Runner.unlock(port)
            File.write!(Path.join(root, "guard-review-ready"), "unlocked")
        end
      end)

    guard = fn send_display ->
      {:ok, port} = Runner.protected_lock(lock)

      try do
        :ok = send_display.(System.system_time(:millisecond) + 5000)
      after
        :ok = Runner.unlock(port)
      end

      send(observer.pid, :verify_unlocked)
      :ok = Task.await(observer, 5000)
    end

    {:ok, receipt} =
      Review.with_review(
        "correct",
        facts,
        fn permit ->
          "unlocked" = File.read!(Path.join(root, "guard-review-ready"))
          {:ok, port} = Runner.protected_lock(lock)
          :ok = Runner.unlock(port)
          {:ok, receipt} = Review.consume(permit, "correct", facts)
          {:ok, receipt}
        end,
        guard
      )

    true = receipt["facts_sha256"] == Ipse.JSON.digest([facts])

  "queued_cancel" ->
    {:ok, scope} = Ipse.Session.Resources.start(self())
    Ipse.Session.Resources.bind(scope)

    ^refused =
      Review.with_review(
        "correct",
        facts,
        fn _ -> raise "cancelled review must not issue a permit" end,
        fn send_display ->
          :ok = send_display.(System.system_time(:millisecond) + 5000)
          send(self(), :ipse_cancel_operator_input)
          :ok
        end
      )

    :ok = Ipse.Session.Resources.finish(scope)

  "expired" ->
    ^refused =
      Review.with_review(
        "correct",
        facts,
        fn _ -> raise "unexpected callback" end,
        fn send_display ->
          {:error, _} = send_display.(System.system_time(:millisecond))
          :ok
        end
      )

  "double" ->
    ^refused =
      Review.with_review(
        "correct",
        facts,
        fn _ -> raise "unexpected callback" end,
        fn send_display ->
          deadline = System.system_time(:millisecond) + 5000
          :ok = send_display.(deadline)
          {:error, _} = send_display.(deadline)
          :ok
        end
      )

  "foreign" ->
    ^refused =
      Review.with_review(
        "correct",
        facts,
        fn _ -> raise "unexpected callback" end,
        fn send_display ->
          deadline = System.system_time(:millisecond) + 5000
          {:error, _} = Task.async(fn -> send_display.(deadline) end) |> Task.await()
          {:error, _} = send_display.(deadline)
          :ok
        end
      )

  "stored" ->
    ^refused =
      Review.with_review(
        "correct",
        facts,
        fn _ -> raise "unexpected callback" end,
        fn send_display ->
          Process.put(:stored_display, send_display)
          :ok
        end
      )

    saved = Process.delete(:stored_display)
    started = System.monotonic_time(:millisecond)
    {:error, _} = saved.(System.system_time(:millisecond) + 5000)
    true = System.monotonic_time(:millisecond) - started < 500

  "backpressure" ->
    {:ok, scope} = Ipse.Session.Resources.start(self())
    parent = self()
    prompt = "GUARDED_LATE_SECRET_PREFIX" <> String.duplicate("A", 1_048_576)

    {owner, owner_ref} =
      spawn_monitor(fn ->
        receive do: (:start_guarded -> :ok)
        Ipse.Session.Resources.bind(scope)

        Runner.operator_input(prompt, 30_000, 2, fn send_display ->
          operator_port =
            Enum.find(:erlang.ports(), &(Port.info(&1, :connected) == {:connected, self()}))

          true = is_port(operator_port)
          {:ok, port} = Runner.protected_lock(lock)
          send(parent, {:guard_lock_held, operator_port})
          receive do: (:continue_guarded -> :ok)

          try do
            send_display.(System.system_time(:millisecond) + 20_000)
          after
            Runner.unlock(port)
          end
        end)
      end)

    send(owner, :start_guarded)

    port =
      receive do
        {:guard_lock_held, port} -> port
      after
        5000 -> raise "guard lock and owner-held native port were not observed"
      end

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    {_, 0} = System.cmd("/bin/kill", ["-STOP", Integer.to_string(os_pid)])

    try do
      send(owner, :continue_guarded)
      Process.sleep(100)
      true = Process.alive?(owner)
      Process.exit(owner, :kill)

      receive do
        {:DOWN, ^owner_ref, :process, ^owner, :killed} -> :ok
      after
        5000 -> raise "guard owner did not terminate"
      end

      case Port.info(port, :connected) do
        nil -> :ok
        {:connected, connected} -> false = Process.alive?(connected)
      end

      acquire = fn acquire, remaining ->
        case Runner.protected_lock(lock) do
          {:ok, lock_port} ->
            Runner.unlock(lock_port)

          _ when remaining > 0 ->
            Process.sleep(10)
            acquire.(acquire, remaining - 1)

          _ ->
            raise "source lock did not release"
        end
      end

      :ok = acquire.(acquire, 500)
      File.write!(Path.join(root, "guard-owner-lost"), "released")
    after
      System.cmd("/bin/kill", ["-CONT", Integer.to_string(os_pid)], stderr_to_stdout: true)
    end

    Process.sleep(1000)
    {:error, :cleanup_unconfirmed} = Ipse.Session.Resources.finish(scope)
    Process.sleep(200)
end

IO.puts("GUARDED_REVIEW_" <> String.upcase(mode) <> "_PASSED")
