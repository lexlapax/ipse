defmodule IpseModelExample.Proof do
  @moduledoc false
  alias Ipse.{Session, Journal, Usage, Budget}
  alias Ipse.Extensions.{Store, Config, Registry, Manifest}

  def run(artifact, thinking \\ nil) when thinking in [nil, "none"] do
    {:ok, _} = Application.ensure_all_started(:ipse)
    root = Path.join(System.tmp_dir!(), "ipse-model-proof-#{Usage.id()}")
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    Process.put(:model_proof_sessions, [])
    Process.put(:model_proof_server, nil)
    {base, listener} = fixture()

    try do
      cwd = Path.join(root, "workspace")
      home = Path.join(root, "home")
      dir = Path.join(root, "state")
      File.mkdir_p!(cwd)
      {:ok, installed} = Store.import(artifact, Path.join(home, "extensions/artifacts"))

      source = %{
        scope: "operator",
        path: Path.join(root, "operator.json"),
        data: %{
          "extensions" => [
            %{
              "instance" => "model",
              "artifact" => installed.digest,
              "enabled" => true,
              "options" => %{},
              "order" => 1,
              "lifetime" => "persistent"
            },
            %{
              "instance" => "costs",
              "artifact" => "builtin:cost-summary:1",
              "enabled" => true,
              "options" => %{"rate_card" => card(base)},
              "order" => 2,
              "lifetime" => "persistent"
            }
          ],
          "extension_trust" => [
            %{
              "artifact" => installed.digest,
              "capabilities" => ~w(invoke.command host.actions host.model),
              "allow_project" => false,
              "allow_children" => false
            },
            %{
              "artifact" => "builtin:cost-summary:1",
              "capabilities" => ~w(invoke.command host.actions host.usage host.usage.scan),
              "allow_project" => false,
              "allow_children" => false
            }
          ]
        }
      }

      {:ok, selections} = Config.resolve([source], [])
      {:ok, entries} = Registry.prepare(selections, home)

      config = %{
        provider: :openai,
        model: "unused-main-fixture",
        api_key: "synthetic-unused-main",
        home: home,
        operator_home: Path.join(root, "operator-home"),
        approval: :ask,
        extensions: entries,
        budget: %{"version" => 1, "max_requests" => 1},
        profiles: %{
          "extract" => %{
            "provider" => "ollama",
            "model" => "fixture-extract",
            "base_url" => base,
            "max_output_tokens" => 32
          }
        }
      }

      config =
        if thinking == "none",
          do: put_in(config, [:profiles, "extract", "reasoning_effort"], "none"),
          else: config

      request = %{
        "op" => "model.complete",
        "version" => 1,
        "profile" => "extract",
        "instruction" => "Return names only.",
        "input" => "Public synthetic input",
        "timeout_ms" => 5000,
        "max_output_bytes" => 1024
      }

      pid = start(config, cwd, dir)
      :ok = Session.invoke_export(pid, :command, "ext__model__complete", %{"request" => request})

      ref =
        receive do
          {:ipse, ^pid, {:approval, ref, "extension:model.complete", proposed}} ->
            true =
              proposed["request"] == request and proposed["execution"]["provider"] == "ollama"

            true = proposed["destination"]["origin"] == base

            true =
              proposed["destination"]["target_sha256"] == Manifest.sha256(base <> "/api/chat")

            ref
        after
          5000 -> raise "Model approval was not displayed"
        end

      server = serve_fixture(listener, self())
      Process.put(:model_proof_server, server)
      :ok = Session.approve(pid, ref, true)
      done(pid, :ok)
      {headers, wire} = Task.await(server)

      [helper_system, helper_context] = wire["messages"]
      "system" = helper_system["role"]
      false = String.contains?(helper_system["content"], request["instruction"])
      "user" = helper_context["role"]
      [label, encoded] = String.split(helper_context["content"], "\n", parts: 2)
      true = String.contains?(label, "Untrusted extension task context")
      true = Jason.decode!(encoded) == Map.take(request, ~w(instruction input))

      true = wire["model"] == "fixture-extract" and wire["tools"] == []
      true = wire["options"] == %{"num_predict" => 32}

      if thinking == "none" do
        true = wire["think"] === false
      else
        false = Map.has_key?(wire, "think")
      end

      false = String.contains?(String.downcase(headers), "authorization")
      result = Session.info(pid).extension_result["value"]
      true = result["status"] == "ok" and result["value"]["text"] == "entities"
      true = result["value"]["usage"]["counts"]["total_tokens"] == 10
      false = Jason.encode!(result) =~ "private-fixture"

      :ok = Session.invoke_export(pid, :command, "ext__costs__summary", %{})
      done(pid, :ok)
      report = Session.info(pid).extension_result["value"]
      true = report["enumeration_complete"] and report["cost_estimate_complete"]
      true = report["request_count"] == 1
      [group] = report["groups"]
      true = group["provider"] == "ollama" and group["billing_mode"] == "local"
      true = group["basis"] == "local_estimate" and group["amount_nanos"] == 44_000
      true = group["counts"]["total_tokens"]["total"] == 10

      :ok = Session.invoke_export(pid, :command, "ext__model__complete", %{"request" => request})

      ref =
        receive do
          {:ipse, ^pid, {:approval, ref, "extension:model.complete", _}} -> ref
        after
          5000 -> raise "Second model approval was not displayed"
        end

      :ok = Session.approve(pid, ref, true)
      done(pid, :ok)

      true =
        Session.info(pid).extension_result["value"] == %{
          "status" => "failed",
          "value" => %{"code" => "model_request_failed"}
        }

      :ok = Session.prompt(pid, "This request must be refused by the same quota.")
      done(pid, :error)
      id = Session.info(pid).id
      {:ok, budget} = Budget.saved(dir, id)
      true = budget["request_count"] == 1 and budget["refused_count"] == 2
      {:ok, events} = Journal.load(dir, id)
      {:ok, ledger} = Usage.restore(events, id)
      true = length(ledger.order) == 3
      {:ok, _} = Session.restore_context(events)
      native = Enum.find(events, &(&1["type"] == "extension_model_response"))
      source = Enum.find(events, &(&1["type"] == "extension_model_request"))
      true = source["execution"]["reasoning_effort"] == thinking

      true =
        get_in(native, ["assistant", "provider_data", "message", "thinking"]) == "private-fixture"

      :ok = Session.close(pid)
      bytes = File.read!(Path.join(dir, id <> ".jsonl"))
      budget_path = Path.join([dir, "budgets", id <> ".jsonl"])
      budget_bytes = File.read!(budget_path)
      resumed = start(config, cwd, dir, id)
      true = Session.info(resumed).phase == :idle
      true = File.read!(Path.join(dir, id <> ".jsonl")) == bytes
      true = File.read!(budget_path) == budget_bytes

      %{
        "version" => 1,
        "thinking_selection" => thinking || "default",
        "checks" =>
          Map.new(
            ~w(independent_artifact full_approval explicit_profile private_native_receipt bounded_text canonical_usage accounted_report shared_refusal inert_resume),
            &{&1, true}
          )
      }
    after
      Enum.each(Process.get(:model_proof_sessions, []), fn pid ->
        if Process.alive?(pid), do: Session.close(pid)
      end)

      :gen_tcp.close(listener)
      if server = Process.get(:model_proof_server), do: Task.shutdown(server, :brutal_kill)
      File.rm_rf!(root)
    end
  end

  defp card(base) do
    %{
      "version" => 1,
      "id" => "synthetic-model-proof",
      "revision" => "fixture-1",
      "currency" => "USD",
      "source" => "operator:synthetic-fixture",
      "published_on" => "2026-10-17",
      "rows" => [
        %{
          "id" => "local",
          "provider" => "ollama",
          "billing_mode" => "local",
          "basis" => "local_estimate",
          "model" => "fixture-reported",
          "endpoint_sha256" => Ipse.Extensions.Manifest.sha256(base),
          "from" => "2000-01-01",
          "until" => nil,
          "input_min" => 0,
          "input_max" => nil,
          "input_mode" => "flat",
          "rates" => %{"input" => "2", "output" => "10"}
        }
      ]
    }
  end

  defp start(config, cwd, dir, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config, cwd: cwd, state_dir: dir, id: id, subscriber: self(), owner: self()}
      )

    Process.put(:model_proof_sessions, [pid | Process.get(:model_proof_sessions)])
    pid
  end

  defp done(pid, expected) do
    receive do
      {:ipse, ^pid, {:done, ^expected}} -> :ok
      {:ipse, ^pid, {:done, _}} -> raise "Unexpected model proof outcome"
      {:ipse, ^pid, _} -> done(pid, expected)
    after
      5000 -> raise "Model proof did not finish"
    end
  end

  defp fixture do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    {"http://127.0.0.1:#{port}", listener}
  end

  defp serve_fixture(listener, owner) do
    Task.async(fn ->
      {:ok, socket} = :gen_tcp.accept(listener, 5000)
      {headers, body} = read_request(socket, "")
      send(owner, :model_fixture_dispatched)

      framing =
        String.duplicate(
          Jason.encode!(%{"done" => false, "message" => %{"content" => ""}}) <> "\n",
          2000
        )

      true = byte_size(framing) > 65_536

      response =
        framing <>
          Jason.encode!(%{
            "done" => true,
            "message" => %{"content" => "entities", "thinking" => "private-fixture"},
            "model" => "fixture-reported",
            "prompt_eval_count" => 7,
            "eval_count" => 3
          }) <> "\n"

      :ok =
        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(response)}\r\nconnection: close\r\n\r\n" <>
            response
        )

      :gen_tcp.close(socket)
      :gen_tcp.close(listener)
      {headers, Jason.decode!(body)}
    end)
  end

  defp read_request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
        {headers, read_body(socket, body, String.to_integer(size))}

      [_] ->
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
        read_request(socket, buffer <> bytes)
    end
  end

  defp read_body(_, body, size) when byte_size(body) >= size, do: body

  defp read_body(socket, body, size) do
    {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
    read_body(socket, body <> bytes, size)
  end
end
