defmodule Ipse.HTTPProfileTest do
  use ExUnit.Case, async: false
  alias Ipse.HTTP

  test "private provider pool loss stops Session and requires explicit inert resume" do
    root = Path.join(System.tmp_dir!(), "ipse-pool-loss-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    config = %{
      provider: :ollama,
      model: "fixture",
      base_url: "http://127.0.0.1:#{port}",
      home: Path.join(root, "home"),
      approval: :deny
    }

    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session,
         config: config, cwd: root, state_dir: Path.join(root, "sessions"), subscriber: self()}
      )

    id = Ipse.Session.info(session).id
    monitor = Process.monitor(session)

    try do
      :ok = Ipse.Session.prompt(session, "held provider connection")
      {:ok, socket} = :gen_tcp.accept(listener, 5_000)

      try do
        assert {:ok, _} = :gen_tcp.recv(socket, 0, 5_000)
        worker = :sys.get_state(session).task.pid
        worker_monitor = Process.monitor(worker)
        guardian = HTTP.finch_guardian(worker)

        pool =
          Registry.keys(Ipse.Registry, guardian)
          |> Enum.find_value(fn
            {HTTP, name} when is_atom(name) ->
              {:dictionary, dictionary} = Process.info(Process.whereis(name), :dictionary)
              [supervisor | _] = Keyword.fetch!(dictionary, :"$ancestors")
              if is_atom(supervisor), do: Process.whereis(supervisor), else: supervisor

            _ ->
              nil
          end)

        assert is_pid(pool)
        Process.exit(pool, :kill)
        assert_receive {:ipse, ^session, {:done, :error}}, 5_000
        assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 5_000
        assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}, 5_000
        assert :ok = await_socket_close(socket, System.monotonic_time(:millisecond) + 2_000)
        dir = Path.join(root, "sessions")
        {:ok, events} = Ipse.Journal.load(dir, id)
        assert {:ok, _} = Ipse.Session.restore_context(events)

        {:ok, resumed} =
          DynamicSupervisor.start_child(
            Ipse.Sessions,
            {Ipse.Session, config: config, cwd: root, state_dir: dir, id: id, subscriber: self()}
          )

        assert Ipse.Session.info(resumed).phase == :idle
        assert {:ok, ^events} = Ipse.Journal.load(dir, id)
        assert {:error, :timeout} = :gen_tcp.accept(listener, 100)
        assert :ok = Ipse.Session.close(resumed)
      after
        :gen_tcp.close(socket)
      end
    after
      if Process.alive?(session), do: Ipse.Session.close(session)
      :gen_tcp.close(listener)
      File.rm_rf!(root)
    end
  end

  defp await_socket_close(socket, deadline) do
    case :gen_tcp.recv(socket, 0, max(deadline - System.monotonic_time(:millisecond), 0)) do
      {:ok, _already_sent_request_bytes} -> await_socket_close(socket, deadline)
      {:error, :closed} -> :ok
      other -> other
    end
  end

  test "pool loss retains its HTTP slot until a stalled named child exits" do
    parent = self()

    borrower =
      spawn(fn ->
        HTTP.with_finch(fn name ->
          send(parent, {:client_tree, name, HTTP.finch_guardian(self())})
          Process.sleep(:infinity)
        end)
      end)

    on_exit(fn -> Process.exit(borrower, :kill) end)
    assert_receive {:client_tree, name, guardian}, 2_000
    registry = Process.whereis(name)
    {:dictionary, dictionary} = Process.info(registry, :dictionary)
    [supervisor | _] = Keyword.fetch!(dictionary, :"$ancestors")
    supervisor = if is_atom(supervisor), do: Process.whereis(supervisor), else: supervisor
    monitor = Process.monitor(guardian)
    :erlang.suspend_process(registry)

    try do
      Process.exit(supervisor, :kill)
      refute_receive {:DOWN, ^monitor, :process, ^guardian, _}, 100
      assert Process.alive?(registry)
    after
      :erlang.resume_process(registry)
    end

    assert_receive {:DOWN, ^monitor, :process, ^guardian, :normal}, 5_000
    refute Process.alive?(registry)
    assert HTTP.with_finch(fn _ -> true end)
  end

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
               HTTP.bounded_request(
                 Finch.build(:get, "http://127.0.0.1:#{port}"),
                 1_048_576
               )

      Task.await(fixture, 3_000)
    end
  end

  test "closing an owned task confirms its active HTTP socket and pool have exited" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    {:ok, scope} = Ipse.Session.Resources.start(self())
    parent = self()

    task =
      Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
        receive do: (:start -> :ok)
        Ipse.Session.Resources.bind(scope)

        HTTP.with_finch(fn name ->
          send(parent, {:owned_pool, Process.whereis(name)})

          Finch.build(:get, "http://127.0.0.1:#{port}")
          |> Finch.request(name, receive_timeout: 10_000)
        end)
      end)

    :ok = Ipse.Session.Resources.attach(scope, task.pid)

    try do
      send(task.pid, :start)
      assert_receive {:owned_pool, pool}, 2000
      {:ok, socket} = :gen_tcp.accept(listener, 2000)
      assert {:ok, _} = :gen_tcp.recv(socket, 0, 2000)
      assert :ok = Ipse.Session.Resources.close(scope)
      refute Process.alive?(task.pid)
      refute Process.alive?(pool)
      assert {:error, :closed} = :gen_tcp.recv(socket, 0, 2000)
      :gen_tcp.close(socket)
    after
      Process.exit(task.pid, :kill)
      if Process.alive?(scope), do: Ipse.Session.Resources.close(scope)
      :gen_tcp.close(listener)
    end
  end

  test "a prepared Finch guardian can be cancelled before borrower registration" do
    lease = {guardian, _} = HTTP.prepare_finch(self())
    ref = Process.monitor(guardian)
    assert ^guardian = HTTP.cancel_finch(lease)
    assert :ok = HTTP.await_guardian(guardian)
    assert_receive {:DOWN, ^ref, :process, ^guardian, :normal}, 1000

    assert {:error, _} =
             HTTP.with_finch(fn _ -> flunk("cancelled lease borrowed") end, [], lease)
  end

  test "a prepared guardian cannot confirm cleanup while pool teardown is stalled" do
    lease = {guardian, _} = HTTP.prepare_finch(self())
    parent = self()

    borrower =
      spawn(fn ->
        HTTP.with_finch(
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
      HTTP.cancel_finch(lease)
      assert {:error, :cleanup_unconfirmed} = HTTP.await_guardian(guardian)
      assert Process.alive?(pool)
    after
      :erlang.resume_process(guardian)
      Process.exit(borrower, :kill)
    end

    assert :ok = HTTP.await_guardian(guardian)
    refute Process.alive?(pool)
  end

  test "private Finch pools and their guardians stop on return and borrower death" do
    {pid, monitor, guardian} =
      HTTP.with_finch(fn name ->
        pid = Process.whereis(name)
        {pid, Process.monitor(pid), HTTP.finch_guardian(self())}
      end)

    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 2000
    refute Process.alive?(guardian)

    parent = self()

    borrower =
      spawn(fn ->
        HTTP.with_finch(fn name ->
          send(parent, {:finch_ready, Process.whereis(name), HTTP.finch_guardian(self())})
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

    assert HTTP.with_finch(fn name -> is_pid(Process.whereis(name)) end)
  end

  test "overlapping Finch requests are isolated and cancellation does not stop peers" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    parent = self()

    borrowers =
      for index <- 1..8 do
        spawn(fn ->
          result =
            HTTP.with_finch(fn name ->
              send(parent, {:ready, index, Process.whereis(name), HTTP.finch_guardian(self())})

              Finch.build(:get, "http://127.0.0.1:#{port}/#{index}")
              |> Finch.request(name, receive_timeout: 10_000)
            end)

          send(parent, {:response, index, result})
        end)
      end

    on_exit(fn ->
      Enum.each(borrowers, &Process.exit(&1, :kill))
      :gen_tcp.close(listener)
    end)

    pools =
      Map.new(borrowers, fn _ ->
        assert_receive {:ready, index, pool, guardian}, 2_000
        {index, {pool, guardian}}
      end)

    assert pools |> Map.values() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 8

    sockets =
      Map.new(borrowers, fn _ ->
        {:ok, socket} = :gen_tcp.accept(listener, 2_000)
        assert {:ok, request} = :gen_tcp.recv(socket, 0, 2_000)
        assert [_, index] = Regex.run(~r"GET /(\d+) HTTP/1.1", request)
        {String.to_integer(index), socket}
      end)

    try do
      {pool, guardian} = Map.fetch!(pools, 1)
      monitors = Enum.map([pool, guardian], &{&1, Process.monitor(&1)})
      Process.exit(hd(borrowers), :kill)

      for {pid, monitor} <- monitors do
        assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 2_000
      end

      assert {:error, :closed} = :gen_tcp.recv(Map.fetch!(sockets, 1), 0, 2_000)

      for index <- 2..8 do
        body = Integer.to_string(index)
        socket = Map.fetch!(sockets, index)

        :ok =
          :gen_tcp.send(socket, ["HTTP/1.1 200 OK\r\ncontent-length: 1\r\n\r\n", body])

        assert_receive {:response, ^index, {:ok, %Finch.Response{status: 200, body: ^body}}},
                       2_000

        {peer_pool, peer_guardian} = Map.fetch!(pools, index)
        refute Process.alive?(peer_pool)
        refute Process.alive?(peer_guardian)
      end
    after
      Enum.each(Map.values(sockets), &:gen_tcp.close/1)
    end
  end

  test "cancelling an active Finch request closes its children and socket before reuse" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_ip, port}} = :inet.sockname(listener)
    parent = self()

    try do
      for _ <- 1..5 do
        borrower =
          spawn(fn ->
            HTTP.with_finch(fn name ->
              send(parent, {:active, Process.whereis(name), HTTP.finch_guardian(self())})

              Finch.build(:get, "http://127.0.0.1:#{port}/")
              |> Finch.request(name, receive_timeout: 5_000)
            end)
          end)

        on_exit(fn -> Process.exit(borrower, :kill) end)
        {:ok, socket} = :gen_tcp.accept(listener, 2_000)
        assert {:ok, _request} = :gen_tcp.recv(socket, 0, 2_000)
        assert_receive {:active, pool, guardian}, 2_000

        children =
          for {_, pid, _, _} <- Supervisor.which_children(pool), is_pid(pid), do: pid

        monitors = Enum.map([pool, guardian | children], &{&1, Process.monitor(&1)})
        Process.exit(borrower, :kill)

        for {pid, reference} <- monitors do
          assert_receive {:DOWN, ^reference, :process, ^pid, _}, 2_000
        end

        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 2_000)
        :gen_tcp.close(socket)
        assert HTTP.with_finch(fn name -> is_pid(Process.whereis(name)) end)
      end
    after
      :gen_tcp.close(listener)
    end
  end
end
