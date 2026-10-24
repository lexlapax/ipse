defmodule Ipse.Development.Verification.Runtime do
  @moduledoc "Owned verification runtime, pre-launch compiler and isolated child environment."
  alias Ipse.Development.Verification.Scenarios

  @utilities ~w(dirname basename cut sed cat grep readlink sleep uname expr awk id tr head)
  @forbidden ~w(elixir elixirc erlc mix rustc cargo)
  @source_root Path.expand("../..", __DIR__)
  @erts_bootstrap ~S'ROOTDIR=$1; BINDIR=$2; EMU=beam; PROGNAME=erl; export ROOTDIR BINDIR EMU PROGNAME; shift 2; exec "$BINDIR/erlexec" "$@"'

  alias Ipse.Development.Verification.Package

  def verification_main(argv) do
    {scenario, options} = Scenarios.parse!(argv)

    report =
      case scenario do
        "package" ->
          Code.require_file("../release.exs", __DIR__)
          apply(Ipse.Development.Release, :verify_checksum!, [Keyword.fetch!(options, :archive)])
          Code.require_file("package.exs", __DIR__)

          run(scenario, options, fn runtime, selected ->
            apply(Package, :run, [runtime, selected, Keyword.fetch!(options, :archive)])
          end)

        _ ->
          run(scenario, options)
      end

    IO.puts(:json.encode(report))
  end

  def evaluation_main(argv) do
    alias Ipse.Development.Verification.Runtime
    alias Ipse.Development.Verification.Scenarios

    arguments =
      case argv do
        ["--" | rest] -> rest
        rest -> rest
      end

    {options, rest, invalid} = OptionParser.parse(arguments, strict: switches())
    selected = Enum.any?(~w(sdk archive repository)a, &Keyword.has_key?(options, &1))

    result =
      cond do
        rest != [] or invalid != [] or
            length(Keyword.keys(options)) != length(Enum.uniq(Keyword.keys(options))) ->
          {:error, %{"code" => "invalid_options"}}

        selected ->
          true = options[:phase] == "freeze-measured"
          true = Keyword.has_key?(options, :repository)
          true = Keyword.has_key?(options, :sdk) != Keyword.has_key?(options, :archive)
          output = Path.expand(Keyword.fetch!(options, :output))

          spec =
            Scenarios.evaluator()
            |> Map.put(:retained, true)
            |> Map.put(
              :native_environment,
              if(:os.type() == {:unix, :linux}, do: :manager, else: :base)
            )

          runtime_options =
            Keyword.take(options, ~w(sdk archive repository)a) ++
              [
                input: Path.expand(Keyword.fetch!(options, :experiment)),
                output: output <> ".runtime"
              ]

          child =
            options
            |> Keyword.drop(~w(sdk archive repository)a)
            |> evaluation_arguments()

          {:child,
           Runtime.with_runtime(spec, runtime_options, &Runtime.invoke_evaluation!(&1, child))}

        options[:freeze] != nil and options[:freeze_sha256] != nil ->
          case Runtime.reopen_evaluation!(options[:freeze], options[:freeze_sha256], arguments) do
            nil -> :source
            child -> {:child, child}
          end

        true ->
          :source
      end

    case result do
      :source ->
        emit_evaluation(source_evaluation!(options, arguments))

      {:child, {output, status}} ->
        IO.write(output)
        if status != 0, do: System.halt(status)

      {:error, reason} ->
        IO.puts(:json.encode(%{"status" => "failed", "reason" => reason}))
        System.halt(1)
    end
  rescue
    _ ->
      IO.puts(
        :json.encode(%{"status" => "failed", "reason" => %{"code" => "frozen_runtime_refused"}})
      )

      System.halt(1)
  catch
    {:evaluation_result, result} -> emit_evaluation(result)
  end

  defp emit_evaluation({output, status}) do
    IO.puts(output)
    if status != 0, do: System.halt(status)
  end

  defp source_evaluation!(options, arguments) do
    evaluate = fn ->
      Code.require_file("../evaluation/runner.exs", __DIR__)
      cli = Code.ensure_loaded!(Ipse.Development.Evaluation.Runner)
      {_, status} = result = cli.evaluate(arguments)
      if status != 0, do: throw({:evaluation_result, result})
      result
    end

    if source_research?(options) do
      spec = Scenarios.fixture!(:knowledge)
      existing = Enum.map(spec.modules, &:code.which/1)

      if Enum.any?(existing, &is_list/1) do
        true = Enum.all?(existing, &is_list/1)
        files = Enum.map(existing, &(to_string(&1) |> fixture_identity!()))

        directory_files =
          for directory <- Enum.uniq(Enum.map(files, &Path.dirname(&1["path"]))),
              name <- File.ls!(directory),
              String.ends_with?(name, ".beam"),
              do: fixture_identity!(Path.join(directory, name))

        activate_source_fixture!(files, directory_files)
        evaluate.()
      else
        runtime_options = [sdk: Application.app_dir(:ipse, "ebin"), input: options[:plan]]

        {spec, runtime_options} =
          if options[:phase] == "freeze" do
            false = File.exists?(options[:output])

            {Map.put(spec, :retained, true),
             runtime_options ++ [output: Path.expand(options[:output]) <> ".runtime"]}
          else
            {spec, runtime_options}
          end

        with_runtime(spec, runtime_options, fn runtime ->
          files = Enum.map(spec.modules, &(beam(runtime.harness, &1) |> fixture_identity!()))
          activate_source_fixture!(files)
          evaluate.()
        end)
      end
    else
      evaluate.()
    end
  end

  defp source_research?(options) do
    case attempt(fn ->
           phase = options[:phase]
           true = phase in ~w(freeze tune verify)

           required =
             if phase == "freeze",
               do: ~w(output phase plan)a,
               else: ~w(corpus output phase plan queries)a

           true = Enum.sort(Keyword.keys(options)) == required
           Code.require_file("../evaluation/contract.exs", __DIR__)
           contract = Code.ensure_loaded!(Ipse.Development.Evaluation.Contract)
           json = Code.ensure_loaded!(Ipse.JSON)
           {:ok, plan} = json.decode_bounded(bounded!(options[:plan], 1_048_576), 1_048_576)
           :ok = contract.validate(plan)
           true = plan["version"] == 1
           Enum.any?(plan["variants"], &(&1["prepare"] == "research"))
         end) do
      {:returned, required} -> required
      _ -> false
    end
  end

  defp fixture_identity!(file) do
    bytes = bounded!(file, 67_108_864)
    %{"path" => Path.expand(file), "bytes" => byte_size(bytes), "sha256" => hash(bytes)}
  end

  defp activate_source_fixture!(files, runtime_files \\ nil) do
    modules = Scenarios.fixture!(:knowledge).modules
    names = Enum.map(modules, &(Atom.to_string(&1) <> ".beam"))
    true = Enum.sort(Enum.map(files, &Path.basename(&1["path"]))) == Enum.sort(names)
    [directory] = files |> Enum.map(&Path.dirname(&1["path"])) |> Enum.uniq()
    verify_identities!(files)

    directory_files =
      Enum.filter(runtime_files || files, &(Path.dirname(&1["path"]) == directory))

    verify_code_paths!([directory], directory_files)

    for path <- :code.get_path(), name <- names do
      file = Path.expand(name, to_string(path))
      if File.regular?(file), do: true = file == Path.join(directory, name)
    end

    bindings =
      for module <- modules do
        [identity] =
          Enum.filter(files, &(Path.basename(&1["path"]) == Atom.to_string(module) <> ".beam"))

        bytes = bounded!(identity["path"], 67_108_864)
        true = byte_size(bytes) == identity["bytes"] and hash(bytes) == identity["sha256"]
        {:ok, {^module, md5}} = :beam_lib.md5(bytes)

        if :code.is_loaded(module) != false do
          true = to_string(:code.which(module)) == identity["path"]
          true = module.module_info(:md5) == md5
        end

        {module, identity["path"], bytes}
      end

    unless Enum.any?(:code.get_path(), &(Path.expand(to_string(&1)) == directory)),
      do: Code.prepend_path(directory)

    for {module, file, bytes} <- bindings, :code.is_loaded(module) == false do
      {:module, ^module} = :code.load_binary(module, String.to_charlist(file), bytes)
    end

    :ok
  end

  defp switches do
    for name <-
          ~w(phase plan corpus queries output freeze freeze_sha256 experiment experiment_sha256 resolution data_manifest predictions prediction_sha256 audit_sha256 labels reviews sdk archive repository)a,
        do: {name, [:string, :keep]}
  end

  defp evaluation_arguments(options) do
    paths =
      ~w(plan corpus queries output freeze experiment resolution data_manifest predictions labels reviews)a

    Enum.flat_map(options, fn {key, value} ->
      value = if key in paths, do: Path.expand(value), else: value
      ["--" <> String.replace(Atom.to_string(key), "_", "-"), value]
    end)
  end

  def load_fixture!(name) do
    spec = Scenarios.fixture!(name)

    if not Code.ensure_loaded?(spec.module) do
      root = Path.join(System.tmp_dir!(), "ipse-fixture-" <> id())
      File.mkdir!(root)

      try do
        File.chmod!(root, 0o700)
        harness = Path.join(root, "harness")
        File.mkdir!(harness)
        sdk_file = Ipse.Extension |> :code.which() |> to_string()
        %{type: :regular} = File.lstat!(sdk_file)
        true = Path.extname(sdk_file) == ".beam"
        paths = source_paths(Path.dirname(sdk_file))
        compile!(spec, paths, harness)
        Code.prepend_path(harness)
        System.at_exit(fn _ -> File.rm_rf!(root) end)
      rescue
        error ->
          File.rm_rf!(root)
          reraise error, __STACKTRACE__
      end
    end

    for module <- spec.modules do
      Code.ensure_loaded!(module)
      file = module |> :code.which() |> to_string()
      %{type: :regular} = File.lstat!(file)
      true = Path.extname(file) == ".beam"
    end

    :ok
  end

  def run(scenario, options, verification \\ nil) do
    spec = Scenarios.fetch!(scenario)

    if Map.get(spec, :linux_only, false) and :os.type() != {:unix, :linux},
      do: raise("This verification requires the optional Linux measurement backend")

    input = options |> Keyword.fetch!(:input) |> Path.expand()
    selection = Keyword.get(options, :selection, "default")
    Scenarios.selection!(scenario, selection)

    with_runtime(spec, options, fn runtime ->
      report =
        if verification do
          verification.(runtime, input)
        else
          context = %{
            repository: runtime.repository,
            output: if(options[:output], do: File.cd!(options[:output], &File.cwd!/0))
          }

          value =
            eval!(runtime, Scenarios.expression(spec, input, selection, runtime.mode, context))

          :ok = Scenarios.validate!(spec, value, selection)
          value
        end

      Map.merge(report, %{
        "verification" => %{
          "scenario" => scenario,
          "mode" => Atom.to_string(runtime.mode),
          "private_home" => true,
          "precompiled_harness" => true,
          "system_toolchain_on_runtime_path" => false,
          "inventories_unchanged" => true
        }
      })
    end)
  end

  def with_runtime(spec, options, callback) do
    input = options |> Keyword.fetch!(:input) |> Path.expand()
    inputs = if Map.get(spec, :artifact_input, false), do: artifact_inputs!(input), else: [input]
    frozen_input = Map.new(inputs, &{&1, inventory(&1)})
    {mode, origin} = origin!(options)
    frozen_origin = inventory(origin)
    repository = repository!(options)

    frozen_repository =
      if Keyword.has_key?(options, :repository), do: source_inventory!(repository)

    retained = Map.get(spec, :retained, false)
    root = runtime_root!(retained, options, [repository, origin | inputs])

    outcome =
      attempt(fn ->
        File.chmod!(root, 0o700)

        for name <- ~w(home tmp harness utilities runtime-bin) do
          directory = Path.join(root, name)
          File.mkdir!(directory)
          File.chmod!(directory, 0o700)
        end

        runtime = prepare!(mode, origin, root, spec, repository)
        frozen = inventories(runtime)
        runtime = Map.put(runtime, :frozen_inventories, frozen)

        verify = fn ->
          true = frozen == inventories(runtime)
          true = frozen_input == Map.new(inputs, &{&1, inventory(&1)})
          true = frozen_origin == inventory(origin)

          if frozen_repository,
            do: true = frozen_repository == source_inventory!(repository)

          :ok
        end

        :ok = verify.()
        outcome = attempt(fn -> callback.(runtime) end)
        checked = attempt(verify)

        if match?({:failed, _, _, _}, outcome) or match?({:failed, _, _, _}, checked) do
          File.write(
            Path.join(root, "verification-failure.json"),
            :json.encode(%{
              "version" => 1,
              "callback_failed" => match?({:failed, _, _, _}, outcome),
              "inventories_unchanged" => match?({:returned, _}, checked)
            }),
            [:exclusive, :sync]
          )
        end

        first_result!(outcome, checked)
      end)

    cleanup = if retained, do: {:returned, :ok}, else: attempt(fn -> File.rm_rf!(root) end)

    if match?({:failed, _, _, _}, cleanup),
      do:
        attempt(fn ->
          IO.puts(:stderr, "Verification runtime cleanup failed at " <> inspect(root))
        end)

    first_result!(outcome, cleanup)
  end

  def eval!(runtime, expression) do
    program =
      bootstrap(runtime) <>
        "\n{value, _} = Code.eval_string(#{inspect(expression, limit: :infinity, printable_limit: :infinity)})\nIO.puts(:json.encode(value))"

    case launch(runtime, program) do
      {output, 0} -> output |> String.split("\n", trim: true) |> List.last() |> :json.decode()
      {output, code} -> raise("Verification child exited #{code}: " <> output)
    end
  end

  def invoke_evaluation!(runtime, argv) do
    expression = "Ipse.Development.Evaluation.Runner.main(#{inspect(argv)})"
    program = bootstrap(runtime) <> "\nCode.eval_string(#{inspect(expression)})"
    launch(runtime, program, runtime.repository)
  end

  defp launch(runtime, program, cwd \\ nil) do
    unchanged =
      try do
        runtime.frozen_inventories == inventories(runtime) and
          Enum.all?(runtime.startup_files, fn {path, expected} -> expected == inventory(path) end)
      rescue
        _ -> false
      end

    if not unchanged, do: raise("Verification runtime changed before launch")

    case runtime.mode do
      :installed ->
        System.cmd(runtime.launcher, ["eval", program],
          cd: cwd || runtime.release,
          env: runtime.env,
          stderr_to_stdout: true
        )

      :source ->
        args =
          ["+S", "2:2", "+A", "1", "-noshell", "-boot", runtime.boot, "-pa"] ++
            runtime.code_paths ++ ["-eval", erlang_eval(program)]

        bindir = Path.dirname(runtime.erts_executable)
        args = ["-c", @erts_bootstrap, "ipse-erts", Path.expand("../..", bindir), bindir | args]

        System.cmd("/bin/sh", args,
          cd: cwd || runtime.root,
          env: runtime.env,
          stderr_to_stdout: true
        )
    end
  end

  @doc "Reopen a captured evaluator without compiling or loading its source."
  def reopen_evaluation!(path, expected, argv) do
    {options, [], []} = OptionParser.parse(argv, strict: switches())
    true = length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options)))
    argv = evaluation_arguments(options)
    true = is_binary(expected) and Regex.match?(~r/\A[0-9a-f]{64}\z/, expected)
    path = Path.expand(path)
    bytes = bounded!(path, 1_048_576)
    true = hash(bytes) == expected
    manifest = decode_manifest!(bytes)
    files = manifest["runtime"]["files"]
    true = is_list(files) and length(files) in 1..4096
    legacy_cli = :"Elixir.Ipse.Development.Evaluation.CLI"
    legacy_name = Atom.to_string(legacy_cli) <> ".beam"
    separate_cli = Enum.any?(files, &(Path.basename(&1["path"]) == legacy_name))
    modules = Scenarios.evaluator().modules ++ if(separate_cli, do: [legacy_cli], else: [])
    entrypoint = if separate_cli, do: legacy_cli, else: Ipse.Development.Evaluation.Runner
    names = Enum.map(modules, &(Atom.to_string(&1) <> ".beam"))
    captured = Enum.filter(files, &(Path.basename(&1["path"]) in names))

    fixture_names =
      Enum.map(Scenarios.fixture!(:knowledge).modules, &(Atom.to_string(&1) <> ".beam"))

    if Enum.any?(captured, &(Path.basename(&1["path"]) not in fixture_names)) do
      2 = manifest["version"]
      launch = manifest["runtime"]["launch"]
      true = is_map(launch)
      true = Enum.sort(Map.keys(launch)) == ~w(boot code_paths executable files root)
      paths = launch["code_paths"]
      true = is_list(paths) and length(paths) in 1..256
      true = Enum.uniq(paths) == paths
      for path <- paths, do: absolute!(path)
      root = absolute!(launch["root"])
      boot = absolute!(launch["boot"])
      executable = absolute!(launch["executable"])
      bindir = Path.dirname(executable)
      true = Path.expand("../..", bindir) == root
      true = Path.basename(executable) == "erl"
      launch_files = launch["files"]
      true = is_list(launch_files) and length(launch_files) in 1..4096
      verify_code_paths!(paths, files)
      verify_identities!(files)
      verify_identities!(launch_files)
      erlexec = Path.join(bindir, "erlexec")

      for file <- [erlexec, executable, boot <> ".boot"] do
        [_] = Enum.filter(launch_files, &(&1["path"] == file))
      end

      bindings =
        for module <- modules do
          name = Atom.to_string(module) <> ".beam"
          [identity] = Enum.filter(captured, &(Path.basename(&1["path"]) == name))
          true = Path.dirname(identity["path"]) in paths
          bytes = bounded!(identity["path"], 67_108_864)
          true = hash(bytes) == identity["sha256"]
          {:ok, {^module, md5}} = :beam_lib.md5(bytes)
          {module, identity["path"], md5, identity["sha256"]}
        end

      environment = Ipse.Development.Evaluation.MeasuredExecution.Environment
      {^environment, environment_file, _, _} = Enum.find(bindings, &(elem(&1, 0) == environment))
      harness = Path.dirname(environment_file)
      true = Path.basename(harness) == "harness"
      runtime = Path.dirname(harness)

      with_scratch!(path, runtime, fn scratch ->
        program = """
        manifest = File.read!(#{inspect(path)})
        true = Base.encode16(:crypto.hash(:sha256, manifest), case: :lower) == #{inspect(expected)}
        captured = :json.decode(manifest)
        paths = captured["runtime"]["launch"]["code_paths"]
        beams = paths |> Enum.flat_map(fn path ->
          for name <- File.ls!(path), String.ends_with?(name, ".beam"), do: Path.join(path, name)
        end) |> Enum.uniq() |> Enum.sort()
        true = beams == (captured["runtime"]["files"] |> Enum.map(& &1["path"]) |> Enum.filter(&(Path.extname(&1) == ".beam")) |> Enum.sort())
        verified = for {module, file, md5, sha256} <- #{inspect(bindings, limit: :infinity)}, into: %{} do
          %{type: :regular, size: size} = File.lstat!(file)
          true = size <= 67_108_864
          bytes = File.read!(file)
          true = byte_size(bytes) == size
          true = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == sha256
          {:ok, {^module, ^md5}} = :beam_lib.md5(bytes)
          true = to_string(:code.which(module)) == file
          false = :code.is_loaded(module)
          {module, {file, bytes}}
        end
        load = fn module ->
          {file, bytes} = Map.fetch!(verified, module)
          {:module, ^module} = :code.load_binary(module, String.to_charlist(file), bytes)
          module
        end
        environment = load.(#{inspect(environment)})
        :ok = apply(environment, #{inspect(if manager_cli?(argv), do: :enter_manager!, else: :enter!)}, [])
        for module <- #{inspect(modules, limit: :infinity)}, module != #{inspect(environment)}, do: load.(module)
        freeze = Enum.find(Map.keys(verified), &(&1 == Ipse.Development.Evaluation.Freeze))
        cli = Enum.find(Map.keys(verified), &(&1 == #{inspect(entrypoint)}))
        case apply(freeze, :verify, [#{inspect(path)}, #{inspect(expected)}]) do
          {:ok, _} -> apply(cli, :main, [#{inspect(argv)}])
          {:error, reason} ->
            IO.puts(JSON.encode!(%{"status" => "failed", "reason" => %{"code" => to_string(reason)}}))
            System.halt(1)
        end
        """

        encoded_paths =
          paths |> Enum.map(&String.to_charlist/1) |> :erlang.term_to_binary() |> Base.encode64()

        encoded = Base.encode64(program)

        evaluation =
          "P=binary_to_term(base64:decode(\"#{encoded_paths}\"),[safe]),true=code:set_path(P),{ok,_}=application:ensure_all_started(elixir),true=(code:get_path()=:=P),'Elixir.Code':eval_string(base64:decode(\"#{encoded}\")),halt()."

        arguments = [
          "+S",
          "2:2",
          "+A",
          "1",
          "-noshell",
          "-mode",
          "interactive",
          "-boot",
          boot,
          "-boot_var",
          "RELEASE_LIB",
          Path.join(root, "lib"),
          "-eval",
          evaluation
        ]

        true = Enum.sum(Enum.map([erlexec | arguments], &byte_size/1)) <= 65_536
        inherited = System.get_env()

        manager =
          if manager_cli?(argv),
            do: Map.take(inherited, ~w(DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR)),
            else: %{}

        env =
          Map.new(Map.keys(inherited), &{&1, nil})
          |> Map.merge(%{
            "ROOTDIR" => root,
            "BINDIR" => bindir,
            "EMU" => "beam",
            "PROGNAME" => "erl",
            "HOME" => Path.join(scratch, "home"),
            "IPSE_HOME" => Path.join(scratch, "home/.ipse"),
            "TMPDIR" => Path.join(scratch, "tmp"),
            "LANG" => "C.UTF-8",
            "PATH" => Path.join(runtime, "utilities") <> ":" <> Path.join(runtime, "runtime-bin"),
            "ERL_CRASH_DUMP" => "/dev/null"
          })
          |> Map.merge(manager)
          |> Map.to_list()

        System.cmd(erlexec, arguments,
          cd: manifest["source"]["root"],
          env: env,
          stderr_to_stdout: true
        )
      end)
    else
      if captured != [] do
        true = manifest["version"] in [1, 2]
        activate_source_fixture!(captured, files)
      end

      nil
    end
  end

  defp manager_cli?(argv) do
    {options, _, _} = OptionParser.parse(argv, strict: [phase: [:string, :keep]])
    options[:phase] == "measure"
  end

  defp artifact_inputs!(input) do
    artifacts = input |> bounded!(1_048_576) |> decode_manifest!()

    true =
      Enum.sort(Map.keys(artifacts)) == ~w(answer dense explicit lexical model research semantic)

    paths =
      for path <- Map.values(artifacts) do
        path = absolute!(path)
        true = File.dir?(path)
        path
      end

    Enum.uniq([input | paths])
  end

  defp decode_manifest!(bytes) do
    start = fn {depth, _} ->
      true = depth < 64
      {depth + 1, []}
    end

    object_start = fn {depth, _} ->
      true = depth < 64
      {depth + 1, %{}}
    end

    {value, {0, nil}, rest} =
      :json.decode(bytes, {0, nil}, %{
        array_start: start,
        array_push: fn value, {depth, values} -> {depth, [value | values]} end,
        array_finish: fn {_, values}, parent -> {Enum.reverse(values), parent} end,
        object_start: object_start,
        object_push: fn key, value, {depth, values} ->
          false = Map.has_key?(values, key)
          {depth, Map.put(values, key, value)}
        end,
        object_finish: fn {_, values}, parent -> {values, parent} end
      })

    true = String.trim(rest) == ""
    true = is_map(value)
    value
  end

  defp verify_identities!(files) do
    true = Enum.uniq_by(files, & &1["path"]) == files

    for identity <- files do
      true = is_map(identity) and Enum.sort(Map.keys(identity)) == ~w(bytes path sha256)
      path = absolute!(identity["path"])
      size = identity["bytes"]
      true = is_integer(size) and size in 0..67_108_864

      true =
        is_binary(identity["sha256"]) and Regex.match?(~r/\A[0-9a-f]{64}\z/, identity["sha256"])

      %{type: :regular, size: ^size} = File.lstat!(path)
      true = digest(path) == identity["sha256"]
    end
  end

  defp verify_code_paths!(paths, files) do
    actual =
      paths
      |> Enum.flat_map(fn path ->
        for name <- File.ls!(path), String.ends_with?(name, ".beam"), do: Path.join(path, name)
      end)
      |> Enum.uniq()
      |> Enum.sort()

    expected =
      files
      |> Enum.map(& &1["path"])
      |> Enum.filter(&(Path.extname(&1) == ".beam"))
      |> Enum.sort()

    true = actual == expected
  end

  defp bounded!(path, limit) do
    %{type: :regular, size: size} = File.lstat!(path)
    true = size <= limit
    {:ok, bytes} = File.open(path, [:read, :binary], &IO.binread(&1, limit + 1))
    true = is_binary(bytes) and byte_size(bytes) == size
    bytes
  end

  defp absolute!(path) do
    true = is_binary(path) and byte_size(path) in 1..4096 and Path.type(path) == :absolute
    true = Path.expand(path) == path
    path
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp with_scratch!(freeze, runtime, callback) do
    temporary = File.cd!(System.tmp_dir!(), &File.cwd!/0)
    frozen = File.cd!(Path.dirname(freeze), &File.cwd!/0)
    false = within?(temporary, frozen) or within?(temporary, runtime)
    scratch = Path.join(temporary, "ipse-evaluation-" <> id())
    File.mkdir!(scratch)

    outcome =
      attempt(fn ->
        File.chmod!(scratch, 0o700)

        for name <- ~w(home tmp) do
          directory = Path.join(scratch, name)
          File.mkdir!(directory)
          File.chmod!(directory, 0o700)
        end

        callback.(scratch)
      end)

    cleanup = attempt(fn -> File.rm_rf!(scratch) end)
    first_result!(outcome, cleanup)
  end

  def bootstrap(runtime) do
    modules = Enum.map(runtime.spec.modules, &{&1, beam(runtime.harness, &1)})

    """
    :ok = :io.setopts(:standard_io, encoding: :unicode)
    canonical = fn path -> {:ok, resolved} = Ipse.Workspace.canonical_path(path); resolved end
    erl = canonical.(#{inspect(runtime.erl)})
    startup_path = Path.dirname(erl) <> ":" <> Path.expand("../../bin", Path.dirname(erl)) <> ":" <> #{inspect(runtime.path)}
    ^startup_path = System.fetch_env!("PATH")
    System.put_env("PATH", #{inspect(runtime.path)})
    #{inspect(runtime.home)} = System.fetch_env!("HOME")
    #{inspect(runtime.home <> "/.ipse")} = System.fetch_env!("IPSE_HOME")
    #{inspect(runtime.tmp)} = System.fetch_env!("TMPDIR")
    #{inspect(runtime.path)} = System.fetch_env!("PATH")
    for name <- #{inspect(@forbidden)}, do: nil = System.find_executable(name)
    true = canonical.(System.find_executable("erl")) == canonical.(#{inspect(runtime.erl)})
    {:ok, helper} = Ipse.Runner.native_helper(#{inspect(runtime.tmp)})
    true = helper == canonical.(Application.app_dir(:ipse, "priv/ipse-runner"))
    for {name, expected} <- #{inspect(runtime.utilities)} do
      true = canonical.(System.find_executable(name)) == canonical.(expected)
    end
    Code.prepend_path(#{inspect(runtime.harness)})
    expected = #{inspect(runtime.harness_files)}
    true = Enum.sort(File.ls!(#{inspect(runtime.harness)})) == Enum.sort(Map.keys(expected))
    for {name, %{type: :regular, mode: mode, sha256: digest}} <- expected do
      file = Path.join(#{inspect(runtime.harness)}, name)
      %{type: :regular, mode: ^mode} = File.lstat!(file)
      actual = :crypto.hash(:sha256, File.read!(file)) |> Base.encode16(case: :lower)
      ^digest = actual
    end
    for {module, file} <- #{inspect(modules)} do
      %{type: :regular} = File.lstat!(file)
      if module == #{inspect(runtime.spec.module)}, do: Code.ensure_loaded!(module)
      true = to_string(:code.which(module)) == file
      {:ok, {^module, md5}} = :beam_lib.md5(String.to_charlist(file))
      if :code.is_loaded(module) != false, do: true = module.module_info(:md5) == md5
    end
    """
  end

  def inventory(path) do
    walk(Path.expand(path), MapSet.new())
  end

  defp walk(path, ancestors) do
    stat = File.lstat!(path)
    key = {stat.major_device, stat.minor_device, stat.inode}

    if MapSet.member?(ancestors, key),
      do: raise(ArgumentError, "Cyclic verification input: " <> path)

    ancestors = MapSet.put(ancestors, key)
    entry = identity(path, stat)

    case stat.type do
      :directory ->
        Enum.reduce(File.ls!(path), %{"." => entry}, fn name, files ->
          Enum.reduce(walk(Path.join(path, name), ancestors), files, fn {child, value}, files ->
            relative = if child == ".", do: name, else: Path.join(name, child)
            Map.put(files, relative, value)
          end)
        end)

      :symlink ->
        target =
          if Path.type(entry.target) == :absolute,
            do: entry.target,
            else: Path.join(Path.dirname(path), entry.target)

        %{"." => Map.put(entry, :resolved, walk(target, ancestors))}

      :regular ->
        %{"." => entry}
    end
  end

  def digest(path) do
    path
    |> File.stream!(1_048_576, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp origin!(options) do
    case {Keyword.fetch(options, :archive), Keyword.fetch(options, :sdk)} do
      {{:ok, archive}, :error} ->
        path = Path.expand(archive)
        %{type: :regular} = File.lstat!(path)
        {:installed, path}

      {:error, {:ok, sdk}} ->
        path = Path.expand(sdk)
        true = File.regular?(Path.join(path, "ipse.app"))
        {:source, path}
    end
  end

  defp prepare!(mode, origin, root, spec, repository) do
    {release, code_paths, erl, boot, launcher} = host!(mode, origin, root)
    harness = Path.join(root, "harness")

    names =
      @utilities ++
        Map.get(spec, :utilities, []) ++
        if(Map.get(spec, :native_environment), do: ["git"], else: []) ++
        if(Map.get(spec, :native_environment) == :manager,
          do: ["systemd-run", "systemctl"],
          else: []
        )

    utilities =
      Map.new(names, fn name ->
        target = System.find_executable(name) || raise("Missing declared utility: " <> name)
        File.ln_s!(target, Path.join([root, "utilities", name]))
        {name, target}
      end)

    File.ln_s!(erl, Path.join([root, "runtime-bin", "erl"]))
    home = Path.join(root, "home")
    tmp = Path.join(root, "tmp")
    path = Path.join(root, "utilities") <> ":" <> Path.join(root, "runtime-bin")

    policy =
      if Map.get(spec, :native_environment) do
        %{
          path: path,
          forbidden: @forbidden,
          executable: erl,
          startup_script: @erts_bootstrap,
          directories: [Path.join(root, "utilities"), Path.join(root, "runtime-bin")],
          links:
            Enum.map(utilities, fn {name, target} ->
              {Path.join([root, "utilities", name]), target}
            end) ++ [{Path.join([root, "runtime-bin", "erl"]), erl}]
        }
      end

    erts_executable = compile!(spec, code_paths, harness, policy, erl, repository)

    inherited = System.get_env()

    manager =
      if Map.get(spec, :native_environment) == :manager,
        do: Map.take(inherited, ~w(DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR)),
        else: %{}

    env =
      Map.new(Map.keys(inherited), &{&1, nil})
      |> Map.merge(%{
        "HOME" => home,
        "IPSE_HOME" => home <> "/.ipse",
        "TMPDIR" => tmp,
        "LANG" => "C.UTF-8",
        "PATH" => path
      })
      |> Map.merge(manager)
      |> Map.to_list()

    if mode == :installed, do: command!(Path.join(release, "ipse"), ["--help"], release, env)

    %{
      mode: mode,
      root: root,
      repository: repository,
      release: release,
      code_paths: code_paths,
      erl: erl,
      erts_executable: erts_executable,
      boot: boot,
      launcher: launcher,
      harness: harness,
      spec: spec,
      env: env,
      home: home,
      tmp: tmp,
      path: path,
      utilities: utilities,
      startup_files:
        Map.new(
          ["/bin/sh", Path.join(root, "utilities"), Path.join(root, "runtime-bin")],
          fn path ->
            {path, inventory(path)}
          end
        ),
      harness_files: inventory(harness) |> Map.delete(".")
    }
  end

  defp host!(:installed, archive, root) do
    release = Path.join(root, "release")
    File.mkdir!(release)
    tar = System.find_executable("tar") || raise("tar is required")
    command!(tar, ["-xzf", archive, "-C", release], root, [])
    [erts] = File.ls!(release) |> Enum.filter(&String.starts_with?(&1, "erts-"))
    erl = Path.join([release, erts, "bin", "erl"])
    %{type: :regular} = File.lstat!(erl)

    {release, ebins(Path.join(release, "lib")), erl, nil, Path.join(release, "bin/ipse")}
  end

  defp host!(:source, sdk, _root) do
    erl =
      Path.join([
        to_string(:code.root_dir()),
        "erts-" <> to_string(:erlang.system_info(:version)),
        "bin/erl"
      ])

    code_paths = source_paths(sdk)
    boot = Path.join([to_string(:code.root_dir()), "bin/no_dot_erlang"])
    true = File.regular?(boot <> ".boot")
    {nil, code_paths, erl, boot, nil}
  end

  defp source_paths(sdk) do
    paths = ebins(Path.expand("../..", sdk))
    true = sdk in paths
    otp = ebins(Path.join(to_string(:code.root_dir()), "lib"))
    elixir = Application.app_dir(:elixir) |> Path.dirname() |> ebins()

    Enum.uniq(paths ++ otp ++ elixir)
  end

  defp ebins(root) do
    root
    |> File.ls!()
    |> Enum.sort()
    |> Enum.map(&Path.join([root, &1, "ebin"]))
    |> Enum.filter(&File.dir?/1)
  end

  defp compile!(
         spec,
         code_paths,
         harness,
         policy \\ nil,
         executable \\ nil,
         repository \\ @source_root
       ) do
    sources = Enum.map(Map.get(spec, :sources, [spec.source]), &Path.expand(&1, repository))
    compiler = System.find_executable("elixir") || raise("Pre-launch Elixir compiler required")

    expression = """
    policy = #{inspect(policy, limit: :infinity)}
    policy = if policy do
      files = for {link, target} <- policy.links do
        %{type: :symlink, mode: link_mode} = File.lstat!(link)
        ^target = File.read_link!(link)
        {:ok, resolved} = Ipse.Workspace.canonical_path(target)
        %{type: :regular, mode: mode, size: size} = File.lstat!(resolved)
        true = size <= 67_108_864
        %{link: link, target: target, resolved: resolved, link_mode: link_mode,
          mode: mode, bytes: size, sha256: Ipse.JSON.sha256(File.read!(resolved))}
      end
      directories = for directory <- policy.directories do
        %{type: :directory, mode: mode} = File.lstat!(directory)
        %{path: directory, mode: mode, names: Enum.sort(File.ls!(directory))}
      end
      {:ok, erl} = Ipse.Workspace.canonical_path(policy.executable)
      {:ok, shell} = Ipse.Workspace.canonical_path("/bin/sh")
      %{type: :regular, mode: shell_mode, size: shell_size} = File.lstat!(shell)
      true = shell_size <= 67_108_864
      shell = %{path: shell, mode: shell_mode, bytes: shell_size, sha256: Ipse.JSON.sha256(File.read!(shell))}
      startup_path = Path.dirname(erl) <> ":" <> Path.expand("../../bin", Path.dirname(erl)) <> ":" <> policy.path
      %{path: policy.path, executable: erl, shell: shell, startup_script: policy.startup_script, startup_path: startup_path, forbidden: policy.forbidden, files: files, directories: directories}
    end
    Application.put_env(:ipse, :verification_environment, policy)
    result = Kernel.ParallelCompiler.compile_to_path(#{inspect(sources)}, #{inspect(harness)}, return_diagnostics: true)
    modules = case result do
      {:ok, modules, []} -> modules
      {:ok, modules, %{compile_warnings: [], runtime_warnings: []}} -> modules
      other -> raise("Harness compiler diagnostics: " <> inspect(other))
    end
    true = Enum.sort(modules) == Enum.sort(#{inspect(spec.modules)})
    executable = if #{inspect(executable)} do
      {:ok, canonical} = Ipse.Workspace.canonical_path(#{inspect(executable)})
      canonical
    end
    IO.puts(:json.encode(%{"executable" => executable}))
    """

    args = Enum.flat_map(code_paths, &["-pa", &1]) ++ ["--erl", "+S 2:2", "-e", expression]
    output = command!(compiler, args, repository, [])
    %{"executable" => executable} = :json.decode(output)
    expected = Enum.map(spec.modules, &Path.basename(beam(harness, &1))) |> Enum.sort()
    ^expected = harness |> File.ls!() |> Enum.sort()
    executable
  end

  defp inventories(runtime) do
    roots =
      if runtime.release do
        [runtime.release]
      else
        private =
          runtime.code_paths
          |> Enum.map(&Path.join(Path.dirname(&1), "priv"))
          |> Enum.filter(&File.exists?/1)

        runtime.code_paths ++
          private ++ [Path.dirname(Path.dirname(runtime.erl)), runtime.boot <> ".boot"]
      end

    %{
      "host" => Map.new(roots, &{&1, inventory(&1)}),
      "harness" => inventory(runtime.harness),
      "utilities" => inventory(Path.join(runtime.root, "utilities")),
      "runtime-bin" => inventory(Path.join(runtime.root, "runtime-bin")),
      "utility_targets" => Map.new(runtime.utilities, fn {name, path} -> {name, digest(path)} end)
    }
  end

  defp repository!(options) do
    if repository = Keyword.get(options, :repository) do
      path = repository |> Path.expand()

      root =
        command!("git", ["-C", path, "rev-parse", "--show-toplevel"], @source_root, [])
        |> path_output!()

      true = Path.type(root) == :absolute
      root
    else
      @source_root
    end
  end

  defp source_inventory!(repository) do
    git = fn args -> command!("git", ["-C", repository | args], repository, []) end
    "" = git.(["status", "--porcelain=v1", "--untracked-files=all"])
    files = git.(["ls-files", "-z", "--cached"]) |> String.split(<<0>>, trim: true)
    true = length(files) in 1..4096

    %{
      commit: git.(["rev-parse", "HEAD"]),
      files: Map.new(files, &{&1, inventory(Path.join(repository, &1))})
    }
  end

  defp runtime_root!(false, options, inputs) do
    if Keyword.has_key?(options, :output), do: private_output!(options, inputs)
    root = Path.join(System.tmp_dir!(), "ipse-verification-" <> id())
    File.mkdir!(root)
    root
  end

  defp runtime_root!(true, options, inputs) do
    output = private_output!(options, inputs)
    root = Path.join(output, "runtime")
    File.mkdir!(root)
    root
  end

  defp private_output!(options, inputs) do
    output = options |> Keyword.fetch!(:output) |> Path.expand()
    parent = command!("/bin/sh", ["-c", "pwd -P"], Path.dirname(output), []) |> path_output!()
    output = Path.join(parent, Path.basename(output))

    for input <- inputs, File.dir?(input) do
      input = command!("/bin/sh", ["-c", "pwd -P"], input, []) |> path_output!()
      false = within?(output, input) or within?(input, output)
    end

    File.mkdir!(output)
    File.chmod!(output, 0o700)
    output
  end

  defp within?(path, root),
    do: path == root or String.starts_with?(path, String.trim_trailing(root, "/") <> "/")

  defp path_output!(bytes) do
    true = String.ends_with?(bytes, "\n")
    binary_part(bytes, 0, byte_size(bytes) - 1)
  end

  defp attempt(callback) do
    {:returned, callback.()}
  catch
    kind, reason -> {:failed, kind, reason, __STACKTRACE__}
  end

  defp first_result!({:failed, kind, reason, stack}, _), do: :erlang.raise(kind, reason, stack)
  defp first_result!(_, {:failed, kind, reason, stack}), do: :erlang.raise(kind, reason, stack)
  defp first_result!({:returned, value}, {:returned, _}), do: value

  defp command!(command, arguments, cwd, env) do
    case System.cmd(command, arguments, cd: cwd, env: env, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, code} -> raise("Verification child exited #{code}: " <> output)
    end
  end

  defp identity(path, stat) do
    case stat.type do
      :regular -> %{type: :regular, mode: stat.mode, sha256: digest(path)}
      :directory -> %{type: :directory, mode: stat.mode}
      :symlink -> %{type: :symlink, mode: stat.mode, target: File.read_link!(path)}
    end
  end

  defp beam(harness, module), do: Path.join(harness, Atom.to_string(module) <> ".beam")
  defp id, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  defp erlang_eval(expression) do
    encoded = :io_lib.format(~c"~p", [expression]) |> IO.iodata_to_binary()

    "application:ensure_all_started(elixir), 'Elixir.Code':eval_string(" <>
      encoded <> "), init:stop()."
  end
end
