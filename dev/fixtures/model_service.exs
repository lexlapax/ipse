defmodule Ipse.Development.Fixtures.ModelService do
  @moduledoc "Synthetic model distribution for complete measured evaluation controls."

  alias __MODULE__.Daemon
  @models ~w(fixture-text:latest fixture-embedding:latest)
  @launch_keys ~w(executable boot root code_paths files)
  @gpu_uuid "GPU-00000000-0000-0000-0000-000000000001"

  def configuration(root, launch, origin, options \\ []) do
    true =
      Keyword.keyword?(options) and
        Enum.all?(Keyword.keys(options), &(&1 in [:fault, :verification, :gpu, :context_tokens]))

    fault = Keyword.get(options, :fault)
    verification = Keyword.get(options, :verification, false)
    gpu = Keyword.get(options, :gpu, false)
    context_tokens = Keyword.get(options, :context_tokens)

    true =
      is_nil(context_tokens) or (is_integer(context_tokens) and context_tokens in 1..1_048_576)

    true = fault in [nil, :exit_on_answer]
    true = verification in [false, true]
    true = is_boolean(gpu)
    true = Path.type(root) == :absolute
    {:ok, ^root} = Ipse.Workspace.canonical_path(root)
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

    beam_name = Atom.to_string(Daemon) <> ".beam"
    beam_source = Daemon |> :code.which() |> to_string()
    %{type: :regular, size: size} = File.lstat!(beam_source)
    true = size <= 67_108_864
    true = Path.basename(beam_source) == beam_name
    beam_bytes = File.read!(beam_source)

    daemon_identity = %{
      "bytes" => byte_size(beam_bytes),
      "sha256" => Ipse.JSON.sha256(beam_bytes)
    }

    daemon = Path.join(source, beam_name)
    private_file(daemon, beam_bytes)

    {environment_files, environment_modules} =
      if verification do
        module = Module.concat(Ipse.Development.Evaluation.MeasuredExecution, "Environment")
        file = module |> :code.which() |> to_string()
        %{type: :regular, size: size} = File.lstat!(file)
        true = size <= 67_108_864
        bytes = File.read!(file)
        {:ok, {^module, md5}} = :beam_lib.md5(bytes)

        if :code.is_loaded(module) == false,
          do: {:module, ^module} = :code.load_binary(module, String.to_charlist(file), bytes)

        true = module.module_info(:md5) == md5 and module.bound?()
        name = Atom.to_string(module) <> ".beam"
        target = Path.join(source, name)
        private_file(target, bytes)
        identity = %{"bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        {[runtime_file(target, "lib/ollama/" <> name, false)], [{module, name, identity}]}
      else
        {[], []}
      end

    control_values = %{
      "version" => 1,
      "models" => models,
      "launch" => launch,
      "daemon" => daemon_identity,
      "verification_environment" => verification,
      "fault" => if(fault, do: Atom.to_string(fault), else: nil)
    }

    control_values =
      if gpu, do: Map.put(control_values, "cuda_visible_devices", @gpu_uuid), else: control_values

    control_values =
      if context_tokens,
        do: Map.put(control_values, "context_tokens", context_tokens),
        else: control_values

    control_bytes = JSON.encode!(control_values) <> "\n"

    true = byte_size(control_bytes) <= 1_048_576
    private_file(control, control_bytes)

    wrapper = Path.join(source, "ollama")

    private_file(
      wrapper,
      wrapper(launch, environment_modules ++ [{Daemon, beam_name, daemon_identity}], verification)
    )

    File.chmod!(wrapper, 0o500)

    config = %{
      "version" => 1,
      "origin" => origin,
      "models" => models,
      "manifests" => Map.new(manifests, fn {name, value} -> {name, value.path} end),
      "cache_source" => cache,
      "runtime" => %{
        "executable" => "bin/ollama",
        "files" =>
          [
            runtime_file(wrapper, "bin/ollama", true),
            runtime_file(daemon, "lib/ollama/" <> beam_name, false),
            runtime_file(control, "lib/ollama/control.json", false)
          ] ++ environment_files
      },
      "limits" => %{"ready_ms" => 15_000, "lifetime_ms" => 180_000, "metadata_ms" => 5_000},
      "cpu_policy" => "visibility_v1"
    }

    config =
      if gpu do
        config
        |> Map.delete("cpu_policy")
        |> Map.merge(%{
          "version" => 2,
          "device_selection" => %{"policy" => "nvidia_visible_mixed_v1", "uuid" => @gpu_uuid}
        })
      else
        config
      end

    if context_tokens do
      config
      |> Map.delete("cpu_policy")
      |> Map.merge(%{
        "version" => 3,
        "context_tokens" => context_tokens,
        "device_selection" =>
          if(gpu, do: config["device_selection"], else: %{"policy" => "cpu_only"})
      })
    else
      config
    end
  end

  defp wrapper(launch, modules, verification) do
    paths = launch["code_paths"]

    term =
      :io_lib.format(~c"~tp", [Enum.map(paths, &String.to_charlist/1)]) |> IO.iodata_to_binary()

    module = "'Elixir.Ipse.Development.Fixtures.ModelService.Daemon'"

    modules =
      Enum.map(modules, fn {module, name, identity} ->
        {module, String.to_charlist(name), identity["bytes"],
         Base.decode16!(identity["sha256"], case: :lower)}
      end)

    declarations = :io_lib.format(~c"~w", [modules]) |> IO.iodata_to_binary()

    expression =
      "[Directory,Control] = init:get_plain_arguments(), Paths = [Directory|#{term}], true = code:set_path(Paths), {ok,_} = application:ensure_all_started(elixir), true = (code:get_path() =:= Paths), Load = fun({Module,Name,Size,Hash}) -> File = filename:join(Directory,Name), {ok,Info} = file:read_link_info(File), true = (element(3,Info) =:= regular), true = (element(2,Info) =:= Size), {ok,Bytes} = file:read_file(File), true = (byte_size(Bytes) =:= Size), true = (crypto:hash(sha256,Bytes) =:= Hash), {module,Module} = code:load_binary(Module,File,Bytes), true = (code:which(Module) =:= File) end, lists:foreach(Load,#{declarations}), #{module}:main(unicode:characters_to_binary(Control),#{verification})."

    arguments =
      [
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

    {executable, arguments} =
      if verification do
        module = Module.concat(Ipse.Development.Evaluation.MeasuredExecution, "Environment")
        module.launch!(launch, arguments)
      else
        {launch["executable"], arguments}
      end

    "#!/bin/sh\nset -eu\ntest \"$#\" -eq 1 && test \"$1\" = serve || exit 64\nipse_fixture_bin=${0%/*}\nipse_fixture_runtime=${ipse_fixture_bin%/*}\nexec " <>
      Enum.map_join([executable | arguments], " ", &shell_quote/1) <>
      " \"$ipse_fixture_runtime/lib/ollama\" \"$ipse_fixture_runtime/lib/ollama/control.json\"\n"
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

defmodule Ipse.Development.Fixtures.ModelService.Daemon do
  @moduledoc "Bounded scripted Ollama wire fixture; it performs no model inference."
  @header_limit 16_384
  @body_limit 65_536
  @log_limit 16_777_216
  @request_limit 4096

  def main(control_path, verification) when is_boolean(verification) do
    control = decode_file!(control_path)
    cuda = Map.get(control, "cuda_visible_devices", "-1")
    true = cuda in ["-1", "GPU-00000000-0000-0000-0000-000000000001"]
    ^verification = control["verification_environment"]
    context_tokens = control["context_tokens"]

    if context_tokens,
      do: true = System.fetch_env!("OLLAMA_CONTEXT_LENGTH") == Integer.to_string(context_tokens)

    %{"version" => 1, "models" => models, "launch" => launch} = control
    true = Enum.sort(Map.keys(models)) == ~w(fixture-embedding:latest fixture-text:latest)
    beam = Path.join(Path.dirname(control_path), Atom.to_string(__MODULE__) <> ".beam")
    %{type: :regular, size: size} = File.lstat!(beam)
    true = size == control["daemon"]["bytes"]
    true = sha_file(beam) == control["daemon"]["sha256"]
    true = to_string(:code.which(__MODULE__)) == beam
    {:ok, {__MODULE__, md5}} = :beam_lib.md5(String.to_charlist(beam))
    true = __MODULE__.module_info(:md5) == md5
    expected_paths = [Path.dirname(beam) | launch["code_paths"]]
    true = :code.get_path() == Enum.map(expected_paths, &String.to_charlist/1)

    if verification do
      module = Module.concat(Ipse.Development.Evaluation.MeasuredExecution, "Environment")
      :ok = module.enter!()
    end

    for file <- launch["files"] do
      %{type: :regular, size: size} = File.lstat!(file["path"])
      true = size == file["bytes"]
      true = sha_file(file["path"]) == file["sha256"]
    end

    for {key, value} <- [
          {"CUDA_VISIBLE_DEVICES", cuda},
          {"ROCR_VISIBLE_DEVICES", "-1"},
          {"OLLAMA_VULKAN", "0"},
          {"GGML_VK_VISIBLE_DEVICES", "-1"},
          {"OLLAMA_NO_CLOUD", "1"}
        ],
        do: ^value = System.fetch_env!(key)

    uri = URI.parse(System.fetch_env!("OLLAMA_HOST"))
    true = System.fetch_env!("OLLAMA_HOST") == "http://127.0.0.1:#{uri.port}"
    home = System.fetch_env!("HOME")

    if verification do
      values = Map.new(~w(PATH LANG HOME IPSE_HOME TMPDIR), &{&1, System.fetch_env!(&1)})

      File.write!(Path.join(home, "fixture-environment.json"), JSON.encode!(values), [
        :exclusive,
        :sync
      ])

      File.chmod!(Path.join(home, "fixture-environment.json"), 0o600)
    end

    File.write!(Path.join(home, "fixture-daemon.pid"), System.pid(), [:exclusive])
    File.write!(Path.join(home, "fixture-requests.jsonl"), <<>>, [:exclusive, :sync])
    File.chmod!(Path.join(home, "fixture-requests.jsonl"), 0o600)

    {:ok, listener} =
      :gen_tcp.listen(uri.port, [
        :binary,
        active: false,
        ip: {127, 0, 0, 1},
        reuseaddr: true,
        backlog: 16,
        send_timeout: 1000,
        send_timeout_close: true
      ])

    true = control["fault"] in [nil, "exit_on_answer"]

    loop(listener, %{
      models: models,
      home: home,
      requests: 0,
      log_bytes: 0,
      counts: %{},
      gpu: cuda != "-1",
      context_tokens: context_tokens,
      resident: MapSet.new(),
      fault: control["fault"]
    })
  end

  def response("GET", "/api/tags", body, models) when map_size(body) == 0 do
    {"tags",
     %{
       "models" =>
         Enum.map(Enum.sort(models), fn {name, digest} ->
           %{"name" => name, "model" => name, "digest" => digest}
         end)
     }}
  end

  def response("POST", "/api/show", %{"model" => name}, models) do
    true = Map.has_key?(models, name)

    capabilities =
      if name == "fixture-text:latest", do: ["completion", "tools"], else: ["embedding"]

    {"show", %{"capabilities" => capabilities, "thinking" => %{"values" => [false]}}}
  end

  def response("GET", "/api/ps", body, _models) when map_size(body) == 0,
    do: {"resident", %{"models" => []}}

  def response(
        "POST",
        "/api/embed",
        %{"model" => "fixture-embedding:latest", "input" => inputs} = body,
        models
      ) do
    true = Map.has_key?(models, body["model"]) and is_list(inputs) and length(inputs) in 1..128

    vectors =
      Enum.map(inputs, fn input ->
        true = is_binary(input) and byte_size(input) <= 32_768
        if String.contains?(String.downcase(input), "release"), do: [1.0, 0.0], else: [0.0, 1.0]
      end)

    {"embedding", %{"model" => body["model"], "embeddings" => vectors, "prompt_eval_count" => 3}}
  end

  def response(
        "POST",
        "/api/chat",
        %{"model" => "fixture-text:latest", "messages" => messages} = body,
        models
      ) do
    true = Map.has_key?(models, body["model"]) and is_list(messages) and length(messages) in 1..32

    input =
      messages
      |> List.last()
      |> Map.fetch!("content")
      |> String.split("\n", parts: 2)
      |> List.last()
      |> JSON.decode!()
      |> Map.fetch!("input")
      |> JSON.decode!()

    {kind, answer} =
      cond do
        is_list(input["chunks"]) ->
          [chunk] = input["chunks"]

          {"extraction",
           %{
             "facts" => [
               %{
                 "subject" => "Release",
                 "predicate" => "requires",
                 "object" => "quiescence",
                 "polarity" => "positive",
                 "chunk" => chunk["id"],
                 "quote" => chunk["text"]
               }
             ]
           }}

        is_integer(input["required_count"]) ->
          true = input["required_count"] == length(input["candidates"])
          {"rerank", %{"order" => Enum.map(input["candidates"], & &1["id"])}}

        input["candidates"] == [] or input["query"] == "absent mineral" ->
          {"answer", %{"classification" => "abstain", "claims" => []}}

        true ->
          {"answer",
           %{
             "classification" => "answer",
             "claims" => [
               %{
                 "text" => "Release requires quiescence.",
                 "citations" => [hd(input["candidates"])["id"]]
               }
             ]
           }}
      end

    {kind,
     %{
       "model" => body["model"],
       "message" => %{"role" => "assistant", "content" => JSON.encode!(answer)},
       "done" => true,
       "done_reason" => "stop",
       "prompt_eval_count" => 8,
       "eval_count" => 8
     }}
  end

  defp loop(listener, state) do
    {:ok, socket} = :gen_tcp.accept(listener)

    next =
      try do
        {method, path, body} = request(socket, <<>>, System.monotonic_time(:millisecond) + 5_000)
        {kind, value} = response(method, path, body, state.models)

        value =
          if (state.gpu or state.context_tokens != nil) and path == "/api/ps" do
            rows =
              for name <- Enum.sort(state.resident) do
                row = %{
                  "name" => name,
                  "digest" => state.models[name],
                  "size" => 16,
                  "size_vram" => if(state.gpu, do: 8, else: 0)
                }

                if state.context_tokens,
                  do:
                    Map.put(
                      row,
                      "context_length",
                      if(name == "fixture-embedding:latest", do: 2048, else: state.context_tokens)
                    ),
                  else: row
              end

            %{"models" => rows}
          else
            value
          end

        bytes = JSON.encode!(value) <> "\n"
        true = byte_size(bytes) <= @body_limit
        {:ok, method, path, body, kind, bytes}
      rescue
        _ -> :refused
      end

    state =
      try do
        case next do
          {:ok, method, path, body, kind, bytes} ->
            recorded = record(state, method, path, body, kind)

            recorded =
              if (state.gpu or state.context_tokens != nil) and
                   kind in ~w(embedding extraction rerank answer),
                 do: %{recorded | resident: MapSet.put(recorded.resident, body["model"])},
                 else: recorded

            if state.fault == "exit_on_answer" and kind == "answer", do: System.halt(86)

            _ =
              :gen_tcp.send(socket, [
                "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(bytes)}\r\nconnection: close\r\n\r\n",
                bytes
              ])

            recorded

          :refused ->
            _ =
              :gen_tcp.send(
                socket,
                "HTTP/1.1 400 Bad Request\r\ncontent-length: 0\r\nconnection: close\r\n\r\n"
              )

            state
        end
      after
        :gen_tcp.close(socket)
      end

    loop(listener, state)
  end

  defp request(socket, bytes, deadline) do
    true = byte_size(bytes) <= @header_limit + @body_limit

    case :binary.split(bytes, "\r\n\r\n") do
      [header, rest] ->
        true = byte_size(header) <= @header_limit
        [line | lines] = String.split(header, "\r\n")
        [method, path, "HTTP/1.1"] = String.split(line, " ")

        true =
          method in ["GET", "POST"] and
            path in ~w(/api/tags /api/show /api/ps /api/chat /api/embed)

        headers =
          Enum.map(lines, fn line ->
            [key, value] = String.split(line, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        false = Enum.any?(headers, &(elem(&1, 0) == "transfer-encoding"))
        lengths = for {"content-length", value} <- headers, do: value

        length =
          case lengths do
            [] when method == "GET" ->
              0

            [value] ->
              {length, ""} = Integer.parse(value)
              true = length in 0..@body_limit and Integer.to_string(length) == value
              length
          end

        if byte_size(rest) < length do
          request(socket, bytes <> receive_bytes(socket, deadline), deadline)
        else
          true = byte_size(rest) == length
          body = if length == 0, do: %{}, else: decode!(rest)
          true = is_map(body)
          {method, path, body}
        end

      [_] ->
        true = byte_size(bytes) <= @header_limit
        request(socket, bytes <> receive_bytes(socket, deadline), deadline)
    end
  end

  defp receive_bytes(socket, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    true = remaining > 0
    {:ok, bytes} = :gen_tcp.recv(socket, 0, remaining)
    true = byte_size(bytes) > 0
    bytes
  end

  defp record(state, method, path, body, kind) do
    true = state.requests < @request_limit

    bytes =
      JSON.encode!(%{
        "method" => method,
        "path" => path,
        "operation" => kind,
        "model" => body["model"],
        "request" => body
      }) <> "\n"

    true = state.log_bytes + byte_size(bytes) <= @log_limit
    File.write!(Path.join(state.home, "fixture-requests.jsonl"), bytes, [:append, :sync])
    counts = Map.update(state.counts, kind, 1, &(&1 + 1))

    next = %{
      state
      | requests: state.requests + 1,
        log_bytes: state.log_bytes + byte_size(bytes),
        counts: counts
    }

    summary =
      JSON.encode!(%{
        "synthetic" => true,
        "model_inference" => false,
        "requests" => next.requests,
        "log_bytes" => next.log_bytes,
        "operations" => counts
      }) <> "\n"

    temporary = Path.join(state.home, "fixture-requests-summary.tmp")
    File.write!(temporary, summary, [:sync])
    File.chmod!(temporary, 0o600)
    File.rename!(temporary, Path.join(state.home, "fixture-requests-summary.json"))
    next
  end

  defp decode_file!(path) do
    %{type: :regular, size: size} = File.lstat!(path)
    true = size <= 1_048_576
    File.read!(path) |> decode!()
  end

  defp decode!(bytes) do
    {:ok, value} = Ipse.JSON.decode_bounded(bytes, 1_048_576)
    value
  end

  defp sha_file(path) do
    File.stream!(path, 1_048_576, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end
