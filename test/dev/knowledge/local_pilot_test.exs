Code.require_file("../../../dev/knowledge/local_pilot.exs", __DIR__)

defmodule Ipse.Development.Knowledge.LocalPilotFakeModels do
  def begin_job(config, :text, 80_000) do
    send(self(), {:begin_job, config})
    if config[:refuse], do: {:error, :pin_mismatch}, else: {:ok, :job}
  end

  def with_job(:job, config, fun), do: fun.(config)

  def finish_job(:job, _config, result) do
    send(self(), :finish_job)
    if Process.get(:fail_finish), do: {:error, :pin_changed}, else: result
  end
end

defmodule Ipse.Development.Knowledge.LocalPilotTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Knowledge.{LocalPilot, LocalPilotFakeModels}

  setup do
    path = Path.join(System.tmp_dir!(), "ipse-local-pilot-attempts-" <> Ipse.Usage.id())
    {:ok, file} = File.open(path, [:write, :binary, :exclusive])

    on_exit(fn ->
      File.close(file)
      File.rm(path)
    end)

    %{attempt_file: file, path: path, counter: :atomics.new(1, signed: false)}
  end

  test "the wrapper checks pin and guard, records intent, and checks the returned job", c do
    config = %{provider: :ollama, model: "fixture"}

    guard = fn ->
      send(self(), :guard_checked)
      :ok
    end

    provider = fn actual, messages, tools, _emit ->
      assert actual == config
      assert messages == [:synthetic] and tools == [:tool]
      assert c.path |> File.read!() |> Jason.decode!() == %{"attempt" => 1, "version" => 1}
      send(self(), :provider_called)
      {:ok, %{"role" => "assistant"}, %{}}
    end

    assert {:ok, _, _} =
             LocalPilot.guarded_request(
               config,
               [:synthetic],
               [:tool],
               fn _ -> :ok end,
               c.attempt_file,
               c.counter,
               guard,
               LocalPilotFakeModels,
               provider
             )

    assert_receive :guard_checked
    assert_receive {:begin_job, ^config}
    assert_receive :guard_checked
    assert_receive :provider_called
    assert_receive :finish_job
    assert :atomics.get(c.counter, 1) == 1
  end

  test "pin refusal and a lost guard stop before an attempt or provider call", c do
    provider = fn _, _, _, _ -> flunk("provider must not be called") end
    ok = fn -> :ok end

    assert {:error, :pilot_model_unavailable} =
             LocalPilot.guarded_request(
               %{refuse: true},
               [],
               [],
               fn _ -> :ok end,
               c.attempt_file,
               c.counter,
               ok,
               LocalPilotFakeModels,
               provider
             )

    Process.put(:guard_count, 0)

    guard = fn ->
      count = Process.get(:guard_count)
      Process.put(:guard_count, count + 1)
      if count == 0, do: :ok, else: {:error, :lost_reservation}
    end

    assert {:error, :pilot_attempt_unavailable} =
             LocalPilot.guarded_request(
               %{},
               [],
               [],
               fn _ -> :ok end,
               c.attempt_file,
               c.counter,
               guard,
               LocalPilotFakeModels,
               provider
             )

    assert :atomics.get(c.counter, 1) == 0
    assert File.read!(c.path) == ""
  end

  test "a failed post-job check retains its attempt and is never retried by the wrapper", c do
    Process.put(:fail_finish, true)

    provider = fn _, _, _, _ ->
      send(self(), :provider_called)
      {:ok, %{}, %{}}
    end

    assert {:error, :pin_changed} =
             LocalPilot.guarded_request(
               %{},
               [],
               [],
               fn _ -> :ok end,
               c.attempt_file,
               c.counter,
               fn -> :ok end,
               LocalPilotFakeModels,
               provider
             )

    assert_receive :provider_called
    refute_receive :provider_called
    assert :atomics.get(c.counter, 1) == 1
    assert c.path |> File.read!() |> Jason.decode!() == %{"attempt" => 1, "version" => 1}
  end
end
