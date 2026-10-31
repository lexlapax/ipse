defmodule Ipse.InstalledDecisionProbe do
  @moduledoc "Synthetic decision Session proof using a loopback fixture."
  alias Ipse.{Journal, Session, Usage}
  alias Ipse.Extension.{Actions, Artifact, Config, Registry}

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("unexpected conversation inference")
  end

  def run(artifact_path) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    root = Path.join(System.tmp_dir!(), "ipse-decision-proof-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    Process.put(:decision_probe_sessions, [])
    home = Path.join(root, "home")
    dir = Path.join(root, "sessions")
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    server = spawn_link(fn -> serve(listener, owner) end)

    try do
      {:ok, artifact} = Artifact.import(artifact_path, Path.join(home, "extensions/artifacts"))
      caps = ~w(invoke.command host.actions host.decision)

      data = %{
        "extensions" => [
          %{
            "instance" => "advice",
            "artifact" => artifact.digest,
            "enabled" => true,
            "options" => %{},
            "order" => 1,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => artifact.digest,
            "capabilities" => caps,
            "allow_project" => false,
            "allow_children" => false
          }
        ]
      }

      {:ok, selected} =
        Config.resolve(
          [%{scope: "operator", path: Path.join(root, "operator.json"), data: data}],
          []
        )

      {:ok, entries} = Registry.prepare(selected, home)

      config = %{
        provider: :ollama,
        model: "unused",
        provider_module: NoModel,
        home: home,
        extensions: entries,
        approval: :ask,
        compact: false,
        decision_profiles: %{
          "advice" => %{
            "operation" => "decision",
            "provider" => "system_one_compatible",
            "model" => "fixture",
            "expected_model" => "fixture",
            "service_id" => "development",
            "base_url" => "http://127.0.0.1:#{port}"
          }
        }
      }

      request = %{
        "op" => "decision.create",
        "version" => 1,
        "profile" => "advice",
        "input" => "Synthetic installed decision",
        "questions" => [
          %{"id" => "relevant", "type" => "predicate", "instructions" => "Does this apply?"}
        ],
        "timeout_ms" => 10_000
      }

      {:ok, pid} = start(config, root, dir, nil)
      :ok = Session.invoke_export(pid, :command, "ext__advice__decide", %{"request" => request})
      {ref, proposal} = approval(pid)
      true = proposal["request"] == request

      receive do
        {:probe_http, _, _, _} -> raise "request dispatched before approval"
      after
        150 -> :ok
      end

      :ok = Session.approve(pid, ref, true)

      receive do
        {:probe_http, handler, headers, body} ->
          true = String.starts_with?(headers, "POST /systemone HTTP/1.1")
          false = String.contains?(String.downcase(headers), "authorization:")
          true = body["state"] == request["input"]
          send(handler, :respond)
      after
        10_000 -> raise "decision request did not arrive"
      end

      :ok = done(pid)
      id = Session.info(pid).id
      {:ok, events} = Journal.load(dir, id)
      {:ok, _} = Usage.restore(events, id)
      {:ok, _} = Actions.restore(events)

      types =
        ~w(extension_action_intent extension_decision_request request_admitted request_usage_observed extension_decision_response request_finished extension_action_result)

      positions = Enum.map(types, fn type -> Enum.find_index(events, &(&1["type"] == type)) end)
      true = Enum.all?(positions, &is_integer/1) and positions == Enum.sort(positions)
      outcome = Enum.find(events, &(&1["type"] == "extension_action_result"))["outcome"]
      "ok" = outcome["status"]

      [%{"id" => "relevant", "type" => "predicate", "probability" => 0.8}] =
        outcome["value"]["result"]["answers"]

      10 = outcome["value"]["usage"]["counts"]["input_tokens"]
      :ok = Session.close_confirmed(pid)
      {:ok, resumed} = start(config, root, dir, id)
      :idle = Session.info(resumed).phase

      receive do
        {:probe_http, _, _, _} -> raise "decision request replayed on resume"
      after
        150 -> :ok
      end

      :ok = Session.close_confirmed(resumed)

      {:ok, denied} = start(config, root, dir, nil)

      :ok =
        Session.invoke_export(denied, :command, "ext__advice__decide", %{"request" => request})

      {deny_ref, _} = approval(denied)
      :ok = Session.approve(denied, deny_ref, false)
      :ok = done(denied)
      no_request!()
      denied_id = Session.info(denied).id
      {:ok, denied_events} = Journal.load(dir, denied_id)
      false = Enum.any?(denied_events, &(&1["type"] == "request_admitted"))
      {:ok, _} = Actions.restore(denied_events)
      :ok = Session.close_confirmed(denied)
      {:ok, denied_resume} = start(config, root, dir, denied_id)
      :idle = Session.info(denied_resume).phase
      no_request!()
      :ok = Session.close_confirmed(denied_resume)

      {:ok, interrupted} = start(config, root, dir, nil)

      :ok =
        Session.invoke_export(interrupted, :command, "ext__advice__decide", %{
          "request" => request
        })

      {interrupt_ref, _} = approval(interrupted)
      :ok = Session.approve(interrupted, interrupt_ref, true)

      handler =
        receive do
          {:probe_http, handler, _, _} -> handler
        after
          10_000 -> raise "interrupted request did not arrive"
        end

      :ok = Session.cancel(interrupted)

      receive do
        {:probe_http_closed, ^handler} -> :ok
      after
        10_000 -> raise "interrupted socket did not close"
      end

      interrupted_id = Session.info(interrupted).id
      {:ok, interrupted_events} = Journal.load(dir, interrupted_id)
      {:ok, _} = Usage.restore(interrupted_events, interrupted_id)
      {:ok, _} = Actions.restore(interrupted_events)
      false = Enum.any?(interrupted_events, &(&1["type"] == "extension_decision_response"))

      %{"outcome" => "cancelled", "finality" => "partial"} =
        Enum.find(interrupted_events, &(&1["type"] == "request_finished"))

      :ok = Session.close_confirmed(interrupted)
      {:ok, interrupted_resume} = start(config, root, dir, interrupted_id)
      :idle = Session.info(interrupted_resume).phase
      no_request!()
      :ok = Session.close_confirmed(interrupted_resume)

      %{
        "checks" => %{
          "approval_before_request" => true,
          "compatible_route_no_authorization" => true,
          "typed_advice" => true,
          "ordered_usage_restores" => true,
          "idle_resume_no_replay" => true,
          "denial_no_egress" => true,
          "interrupted_no_replay" => true
        },
        "synthetic" => true,
        "conversation_inference" => false
      }
    after
      :gen_tcp.close(listener)
      Process.unlink(server)
      Process.exit(server, :shutdown)

      for session <- Process.get(:decision_probe_sessions, []),
          Process.alive?(session),
          do: Session.close_confirmed(session)

      Process.delete(:decision_probe_sessions)
      File.rm_rf!(root)
    end
  end

  defp start(config, root, dir, id) do
    case DynamicSupervisor.start_child(
           Ipse.Sessions,
           {Session, config: config, cwd: root, state_dir: dir, id: id, subscriber: self()}
         ) do
      {:ok, pid} = result ->
        Process.put(:decision_probe_sessions, [pid | Process.get(:decision_probe_sessions, [])])
        result

      error ->
        error
    end
  end

  defp approval(pid) do
    receive do
      {:ipse, ^pid, {:approval, ref, "extension:decision.create", proposal}} -> {ref, proposal}
      {:ipse, ^pid, {:done, reason}} -> raise "decision ended before approval: #{inspect(reason)}"
      {:ipse, ^pid, _} -> approval(pid)
    after
      10_000 -> raise "approval timed out"
    end
  end

  defp done(pid) do
    receive do
      {:ipse, ^pid, {:done, :ok}} -> :ok
      {:ipse, ^pid, {:done, reason}} -> raise "decision failed: #{inspect(reason)}"
      {:ipse, ^pid, _} -> done(pid)
    after
      10_000 -> raise "decision completion timed out"
    end
  end

  defp no_request! do
    receive do
      {:probe_http, _, _, _} -> raise "unexpected decision request"
    after
      150 -> :ok
    end
  end

  defp serve(listener, owner) do
    case :gen_tcp.accept(listener, 30_000) do
      {:ok, socket} ->
        try do
          {headers, body} = request(socket, "")
          send(owner, {:probe_http, self(), headers, Jason.decode!(body)})
          :ok = :inet.setopts(socket, active: :once)

          receive do
            :respond ->
              response =
                Jason.encode!(%{
                  "model" => "fixture",
                  "answers" => %{"relevant" => %{"type" => "noul", "noul" => 0.8}},
                  "usage" => %{"input_tokens" => 10, "output_tokens" => 2}
                })

              :ok =
                :gen_tcp.send(socket, [
                  "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(response)}\r\nconnection: close\r\n\r\n",
                  response
                ])

            {:tcp_closed, ^socket} ->
              send(owner, {:probe_http_closed, self()})

            {:tcp_error, ^socket, _} ->
              send(owner, {:probe_http_closed, self()})
          after
            10_000 -> raise "fixture response timed out"
          end
        after
          :gen_tcp.close(socket)
        end

        serve(listener, owner)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        raise "fixture accept failed: #{inspect(reason)}"
    end
  end

  defp request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
        {headers, body(socket, body, String.to_integer(size))}

      [_] ->
        {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
        request(socket, buffer <> chunk)
    end
  end

  defp body(_, body, size) when byte_size(body) >= size, do: body

  defp body(socket, body, size) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
    body(socket, body <> chunk, size)
  end
end
