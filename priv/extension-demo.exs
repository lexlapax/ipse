defmodule Ipse.ExtensionDemo do
  @moduledoc false
  defmodule Model do
    def complete(config, messages, _tools, emit) do
      send(config.test_pid, {:extension_fixture_context, messages})
      emit.({:text, "fixture answer"})

      {:ok,
       %{
         "role" => "assistant",
         "content" => "fixture answer",
         "provider_data" => %{"opaque" => "synthetic-private-native"}
       }, %{}}
    end
  end

  def run do
    Application.ensure_all_started(:ipse)

    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-extension-demo-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      )

    File.mkdir_p!(root)

    try do
      instances = [
        %{
          "instance" => "annotation",
          "artifact" => "builtin:prompt-annotation:1",
          "enabled" => true,
          "options" => %{"text" => "Fixture context"},
          "order" => 1,
          "lifetime" => "session"
        },
        %{
          "instance" => "formatter",
          "artifact" => "builtin:answer-format:1",
          "enabled" => true,
          "options" => %{"prefix" => "<answer>", "suffix" => "</answer>"},
          "order" => 2,
          "lifetime" => "session"
        }
      ]

      trust =
        Enum.map(Ipse.Extensions.Registry.builtins(), fn descriptor ->
          %{
            "artifact" => descriptor["artifact"],
            "capabilities" => descriptor["capabilities"],
            "allow_project" => false,
            "allow_children" => false
          }
        end)

      source = %{
        scope: "operator",
        path: "/synthetic/operator.json",
        data: %{"extensions" => instances, "extension_trust" => trust}
      }

      {:ok, catalog} = Ipse.Extensions.Config.resolve([source], [])
      {:ok, entries} = Ipse.Extensions.Registry.prepare(catalog, Path.join(root, "home"))

      config = %{
        provider: :ollama,
        model: "fixture",
        provider_module: Model,
        test_pid: self(),
        approval: :deny,
        home: Path.join(root, "home"),
        compact: false,
        context_bytes: 400_000,
        extensions: entries
      }

      opts = [
        config: config,
        cwd: root,
        state_dir: Path.join(root, "sessions"),
        subscriber: self()
      ]

      {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
      :ok = Ipse.Session.prompt(session, "original fixture task")
      await(session)

      receive do
        {:extension_fixture_context, [_system, user]} ->
          true = String.starts_with?(user["content"], "original fixture task")
          true = String.contains?(user["content"], "Fixture context")
      after
        1000 -> raise "Extension fixture context unavailable"
      end

      info = Ipse.Session.info(session)
      "<answer>fixture answer</answer>" = info.final
      {:ok, events} = Ipse.Journal.load(opts[:state_dir], info.id)
      {:ok, [_user, assistant]} = Ipse.Session.restore_context(events)
      "fixture answer" = assistant["content"]
      %{"opaque" => "synthetic-private-native"} = assistant["provider_data"]
      projections = Enum.filter(events, &(&1["type"] == "extension_transform_result"))
      2 = length(projections)
      false = String.contains?(Jason.encode!(projections), "synthetic-private-native")
      :ok = Ipse.Session.close(session)
      path = Path.join(opts[:state_dir], info.id <> ".jsonl")
      bytes = File.read!(path)

      {:ok, resumed} =
        DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts ++ [id: info.id]})

      :idle = Ipse.Session.info(resumed).phase
      "<answer>fixture answer</answer>" = Ipse.Session.info(resumed).final
      ^bytes = File.read!(path)
      :ok = Ipse.Session.close(resumed)

      IO.puts(
        "Extension prompt/presentation and unchanged idle resume fixture passed without inference."
      )

      :ok
    after
      File.rm_rf!(root)
    end
  end

  defp await(session) do
    receive do
      {:ipse, ^session, {:done, :ok}} -> :ok
      {:ipse, ^session, {:done, _}} -> raise "Extension fixture failed"
      {:ipse, ^session, _} -> await(session)
    after
      15_000 -> raise "Extension fixture timed out"
    end
  end
end
