defmodule Ipse.Test.OllamaMetadataFixture do
  @moduledoc false

  def scan(opts \\ []) do
    version = %{"version" => Keyword.get(opts, :version, "0.40.13")}

    row = %{
      "name" => "fixture",
      "model" => "fixture",
      "digest" => Keyword.get(opts, :digest, String.duplicate("a", 64)),
      "size" => 1024
    }

    show = %{
      "details" => %{"quantization_level" => "fixture-q8"},
      "model_info" => %{"general.architecture" => "fixture", "fixture.context_length" => 32768},
      "capabilities" => ["completion", "embedding"],
      "template" => Keyword.get(opts, :template, "fixture template")
    }

    loaded =
      case Keyword.get(opts, :context, 8192) do
        nil -> []
        context -> [Map.put(row, "context_length", context)]
      end

    {Enum.map(
       [
         version,
         %{"models" => [row]},
         show,
         %{"models" => loaded},
         %{"models" => [row]},
         version
       ],
       &Jason.encode!/1
     ),
     %{
       "version" => 1,
       "trust_boundary" => "cooperative_service_metadata",
       "manifest_sha256" => row["digest"],
       "runtime_version" => version["version"],
       "metadata_sha256" => Ipse.JSON.digest([version, row, show]),
       "minimum_context_tokens" => 8192
     }}
  end
end
