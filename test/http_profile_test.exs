defmodule Ipse.HTTPProfileTest do
  use ExUnit.Case, async: false
  alias Ipse.HTTPProfile

  test "bounded buffered requests stop every status before a chunked body completes" do
    for status <- [200, 201, 302, 429, 500], framing <- [:length, :chunked] do
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, {_, port}} = :inet.sockname(listener)

      fixture =
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.accept(listener, 2_000)

          try do
            {:ok, _} = :gen_tcp.recv(socket, 0, 2_000)

            header =
              if framing == :length,
                do: "content-length: 1048577",
                else: "transfer-encoding: chunked"

            :ok = :gen_tcp.send(socket, "HTTP/1.1 #{status} Fixture\r\n#{header}\r\n\r\n")

            if framing == :chunked do
              chunk = String.duplicate("x", 16_384)

              Enum.reduce_while(1..65, :ok, fn _, _ ->
                case :gen_tcp.send(socket, ["4000\r\n", chunk, "\r\n"]) do
                  :ok -> {:cont, :ok}
                  _ -> {:halt, :closed}
                end
              end)
            end

            assert {:error, :closed} = :gen_tcp.recv(socket, 0, 2_000)
          after
            :gen_tcp.close(socket)
            :gen_tcp.close(listener)
          end
        end)

      assert {:error, :response_too_large} =
               HTTPProfile.bounded_request(
                 Finch.build(:get, "http://127.0.0.1:#{port}"),
                 1_048_576
               )

      Task.await(fixture, 3_000)
    end
  end

  test "closing an owned task confirms its active HTTP socket and pool have exited" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    {:ok, scope} = Ipse.TaskResources.start(self())
    parent = self()

    task =
      Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
        receive do: (:start -> :ok)
        Ipse.TaskResources.bind(scope)

        HTTPProfile.with_finch(fn name ->
          send(parent, {:owned_pool, Process.whereis(name)})

          Finch.build(:get, "http://127.0.0.1:#{port}")
          |> Finch.request(name, receive_timeout: 10_000)
        end)
      end)

    :ok = Ipse.TaskResources.attach(scope, task.pid)

    try do
      send(task.pid, :start)
      assert_receive {:owned_pool, pool}, 2000
      {:ok, socket} = :gen_tcp.accept(listener, 2000)
      assert {:ok, _} = :gen_tcp.recv(socket, 0, 2000)
      assert :ok = Ipse.TaskResources.close(scope)
      refute Process.alive?(task.pid)
      refute Process.alive?(pool)
      assert {:error, :closed} = :gen_tcp.recv(socket, 0, 2000)
      :gen_tcp.close(socket)
    after
      Process.exit(task.pid, :kill)
      if Process.alive?(scope), do: Ipse.TaskResources.close(scope)
      :gen_tcp.close(listener)
    end
  end

  test "a prepared Finch guardian can be cancelled before borrower registration" do
    lease = {guardian, _} = HTTPProfile.prepare_finch(self())
    ref = Process.monitor(guardian)
    assert ^guardian = HTTPProfile.cancel_finch(lease)
    assert :ok = HTTPProfile.await_guardian(guardian)
    assert_receive {:DOWN, ^ref, :process, ^guardian, :normal}, 1000

    assert {:error, _} =
             HTTPProfile.with_finch(fn _ -> flunk("cancelled lease borrowed") end, [], lease)
  end

  test "a prepared guardian cannot confirm cleanup while pool teardown is stalled" do
    lease = {guardian, _} = HTTPProfile.prepare_finch(self())
    parent = self()

    borrower =
      spawn(fn ->
        HTTPProfile.with_finch(
          fn name ->
            send(parent, {:prepared_pool, Process.whereis(name)})
            Process.sleep(:infinity)
          end,
          [],
          lease
        )
      end)

    assert_receive {:prepared_pool, pool}, 2000
    :erlang.suspend_process(guardian)

    try do
      Process.exit(borrower, :kill)
      HTTPProfile.cancel_finch(lease)
      assert {:error, :cleanup_unconfirmed} = HTTPProfile.await_guardian(guardian)
      assert Process.alive?(pool)
    after
      :erlang.resume_process(guardian)
      Process.exit(borrower, :kill)
    end

    assert :ok = HTTPProfile.await_guardian(guardian)
    refute Process.alive?(pool)
  end

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
