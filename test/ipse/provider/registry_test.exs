Code.require_file("../../support/provider_registry_fixture.ex", __DIR__)

defmodule Ipse.Provider.RegistryTest do
  use ExUnit.Case, async: false
  @fixtures Path.expand("../../fixtures/provider_registry", __DIR__)
  @constants [
    {"chatgpt", :chatgpt, "gpt-6.1-sol", "ipse-auth", "subscription", nil},
    {"openai", :openai, "gpt-6.1-sol", "OPENAI_API_KEY", "api", 16..1_000_000},
    {"ollama", :ollama, "qwen3:8b", "none", "local", 1..1_000_000},
    {"anthropic", :anthropic, "claude-sonnet-4-5", "ANTHROPIC_API_KEY", "api", 1..1_000_000},
    {"demo", :demo, "scripted", "none", "none", nil}
  ]

  test "registry is closed, ordered and owns native capabilities and existing secret names" do
    alias Ipse.Provider.Registry
    assert Registry.ids() == ~w(chatgpt openai ollama anthropic demo)
    assert Registry.chat_ids() == ~w(chatgpt openai ollama anthropic)
    assert Registry.embedding_ids() == ~w(openai ollama)
    assert Registry.secret_env() == ~w(OPENAI_API_KEY ANTHROPIC_API_KEY IPSE_CHATGPT_ACCESS_TOKEN)
    assert Registry.fetch("unknown-provider-fixture") == :error
    assert Registry.fetch(nil) == :error
    assert Registry.fetch(123) == :error
    assert Registry.rate_card_ids() == ~w(openai chatgpt anthropic ollama)
    assert Registry.billing_modes() == ~w(api subscription local)
    assert Registry.cost_bases() == ~w(api_estimate api_equivalent local_estimate)
    assert Registry.fetch!(:chatgpt).replay_key == "openai"
    assert Registry.fetch!(:openai).replay_key == "openai"
    assert Registry.fetch!(:chatgpt).base_url_policy == :fixed

    for id <- Registry.ids() do
      spec = Registry.fetch!(id)
      assert Registry.fetch!(spec.atom) == spec
      assert Registry.supports?(id, :structured_output?) == (id == "ollama")
      assert Registry.supports?(id, :summary_schema?) == (id == "ollama")
      assert Registry.embedding?(id) == id in ~w(openai ollama)
    end
  end

  test "captured data retains its original recorded hashes" do
    provenance = @fixtures |> Path.join("provenance.json") |> File.read!() |> Jason.decode!()
    assert provenance["source_commit"] == "dd510a72e31e15402eeb473fcf29929243b8ca2c"

    for {file, expected} <- provenance["files_sha256"] do
      assert Ipse.JSON.sha256(File.read!(Path.join(@fixtures, file))) == expected
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-registry-equivalence-" <> Ipse.Usage.id())
    File.mkdir!(root)
    home = Path.join(root, "absent-home")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, home: home}
  end

  test "existing provider manifests, destination digests, usage and cost match dd510a7", c do
    golden = @fixtures |> Path.join("equivalence.json") |> File.read!() |> Jason.decode!()
    assert Ipse.Test.ProviderRegistryFixture.facts(c.root, c.home) == golden
  end

  test "existing defaults, credentials, billing, caps and reasoning allowlist are fixed", c do
    for {id, provider, model, credential, billing, range} <- @constants do
      spec = Ipse.Provider.Registry.fetch!(id)
      assert {spec.atom, spec.default_model, spec.billing_mode} == {provider, model, billing}
      assert spec.output_limit == (range || :refuse_cap)
      assert Ipse.Provider.Registry.credential_reference(spec.credential) == credential

      if provider != :demo do
        assert Ipse.Provider.destination(%{provider: provider, model: model}) ==
                 Ipse.Provider.destination(%{
                   provider: provider,
                   model: model,
                   base_url: spec.default_base_url
                 })
      end

      {:ok, resolved} =
        Ipse.Config.resolve(c.root, c.home, [provider: id, project_config: false], %{})

      assert resolved.settings["model"] == model
      assert Ipse.Usage.billing_mode(provider) == billing

      assert :ok =
               Ipse.Config.Profiles.validate_profile(%{
                 "provider" => id,
                 "model" => model,
                 "credential" => credential
               })

      assert {:error, _} =
               Ipse.Config.Profiles.validate_profile(%{
                 "provider" => id,
                 "model" => model,
                 "credential" => "invalid"
               })

      assert :ok = Ipse.Provider.validate_output_limit(%{provider: provider})

      for n <- [0, 1, 15, 16, 1_000_000, 1_000_001] do
        result = Ipse.Provider.validate_output_limit(%{provider: provider, max_output_tokens: n})
        assert result == :ok == (not is_nil(range) and n in range)
      end

      for effort <- ~w(none low medium high xhigh max) do
        allowed =
          (provider in [:chatgpt, :openai] and effort != "none") or
            (provider == :ollama and effort == "none")

        assert Ipse.Config.Profiles.reasoning(id, model, effort) == :ok == allowed

        assert Ipse.Config.Profiles.reasoning(id, "different-model", effort) == :ok ==
                 (provider == :ollama and effort == "none")
      end
    end
  end

  test "pre-refactor saved sessions restore usage and resume idle without changing bytes", c do
    for {id, provider, model, _, _, _} <- @constants, legacy? <- [false, true] do
      suffix = if legacy?, do: "-legacy", else: ""

      events =
        @fixtures
        |> Path.join(id <> suffix <> ".jsonl")
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      events =
        Enum.map(events, fn
          %{"type" => "session"} = event ->
            put_in(event, ["metadata", "cwd"], c.root)

          %{"type" => "workspace_context_snapshot"} = event ->
            event
            |> put_in(["snapshot", "cwd"], c.root)
            |> put_in(["snapshot", "boundary"], c.root)

          event ->
            event
        end)

      session =
        if legacy?,
          do: String.duplicate("b", 32),
          else: Enum.find(events, &(&1["type"] == "request_admitted"))["session_id"]

      state = Path.join(c.root, id <> suffix)
      File.mkdir!(state)
      File.chmod!(state, 0o700)
      path = Path.join(state, session <> ".jsonl")
      bytes = Enum.map_join(events, "\n", &Jason.encode!/1) <> "\n"
      File.write!(path, bytes)
      File.chmod!(path, 0o600)
      {:ok, usage} = Ipse.Usage.restore(events, session)

      unless legacy? do
        expected = @fixtures |> Path.join(id <> "-usage.json") |> File.read!() |> Jason.decode!()

        assert Jason.decode!(Jason.encode!(Ipse.Test.ProviderRegistryFixture.portable(usage))) ==
                 expected
      end

      config = %{
        provider: provider,
        model: model,
        approval: :deny,
        home: c.home,
        sandbox: :off,
        extensions: []
      }

      assert {:ok, pid} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Ipse.Session,
                  config: config, cwd: c.root, state_dir: state, id: session, subscriber: self()}
               )

      assert %{phase: :idle} = Ipse.Session.info(pid)
      assert :ok = Ipse.Session.close(pid)
      assert File.read!(path) == bytes
      refute_received {:ipse, ^pid, {:text, _}}
    end
  end
end
