Code.require_file("../../../dev/knowledge/pilot_reservation.exs", __DIR__)
Code.require_file("../../../dev/knowledge/local_pilot.exs", __DIR__)

defmodule Ipse.Development.Knowledge.ReservationFakeModels do
  def begin_job(_config, :text, 80_000), do: {:ok, :job}
  def with_job(:job, config, fun), do: fun.(config)
  def finish_job(:job, _config, result), do: result
end

defmodule Ipse.Development.Knowledge.PilotReservationTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.Knowledge.PilotReservation, as: Reservation
  alias Ipse.Runner

  @id "6a505a8bc83441888b1997c7f0f941f0"
  @error {:error, :pilot_reservation_unavailable}
  # The reservation requires the Linux-only retained protected header lock.
  @linux_reservation if(:os.type() == {:unix, :linux},
                       do: false,
                       else: "Linux native retained header lock"
                     )

  setup do
    home = Path.join(System.tmp_dir!(), "ipse-pilot-reservation-" <> Ipse.Usage.id())
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    File.mkdir!(Path.join(home, ".ipse"))
    File.chmod!(Path.join(home, ".ipse"), 0o700)
    on_exit(fn -> File.rm_rf!(home) end)
    %{home: home, root: Path.join([home, ".ipse", "p31a-pilot-authorizations"])}
  end

  test "only one matching local account selects an absolute home, independent of environment" do
    entry = "operator:x:1234:1234:Operator:/home/operator:/bin/sh\n"
    assert {:ok, "/home/operator"} = Reservation.account_home(entry, 1234)
    assert @error = Reservation.account_home(entry, 1235)
    assert @error = Reservation.account_home(entry <> entry, 1234)
    assert @error = Reservation.account_home("name:x:1234:1234:x:relative:/bin/sh\n", 1234)
    assert @error = Reservation.account_home("name:x:1234:1234:x:/home/with\0nul:/bin/sh\n", 1234)
    assert @error = Reservation.account_home(String.duplicate("x", 1_048_577), 1234)
  end

  test "account lookup requires confirmed EOF after a bounded read" do
    row = "operator:x:1234:1234:Operator:/home/operator:/bin/sh\n"

    complete = fn
      1_048_577 -> {:ok, row}
      1 -> :eof
    end

    short = fn
      1_048_577 -> {:ok, row}
      1 -> {:ok, "o"}
    end

    oversized = fn 1_048_577 -> {:ok, String.duplicate("x", 1_048_577)} end

    assert {:ok, "/home/operator"} = Reservation.read_account_home(complete, 1234)
    assert @error = Reservation.read_account_home(short, 1234)
    assert @error = Reservation.read_account_home(oversized, 1234)
  end

  test "one synced reservation authorizes one callback and preserves the lock inode", c do
    declaration = %{"case_hash" => "synthetic"}
    owner = self()

    if :os.type() == {:unix, :linux} do
      linux_reservation(c, declaration, owner)
    else
      # The retained header lock is Linux-only; elsewhere nothing is reserved.
      assert @error =
               Reservation.with_reservation_in_home(c.home, declaration, fn _ ->
                 send(owner, :entered)
                 {:ok, :done}
               end)

      refute_received :entered
      refute File.exists?(Path.join(c.root, @id <> ".lock"))
      refute File.exists?(Path.join(c.root, @id <> ".reservation"))
    end
  end

  defp linux_reservation(c, declaration, owner) do
    assert {:ok, :done} =
             Reservation.with_reservation_in_home(c.home, declaration, fn guard ->
               assert :ok = guard.()
               send(owner, :entered)
               {:ok, :done}
             end)

    assert_receive :entered
    lock = Path.join(c.root, @id <> ".lock")
    reservation = Path.join(c.root, @id <> ".reservation")
    assert {:ok, before} = File.lstat(lock)
    event = reservation |> File.read!() |> Jason.decode!()
    assert event["authorization_id"] == @id
    assert event["previously_charged"] == 4 and event["reserved_calls"] == 120
    assert event["declaration_sha256"] == Ipse.JSON.digest([declaration])

    assert @error =
             Reservation.with_reservation_in_home(c.home, declaration, fn _ ->
               flunk("a reservation cannot be reused")
             end)

    assert {:ok, after_lock} = File.lstat(lock)
    assert {after_lock.major_device, after_lock.inode} == {before.major_device, before.inode}
  end

  @tag skip: @linux_reservation
  test "the actual request wrapper uses the retained one-shot reservation", c do
    alias Ipse.Development.Knowledge.{LocalPilot, ReservationFakeModels}
    path = Path.join(c.home, "attempts.jsonl")
    {:ok, attempts} = File.open(path, [:write, :binary, :exclusive])
    counter = :atomics.new(1, signed: false)
    owner = self()

    provider = fn _, _, _, _ ->
      send(owner, :called)
      {:ok, %{}, %{}}
    end

    try do
      assert {:ok, _, _} =
               Reservation.with_reservation_in_home(c.home, %{"synthetic" => true}, fn guard ->
                 LocalPilot.guarded_request(
                   %{},
                   [],
                   [],
                   fn _ -> :ok end,
                   attempts,
                   counter,
                   guard,
                   ReservationFakeModels,
                   provider
                 )
               end)

      assert_receive :called
      assert :atomics.get(counter, 1) == 1

      assert @error =
               Reservation.with_reservation_in_home(c.home, %{"synthetic" => true}, fn _ ->
                 flunk("a second wrapper invocation must not run")
               end)

      refute_receive :called
    after
      File.close(attempts)
    end
  end

  @tag skip: @linux_reservation
  test "a concurrent owner cannot acquire the retained lock or run a second callback", c do
    owner = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        result =
          Reservation.with_reservation_in_home(c.home, %{"case" => "one"}, fn guard ->
            assert :ok = guard.()
            send(owner, {:reserved, self()})
            receive do: (:release -> {:ok, :done})
          end)

        send(owner, {:finished, result})
      end)

    assert_receive {:reserved, ^pid}, 10_000
    assert {:error, _} = Runner.protected_resume_lock(Path.join(c.root, @id <> ".lock"))

    assert @error =
             Reservation.with_reservation_in_home(c.home, %{"case" => "two"}, fn _ ->
               flunk("a concurrent run cannot spend the same authorization")
             end)

    send(pid, :release)
    assert_receive {:finished, {:ok, :done}}, 10_000
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
  end

  @tag skip: @linux_reservation
  test "owner death after reservation leaves the whole authorization consumed", c do
    owner = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        Reservation.with_reservation_in_home(c.home, %{"case" => "interrupted"}, fn guard ->
          assert :ok = guard.()
          send(owner, {:reserved, self()})
          receive do: (:never -> :ok)
        end)
      end)

    assert_receive {:reserved, ^pid}, 10_000
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5_000
    assert File.regular?(Path.join(c.root, @id <> ".reservation"))

    assert @error =
             Reservation.with_reservation_in_home(c.home, %{"case" => "new"}, fn _ ->
               flunk("an interrupted authorization must not replay")
             end)
  end

  test "malformed prior state and unsafe parent permissions refuse before the callback", c do
    File.mkdir!(c.root)
    File.chmod!(c.root, 0o700)
    File.write!(Path.join(c.root, @id <> ".reservation"), "incomplete")

    assert @error =
             Reservation.with_reservation_in_home(c.home, %{}, fn _ ->
               flunk("an unverifiable reservation stays charged")
             end)

    File.chmod!(Path.join(c.home, ".ipse"), 0o755)

    assert @error =
             Reservation.with_reservation_in_home(c.home, %{}, fn _ ->
               flunk("unsafe owner state must not proceed")
             end)
  end

  @tag skip: @linux_reservation
  test "removing a live reservation invalidates the guard and the retained lock blocks reset",
       c do
    assert @error =
             Reservation.with_reservation_in_home(c.home, %{}, fn guard ->
               File.rm!(Path.join(c.root, @id <> ".reservation"))
               assert {:error, _} = guard.()
               {:ok, :should_not_admit}
             end)

    assert File.regular?(Path.join(c.root, @id <> ".lock"))

    assert @error =
             Reservation.with_reservation_in_home(c.home, %{}, fn _ ->
               flunk("the retained lock file makes missing state unverifiable")
             end)
  end
end
