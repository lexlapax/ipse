defmodule FrozenModelSelection do
  @moduledoc false

  def configuration(models, root, origin) do
    %{
      "version" => 1,
      "origin" => origin,
      "models" => models,
      "manifests" =>
        Map.new(models, fn {name, _} ->
          {name, "manifests/registry.ollama.ai/library/" <> String.replace(name, ":", "/")}
        end),
      "cache_source" => Path.join(root, "unopened-cache"),
      "runtime" => %{
        "executable" => "bin/ollama",
        "files" => [
          %{
            "source" => Path.join(root, "unopened-runtime"),
            "path" => "bin/ollama",
            "bytes" => 1,
            "sha256" => String.duplicate("c", 64),
            "executable" => true
          }
        ]
      },
      "limits" => %{"ready_ms" => 1000, "lifetime_ms" => 60_000, "metadata_ms" => 1000},
      "cpu_policy" => "visibility_v1"
    }
  end
end
