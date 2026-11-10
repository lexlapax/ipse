defmodule Ipse.Extension.ValidatedMemoTest do
  # Global call counters observe every process, so this module is synchronous.
  use ExUnit.Case, async: false
  alias Ipse.Extension.Collection, as: C
  alias Ipse.Extension.Collection.Blocks
  alias Ipse.Extension.{Consent, SemanticConsent, ValidatedMemo}
  alias Ipse.JSON

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-validated-memo-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    %{root: Path.join(parent, "collections"), project: JSON.sha256("memo project")}
  end

  defp counted(mfa, fun) do
    :erlang.trace_pattern(mfa, true, [:call_count])

    try do
      fun.()
      {:call_count, count} = :erlang.trace_info(mfa, :call_count)
      count
    after
      :erlang.trace_pattern(mfa, false, [:call_count])
    end
  end

  defp run(c, request), do: C.execute(c.root, c.project, request, Ipse.Usage.id())

  defp commit(generation, changes),
    do: %{
      "op" => "commit",
      "expected_generation" => generation,
      "changes" => changes,
      "advance_floor" => false
    }

  defp change(key, revision, value),
    do: %{"key" => key, "expected_revision" => revision, "value" => value}

  @tag :native_storage
  test "unchanged protected reads reconstruct a manifest once but still check every block", c do
    changes = for i <- 1..40, do: change("note.#{i}", 0, %{"text" => "value #{i}"})
    assert {:ok, %{"generation" => 1}} = run(c, commit(0, changes))
    get = %{"op" => "get", "key" => "note.7"}

    # The first protected load validates in full; later loads of the same
    # manifest hash read and hash-check every block but reuse reconstruction.
    reconstructions =
      counted({Blocks, :reconstruct, 3}, fn ->
        for _ <- 1..6 do
          assert {:ok, %{"record" => %{"value" => %{"text" => "value 7"}}}} = run(c, get)
        end
      end)

    assert reconstructions <= 1

    block_reads =
      counted({Blocks, :read, 2}, fn ->
        for _ <- 1..3, do: assert({:ok, _} = run(c, get))
      end)

    assert block_reads == 3

    path = Path.join(c.root, c.project)
    pointer = Path.join(path, "root.json") |> File.read!() |> Jason.decode!()

    block =
      Path.wildcard(Path.join([path, "manifests", "*.json"]))
      |> Enum.reject(&(Path.basename(&1, ".json") == pointer["manifest"]))
      |> hd()

    original = File.read!(block)
    # Same size, different bytes: only a fresh read and hash check can notice.
    damaged = String.replace(original, "1", "2", global: false)
    assert byte_size(damaged) == byte_size(original) and damaged != original
    File.write!(block, damaged)
    refute match?({:ok, _}, run(c, get))
    File.write!(block, original)
    assert {:ok, _} = run(c, get)

    # A new manifest hash is a different key and is validated in full.
    assert {:ok, %{"generation" => 2}} = run(c, commit(1, [change("note.41", 0, %{})]))

    assert counted({Blocks, :reconstruct, 3}, fn ->
             assert {:ok, %{"record" => %{"revision" => 2}}} =
                      run(c, %{"op" => "get", "key" => "note.41"})
           end) == 1
  end

  test "consent control decoding is reused only for byte-identical input" do
    project = JSON.sha256("memo consent")

    state = %{
      "version" => 2,
      "project" => project,
      "epoch" => 1,
      "sequence" => 0,
      "policy" => nil,
      "operations" => %{},
      "compacted" => %{}
    }

    assert {:ok, bytes} = Consent.encode_control(state, project)
    assert {:ok, decoded} = Consent.decode_control(bytes, project)
    assert {:ok, ^decoded} = ValidatedMemo.fetch({Consent, project, :crypto.hash(:sha256, bytes)})
    assert {:ok, ^decoded} = Consent.decode_control(bytes, project)
    assert {:error, :consent_unavailable} = Consent.decode_control(bytes, JSON.sha256("other"))
    invalid = String.replace(bytes, "\"epoch\":1", "\"epoch\":\"1\"")
    assert invalid != bytes
    assert {:error, :consent_unavailable} = Consent.decode_control(invalid, project)
    assert :error = ValidatedMemo.fetch({Consent, project, :crypto.hash(:sha256, invalid)})
  end

  test "semantic policy validation remembers only exact accepted terms" do
    # Preparation itself validates; measure from a process with no prior use.
    policy = Task.async(&valid_policy/0) |> Task.await()
    validations = fn fun -> counted({Consent, :valid_policy?, 1}, fun) end

    assert validations.(fn -> assert SemanticConsent.policy?(policy) end) == 1
    assert validations.(fn -> for _ <- 1..5, do: assert(SemanticConsent.policy?(policy)) end) == 0

    changed = %{policy | "expires_at_ms" => policy["expires_at_ms"] + 1}
    assert validations.(fn -> assert SemanticConsent.policy?(changed) end) == 1

    refused = %{policy | "operations" => []}

    assert validations.(fn ->
             for _ <- 1..3, do: refute(SemanticConsent.policy?(refused))
           end) == 3

    other = Task.async(fn -> validations.(fn -> SemanticConsent.policy?(policy) end) end)
    assert Task.await(other) == 1
  end

  defp valid_policy do
    binding = %{
      "version" => 1,
      "project_id" => JSON.sha256("project"),
      "worktree_id" => JSON.sha256("tree"),
      "scope" => "repository",
      "root" => "/fixture/worktree",
      "primary_root" => "/fixture/primary",
      "common_directory" => "/fixture/primary/.git",
      "binding_sha256" => JSON.sha256("binding")
    }

    identity = %{
      "instance" => "notes",
      "artifact" => JSON.sha256("artifact"),
      "artifact_sha256" => JSON.sha256("artifact"),
      "options_sha256" => JSON.sha256("options"),
      "exports_sha256" => JSON.sha256("exports"),
      "requires_sha256" => JSON.sha256("requires"),
      "subscriptions_sha256" => JSON.sha256("subscriptions"),
      "services" => [],
      "scope" => "operator",
      "source_sha256" => JSON.sha256("source"),
      "sdk" => 1,
      "protocol" => 1,
      "capabilities" => ~w(invoke.tool host.actions host.state.read),
      "order" => 1,
      "lifetime" => "session",
      "expires_at" => nil,
      "runtime" => %{
        "architecture" => "fixture",
        "elixir" => "1.18.5",
        "erts" => "15",
        "otp" => "27"
      },
      "host_sha256" => JSON.sha256("host"),
      "generation" => 1,
      "allow_children" => false
    }

    selection = %{
      "domain" => "knowledge",
      "namespace" => elem(SemanticConsent.namespace(binding["project_id"], "notes"), 1),
      "scope" => %{"kind" => "project", "worktree_id" => nil},
      "sources" => %{"categories" => ~w(typed_host_outcome), "exclusions" => ["private/"]},
      "storage" => %{"kind" => "local_collection", "collection" => "notes"},
      "retention" => %{"automatic" => 90, "manual" => 3650},
      "routes" => [
        %{
          "operation" => "main",
          "provider" => "ollama",
          "profile" => nil,
          "model" => "fixture",
          "endpoint" => "http://127.0.0.1:11434/api/chat",
          "service_id" => "local",
          "billing_mode" => "local",
          "processing_region" => nil,
          "storage_region" => nil,
          "cache_retention" => nil,
          "account_controls" => nil
        }
      ],
      "effects" => [
        %{
          "operation" => "notes.capture",
          "class" => "collection.publish",
          "outer_sha256" => JSON.sha256("outer"),
          "inner_op" => "collection.call"
        }
      ],
      "limits" => Map.merge(Consent.zero(), %{"operations" => 100, "input_bytes" => 1_000_000}),
      "period_ms" => 86_400_000,
      "expires_at_ms" => 1_100_000,
      "headless" => true
    }

    {:ok, policy} = SemanticConsent.prepare(binding, identity, selection)
    policy
  end
end
