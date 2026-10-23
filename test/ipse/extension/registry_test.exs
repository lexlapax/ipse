defmodule Ipse.Extension.RegistryTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.{Config, Registry}

  defp catalog(instance_changes \\ %{}, trust_changes \\ %{}) do
    artifact = "builtin:prompt-annotation:1"

    instance =
      Map.merge(
        %{
          "instance" => "annotation",
          "artifact" => artifact,
          "enabled" => true,
          "options" => %{"text" => "note"},
          "order" => 1,
          "lifetime" => "persistent"
        },
        instance_changes
      )

    trust =
      Map.merge(
        %{
          "artifact" => instance["artifact"],
          "capabilities" => ["transform.prompt"],
          "allow_project" => false,
          "allow_children" => false
        },
        trust_changes
      )

    source = %{
      scope: "operator",
      path: "/fixture/operator.json",
      data: %{"extensions" => [instance], "extension_trust" => [trust]}
    }

    {:ok, catalog} = Config.resolve([source], [])
    catalog
  end

  test "disabled discovery is inert and does not require an installed artifact or home" do
    home =
      Path.join(
        System.tmp_dir!(),
        "ipse-missing-extension-home-#{System.unique_integer([:positive])}"
      )

    assert {:ok, []} =
             Registry.prepare(
               catalog(%{"enabled" => false, "artifact" => String.duplicate("a", 64)}),
               home
             )

    refute File.exists?(home)
    assert length(Registry.builtins()) == 8
  end

  test "exact built-in code, runtime and options are bound into immutable identities" do
    assert {:ok, [entry]} = Registry.prepare(catalog(), "/fixture/home")
    assert {:ok, [unchanged]} = Registry.prepare(catalog(), "/fixture/home")
    assert unchanged.identity == entry.identity
    assert Registry.valid_entries?(%{extensions: [entry]})
    assert entry.identity["artifact"] == "builtin:prompt-annotation:1"
    assert entry.identity["options_sha256"] == Ipse.JSON.digest([%{"text" => "note"}])
    assert byte_size(entry.identity["host_sha256"]) == 64
    assert entry.identity["scope"] == "operator"

    assert entry.identity["source_sha256"] ==
             Ipse.JSON.sha256("/fixture/operator.json")

    assert entry.identity["exports_sha256"] == Ipse.Extension.Catalog.digest(entry.exports)

    refute Registry.valid_entries?(%{
             extensions: [put_in(entry, [:identity, "scope"], "untrusted")]
           })

    refute Registry.valid_entries?(%{
             extensions: [put_in(entry, [:identity, "exports_sha256"], String.duplicate("a", 64))]
           })

    assert {:error, _} =
             Registry.prepare(catalog(%{"options" => %{"unsupported" => true}}), "/fixture/home")

    assert {:error, _} =
             Registry.prepare(catalog(%{"artifact" => "builtin:unknown:1"}), "/fixture/home")

    assert {:error, _} = Registry.prepare(catalog(%{}, %{"capabilities" => []}), "/fixture/home")

    refute Registry.valid_entries?(%{
             extensions: [Map.put(entry, :options, %{"text" => "changed"})]
           })
  end

  test "host identities cover application modules beyond the extension call path" do
    directory =
      Path.join(System.tmp_dir!(), "host-code-shadow-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    program = """
    {:ok, _} = Application.ensure_all_started(:ipse)
    directory = #{inspect(directory)}
    root = Application.app_dir(:ipse)
    {:ok, _} = Ipse.Extension.Registry.lookup(nil, "builtin:prompt-annotation:1")
    module = Ipse.Application
    shadow = Path.join(directory, Atom.to_string(module) <> ".beam")
    File.cp!(:code.which(module), shadow)
    true = :code.add_patha(String.to_charlist(directory))
    :code.purge(module)
    :code.delete(module)
    {:module, ^module} = :code.load_file(module)
    unless Application.app_dir(:ipse) == root, do: raise("application directory changed")
    {:ok, artifact} = Ipse.Extension.Registry.lookup(nil, "builtin:prompt-annotation:1")
    unless Ipse.Extension.Artifact.compatible?(artifact.manifest), do: raise("builtin incompatible")
    missing = Enum.reject(Application.spec(:ipse, :modules), fn m ->
      path = :code.which(m)
      is_list(path) and File.regular?(path)
    end)
    unless missing == [], do: raise("missing module files: " <> inspect(missing))
    prepared = Ipse.Extension.Registry.prepare(#{inspect(catalog(), limit: :infinity)}, "/fixture/home")
    unless match?({:ok, [_]}, prepared), do: raise("positive preparation failed")
    {:ok, [entry]} = prepared
    config = %{extensions: [entry]}
    unless Ipse.Extension.Registry.revalidate(config) == :ok, do: raise("positive revalidation failed")
    File.write!(shadow, File.read!(shadow) <> "changed")
    {:error, _} = Ipse.Extension.Registry.revalidate(config)
    IO.puts("host code change refused")
    """

    paths = :code.get_path() |> Enum.reverse() |> Enum.flat_map(&["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", program],
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 2:2 +A 2"}, {"ERL_CRASH_DUMP", "/dev/null"}]
      )

    assert status == 0, output
    assert output == "host code change refused\n"
  end

  test "trust and lease expiry are independently checked at admission" do
    for {instance, trust} <- [{%{"expires_at" => 100}, %{}}, {%{}, %{"expires_at" => 100}}] do
      assert {:ok, [entry]} =
               Registry.prepare(catalog(instance, trust), "/fixture/home", false, 99)

      assert entry.identity["expires_at"] == 100
      assert Registry.live?(entry.identity, 99)
      refute Registry.live?(entry.identity, 100)
      assert {:error, _} = Registry.prepare(catalog(instance, trust), "/fixture/home", false, 100)
      refute Registry.valid_entries?(%{extensions: [entry]})
    end
  end

  test "child admission and inherited/selected-profile routing preserve only the approved subset" do
    assert {:error, _} = Registry.prepare(catalog(), "/fixture/home", true)
    assert {:ok, [blocked]} = Registry.prepare(catalog(), "/fixture/home")

    assert {:ok, [allowed]} =
             Registry.prepare(catalog(%{}, %{"allow_children" => true}), "/fixture/home", true)

    assert Registry.child_entries(%{extensions: [blocked]}) == []
    assert Registry.child_entries(%{extensions: [allowed]}) == [allowed]
    assert Ipse.Tools.Delegation.child_config(%{extensions: [blocked]}, %{}).extensions == []

    parent = %{
      extensions: [allowed],
      profiles: %{"routine" => %{"provider" => "ollama", "model" => "fixture"}},
      roles: %{"routine" => "routine"}
    }

    assert {:ok, child} = Ipse.Config.Profiles.child_config(parent, %{}, %{})
    assert child.extensions == [allowed]
    assert child.mcp_servers == []
    assert child.subagents == false
  end
end
