defmodule MeasuredModelFixture do
  @moduledoc "Synthetic model distribution for complete measured evaluation controls."

  @models ~w(fixture-text:latest fixture-embedding:latest)
  @launch_keys ~w(executable boot root code_paths files)

  def configuration(root, launch, origin, fault \\ nil) do
    true = fault in [nil, :exit_on_answer]
    true = Path.type(root) == :absolute
    {:ok, ^root} = Ipse.WorkspaceContext.canonical_path(root)
    private_root(root)
    validate_launch!(launch)
    source = Path.join(root, "measured-model-source")
    File.mkdir!(source)
    File.chmod!(source, 0o700)
    cache = Path.join(source, "models")
    File.mkdir!(cache)
    File.mkdir!(Path.join(cache, "blobs"))

    manifests =
      Map.new(@models, fn name ->
        descriptor = fn bytes, media ->
          digest = Ipse.JSON.sha256(bytes)
          path = Path.join(cache, "blobs/sha256-" <> digest)
          unless File.exists?(path), do: private_file(path, bytes)
          %{"mediaType" => media, "digest" => "sha256:" <> digest, "size" => byte_size(bytes)}
        end

        config =
          JSON.encode!(%{
            "architecture" => "fixture",
            "os" => "fixture",
            "rootfs" => %{"type" => "layers", "diff_ids" => []},
            "model_format" => "synthetic",
            "model_family" => "fixture"
          })

        manifest =
          JSON.encode!(%{
            "schemaVersion" => 2,
            "mediaType" => "application/vnd.docker.distribution.manifest.v2+json",
            "config" => descriptor.(config, "application/vnd.docker.container.image.v1+json"),
            "layers" => [
              descriptor.(
                "synthetic cache bytes for " <> name <> "\n",
                "application/vnd.ollama.image.model"
              )
            ]
          })

        relative = "manifests/registry.ollama.ai/library/" <> String.replace(name, ":", "/")
        File.mkdir_p!(Path.dirname(Path.join(cache, relative)))
        private_file(Path.join(cache, relative), manifest)
        {name, %{path: relative, digest: Ipse.JSON.sha256(manifest)}}
      end)

    models = Map.new(manifests, fn {name, value} -> {name, value.digest} end)
    control = Path.join(source, "control.json")

    control_bytes =
      JSON.encode!(%{
        "version" => 1,
        "models" => models,
        "launch" => launch,
        "fault" => if(fault, do: Atom.to_string(fault), else: nil)
      }) <> "\n"

    true = byte_size(control_bytes) <= 1_048_576
    private_file(control, control_bytes)

    daemon = Path.join(source, "measured_model_daemon.exs")
    private_file(daemon, File.read!(Path.join(__DIR__, "measured_model_daemon.exs")))
    wrapper = Path.join(source, "ollama")
    private_file(wrapper, wrapper(launch))
    File.chmod!(wrapper, 0o500)

    %{
      "version" => 1,
      "origin" => origin,
      "models" => models,
      "manifests" => Map.new(manifests, fn {name, value} -> {name, value.path} end),
      "cache_source" => cache,
      "runtime" => %{
        "executable" => "bin/ollama",
        "files" => [
          runtime_file(wrapper, "bin/ollama", true),
          runtime_file(daemon, "lib/ollama/measured_model_daemon.exs", false),
          runtime_file(control, "lib/ollama/control.json", false)
        ]
      },
      "limits" => %{"ready_ms" => 15_000, "lifetime_ms" => 180_000, "metadata_ms" => 5_000},
      "cpu_policy" => "visibility_v1"
    }
  end

  defp wrapper(launch) do
    paths = launch["code_paths"]

    term =
      :io_lib.format(~c"~tp", [Enum.map(paths, &String.to_charlist/1)]) |> IO.iodata_to_binary()

    expression =
      "Paths = #{term}, true = code:set_path(Paths), {ok,_} = application:ensure_all_started(elixir), [Script,Control] = init:get_plain_arguments(), 'Elixir.Code':require_file(unicode:characters_to_binary(Script)), 'Elixir.MeasuredModelDaemon':main(unicode:characters_to_binary(Control))."

    arguments =
      [
        launch["executable"],
        "+S",
        "1:1",
        "+A",
        "1",
        "-noshell",
        "-mode",
        "interactive",
        "-boot",
        launch["boot"],
        "-boot_var",
        "RELEASE_LIB",
        Path.join(launch["root"], "lib"),
        "-pa"
      ] ++ paths ++ ["-eval", expression, "-extra"]

    "#!/bin/sh\nset -eu\ntest \"$#\" -eq 1 && test \"$1\" = serve || exit 64\nipse_fixture_bin=${0%/*}\nipse_fixture_runtime=${ipse_fixture_bin%/*}\nexec " <>
      Enum.map_join(arguments, " ", &shell_quote/1) <>
      " \"$ipse_fixture_runtime/lib/ollama/measured_model_daemon.exs\" \"$ipse_fixture_runtime/lib/ollama/control.json\"\n"
  end

  defp validate_launch!(launch) do
    true = is_map(launch) and Enum.sort(Map.keys(launch)) == Enum.sort(@launch_keys)
    for key <- ~w(executable boot root), do: true = absolute?(launch[key])
    true = is_list(launch["code_paths"]) and length(launch["code_paths"]) in 1..256
    true = Enum.all?(launch["code_paths"], &absolute?/1)
    true = Enum.uniq(launch["code_paths"]) == launch["code_paths"]
    true = is_list(launch["files"]) and length(launch["files"]) in 1..64

    paths =
      Enum.map(launch["files"], fn file ->
        true = Enum.sort(Map.keys(file)) == ~w(bytes path sha256)
        true = absolute?(file["path"])
        %{type: :regular, size: size} = File.lstat!(file["path"])
        true = size == file["bytes"] and size <= 67_108_864
        true = Ipse.JSON.sha256(File.read!(file["path"])) == file["sha256"]
        file["path"]
      end)

    true = launch["executable"] in paths and (launch["boot"] <> ".boot") in paths
  end

  defp runtime_file(path, target, executable),
    do: %{
      "source" => path,
      "path" => target,
      "bytes" => File.stat!(path).size,
      "sha256" => Ipse.JSON.sha256(File.read!(path)),
      "executable" => executable
    }

  defp private_root(root) do
    case File.lstat(root) do
      {:error, :enoent} -> File.mkdir!(root)
      {:ok, %{type: :directory, mode: mode}} -> true = Bitwise.band(mode, 0o077) == 0
    end

    File.chmod!(root, 0o700)
  end

  defp private_file(path, bytes) do
    File.write!(path, bytes, [:exclusive, :sync])
    File.chmod!(path, 0o600)
  end

  defp absolute?(value),
    do:
      is_binary(value) and Path.type(value) == :absolute and Path.expand(value) == value and
        not String.contains?(value, <<0>>)

  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
end
