defmodule Ipse.HTTPProfile do
  @moduledoc false

  # Fixed names bound atom usage. Each guardian retains its registry lease until
  # the profile has exited, including when its borrower is killed.
  @profiles for index <- 1..64, do: :"ipse_http_#{index}"

  def with_profile(fun) when is_function(fun, 1) do
    with_client(fun, :httpc)
  end

  def with_finch(fun, conn_opts \\ []) when is_function(fun, 1),
    do: with_client(fun, {:finch, conn_opts})

  def finch_guardian(owner) do
    case Registry.lookup(Ipse.Registry, {__MODULE__, :finch_borrower, owner}) do
      [{guardian, _}] -> guardian
      [] -> nil
    end
  end

  def await_guardian(nil), do: :ok

  def await_guardian(pid) do
    monitor = Process.monitor(pid)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> :ok
    after
      2000 ->
        Process.demonitor(monitor, [:flush])
        {:error, :cleanup_unconfirmed}
    end
  end

  defp with_client(fun, backend) do
    Application.ensure_all_started(:ipse)
    owner = self()
    reference = make_ref()
    {guardian, monitor} = spawn_monitor(fn -> own_profile(owner, reference, backend) end)

    receive do
      {^reference, {:ok, profile}} ->
        try do
          fun.(profile)
        after
          send(guardian, {reference, :finished})
          await_exit(guardian, monitor)
        end

      {^reference, {:error, _} = error} ->
        await_exit(guardian, monitor)
        error

      {:DOWN, ^monitor, :process, ^guardian, _} ->
        {:error, "Could not start an isolated HTTP client."}
    end
  end

  defp own_profile(owner, reference, backend) do
    Process.flag(:trap_exit, true)
    owner_monitor = Process.monitor(owner)

    if match?({:finch, _}, backend),
      do: Registry.register(Ipse.Registry, {__MODULE__, :finch_borrower, owner}, nil)

    case reserve() do
      {:ok, name} ->
        try do
          case start_client(backend, name) do
            {:ok, profile} ->
              profile_monitor = Process.monitor(profile)

              send(
                owner,
                {reference, {:ok, if(match?({:finch, _}, backend), do: name, else: profile)}}
              )

              receive do
                {^reference, :finished} -> :ok
                {:DOWN, ^owner_monitor, :process, ^owner, _} -> :ok
                {:DOWN, ^profile_monitor, :process, ^profile, _} -> :ok
                {:EXIT, ^profile, _} -> :ok
              end

              Process.demonitor(profile_monitor, [:flush])
              stop_profile(profile, backend)

            _ ->
              send(owner, {reference, {:error, "Could not start an isolated HTTP client."}})
          end
        after
          Registry.unregister(Ipse.Registry, {__MODULE__, name})
        end

      :full ->
        send(
          owner,
          {reference, {:error, "HTTP clients are busy. Retry after another request finishes."}}
        )
    end
  end

  defp reserve do
    Enum.find_value(@profiles, :full, fn name ->
      case Registry.register(Ipse.Registry, {__MODULE__, name}, nil) do
        {:ok, _} -> {:ok, name}
        {:error, _} -> nil
      end
    end)
  end

  defp start_client(:httpc, name), do: :inets.start(:httpc, [profile: name], :stand_alone)

  defp start_client({:finch, conn_opts}, name) do
    Finch.start_link(
      name: name,
      pools: %{
        default: [
          size: 1,
          count: 1,
          conn_opts: [protocols: [:http1], max_header_list_size: 16_384] ++ conn_opts
        ]
      }
    )
  end

  defp stop_profile(profile, backend) do
    monitor = Process.monitor(profile)

    if backend == :httpc do
      :inets.stop(:stand_alone, profile)
    else
      try do
        Supervisor.stop(profile, :normal, 1000)
      catch
        :exit, _ -> Process.exit(profile, :kill)
      end
    end

    receive do
      {:DOWN, ^monitor, :process, ^profile, _} -> :ok
    after
      1_000 ->
        Process.exit(profile, :kill)
        await_exit(profile, monitor)
    end
  end

  defp await_exit(pid, monitor) do
    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> :ok
    end
  end
end
