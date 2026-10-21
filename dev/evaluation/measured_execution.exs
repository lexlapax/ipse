Code.require_file("contract.exs", __DIR__)

defmodule Ipse.Development.Evaluation.MeasuredExecution do
  @moduledoc "One permanently claimed, sealed measured knowledge population and its read-only audit."
  alias Ipse.Development.Evaluation.{
    Contract,
    Freeze,
    Runner,
    ModelService,
    Resources
  }

  @compile {:no_warn_undefined, Runner}
  @metric "linux_memcg_charged_peak_bytes_v1"
  @limit 67_108_864
  defmodule Environment do
    @moduledoc false
    @policy Application.compile_env(:ipse, :verification_environment, nil)

    def bound?, do: is_map(@policy)

    if is_map(@policy) do
      def launch!(launch, arguments) do
        policy = policy!()
        verify_shell!(policy.shell)
        {:ok, executable} = Ipse.WorkspaceContext.canonical_path(launch["executable"])
        true = executable == policy.executable
        bindir = Path.dirname(executable)
        root = Path.expand("../..", bindir)
        {:ok, ^root} = Ipse.WorkspaceContext.canonical_path(launch["root"])
        erlexec = Path.join(bindir, "erlexec")
        [identity] = Enum.filter(launch["files"], &(&1["path"] == erlexec))
        %{type: :regular, size: size} = File.lstat!(erlexec)
        true = size == identity["bytes"] and size <= 67_108_864
        true = digest!(erlexec, size) == identity["sha256"]
        {"/bin/sh", ["-c", policy.startup_script, "ipse-erts", root, bindir | arguments]}
      end

      def enter! do
        expected = policy!().startup_path
        ^expected = System.fetch_env!("PATH")
        System.put_env("PATH", policy!().path)
        :ok = :io.setopts(:standard_io, encoding: :unicode)
        assert!()
      end

      def enter_manager! do
        manager = Map.take(System.get_env(), ~w(DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR))
        for name <- Map.keys(manager), do: System.delete_env(name)

        try do
          enter!()
        after
          System.put_env(manager)
        end
      end

      def build!(home, tmp) do
        policy = policy!()
        verify_shell!(policy.shell)

        for directory <- policy.directories do
          %{type: :directory, mode: mode} = File.lstat!(directory.path)
          true = mode == directory.mode
          true = Enum.sort(File.ls!(directory.path)) == directory.names
        end

        for file <- policy.files do
          %{type: :symlink, mode: mode} = File.lstat!(file.link)
          true = mode == file.link_mode
          true = File.read_link!(file.link) == file.target
          {:ok, resolved} = Ipse.WorkspaceContext.canonical_path(file.link)
          true = resolved == file.resolved
          %{type: :regular, mode: mode, size: size} = File.lstat!(resolved)
          true = mode == file.mode and size == file.bytes
          true = digest!(resolved, size) == file.sha256
        end

        for directory <- [home, tmp] do
          {:ok, ^directory} = Ipse.WorkspaceContext.canonical_path(directory)
          %{type: :directory, mode: mode} = File.lstat!(directory)
          true = Bitwise.band(mode, 0o077) == 0
        end

        %{
          "PATH" => policy.path,
          "LANG" => "C.UTF-8",
          "HOME" => home,
          "IPSE_HOME" => Path.join(home, ".ipse"),
          "TMPDIR" => tmp
        }
      end

      def assert! do
        home = System.fetch_env!("HOME")
        expected = build!(home, System.fetch_env!("TMPDIR"))

        if System.get_env("IPSE_HOME") == nil,
          do: System.put_env("IPSE_HOME", expected["IPSE_HOME"])

        for {name, value} <- expected, do: ^value = System.fetch_env!(name)
        for name <- policy!().forbidden, do: nil = System.find_executable(name)

        for name <- ~w(DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR),
            do: nil = System.get_env(name)

        :ok
      end

      defp policy!, do: @policy

      defp verify_shell!(shell) do
        {:ok, resolved} = Ipse.WorkspaceContext.canonical_path("/bin/sh")
        true = resolved == shell.path
        %{type: :regular, mode: mode, size: size} = File.lstat!(shell.path)
        true = mode == shell.mode and size == shell.bytes
        true = digest!(shell.path, size) == shell.sha256
        :ok
      end

      defp digest!(path, expected) do
        {context, ^expected} =
          path
          |> File.stream!(1_048_576, [])
          |> Enum.reduce({:crypto.hash_init(:sha256), 0}, fn bytes, {context, size} ->
            size = size + byte_size(bytes)
            true = size <= expected
            {:crypto.hash_update(context, bytes), size}
          end)

        context |> :crypto.hash_final() |> Base.encode16(case: :lower)
      end
    else
      def launch!(_launch, _arguments), do: unbound!()
      def enter!(), do: unbound!()
      def enter_manager!(), do: unbound!()
      def build!(_home, _tmp), do: unbound!()
      def assert!(), do: unbound!()

      defp unbound!, do: raise(ArgumentError, "No compiled verification environment")
    end
  end

  @evaluator_modules [
    __MODULE__,
    Environment,
    Runner,
    Runner.NoMain,
    Contract,
    Freeze,
    ModelService,
    Resources,
    Ipse.Development.Evaluation.Dataset,
    Ipse.Development.Evaluation.Session,
    Ipse.Development.Evaluation.Answer,
    Ipse.Development.Evaluation.Inventory,
    Ipse.Development.Evaluation.Gateway,
    Ipse.Development.Evaluation.Review,
    Ipse.Development.Evaluation.Score,
    Ipse.Development.Evaluation.Metrics,
    Ipse.Development.Fixtures.Knowledge,
    Ipse.Development.Fixtures.Knowledge.Backend
  ]
  @precompiled_roles %{
    evaluator: @evaluator_modules,
    author: [Ipse.Development.Evaluation.Author, IpseKnowledge.Evidence],
    input: [Ipse.Development.Evaluation.Dataset],
    inventory: [],
    cli: [Ipse.Development.Evaluation.CLI | @evaluator_modules]
  }
  @fds [
    {"IPSE_BOUND_ROOT_FD", 4},
    {"IPSE_BOUND_REGISTRY_FD", 5},
    {"IPSE_MEASURE_ROOT_FD", 6},
    {"IPSE_MEASURE_SCOPE_FD", 7},
    {"IPSE_BOUND_SEQUENCE_FD", 8}
  ]

  def run(options) do
    protect(fn ->
      require!(
        Keyword.keyword?(options) and
          Enum.sort(Keyword.keys(options)) == [:freeze, :freeze_sha256],
        :option_shape
      )

      require!(:os.type() == {:unix, :linux}, :unsupported_platform)
      context = context!(options[:freeze], options[:freeze_sha256])
      launch = Path.join(context.freeze, "launch")
      File.mkdir!(launch)
      File.chmod!(launch, 0o700)
      for leaf <- ~w(home tmp), do: mkdir!(Path.join(launch, leaf))
      save_json!(Path.join(launch, "prepare-ticket.json"), ticket(context, "prepare", nil, nil))
      save!(Path.join(context.freeze, "native-authority.bin"), authority(context))
      save!(Path.join(context.freeze, "bootstrap.bin"), bootstrap(context))
      helper = helper!(context)
      systemd = System.find_executable("systemd-run") || fail!(:systemd_unavailable)
      unit = "ipse-measure-" <> context.id
      env = launch_environment(context, launch)

      service_env =
        Map.take(env, ~w(PATH LANG HOME TMPDIR))
        |> Enum.sort()
        |> Enum.map(fn {name, value} -> "--setenv=" <> name <> "=" <> value end)

      arguments =
        [
          "--user",
          "--wait",
          "--collect",
          "--quiet",
          "--pipe",
          "--expand-environment=no",
          "--unit=" <> unit,
          "--property=Type=exec",
          "--property=Delegate=memory",
          "--property=MemoryAccounting=yes",
          "--property=TimeoutStopSec=1s"
        ] ++
          service_env ++
          [
            helper,
            "--measure-cgroup",
            "root",
            context.id,
            Integer.to_string(context.timeouts["root_ms"]),
            context.native,
            "--bound-root",
            Path.join(context.freeze, "native-authority.bin"),
            "--",
            helper,
            "--measure-sequence",
            Path.join(context.freeze, "bootstrap.bin")
          ]

      save_json!(Path.join(launch, "invocation.json"), %{
        "version" => 1,
        "execution_id" => context.id,
        "freeze_sha256" => context.sha,
        "command" => systemd,
        "argv" => arguments,
        "environment" => Map.drop(env, ~w(DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR))
      })

      port =
        Port.open({:spawn_executable, systemd}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          {:args, arguments},
          {:cd, context.freeze},
          {:env, port_environment(env)}
        ])

      try do
        {protocol, status} = await_root(port, <<>>, now() + context.timeouts["root_ms"] + 20_000)
        save!(Path.join(launch, "protocol.bin"), protocol)
        save_json!(Path.join(launch, "exit.json"), %{"exit_code" => status})
      after
        if Port.info(port), do: Port.close(port)
      end

      audit_result(context)
    end)
    |> flatten_result()
  end

  def audit(path, sha) do
    protect(fn -> context!(path, sha) |> audit_result() end) |> flatten_result()
  end

  defp audit_result(context) do
    case protect(fn -> audit!(context) end) do
      {:ok, _} = result ->
        result

      {:error, reason} ->
        summary =
          case protect(fn ->
                 final = json!(Path.join(context.resolution["reports"], "finalized.json"))
                 bytes = read!(Path.join(context.resolution["reports"], "predictions.jsonl"))

                 require!(
                   final["freeze_sha256"] == context.sha and
                     final["prediction_sha256"] == sha(bytes),
                   :prediction_identity
                 )

                 %{
                   "prediction_sha256" => sha(bytes),
                   "rows" => length(jsonl(bytes)),
                   "execution_complete" => false,
                   "resource_complete" => false
                 }
               end) do
            {:ok, value} -> value
            _ -> %{"execution_complete" => false, "resource_complete" => false}
          end

        {:error,
         Map.merge(reason, summary)
         |> Map.put("execution_id", context.id)
         |> Map.put("evidence", context.resolution["reports"])}
    end
  end

  defp flatten_result({:ok, result}) when is_tuple(result), do: result
  defp flatten_result(result), do: result

  @doc false
  def enter(ticket_path) do
    protect(fn ->
      require!(:os.type() == {:unix, :linux}, :unsupported_platform)

      Enum.each(@fds, fn {name, fd} ->
        require!(System.get_env(name) == Integer.to_string(fd), :authority_descriptor)
        directory_identity(fd_path(fd))
      end)

      ticket = json!(ticket_path)

      require!(
        exact?(ticket, ~w(version freeze freeze_sha256 kind ordinal prepared_sha256)) and
          ticket["version"] === 1,
        :ticket_shape
      )

      context = context!(ticket["freeze"], ticket["freeze_sha256"])

      bound =
        if ticket["kind"] == "prepare" do
          require!(ticket["prepared_sha256"] == nil, :prepared_identity)
          nil
        else
          require!(hash?(ticket["prepared_sha256"]), :prepared_identity)
          %{sha: ticket["prepared_sha256"]}
        end

      stage = stage_for!(context, ticket, bound)

      require!(
        ticket_path == stage.ticket and
          read!(ticket_path) ==
            encode(ticket(context, stage.kind, stage.ordinal, if(bound, do: bound.sha))),
        :ticket_changed
      )

      admit_stage!(context, stage)
      claim = Path.join(fd_path(4), "domain-" <> stage.name <> ".claim")

      save_json!(claim, %{
        "version" => 1,
        "freeze_sha256" => context.sha,
        "stage" => stage.name,
        "token" => stage.token,
        "index" => stage.index,
        "ticket_sha256" => sha(read!(ticket_path)),
        "prepared_sha256" => if(bound, do: bound.sha),
        "scope" => directory_identity(fd_path(7)),
        "whole_scope" => directory_identity(fd_path(6))
      })

      prepared = if bound, do: prepared!(context, bound.sha)

      result =
        case stage.kind do
          "prepare" -> prepare!(context)
          "cell" -> cell!(context, prepared, stage.ordinal)
          "finalize" -> finalize!(context, prepared.value)
        end

      save_json!(Path.join(fd_path(4), "domain-" <> stage.name <> ".json"), result)
      require!(result["complete"] == true, :domain_incomplete)
      result
    end)
  end

  @doc false
  def command(launch, requires, expression, argv) do
    code =
      Enum.join(
        ["System.argv(" <> inspect(argv, limit: :infinity, printable_limit: :infinity) <> ")"] ++
          Enum.map(requires, &("Code.require_file(" <> inspect(&1) <> ")")) ++ [expression],
        "; "
      )

    encoded_command(launch, code)
  end

  @doc false
  def execution_context!(verified) do
    require!(verified["manifest"]["version"] == 2, :precompiled_runtime)
    runtime = verified["manifest"]["runtime"]

    require!(
      is_map(runtime) and is_map(runtime["launch"]) and is_list(runtime["files"]),
      :precompiled_runtime
    )

    case :code.which(__MODULE__) do
      [] ->
        name = Atom.to_string(__MODULE__) <> ".beam"

        require!(
          not Enum.any?(runtime["files"], &(Path.basename(&1["path"]) == name)),
          :precompiled_module
        )

        {:source, runtime["launch"]}

      file when is_list(file) ->
        validate_precompiled!(runtime)
        {:precompiled, runtime}

      _ ->
        fail!(:precompiled_runtime)
    end
  end

  @doc false
  def precompiled_command({:precompiled, runtime}, role, expression, argv) do
    modules = Map.fetch!(@precompiled_roles, role)
    bindings = validate_precompiled!(runtime)

    membership =
      for directory <- runtime["launch"]["code_paths"] do
        names =
          runtime["files"]
          |> Enum.map(& &1["path"])
          |> Enum.filter(&(Path.dirname(&1) == directory and Path.extname(&1) == ".beam"))
          |> Enum.map(&Path.basename/1)
          |> Enum.sort()

        {directory, names}
      end

    membership_sha256 = sha(:erlang.term_to_binary(membership))

    bootstrap = """
    membership = for directory <- :code.get_path() do
      directory = to_string(directory)
      names = File.ls!(directory) |> Enum.filter(&String.ends_with?(&1, ".beam")) |> Enum.sort()
      {directory, names}
    end
    true = Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(membership)), case: :lower) == #{inspect(membership_sha256)}
    bindings = #{inspect(bindings, limit: :infinity)}
    verified = for {module, file, expected_md5, expected_sha256} <- bindings, into: %{} do
      %{type: :regular} = File.lstat!(file)
      bytes = File.read!(file)
      true = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == expected_sha256
      true = to_string(:code.which(module)) == file
      if :code.is_loaded(module) != false, do: true = module.module_info(:md5) == expected_md5
      {module, {file, bytes, expected_md5}}
    end
    load = fn module ->
      {file, bytes, expected_md5} = Map.fetch!(verified, module)
      if :code.is_loaded(module) == false, do: {:module, ^module} = :code.load_binary(module, String.to_charlist(file), bytes)
      true = to_string(:code.which(module)) == file
      true = module.module_info(:md5) == expected_md5
      module
    end
    environment = load.(#{inspect(Environment)})
    :ok = apply(environment, :enter!, [])
    for module <- #{inspect(modules, limit: :infinity)}, do: load.(module)
    """

    code =
      Enum.join(
        [
          "System.argv(" <> inspect(argv, limit: :infinity, printable_limit: :infinity) <> ")",
          bootstrap,
          "Code.eval_string(" <>
            inspect(expression, limit: :infinity, printable_limit: :infinity) <> ")"
        ],
        "; "
      )

    {_, arguments} = encoded_command(runtime["launch"], code)
    # The verified environment BEAM can replace the unbound bootstrap module.
    {executable, arguments} = :erlang.apply(Environment, :launch!, [runtime["launch"], arguments])

    require!(
      Enum.sum(Enum.map([executable | arguments], &byte_size/1)) <= 65_536,
      :precompiled_argument_limit
    )

    {executable, arguments}
  end

  @doc false
  def verification_environment({:precompiled, runtime}, home, tmp) do
    validate_precompiled!(runtime)
    Environment.build!(home, tmp)
  end

  defp environment_constructor({:source, _}), do: nil

  defp environment_constructor(execution),
    do: fn home, tmp -> verification_environment(execution, home, tmp) end

  defp validate_precompiled!(runtime) do
    require!(
      is_map(runtime) and is_map(runtime["launch"]) and is_list(runtime["files"]),
      :precompiled_runtime
    )

    bindings =
      @precompiled_roles
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.sort_by(&Atom.to_string/1)
      |> Enum.map(&module_identity!(runtime, &1))

    {Environment, file, md5, digest} = Enum.find(bindings, &(elem(&1, 0) == Environment))

    if :code.is_loaded(Environment) == false do
      bytes = File.read!(file)
      require!(sha(bytes) == digest, :precompiled_module)
      {:ok, {Environment, ^md5}} = :beam_lib.md5(bytes)
      {:module, Environment} = :code.load_binary(Environment, String.to_charlist(file), bytes)
    end

    require!(Environment.bound?(), :verification_environment)
    bindings
  end

  defp module_identity!(runtime, module) do
    file = :code.which(module)
    require!(is_list(file) and file != [], :precompiled_module)
    file = file |> to_string() |> Path.expand()

    require!(
      Path.extname(file) == ".beam" and Path.dirname(file) in runtime["launch"]["code_paths"],
      :precompiled_module
    )

    %{type: :regular, size: size} = File.lstat!(file)
    require!(size <= @limit, :precompiled_module)
    bytes = File.read!(file)
    require!(byte_size(bytes) == size, :precompiled_module)
    identity = %{"path" => file, "bytes" => size, "sha256" => sha(bytes)}

    require!(
      Enum.filter(runtime["files"], &(&1["path"] == file)) == [identity],
      :precompiled_module
    )

    {:ok, {^module, md5}} = :beam_lib.md5(bytes)

    if :code.is_loaded(module) != false,
      do: require!(module.module_info(:md5) == md5, :precompiled_module)

    {module, file, md5, identity["sha256"]}
  end

  defp encoded_command(launch, code) do
    paths = Enum.map(launch["code_paths"], &String.to_charlist/1)
    encoded_paths = Base.encode64(:erlang.term_to_binary(paths))

    encoded_code = Base.encode64(code)

    erl =
      "P=binary_to_term(base64:decode(\"#{encoded_paths}\"),[safe]),true=code:set_path(P),true=(code:get_path()=:=P),{ok,_}=application:ensure_all_started(elixir),true=(code:get_path()=:=P),'Elixir.Code':eval_string(base64:decode(\"#{encoded_code}\")),halt()."

    {launch["executable"],
     [
       "+S",
       "2:2",
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
       "-eval",
       erl
     ]}
  end

  @doc false
  def validate_stage_launch!(helper, stage) do
    {:ok, helper} = Ipse.WorkspaceContext.canonical_path(helper)

    arguments =
      [
        helper,
        "--measure-stage",
        "cell",
        stage.token,
        Integer.to_string(stage.timeout),
        stage.output,
        "--"
      ] ++ stage.argv

    require!(Enum.sum(Enum.map(arguments, &byte_size/1)) <= 65_536, :stage_argument_limit)
    :ok
  end

  defp context!(path, expected) do
    require!(absolute?(path) and hash?(expected), :freeze_identity)
    {:ok, verified} = Freeze.verify(path, expected)
    require!(verified["manifest"]["version"] == 2, :measured_plan_required)
    :ok = Contract.validate(verified["plan"])
    manifest = verified["manifest"]
    expected_directory = Path.join(manifest["source"]["root"], "dev/evaluation")
    require!(Path.expand(__DIR__) == expected_directory, :evaluator_source)

    for relative <-
          ~w(dev/evaluation/runner.exs dev/evaluation/measured_execution.exs dev/evaluation/contract.exs) do
      require!(
        Enum.any?(
          manifest["source"]["files"],
          &(&1["path"] == relative and
              &1["sha256"] == sha(File.read!(Path.join(manifest["source"]["root"], relative))))
        ),
        :evaluator_source
      )
    end

    freeze = Path.dirname(path)

    context = %{
      freeze: freeze,
      path: path,
      sha: expected,
      manifest: manifest,
      verified: verified,
      plan: verified["plan"],
      resolution: verified["resolution"],
      id: manifest["execution_id"],
      native: Path.join(freeze, "native-root"),
      timeouts: manifest["launch_recipe"]["timeouts"],
      runtime: manifest["runtime"]["launch"],
      execution: execution_context!(verified)
    }

    stage(context, "prepare", nil, nil)
    for ordinal <- 0..13, do: stage(context, "cell", ordinal, nil)
    stage(context, "finalize", nil, nil)
    context
  end

  defp authority(context) do
    identity = context.manifest["attempt_registry_identity"]

    IO.iodata_to_binary([
      "IPBND001",
      string(context.manifest["attempt_registry"]),
      <<identity["device"]::64, identity["inode"]::64>>,
      string(context.native),
      string(Path.join(context.freeze, "bootstrap.bin"))
    ])
  end

  defp bootstrap(context) do
    IO.iodata_to_binary([
      "IPSEQ001",
      string(Path.join(context.native, "sequence")),
      string(Path.join(context.native, "prepared/cells.bin")),
      stage_bytes(stage(context, "prepare", nil, nil)),
      stage_bytes(stage(context, "finalize", nil, nil))
    ])
  end

  defp stage(context, kind, ordinal, prepared_sha) do
    name =
      if kind == "cell",
        do: "cell-" <> String.pad_leading(Integer.to_string(ordinal), 3, "0"),
        else: kind

    index =
      case kind do
        "prepare" -> 0
        "cell" -> ordinal + 1
        "finalize" -> 15
      end

    token = sha(context.id <> ":" <> name) |> binary_part(0, 32)

    ticket_path =
      if kind == "prepare",
        do: Path.join(context.freeze, "launch/prepare-ticket.json"),
        else: Path.join(context.native, "prepared/" <> name <> "-ticket.json")

    expression =
      "case Ipse.Development.Evaluation.MeasuredExecution.enter(" <>
        inspect(ticket_path) <>
        ") do {:ok, _} -> System.halt(0); {:error, value} -> IO.puts(JSON.encode!(value)); System.halt(1) end"

    {executable, arguments} =
      case context.execution do
        {:source, launch} ->
          command(launch, [Path.expand("runner.exs", __DIR__)], expression, [])

        {:precompiled, _} = execution ->
          precompiled_command(execution, :evaluator, expression, [])
      end

    timeout =
      context.timeouts[
        case kind do
          "prepare" -> "prepare_ms"
          "cell" -> "cell_ms"
          "finalize" -> "finalize_ms"
        end
      ]

    stage = %{
      kind: kind,
      ordinal: ordinal,
      name: name,
      index: index,
      token: token,
      timeout: timeout,
      output: Path.join(context.native, "metric-" <> name),
      argv: [executable | arguments],
      ticket: ticket_path,
      prepared_sha: prepared_sha
    }

    :ok = validate_stage_launch!(helper!(context), stage)
    stage
  end

  defp stage_for!(context, ticket, prepared) do
    kind = ticket["kind"]
    require!(kind in ~w(prepare cell finalize), :ticket_kind)

    if kind == "cell",
      do: require!(is_integer(ticket["ordinal"]) and ticket["ordinal"] in 0..13, :cell_ordinal),
      else: require!(ticket["ordinal"] == nil, :ticket_ordinal)

    stage(context, kind, ticket["ordinal"], if(prepared, do: prepared.sha))
  end

  defp ticket(context, kind, ordinal, prepared_sha),
    do: %{
      "version" => 1,
      "freeze" => context.path,
      "freeze_sha256" => context.sha,
      "kind" => kind,
      "ordinal" => ordinal,
      "prepared_sha256" => prepared_sha
    }

  defp stage_bytes(stage),
    do:
      IO.iodata_to_binary([
        string(stage.token),
        <<stage.timeout::64>>,
        string(stage.output),
        <<length(stage.argv)::32>>,
        Enum.map(stage.argv, &string/1)
      ])

  defp stage_claim(stage), do: "IPSECLM1" <> stage_bytes(stage)

  defp admit_stage!(context, stage) do
    require!(
      directory_identity(fd_path(4)) == directory_identity(context.native),
      :native_root_identity
    )

    require!(
      directory_identity(fd_path(5)) == context.manifest["attempt_registry_identity"] and
        directory_identity(context.manifest["attempt_registry"]) == directory_identity(fd_path(5)),
      :registry_identity
    )

    require!(
      directory_identity(fd_path(8)) == directory_identity(Path.join(context.native, "sequence")),
      :sequence_identity
    )

    kernel = File.read!("/proc/self/cgroup")
    require!(byte_size(kernel) <= 65_536, :kernel_membership)

    membership =
      kernel
      |> String.split("\n")
      |> Enum.find_value(fn line ->
        if String.starts_with?(line, "0::"), do: String.replace_prefix(line, "0::", "")
      end)

    require!(
      is_binary(membership) and String.starts_with?(membership, "/") and
        not String.contains?(membership, ["/../", "/./"]),
      :kernel_membership
    )

    current = "/sys/fs/cgroup" <> membership
    root = System.get_env("IPSE_MEASURE_ROOT")

    require!(
      absolute?(root) and Path.basename(root) == "ipse-run-" <> context.id and
        directory_identity(root) == directory_identity(fd_path(6)),
      :root_scope
    )

    require!(
      current == Path.join(root, "cell-" <> stage.token) and
        directory_identity(current) == directory_identity(fd_path(7)),
      :stage_scope
    )

    require!(
      System.get_env("IPSE_BOUND_STAGE_INDEX") == Integer.to_string(stage.index) and
        System.get_env("IPSE_BOUND_STAGE_TOKEN") == stage.token,
      :stage_selection
    )

    require!(
      read!(Path.join(fd_path(4), "authority.bin")) == authority(context) and
        read!(Path.join(fd_path(4), "bootstrap.bin")) == bootstrap(context),
      :native_authority
    )

    require!(
      read!(Path.join(fd_path(8), claim_leaf(stage.index))) == stage_claim(stage),
      :native_claim
    )

    started = json!(Path.join(stage.output, "started.json"))

    require!(
      started["token"] == stage.token and started["role"] == "cell" and
        %{"device" => started["scope_device"], "inode" => started["scope_inode"]} ==
          directory_identity(fd_path(7)),
      :started_scope
    )
  end

  defp prepare!(context) do
    root = Path.join("/proc/" <> File.read_link!("/proc/self") <> "/fd/4", "prepared")
    mkdir!(root)
    reports = context.resolution["reports"]
    mkdir!(reports)
    mkdir!(Path.join(reports, "cells"))
    :ok = Application.ensure_all_started(:ipse) |> started_ok()

    {:ok, catalog} =
      Runner.catalog_admission(context.plan, context.verified["artifact_paths"], root)

    Process.put(:comparison_execution, context.execution)

    {:ok, input} =
      Runner.prepare_inputs(context.plan, context.resolution["data_manifest"], root)

    prepared =
      Map.merge(input, %{
        "version" => 1,
        "freeze_sha256" => context.sha,
        "original_plan" => context.plan,
        "artifact_paths" => context.verified["artifact_paths"],
        "runtime_launch" => context.runtime,
        "catalog" => catalog
      })

    bytes = encode(prepared)
    save!(Path.join(root, "population.json"), bytes)
    digest = sha(bytes)
    save!(Path.join(root, "population.sha256"), digest <> "\n")

    stages =
      Enum.map(prepared["schedule"]["cells"], fn cell ->
        value = stage(context, "cell", cell["ordinal"], digest)

        save_json!(
          Path.join(root, value.name <> "-ticket.json"),
          ticket(context, "cell", cell["ordinal"], digest)
        )

        value
      end)

    save_json!(Path.join(root, "finalize-ticket.json"), ticket(context, "finalize", nil, digest))

    save!(
      Path.join(root, "cells.bin"),
      IO.iodata_to_binary(["IPSCELL1", <<length(stages)::32>>, Enum.map(stages, &stage_bytes/1)])
    )

    %{
      "version" => 1,
      "complete" => true,
      "prepared_sha256" => digest,
      "cells" => length(stages),
      "query_count" => length(prepared["queries"])
    }
  end

  defp prepared!(context, expected) do
    require!(hash?(expected), :prepared_identity)
    bytes = read!(Path.join(context.native, "prepared/population.json"))

    require!(
      sha(bytes) == expected and
        read!(Path.join(context.native, "prepared/population.sha256"), 65) == expected <> "\n",
      :prepared_changed
    )

    value = decode!(bytes, @limit)

    require!(
      value["freeze_sha256"] == context.sha and value["original_plan"] == context.plan and
        value["artifact_paths"] == context.verified["artifact_paths"] and
        value["runtime_launch"] == context.runtime,
      :prepared_changed
    )

    {:ok, schedule} = Runner.schedule(context.plan, value["queries"])

    require!(
      value["schedule"] == schedule and length(schedule["cells"]) == 14,
      :prepared_schedule
    )

    %{sha: expected, value: value}
  end

  defp cell!(context, bound, ordinal) do
    prepared = bound.value
    cell = Enum.at(prepared["schedule"]["cells"], ordinal)
    output = Path.join(context.resolution["reports"], "cells/" <> cell["id"])
    mkdir!(output)

    result =
      ModelService.run(
        context.resolution["model_service"],
        Path.join(output, "model-service"),
        fn ->
          Runner.evaluate_cell(
            context.plan,
            cell,
            prepared,
            Path.join(output, "domain"),
            %{
              "origin" => context.plan["model_origin"],
              "admission" => "owned_model_service_before_callback"
            },
            context.execution
          )
        end,
        environment_constructor(context.execution)
      )

    domain =
      case result.work do
        {:returned, {:ok, report}} -> report
        {:returned, {:error, report}} -> report
        _ -> nil
      end

    complete = result.receipt["status"] == "ok" and domain != nil and domain["complete"] == true
    service_path = Path.join(output, "model-service/receipt.json")
    service_sha = if File.regular?(service_path), do: sha(read!(service_path))

    report = %{
      "version" => 1,
      "complete" => complete,
      "cell" => cell["id"],
      "prepared_sha256" => bound.sha,
      "work_status" => result.receipt["work_status"],
      "service" => result.receipt,
      "service_receipt_sha256" => service_sha,
      "domain" => domain
    }

    save_json!(Path.join(output, "cell-result.json"), report)
    report
  end

  defp finalize!(context, prepared) do
    outputs =
      Enum.map(
        prepared["schedule"]["cells"],
        &Path.join(context.resolution["reports"], "cells/" <> &1["id"] <> "/domain")
      )

    errors =
      Enum.flat_map(prepared["schedule"]["cells"], fn cell ->
        path =
          Path.join(context.resolution["reports"], "cells/" <> cell["id"] <> "/cell-result.json")

        case optional_json(path) do
          {:ok, %{"complete" => true}} -> []
          _ -> [%{"phase" => cell["id"], "code" => "cell_incomplete"}]
        end
      end)

    {:ok, finalized} =
      Runner.seal_predictions(
        context.plan,
        prepared["queries"],
        outputs,
        context.resolution["reports"],
        %{"sha256" => context.sha, "errors" => errors}
      )

    %{
      "version" => 1,
      "complete" => finalized["execution_complete"],
      "finalized" => finalized,
      "prediction_sha256" => finalized["prediction_sha256"]
    }
  end

  defp audit!(context) do
    require!(
      read!(Path.join(context.freeze, "native-authority.bin")) == authority(context) and
        read!(Path.join(context.native, "authority.bin")) == authority(context),
      :authority_changed
    )

    require!(
      read!(Path.join(context.freeze, "bootstrap.bin")) == bootstrap(context) and
        read!(Path.join(context.native, "bootstrap.bin")) == bootstrap(context) and
        read!(Path.join(context.native, "sequence/bootstrap.bin")) == bootstrap(context),
      :bootstrap_changed
    )

    prepared_sha =
      read!(Path.join(context.native, "prepared/population.sha256"), 65) |> String.trim()

    prepared = prepared!(context, prepared_sha)

    stages =
      [stage(context, "prepare", nil, nil)] ++
        Enum.map(
          prepared.value["schedule"]["cells"],
          &stage(context, "cell", &1["ordinal"], prepared_sha)
        ) ++ [stage(context, "finalize", nil, prepared_sha)]

    cells_bytes =
      IO.iodata_to_binary([
        "IPSCELL1",
        <<14::32>>,
        Enum.map(Enum.slice(stages, 1, 14), &stage_bytes/1)
      ])

    require!(
      read!(Path.join(context.native, "prepared/cells.bin")) == cells_bytes and
        read!(Path.join(context.native, "sequence/cells.bin")) == cells_bytes,
      :cell_descriptor_changed
    )

    evidence = Enum.map(stages, &audit_stage!(context, &1))
    protocol = read!(Path.join(context.freeze, "launch/protocol.bin"), 8192)
    root_bytes = read!(Path.join(context.native, "receipt.json"), 8192)
    <<?M, size::32, root_protocol::binary>> = protocol
    require!(size == byte_size(root_bytes) and root_protocol == root_bytes, :root_protocol)
    root = decode!(root_bytes, 8192)
    require!(json!(Path.join(context.freeze, "launch/exit.json"))["exit_code"] == 0, :root_exit)
    root_started = json!(Path.join(context.native, "started.json"))

    require!(
      root["token"] == context.id and root["role"] == "root" and
        native_receipt?(root, context.timeouts["root_ms"]) and
        root_started["token"] == context.id and root_started["role"] == "root" and
        positive?(root_started["scope_inode"]) and positive?(root_started["scope_device"]),
      :root_receipt
    )

    require!(
      json!(Path.join(context.native, "sequence/sequence.json")) == %{
        "version" => 1,
        "stages" => 16,
        "complete" => true,
        "cleanup_confirmed" => true
      },
      :sequence_incomplete
    )

    reports = context.resolution["reports"]

    cell_outputs =
      Enum.map(
        prepared.value["schedule"]["cells"],
        &Path.join(reports, "cells/" <> &1["id"] <> "/domain")
      )

    streams = Runner.audit_merged_files(cell_outputs, reports)
    merged_files = Map.new(streams, fn {name, bytes} -> {name, sha(bytes)} end)
    final = json!(Path.join(reports, "finalized.json"))
    predictions = Map.fetch!(streams, "predictions.jsonl")
    rows = jsonl(predictions)

    expected =
      for variant <- context.plan["variants"],
          query <- prepared.value["queries"],
          do: {variant["id"], query["query_id"], query["project"]}

    require!(
      Enum.sort(Enum.map(rows, &{&1["variant"], &1["query_id"], &1["project"]})) ==
        Enum.sort(expected) and length(rows) == length(expected),
      :prediction_grid
    )

    require!(
      final["freeze_sha256"] == context.sha and
        final["data_manifest_sha256"] == context.plan["data"]["manifest_sha256"] and
        final["prediction_sha256"] == sha(predictions) and final["rows"] == length(rows),
      :prediction_identity
    )

    resource = json!(Path.join(context.resolution["reports"], "resource-summary.json"))

    recomputed =
      Resources.summary(
        rows,
        jsonl(Map.fetch!(streams, "timings.jsonl")),
        jsonl(Map.fetch!(streams, "request-resources.jsonl")),
        Enum.filter(jsonl(Map.fetch!(streams, "usage.jsonl")), &Map.has_key?(&1, "budget")),
        jsonl(Map.fetch!(streams, "resources.jsonl"))
      )

    require!(resource == recomputed, :resource_summary_changed)
    finalized_outcome = json!(Path.join(context.native, "domain-finalize.json"))

    require!(
      finalized_outcome["finalized"] == final and
        finalized_outcome["prediction_sha256"] == sha(predictions),
      :finalization_changed
    )

    require!(
      final["execution_complete"] == true and resource["complete"] == true and
        resource["storage_reachability_complete"] == true,
      :evaluation_incomplete
    )

    report = %{
      "version" => 1,
      "execution_id" => context.id,
      "freeze_sha256" => context.sha,
      "prepared_sha256" => prepared_sha,
      "prediction_sha256" => sha(predictions),
      "merged_files" => merged_files,
      "rows" => length(rows),
      "metric" => @metric,
      "whole_lifetime" => root,
      "stages" => evidence,
      "execution_complete" => true,
      "resource_complete" => true,
      "quality_complete" => false
    }

    digest = sha(encode(report))

    %{
      "sha256" => digest,
      "report" => report,
      "prediction_sha256" => report["prediction_sha256"],
      "rows" => report["rows"],
      "execution_complete" => true,
      "resource_complete" => true
    }
  end

  defp audit_stage!(context, stage) do
    prefix =
      Path.join(
        context.native,
        "sequence/stage-" <> String.pad_leading(Integer.to_string(stage.index), 3, "0")
      )

    require!(read!(prefix <> ".claim") == stage_claim(stage), :native_claim_changed)
    bytes = read!(prefix <> ".receipt", 8192)
    require!(read!(Path.join(stage.output, "receipt.json"), 8192) == bytes, :receipt_changed)
    stat = File.lstat!(Path.join(stage.output, "receipt.json"))

    identity =
      "device=#{stat.major_device} inode=#{stat.inode} bytes=#{stat.size} uid=#{stat.uid} mode=#{Integer.to_string(stat.mode, 8)}\n"

    require!(read!(prefix <> ".receipt-identity", 512) == identity, :receipt_identity_changed)
    <<?M, size::32, body::binary>> = read!(prefix <> ".protocol", 8192)
    require!(size == byte_size(bytes) and body == bytes <> <<?T, 2::32, 1, 1>>, :stage_protocol)
    require!(read!(prefix <> ".status", 2) == <<1, 1>>, :stage_terminal)
    receipt = decode!(bytes, 8192)
    started = json!(Path.join(stage.output, "started.json"))

    require!(
      receipt["token"] == stage.token and receipt["role"] == "cell" and
        native_receipt?(receipt, stage.timeout) and
        positive?(receipt["parent_interval_peak_bytes"]),
      :stage_receipt
    )

    require!(
      started["token"] == stage.token and started["role"] == "cell" and
        positive?(started["scope_inode"]) and positive?(started["scope_device"]),
      :stage_started
    )

    outcome = json!(Path.join(context.native, "domain-" <> stage.name <> ".json"))

    require!(
      outcome["complete"] == true,
      :domain_incomplete
    )

    if stage.kind == "prepare",
      do:
        require!(
          outcome["prepared_sha256"] ==
            String.trim(read!(Path.join(context.native, "prepared/population.sha256"), 65)),
          :prepared_changed
        )

    claim = json!(Path.join(context.native, "domain-" <> stage.name <> ".claim"))
    root_started = json!(Path.join(context.native, "started.json"))

    require!(
      claim == %{
        "version" => 1,
        "freeze_sha256" => context.sha,
        "stage" => stage.name,
        "token" => stage.token,
        "index" => stage.index,
        "ticket_sha256" => sha(read!(stage.ticket)),
        "prepared_sha256" => stage.prepared_sha,
        "scope" => %{"device" => started["scope_device"], "inode" => started["scope_inode"]},
        "whole_scope" => %{
          "device" => root_started["scope_device"],
          "inode" => root_started["scope_inode"]
        }
      },
      :domain_claim_changed
    )

    if stage.kind == "cell" do
      output = Path.join(context.resolution["reports"], "cells/" <> stage.name)
      result = json!(Path.join(output, "cell-result.json"))
      require!(outcome == result, :domain_outcome_changed)

      service_bytes = read!(Path.join(output, "model-service/receipt.json"))

      require!(
        sha(service_bytes) == result["service_receipt_sha256"] and
          decode!(service_bytes, @limit) == result["service"],
        :service_receipt_changed
      )

      require!(
        result["complete"] == true and result["prepared_sha256"] == stage.prepared_sha and
          result["service"]["status"] == "ok" and
          result["service"]["native_cleanup"] == "confirmed" and
          result["service"]["staging_cleanup"] == "confirmed",
        :cell_incomplete
      )

      require!(
        ModelService.verify_receipt(
          context.resolution["model_service"],
          Path.join(output, "model-service"),
          result["service"],
          environment_constructor(context.execution)
        ) == :ok,
        :service_evidence
      )

      domain = json!(Path.join(output, "domain/domain-result.json"))

      require!(
        domain == result["domain"] and
          domain["prediction_sha256"] == sha(read!(Path.join(output, "domain/predictions.jsonl"))),
        :domain_changed
      )

      :ok = Runner.audit_cell(Path.join(output, "domain"), domain)
      prepared = prepared!(context, stage.prepared_sha).value
      selected = Enum.at(prepared["schedule"]["cells"], stage.ordinal)
      cell_rows = jsonl(read!(Path.join(output, "domain/predictions.jsonl")))

      require!(
        Enum.map(cell_rows, &{&1["variant"], &1["query_id"], &1["project"]}) ==
          Enum.map(selected["query_ids"], &{selected["variant"], &1, selected["project"]}),
        :cell_prediction_grid
      )
    end

    %{
      "name" => stage.name,
      "token" => stage.token,
      "receipt_sha256" => sha(bytes),
      "domain_sha256" => sha(encode(outcome)),
      "claim_sha256" => sha(encode(claim)),
      "scope" => Map.take(started, ~w(scope_device scope_inode)),
      "fresh_lifetime_peak_bytes" => receipt["peak_bytes"],
      "whole_population_interval_peak_bytes" => receipt["parent_interval_peak_bytes"]
    }
  end

  @doc false
  def native_receipt?(value, timeout_ms)
      when is_map(value) and is_integer(timeout_ms) and timeout_ms > 0 do
    policy = Freeze.completion_policy()
    elapsed = value["elapsed_us"]
    drain = value["natural_drain_us"]

    value["version"] == 2 and value["metric"] == @metric and value["complete"] == true and
      Map.take(value, Map.keys(policy)) == policy and value["population_exit"] == "natural" and
      is_integer(elapsed) and elapsed >= 0 and elapsed < timeout_ms * 1000 and
      is_integer(drain) and drain >= 0 and drain <= elapsed and
      drain < policy["population_drain_limit_ms"] * 1000 and
      value["population_drain_ms"] == div(drain, 1000) and
      value["cleanup_confirmed"] == true and value["born_in_scope"] == true and
      value["exit_code"] == 0 and value["reason"] == "completed" and
      positive?(value["peak_bytes"])
  end

  def native_receipt?(_, _), do: false

  defp launch_environment(context, launch) do
    selected =
      case context.execution do
        {:precompiled, _} ->
          verification_environment(
            context.execution,
            Path.join(launch, "home"),
            Path.join(launch, "tmp")
          )

        {:source, _} ->
          %{
            "PATH" => Path.dirname(context.runtime["executable"]) <> ":/usr/bin:/bin",
            "LANG" => "C.UTF-8",
            "HOME" => Path.join(launch, "home"),
            "TMPDIR" => Path.join(launch, "tmp")
          }
      end

    Enum.reduce(~w(DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR), selected, fn name, acc ->
      if value = System.get_env(name), do: Map.put(acc, name, value), else: acc
    end)
  end

  defp port_environment(selected),
    do:
      Enum.map(System.get_env(), fn {name, _} -> {String.to_charlist(name), false} end) ++
        Enum.map(selected, fn {name, value} ->
          {String.to_charlist(name), String.to_charlist(value)}
        end)

  defp await_root(port, bytes, deadline) do
    receive do
      {^port, {:data, more}} ->
        require!(byte_size(bytes) + byte_size(more) <= 8192, :root_protocol)
        await_root(port, bytes <> more, deadline)

      {^port, {:exit_status, code}} ->
        {bytes, code}
    after
      max(deadline - now(), 0) -> fail!(:root_deadline)
    end
  end

  defp helper!(context) do
    helper = Application.app_dir(:ipse, "priv/ipse-runner") |> Path.expand()

    require!(
      Enum.any?(context.manifest["runtime"]["files"], &(&1["path"] == helper)),
      :helper_identity
    )

    helper
  end

  defp directory_identity(path) do
    %{type: :directory} = stat = File.stat!(path)
    %{"device" => stat.major_device, "inode" => stat.inode}
  end

  defp fd_path(fd), do: "/proc/self/fd/" <> Integer.to_string(fd)

  defp claim_leaf(index),
    do: "stage-" <> String.pad_leading(Integer.to_string(index), 3, "0") <> ".claim"

  defp mkdir!(path),
    do:
      (
        File.mkdir!(path)
        File.chmod!(path, 0o700)
      )

  defp save_json!(path, value), do: save!(path, encode(value))

  defp save!(path, bytes) do
    File.write!(path, bytes, [:exclusive, :sync])
    File.chmod!(path, 0o600)
    {:ok, :ok} = File.open(Path.dirname(path), [:read, :raw, :directory], &:file.sync/1)
  end

  defp read!(path, limit \\ @limit) do
    %{type: :regular, size: size} = File.lstat!(path)
    require!(size <= limit, :file_limit)
    bytes = File.read!(path)
    require!(byte_size(bytes) == size and byte_size(bytes) <= limit, :file_changed)
    bytes
  end

  defp json!(path), do: decode!(read!(path), @limit)
  defp optional_json(path), do: if(File.exists?(path), do: {:ok, json!(path)}, else: :missing)

  defp decode!(bytes, limit) do
    require!(byte_size(bytes) <= limit, :file_limit)
    {:ok, value} = Ipse.JSON.decode_unique(bytes)
    value
  end

  defp jsonl(bytes), do: String.split(bytes, "\n", trim: true) |> Enum.map(&decode!(&1, @limit))
  defp encode(value), do: JSON.encode!(value) <> "\n"
  defp string(value), do: <<byte_size(value)::32, value::binary>>
  defp exact?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)

  defp absolute?(path),
    do: is_binary(path) and Path.type(path) == :absolute and Path.expand(path) == path

  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp positive?(value), do: is_integer(value) and value > 0
  defp sha(bytes), do: Ipse.JSON.sha256(bytes)
  defp started_ok({:ok, _}), do: :ok
  defp now, do: System.monotonic_time(:millisecond)
  defp require!(true, _), do: :ok
  defp require!(_, code), do: fail!(code)
  defp fail!(code), do: throw({:measured_execution, code})

  defp protect(fun) do
    {:ok, fun.()}
  rescue
    error ->
      frames =
        Enum.take(__STACKTRACE__, 4)
        |> Enum.map(fn {module, function, arguments, location} ->
          %{
            "module" => inspect(module),
            "function" => Atom.to_string(function),
            "arity" => if(is_integer(arguments), do: arguments, else: length(arguments)),
            "line" => Keyword.get(location, :line)
          }
        end)

      {:error,
       %{
         "code" => "measured_evidence_unavailable",
         "class" => inspect(error.__struct__),
         "frames" => frames
       }}
  catch
    {:measured_execution, code} -> {:error, %{"code" => Atom.to_string(code)}}
    {:evaluation_runner, code} -> {:error, %{"code" => Atom.to_string(code)}}
    :exit, _ -> {:error, %{"code" => "owned_process_lost"}}
  end
end
