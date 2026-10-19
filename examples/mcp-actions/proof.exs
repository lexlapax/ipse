Code.require_file("fixture.exs", __DIR__)

defmodule IpseMCPExample.Proof do
  @moduledoc false
  alias Ipse.{Session, Journal}
  alias Ipse.Extensions.{Config, Registry, Store, Actions}
  alias IpseMCPExample.Fixture

  defmodule NoModel do
    def complete(_, _, _, _),
      do: raise("Explicit extension command called the conversation provider")
  end

  def run(artifact) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    false = :code.is_loaded(IpseMCPExample.Read) != false
    root = Path.join(System.tmp_dir!(), "ipse-mcp-proof-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    Process.put(:mcp_proof_sessions, [])
    Process.put(:mcp_proof_fixtures, [])

    try do
      http = transport(root, :http)
      stdio = transport(root, :stdio)
      http_cfg = config(artifact, http)
      stdio_cfg = config(artifact, stdio)
      ask = Map.put(http_cfg, :approval, :ask)
      pid = start(http, ask)
      :ok = invoke(pid, %{"before_reads" => 20})
      approval = approval(pid)
      true = approval.proposed["request"] == request()
      binding = approval.proposed["effect_binding"]
      true = binding["kind"] == "mcp" and binding["alias"] == "documents"
      true = binding["schema"] == Fixture.schema()
      true = binding["manifest"]["tool_id"] == "mcp__fixture__fetch"
      true = binding["server"]["fingerprint"] == http.server.fingerprint
      true = Fixture.discoveries(http.root) == 1 and Fixture.calls(http.root) == 0
      :ok = Session.approve(pid, approval.ref, true)
      done(pid, :ok)
      ev = events(http, pid)
      validate_windows(ev)
      results = Enum.filter(ev, &(&1["type"] == "extension_action_result"))
      true = Enum.count(results, &(&1["request"]["op"] == "state.get")) == 20
      true = Enum.all?(results, &(&1["version"] == 2))
      true = Session.info(pid).extension_result["value"]["bytes"] == byte_size(Fixture.text())
      id = Session.info(pid).id
      :ok = Session.close_confirmed(pid)
      path = Path.join(http.dir, id <> ".jsonl")
      original = File.read!(path)
      transport_before = Fixture.records(http.root)
      resumed = start(http, ask, id)
      :idle = Session.info(resumed).phase
      true = File.read!(path) == original and Fixture.records(http.root) == transport_before
      :ok = Session.close_confirmed(resumed)

      local = start(stdio, stdio_cfg)
      :ok = invoke(local)
      done(local, :ok)
      validate_windows(events(stdio, local))
      true = Fixture.calls(stdio.root) == 1
      :ok = Session.close_confirmed(local)

      denied = start(http, ask)
      :ok = invoke(denied)
      denied_approval = approval(denied)
      calls = Fixture.calls(http.root)
      :ok = Session.approve(denied, denied_approval.ref, false)
      done(denied, :ok)
      true = Fixture.calls(http.root) == calls
      [denial] = events(http, denied) |> Enum.filter(&(&1["type"] == "extension_action_result"))
      "denied" = denial["outcome"]["status"]
      :ok = Session.close_confirmed(denied)

      forbidden = start(http, http_cfg)
      discoveries = Fixture.discoveries(http.root)
      :ok = invoke(forbidden, %{"request" => Map.put(request(), "binding", "unselected")})
      done(forbidden, :error)
      true = Fixture.discoveries(http.root) == discoveries and Fixture.calls(http.root) == calls
      :ok = Session.close_confirmed(forbidden)

      drift = start(http, ask)
      :ok = invoke(drift)
      drift_approval = approval(drift)
      File.write!(Path.join(http.root, "change-descriptor"), "changed")
      :ok = Session.approve(drift, drift_approval.ref, true)
      done(drift, :ok)
      true = Fixture.calls(http.root) == calls
      [refused] = events(http, drift) |> Enum.filter(&(&1["type"] == "extension_action_result"))
      %{"status" => "failed", "value" => %{"code" => "mcp_refused"}} = refused["outcome"]
      :ok = Session.close_confirmed(drift)
      File.rm!(Path.join(http.root, "change-descriptor"))

      source = Enum.find(ev, &(&1["type"] == "extension_effect_result"))
      {:error, _} = Actions.restore(List.delete(ev, source))

      forged =
        Enum.map(ev, fn event ->
          if event == source, do: put_in(event, ["data", "text"], "forged"), else: event
        end)

      {:error, _} = Actions.restore(forged)

      limited = start(http, http_cfg)
      before_limit = Fixture.calls(http.root)
      :ok = invoke(limited, %{"repeat" => 17, "read" => false})
      done(limited, :error)
      true = Fixture.calls(http.root) == before_limit + 16
      :ok = Session.close_confirmed(limited)
      false = :code.is_loaded(IpseMCPExample.Read) != false

      %{
        "checks" => %{
          "independent_worker_artifact" => true,
          "full_exact_approval" => true,
          "stdio_and_http_dispatch" => true,
          "source_precedes_descriptor" => true,
          "complete_utf8_windows" => true,
          "idle_resume_inert" => true,
          "mixed_reads_then_effect" => true,
          "denial_has_zero_dispatch" => true,
          "unselected_binding_has_zero_discovery" => true,
          "descriptor_drift_has_zero_dispatch" => true,
          "source_corruption_refused" => true,
          "seventeenth_effect_refused" => true
        },
        "source_bytes" => byte_size(Fixture.text()),
        "live_model_calls" => 0
      }
    after
      Enum.each(Process.get(:mcp_proof_sessions), fn pid ->
        if Process.alive?(pid), do: Session.close(pid)
      end)

      Enum.each(Process.get(:mcp_proof_fixtures), &Fixture.stop/1)
      File.rm_rf!(root)
    end
  end

  defp transport(root, kind) do
    root = Path.join(root, to_string(kind))
    File.mkdir_p!(root)

    entry =
      case kind do
        :stdio ->
          Fixture.stdio_config(root)

        :http ->
          {fixture, entry} = Fixture.http(root, self())
          Process.put(:mcp_proof_fixtures, [fixture | Process.get(:mcp_proof_fixtures)])
          entry
      end

    path = Path.join(root, "mcp.json")
    File.write!(path, Jason.encode!(%{"servers" => [entry]}))
    {:ok, [server]} = Ipse.MCP.Config.load(path)
    %{root: root, dir: Path.join(root, "sessions"), home: Path.join(root, "home"), server: server}
  end

  defp config(artifact, context) do
    {:ok, installed} = Store.import(artifact, Path.join(context.home, "extensions/artifacts"))

    capabilities =
      Jason.decode!(File.read!(Path.join(artifact, "extension.json")))["capabilities"]

    source = %{
      scope: "operator",
      path: Path.join(context.root, "operator.json"),
      data: %{
        "extensions" => [
          %{
            "instance" => "reader",
            "artifact" => installed.digest,
            "enabled" => true,
            "options" => %{},
            "order" => 1,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => installed.digest,
            "capabilities" => capabilities,
            "allow_project" => false,
            "allow_children" => false,
            "mcp_bindings" => [
              %{"instance" => "reader", "alias" => "documents", "tool" => "mcp__fixture__fetch"}
            ]
          }
        ]
      }
    }

    {:ok, selections} = Config.resolve([source], [])
    {:ok, entries} = Registry.prepare(selections, context.home)

    %{
      provider: :ollama,
      model: "unused-explicit-command",
      provider_module: NoModel,
      home: context.home,
      operator_home: nil,
      approval: :allow,
      extensions: entries,
      mcp_servers: [context.server],
      compact: false
    }
  end

  defp start(context, config, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config,
         cwd: context.root,
         state_dir: context.dir,
         id: id,
         subscriber: self(),
         owner: self()}
      )

    Process.put(:mcp_proof_sessions, [pid | Process.get(:mcp_proof_sessions)])
    pid
  end

  defp request,
    do: %{
      "op" => "mcp.call",
      "version" => 1,
      "binding" => "documents",
      "arguments" => %{"text" => "Public synthetic request"},
      "timeout_ms" => 5000
    }

  defp invoke(pid, extra \\ %{}),
    do:
      Session.invoke_export(
        pid,
        :command,
        "ext__reader__read",
        Map.merge(%{"request" => request(), "read" => true}, extra)
      )

  defp approval(pid) do
    receive do
      {:ipse, ^pid, {:approval, ref, "extension:mcp.call", proposed}} ->
        %{ref: ref, proposed: proposed}

      {:ipse, ^pid, {:done, _}} ->
        raise "Command ended before exact MCP approval"

      {:ipse, ^pid, _} ->
        approval(pid)
    after
      10_000 -> raise "MCP approval did not arrive"
    end
  end

  defp done(pid, expected) do
    receive do
      {:ipse, ^pid, {:done, ^expected}} -> :ok
      {:ipse, ^pid, {:done, status}} -> raise "Unexpected MCP proof outcome: #{inspect(status)}"
      {:ipse, ^pid, _} -> done(pid, expected)
    after
      30_000 -> raise "MCP command did not finish"
    end
  end

  defp events(context, pid) do
    {:ok, events} = Journal.load(context.dir, Session.info(pid).id)
    {:ok, _} = Session.restore_context(events)
    events
  end

  defp validate_windows(events) do
    source_index = Enum.find_index(events, &(&1["type"] == "extension_effect_result"))

    result_index =
      Enum.find_index(
        events,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "mcp.call")
      )

    true = is_integer(source_index) and source_index < result_index
    source = Enum.at(events, source_index)
    true = source["data"] == %{"text" => Fixture.text()}

    windows =
      for event <- events,
          event["type"] == "extension_action_result" and
            event["request"]["op"] == "effect.result.read",
          do: event["outcome"]["value"]

    true = length(windows) > 2
    true = Enum.all?(windows, &(String.valid?(&1["text"]) and byte_size(&1["text"]) <= 4096))
    true = Enum.map_join(windows, & &1["text"]) == Fixture.text()
    true = List.last(windows)["complete"] and List.last(windows)["next"] == nil
    :ok
  end
end
