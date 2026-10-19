Code.require_file("../examples/knowledge/evaluation_gateway.exs", __DIR__)
Code.require_file("../examples/knowledge/evaluation_resources.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationServicesTest do
  use ExUnit.Case, async: false
  alias IpseKnowledgeExample.{EvaluationGateway, EvaluationResources}

  defp request(port, tool, arguments) do
    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, packet: 4], 1000)

    try do
      :ok =
        :gen_tcp.send(
          socket,
          JSON.encode!(%{
            "version" => 1,
            "partition" => "evaluation",
            "tool" => tool,
            "arguments" => arguments
          })
        )

      {:ok, bytes} = :gen_tcp.recv(socket, 0, 1000)
      JSON.decode!(bytes)
    after
      :gen_tcp.close(socket)
    end
  end

  test "gateway fetch selection is per query and its global cap survives document changes" do
    {:ok, gateway} = EvaluationGateway.start(0)
    port = EvaluationGateway.port(gateway)

    source = %{
      "source_id" => "fixture:release",
      "uri" => "local:release",
      "title" => "Release",
      "text" => "Release requires quiescence.",
      "observed_at_ms" => 1
    }

    fetch = %{"version" => 1, "contract" => "fetch-v1", "uri" => source["uri"]}
    search = %{"version" => 1, "contract" => "search-v1", "query" => "Release", "limit" => 1}

    try do
      assert :ok = EvaluationGateway.select(gateway, [%{"source" => source}])
      assert request(port, "fetch", fetch)["status"] == "refused"
      assert request(port, "search", search)["status"] == "ok"
      assert EvaluationGateway.selected_uris(gateway) == [source["uri"]]
      assert request(port, "fetch", fetch)["text"] == source["text"]
      assert :ok = EvaluationGateway.begin_query(gateway)
      assert EvaluationGateway.selected_uris(gateway) == []
      assert request(port, "fetch", fetch)["status"] == "refused"
      for _ <- 1..512, do: request(port, "search", search)
      assert length(EvaluationGateway.calls(gateway)) == 512
      assert :ok = EvaluationGateway.select(gateway, [%{"source" => source}])
      assert request(port, "search", search)["status"] == "refused"
      assert length(EvaluationGateway.calls(gateway)) == 512

      assert EvaluationGateway.summary(gateway) == %{
               "call_limit" => 512,
               "recorded_calls" => 512,
               "rejected_over_limit" => 5,
               "request_count" => 517
             }
    after
      assert :ok = EvaluationGateway.stop(gateway)
    end
  end

  test "malformed packets do not stop the gateway and owner death stops its acceptor" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, gateway} = EvaluationGateway.start(0)
        send(parent, {:owned_gateway, gateway})

        receive do
          :done -> :ok
        end
      end)

    assert_receive {:owned_gateway, gateway}
    acceptor = GenServer.call(gateway, :acceptor)
    gateway_monitor = Process.monitor(gateway)
    acceptor_monitor = Process.monitor(acceptor)
    port = EvaluationGateway.port(gateway)

    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, packet: 4], 1000)

    :ok = :gen_tcp.send(socket, "invalid JSON")
    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
    :gen_tcp.close(socket)
    assert request(port, "invalid", %{})["status"] == "refused"
    assert hd(EvaluationGateway.calls(gateway))["tool"] == "other"
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^gateway_monitor, :process, ^gateway, :normal}, 1000
    assert_receive {:DOWN, ^acceptor_monitor, :process, ^acceptor, _}, 1000

    assert {:error, :econnrefused} =
             :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1000)
  end

  test "gateway completes fifty ten-source questions and refuses work beyond its allowance" do
    {:ok, gateway} = EvaluationGateway.start(0, 50 * 11)
    port = EvaluationGateway.port(gateway)

    docs =
      Enum.map(1..10, fn n ->
        %{
          "source" => %{
            "source_id" => "s#{n}",
            "uri" => "local:s#{n}",
            "title" => "Release",
            "text" => "Release requires quiescence.",
            "observed_at_ms" => 1
          }
        }
      end)

    search = %{"version" => 1, "contract" => "search-v1", "query" => "Release", "limit" => 10}

    try do
      assert :ok = EvaluationGateway.select(gateway, docs)

      for question <- 1..50 do
        assert :ok = EvaluationGateway.begin_query(gateway)
        result = request(port, "search", search)
        assert result["status"] == "ok", "search failed at question #{question}"
        assert length(result["hits"]) == 10

        for hit <- result["hits"] do
          args = %{"version" => 1, "contract" => "fetch-v1", "uri" => hit["uri"]}

          assert request(port, "fetch", args)["status"] == "ok",
                 "fetch failed at question #{question}"
        end
      end

      assert length(EvaluationGateway.calls(gateway)) == 550
      assert :ok = EvaluationGateway.select(gateway, docs)
      assert :ok = EvaluationGateway.begin_query(gateway)
      assert request(port, "search", search)["status"] == "refused"
      assert length(EvaluationGateway.calls(gateway)) == 550

      assert EvaluationGateway.summary(gateway) == %{
               "call_limit" => 550,
               "recorded_calls" => 550,
               "rejected_over_limit" => 1,
               "request_count" => 551
             }
    after
      assert :ok = EvaluationGateway.stop(gateway)
    end
  end

  test "gateway refuses invalid finite allowances before starting a listener" do
    for limit <- [0, -1, 11_265, 1.0, "550", nil] do
      assert {:error, :invalid_gateway_limit} = EvaluationGateway.start(0, limit)
    end

    for limit <- [1, 11_264] do
      assert {:ok, gateway} = EvaluationGateway.start(0, limit)

      try do
        assert EvaluationGateway.summary(gateway) == %{
                 "call_limit" => limit,
                 "recorded_calls" => 0,
                 "rejected_over_limit" => 0,
                 "request_count" => 0
               }
      after
        assert :ok = EvaluationGateway.stop(gateway)
      end
    end
  end

  test "sampler reports its measurement scope and stops with its owner" do
    path = Path.join(System.tmp_dir!(), "ipse-evaluation-samples-" <> Ipse.Usage.id())
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)
    sampler = EvaluationResources.start(path, 10)
    assert {:ok, report} = EvaluationResources.stop(sampler)
    assert report["samples"] >= 1
    assert report["start"]["beam_total_bytes"] > 0
    assert report["end"]["beam_total_bytes"] <= report["sampled_beam_max_bytes"]
    assert report["worker_rss"] == nil
    assert report["model_rss"] == nil
    assert report["whole_system_peak"] == nil
    parent = self()

    owner =
      spawn(fn ->
        sampler = EvaluationResources.start(path, 10)
        send(parent, {:owned_sampler, sampler.pid})

        receive do
          :done -> :ok
        end
      end)

    assert_receive {:owned_sampler, pid}
    monitor = Process.monitor(pid)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 1000
  end
end
