defmodule Ipse.Test.BuildPairedAnswer do
  @moduledoc false
  import ExUnit.Assertions
  alias Ipse.JSON

  # Inert fixture compilation, invoked only after separate build release.
  # The artifact BEAM is never added to the host VM code path.
  def build(source, sdk, output, license) do
    refute File.exists?(output)
    File.mkdir_p!(Path.join(output, "ebin"))
    for directory <- [output, Path.join(output, "ebin")], do: File.chmod!(directory, 0o700)
    ebins = Path.wildcard(Path.join(sdk, "_build/test/lib/*/ebin"))
    assert length(ebins) === 16
    args = ["--erl", "+S 1:1 +A 1", "--warnings-as-errors"] ++
      Enum.flat_map(ebins, &["-pa", &1]) ++ ["-o", Path.join(output, "ebin"), source]
    {log, status} = System.cmd("/usr/bin/elixirc", args, stderr_to_stdout: true)
    File.write!(output <> "-compile.log", log)
    assert status === 0 and log === ""
    File.cp!(license, Path.join(output, "LICENSE"))
    files = for relative <- ["LICENSE", "ebin/Elixir.Ipse.Test.PairedAnswerExtension.beam"] do
      File.chmod!(Path.join(output, relative), 0o600)
      bytes = File.read!(Path.join(output, relative))
      %{"path" => relative, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
    end
    export = %{"id" => "answer_context", "description" => "Synthetic protected answer protocol",
      "arguments_schema" => %{"type" => "object", "required" => ["request"], "additionalProperties" => false,
        "properties" => %{"request" => %{"type" => "object"}}}, "result_schema" => %{"type" => "object"}}
    metadata = %{"id" => "metadata", "description" => "Describe synthetic protocol scope without inference",
      "arguments_schema" => %{"type" => "object", "properties" => %{}, "required" => [], "additionalProperties" => false},
      "result_schema" => %{"type" => "object", "required" => ["scope", "inference"], "additionalProperties" => false,
        "properties" => %{"scope" => %{"type" => "string", "enum" => ["synthetic_protocol_only"]}, "inference" => %{"type" => "boolean", "enum" => [false]}}}}
    manifest = %{"format" => 1, "id" => "fixture/paired-answer", "version" => "0.1.0", "sdk" => 2,
      "protocol" => 1, "backend" => "elixir_worker", "entrypoint" => "Ipse.Test.PairedAnswerExtension",
      "license_file" => "LICENSE", "files" => files,
      "capabilities" => ~w(invoke.command invoke.service invoke.result.pages host.actions host.model),
      "exports" => %{"version" => 1, "tools" => [], "commands" => [metadata], "services" => [export]},
      "options_schema" => %{"type" => "object", "additionalProperties" => false, "properties" => %{}, "required" => []},
      "runtime" => %{"elixir" => ">= 1.18.0", "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]}}
    File.write!(Path.join(output, "extension.json"), Jason.encode!(manifest))
    File.chmod!(Path.join(output, "extension.json"), 0o600)
    assert :non_existing === :code.which(Ipse.Test.PairedAnswerExtension)
    %{manifest_sha256: JSON.sha256(File.read!(Path.join(output, "extension.json"))), files: files}
  end
end
