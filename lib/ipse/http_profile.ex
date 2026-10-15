defmodule Ipse.HTTPProfile do
  @moduledoc false

  # Fixed names bound atom usage. Each guardian retains its registry lease until
  # the profile has exited, including when its borrower is killed.
  @profiles for index <- 1..64, do: :"ipse_http_#{index}"

  def with_profile(fun) when is_function(fun, 1) do
    Application.ensure_all_started(:ipse)
    owner = self()
    reference = make_ref()
    {guardian, monitor} = spawn_monitor(fn -> own_profile(owner, reference) end)

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

  defp own_profile(owner, reference) do
    Process.flag(:trap_exit, true)
    owner_monitor = Process.monitor(owner)

    case reserve() do
      {:ok, name} ->
        try do
          case :inets.start(:httpc, [profile: name], :stand_alone) do
            {:ok, profile} ->
              profile_monitor = Process.monitor(profile)
              send(owner, {reference, {:ok, profile}})

              receive do
                {^reference, :finished} -> :ok
                {:DOWN, ^owner_monitor, :process, ^owner, _} -> :ok
                {:DOWN, ^profile_monitor, :process, ^profile, _} -> :ok
                {:EXIT, ^profile, _} -> :ok
              end

              Process.demonitor(profile_monitor, [:flush])
              stop_profile(profile)

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

  defp stop_profile(profile) do
    monitor = Process.monitor(profile)
    :inets.stop(:stand_alone, profile)

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
