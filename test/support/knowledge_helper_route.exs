defmodule Ipse.Test.KnowledgeHelperRoute do
  @moduledoc false
  import ExUnit.Assertions

  # A real inert artifact for route review. Its BEAM never enters the host path.
  def install(root, home) do
    artifact = Path.join(root, "helper-artifact")
    ebin = Path.join(artifact, "ebin")
    File.mkdir_p!(ebin)
    for dir <- [artifact, ebin], do: File.chmod!(dir, 0o700)
    caps = ~w(invoke.command invoke.result.pages host.actions host.model)

    item = %{
      "id" => "metadata",
      "description" => "Inert helper route fixture",
      "arguments_schema" => %{
        "type" => "object",
        "properties" => %{},
        "additionalProperties" => false
      },
      "result_schema" => %{"type" => "object"}
    }

    exports = Ipse.Extension.Catalog.empty() |> Map.put("commands", [item])
    source = Path.join(root, "helper-fixture.ex")

    File.write!(source, """
    defmodule Ipse.Test.KnowledgeHelperRouteArtifact do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 2, "capabilities" => #{inspect(caps)}, "exports" => #{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle("invoke.command", %{"id" => "metadata"}, state),
        do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{"inert" => true}}, state}
    end
    """)

    paths = :code.get_path() |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == "."))

    args =
      ["--erl", "+S 1:1 +A 1", "--warnings-as-errors"] ++
        Enum.flat_map(paths, &["-pa", &1]) ++ ["-o", ebin, source]

    assert {"", 0} = System.cmd(System.find_executable("elixirc"), args, stderr_to_stdout: true)
    File.cp!(Path.expand("../../LICENSE", __DIR__), Path.join(artifact, "LICENSE"))

    files =
      for relative <- ["LICENSE", "ebin/Elixir.Ipse.Test.KnowledgeHelperRouteArtifact.beam"] do
        file = Path.join(artifact, relative)
        File.chmod!(file, 0o600)

        %{
          "path" => relative,
          "bytes" => File.stat!(file).size,
          "sha256" => Ipse.JSON.sha256(File.read!(file))
        }
      end

    manifest = %{
      "format" => 1,
      "id" => "fixture/knowledge-helper",
      "version" => "0.1.0",
      "sdk" => 2,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => "Ipse.Test.KnowledgeHelperRouteArtifact",
      "license_file" => "LICENSE",
      "files" => files,
      "capabilities" => caps,
      "exports" => exports,
      "options_schema" => %{
        "type" => "object",
        "properties" => %{},
        "additionalProperties" => false
      },
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      }
    }

    File.write!(Path.join(artifact, "extension.json"), Jason.encode!(manifest))
    File.chmod!(Path.join(artifact, "extension.json"), 0o600)

    assert {:ok, installed} =
             Ipse.Extension.Artifact.import(artifact, Path.join(home, "extensions/artifacts"))

    assert :non_existing = :code.which(Ipse.Test.KnowledgeHelperRouteArtifact)

    %{
      "extensions" => [
        %{
          "instance" => "helper",
          "artifact" => installed.digest,
          "enabled" => true,
          "options" => %{},
          "order" => 10,
          "lifetime" => "session"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => installed.digest,
          "capabilities" => caps,
          "allow_project" => false,
          "allow_children" => false
        }
      ]
    }
  end

  def profiles do
    %{
      "profiles" => %{
        "extract" => %{
          "provider" => "ollama",
          "model" => "synthetic",
          "credential" => "none",
          "base_url" => "http://127.0.0.1:12345",
          "timeout_ms" => 3000
        }
      },
      "decision_profiles" => %{
        "advice" => %{
          "operation" => "decision",
          "provider" => "system_one_compatible",
          "model" => "synthetic",
          "credential" => "none",
          "service_id" => "fixture",
          "base_url" => "http://127.0.0.1:12345"
        }
      },
      "inference_services" => %{
        "fixture" => %{"version" => 1, "origins" => ["http://127.0.0.1:12345"]}
      }
    }
  end
end
