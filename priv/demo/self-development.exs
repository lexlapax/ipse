defmodule Ipse.SelfDevelopmentDemo do
  @moduledoc false

  defmodule Model do
    def complete(_config, messages, _tools, _emit) do
      step = Enum.count(messages, &(&1["role"] == "tool"))

      calls = [
        {"load_skill", %{"name" => "self-development"}},
        {"load_skill_resource",
         %{"name" => "self-development", "path" => "references/evidence-checklist.md"}},
        {"load_skill_resource",
         %{"name" => "self-development", "path" => "references/review-request.md"}}
      ]

      if step < length(calls) do
        {name, args} = Enum.at(calls, step)

        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "self-development-#{step}",
               "type" => "function",
               "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
             }
           ]
         }, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" =>
             "Scripted skill/resource verification complete; no model inference or effects."
         }, %{}}
      end
    end
  end

  def run do
    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-self-development-demo-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)

    try do
      {:ok, pid} =
        DynamicSupervisor.start_child(
          Ipse.Sessions,
          {Ipse.Session,
           config: %{
             provider: :demo,
             model: "scripted",
             provider_module: Model,
             home: Path.join(root, "home"),
             approval: :deny
           },
           cwd: root,
           state_dir: Path.join(root, "sessions"),
           subscriber: self()}
        )

      try do
        id = Ipse.Session.info(pid).id
        :ok = Ipse.Session.prompt(pid, "Verify inert self-development skill resources only.")
        await(pid)
        {:ok, events} = Ipse.Journal.load(Path.join(root, "sessions"), id)

        results =
          for %{"type" => "message", "message" => %{"role" => "tool"} = message} <- events,
              do: message

        3 = length(results)

        true =
          Enum.all?(results, &(get_in(&1, ["ipse_tool_outcome", "status"]) == "result_recorded"))

        true = Enum.all?(results, &String.contains?(&1["content"], "SHA-256:"))

        true =
          Enum.all?(
            events,
            &(&1["type"] != "tool_started" or &1["name"] in ["load_skill", "load_skill_resource"])
          )

        IO.puts("Self-development skill fixture passed without inference or effects.")
      after
        Ipse.Session.close(pid)
      end
    after
      File.rm_rf!(root)
    end
  end

  defp await(pid) do
    receive do
      {:ipse, ^pid, {:done, :ok}} -> :ok
      {:ipse, ^pid, {:done, status}} -> raise "Skill fixture failed: #{status}"
      {:ipse, ^pid, _} -> await(pid)
    after
      5000 -> raise "Skill fixture timed out"
    end
  end
end
