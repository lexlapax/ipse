defmodule Ipse.HTTPProfileTest do
  use ExUnit.Case, async: false
  alias Ipse.HTTPProfile

  test "private Finch pools and their guardians stop on return and borrower death" do
    {pid, monitor, guardian} =
      HTTPProfile.with_finch(fn name ->
        pid = Process.whereis(name)
        {pid, Process.monitor(pid), HTTPProfile.finch_guardian(self())}
      end)

    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 2000
    refute Process.alive?(guardian)

    parent = self()

    borrower =
      spawn(fn ->
        HTTPProfile.with_finch(fn name ->
          send(parent, {:finch_ready, Process.whereis(name), HTTPProfile.finch_guardian(self())})
          Process.sleep(:infinity)
        end)
      end)

    assert_receive {:finch_ready, pool, guardian}, 2000
    pool_monitor = Process.monitor(pool)
    guardian_monitor = Process.monitor(guardian)

    descendants =
      for {_, child, _, _} <- Supervisor.which_children(pool),
          is_pid(child),
          do: {child, Process.monitor(child)}

    Process.exit(borrower, :kill)
    assert_receive {:DOWN, ^pool_monitor, :process, ^pool, _}, 2000
    assert_receive {:DOWN, ^guardian_monitor, :process, ^guardian, _}, 2000

    for {child, reference} <- descendants do
      assert_receive {:DOWN, ^reference, :process, ^child, _}, 2000
    end

    assert HTTPProfile.with_finch(fn name -> is_pid(Process.whereis(name)) end)
  end

  test "normal return closes the profile before releasing its slot" do
    {profile, monitor} =
      HTTPProfile.with_profile(fn profile ->
        assert Process.alive?(profile)
        {profile, Process.monitor(profile)}
      end)

    assert_receive {:DOWN, ^monitor, :process, ^profile, _}
    refute Process.alive?(profile)
    assert HTTPProfile.with_profile(fn next -> Process.alive?(next) end)
  end

  test "borrower death closes its profile and permits an immediate new request" do
    parent = self()

    borrower =
      spawn(fn ->
        HTTPProfile.with_profile(fn profile ->
          send(parent, {:profile, profile})
          Process.sleep(:infinity)
        end)
      end)

    assert_receive {:profile, profile}, 2_000
    monitor = Process.monitor(profile)
    Process.exit(borrower, :kill)
    assert HTTPProfile.with_profile(fn next -> Process.alive?(next) end)
    assert_receive {:DOWN, ^monitor, :process, ^profile, _}, 2_000
  end

  test "overlapping borrowers have isolated options and cancellation does not stop peers" do
    parent = self()

    borrowers =
      for index <- 1..8 do
        spawn(fn ->
          HTTPProfile.with_profile(fn profile ->
            :ok = :httpc.set_options([keep_alive_timeout: index * 1_000], profile)
            send(parent, {:ready, self(), profile})

            receive do
              :check ->
                send(
                  parent,
                  {:options, self(), :httpc.get_options([:keep_alive_timeout], profile)}
                )
            end

            receive do
              :finish -> :ok
            end
          end)

          send(parent, {:finished, self()})
        end)
      end

    on_exit(fn -> Enum.each(borrowers, &Process.exit(&1, :kill)) end)

    profiles =
      for _ <- borrowers do
        assert_receive {:ready, borrower, profile}, 2_000
        {borrower, profile}
      end

    assert profiles |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 8
    [cancelled | peers] = borrowers
    cancelled_profile = profiles |> List.keyfind(cancelled, 0) |> elem(1)
    monitor = Process.monitor(cancelled_profile)
    Process.exit(cancelled, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^cancelled_profile, _}, 2_000

    for {borrower, index} <- Enum.with_index(peers, 2) do
      send(borrower, :check)
      expected = index * 1_000
      assert_receive {:options, ^borrower, {:ok, [keep_alive_timeout: ^expected]}}, 2_000
      send(borrower, :finish)
      assert_receive {:finished, ^borrower}, 2_000
    end
  end

  test "cancelling an active request closes its handler and socket before profile reuse" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_ip, port}} = :inet.sockname(listener)
    parent = self()

    try do
      for _ <- 1..5 do
        borrower =
          spawn(fn ->
            HTTPProfile.with_profile(fn profile ->
              {:ok, _id} =
                :httpc.request(
                  :get,
                  {~c"http://127.0.0.1:#{port}/", []},
                  [timeout: 5_000],
                  [sync: false],
                  profile
                )

              send(parent, {:active, profile})
              Process.sleep(:infinity)
            end)
          end)

        {:ok, socket} = :gen_tcp.accept(listener, 2_000)
        assert {:ok, _request} = :gen_tcp.recv(socket, 0, 2_000)
        assert_receive {:active, profile}, 2_000
        monitor = Process.monitor(profile)
        {:links, links} = Process.info(profile, :links)

        linked_processes = Enum.filter(links, &is_pid/1)
        monitors = Enum.map(linked_processes, &{&1, Process.monitor(&1)})
        Process.exit(borrower, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^profile, _}, 2_000
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 2_000)

        for {pid, reference} <- monitors do
          assert_receive {:DOWN, ^reference, :process, ^pid, _}, 2_000
        end

        :gen_tcp.close(socket)
        assert HTTPProfile.with_profile(fn next -> Process.alive?(next) end)
      end
    after
      :gen_tcp.close(listener)
    end
  end
end
