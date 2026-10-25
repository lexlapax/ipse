Code.require_file("../../dev/verification/scenarios.exs", __DIR__)
Code.require_file("../../dev/verification/runtime.exs", __DIR__)
Code.require_file("../../dev/verification/package.exs", __DIR__)

defmodule Ipse.Development.VerificationTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.Verification.Scenarios
  alias Ipse.Development.Verification.Runtime

  test "installed diagnosis rejects unexpected warnings for bare and configured routes" do
    validate = &Ipse.Development.Verification.Package.validate_doctor!/2

    report = %{
      "version" => 1,
      "checks" =>
        Enum.map(
          ~w(runtime.build home.layout config.files config.provider credentials.selected sandbox.native mcp.config extensions.selection sessions.store provider.reachability),
          &%{"id" => &1, "status" => "ok"}
        )
    }

    replace = fn id, row ->
      Map.update!(report, "checks", fn checks ->
        Enum.map(checks, fn check ->
          if check["id"] == id, do: Map.merge(check, row), else: check
        end)
      end)
    end

    for platform <- [{:unix, :linux}, {:unix, :darwin}] do
      assert :ok = validate.(report, platform)

      for id <- ["config.files", "config.provider", "credentials.selected", "sandbox.native"] do
        assert_raise MatchError, fn ->
          validate.(
            replace.(id, %{"status" => "warn", "detail" => "unexpected warning"}),
            platform
          )
        end
      end
    end

    warning =
      replace.("sandbox.native", %{"status" => "warn", "detail" => "macOS is experimental."})

    assert :ok = validate.(warning, {:unix, :darwin})
    assert_raise MatchError, fn -> validate.(warning, {:unix, :linux}) end

    assert_raise MatchError, fn ->
      validate.(
        replace.("provider.reachability", %{"status" => "skip", "summary" => ""}),
        {:unix, :linux}
      )
    end

    for incomplete <- [
          %{"version" => 1, "checks" => []},
          Map.put(report, "version", 2),
          Map.update!(report, "checks", &tl/1),
          Map.update!(report, "checks", &(&1 ++ [hd(&1)])),
          Map.update!(report, "checks", &Enum.reverse/1)
        ] do
      assert_raise MatchError, fn -> validate.(incomplete, {:unix, :linux}) end
    end

    source = File.read!("dev/verification/package.exs")
    assert length(Regex.scan(~r/:ok = validate_doctor!\(report\)/, source)) == 3
  end

  test "standalone fixture bootstrap resolves the SDK despite a shadowing application directory" do
    root =
      Path.join(
        System.tmp_dir!(),
        "fixture-bootstrap-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      )

    cwd = Path.join(root, "ipse-0.0.0")
    File.mkdir_p!(cwd)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    expression = """
    sdk = Ipse.Extension |> :code.which() |> to_string() |> Path.dirname()
    if Application.app_dir(:ipse, "ebin") == sdk, do: raise("shadow control did not activate")
    Code.require_file(#{inspect(Path.expand("../../dev/verification/scenarios.exs", __DIR__))})
    Code.require_file(#{inspect(Path.expand("../../dev/verification/runtime.exs", __DIR__))})
    :ok = Ipse.Development.Verification.Runtime.load_fixture!(:knowledge)
    IO.puts("fixture loaded from actual SDK")
    """

    arguments = paths ++ ["-pa", cwd, "-e", expression]
    options = [cd: cwd, stderr_to_stdout: true]
    {output, status} = System.cmd(System.find_executable("elixir"), arguments, options)

    assert status == 0, output
    assert output =~ "fixture loaded from actual SDK"
  end

  test "the complete macOS verifier compiles without launching its platform probes" do
    expression = ~S"""
    [path] = System.argv()
    {:__block__, _, forms} = path |> File.read!() |> Code.string_to_quoted!(file: path)
    [definition] = for {:defmodule, _, _} = form <- forms, do: form
    [{Ipse.Development.Platform.MacSandboxProbe, _}] = Code.compile_quoted(definition, path)
    IO.puts("compiled complete sandbox verifier")
    """

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["-e", expression, "--", Path.expand("../../dev/verify-macos-sandbox.exs", __DIR__)],
        env: [{"ERL_FLAGS", "+S 2:2 +A 1"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output == "compiled complete sandbox verifier\n"
  end

  test "the finite CLI rejects ambiguous and unsupported choices before setup" do
    invalid = [
      [],
      ~w(installed unknown --archive absent --input absent),
      ~w(source model --sdk absent --sdk other --input absent),
      ~w(installed model --archive absent --input absent --input other),
      ~w(installed model --archive absent --input absent --selection none --selection default),
      ~w(installed model --archive absent --sdk absent --input absent),
      ~w(source model --archive absent --input absent),
      ~w(source model --sdk absent --input absent --unknown value),
      ~w(source model --sdk absent --input absent positional),
      ~w(source embedding --sdk absent --input absent --selection json),
      ~w(source model --sdk absent --input absent --selection invalid),
      ~w(source model --sdk absent --input absent --output unwanted),
      ~w(source model-service --sdk absent --input absent),
      ~w(installed model-service --archive absent --input absent --output a --output b),
      ~w(source measured-knowledge --sdk absent --input absent --output evidence),
      ~w(source measured-authority --sdk absent --input absent --repository repo),
      ~w(source measured-authority --sdk absent --input absent --repository repo --output evidence --selection structured),
      ~w(source model --sdk absent --input absent --repository repo),
      ~w(source package --sdk absent --input absent)
    ]

    for argv <- invalid do
      assert catch_error(Scenarios.parse!(argv))
    end

    for mode <- ~w(source installed), selection <- ~w(default none json json-none) do
      origin = if mode == "source", do: "--sdk", else: "--archive"

      assert {"model", options} =
               Scenarios.parse!([
                 mode,
                 "model",
                 origin,
                 "absent",
                 "--input",
                 "absent",
                 "--selection",
                 selection
               ])

      assert options[:selection] == selection
    end

    for mode <- ~w(source installed) do
      origin = if mode == "source", do: "--sdk", else: "--archive"

      assert {"model-service", options} =
               Scenarios.parse!([
                 mode,
                 "model-service",
                 origin,
                 "absent",
                 "--input",
                 "fixture",
                 "--output",
                 "evidence"
               ])

      assert options[:output] == "evidence"
    end

    for mode <- ~w(source installed),
        selection <-
          ~w(default sealed structured sealed-structured sealed-long-answers sealed-gpu-answers) do
      origin = if mode == "source", do: "--sdk", else: "--archive"

      assert {"measured-knowledge", options} =
               Scenarios.parse!([
                 mode,
                 "measured-knowledge",
                 origin,
                 "absent",
                 "--input",
                 "artifacts.json",
                 "--repository",
                 "repo",
                 "--output",
                 "evidence",
                 "--selection",
                 selection
               ])

      assert options[:repository] == "repo"
    end
  end

  test "measured catalogs compile exact declared closures and inventory all prebuilt artifact referents" do
    root = input_root()
    artifact = Path.join(root, "artifact")
    File.mkdir!(artifact)
    file = Path.join(artifact, "unopened-proof.txt")
    File.write!(file, "before")
    input = Path.join(root, "artifacts.json")

    artifacts =
      Map.new(~w(answer dense explicit lexical model research semantic), &{&1, artifact})

    File.write!(input, JSON.encode!(artifacts))

    for {name, count} <- [{"measured-knowledge", 26}, {"measured-authority", 27}] do
      spec =
        Scenarios.fetch!(name) |> Map.put(:retained, false) |> Map.put(:native_environment, :base)

      assert length(spec.modules) == count
      assert Enum.uniq(spec.modules) == spec.modules
      parent = self()
      entered = make_ref()

      assert_raise MatchError, fn ->
        Runtime.with_runtime(spec, Keyword.put(options(), :input, input), fn runtime ->
          assert %{"precompiled" => true} =
                   Runtime.eval!(
                     runtime,
                     ~s|%{"precompiled" => Ipse.Development.Evaluation.MeasuredExecution.Environment.bound?()}|
                   )

          send(parent, entered)
          File.write!(file, "changed")
        end)
      end

      assert_receive ^entered
      File.write!(file, "before")
    end
  end

  test "the precompiled child observes private environment and finite utilities" do
    isolated(fn runtime ->
      assert %{"entered" => true} = Runtime.eval!(runtime, ~s(%{"entered" => true}))
    end)
  end

  test "cold manifest parsing rejects duplicate decoded keys and excessive nesting before launch" do
    root = input_root()
    path = Path.join(root, "manifest.json")

    fixture = %{
      "path" => "/synthetic/Elixir.Ipse.beam",
      "bytes" => 0,
      "sha256" => String.duplicate("0", 64)
    }

    original = JSON.encode!(%{"version" => 1, "runtime" => %{"files" => [fixture]}})
    File.write!(path, original)
    assert Runtime.reopen_evaluation!(path, Ipse.JSON.sha256(original), []) == nil

    duplicate = String.replace_prefix(original, "{", ~S|{"\u0076ersion":2,|)

    nested =
      ~s({"unopened":) <>
        String.duplicate("[", 65) <>
        "0" <>
        String.duplicate("]", 65) <> "," <> binary_part(original, 1, byte_size(original) - 1)

    for refused <- [duplicate, nested, original <> String.duplicate(" ", 1_048_576)] do
      File.write!(path, refused)
      assert catch_error(Runtime.reopen_evaluation!(path, Ipse.JSON.sha256(refused), []))
    end

    File.write!(path, original)
    assert catch_error(Runtime.reopen_evaluation!(path, String.duplicate("0", 64), []))

    [knowledge, backend] =
      for module <- Scenarios.fixture!(:knowledge).modules,
          do: %{fixture | "path" => "/synthetic/" <> Atom.to_string(module) <> ".beam"}

    for files <- [
          [knowledge],
          [knowledge, knowledge],
          [knowledge, backend, knowledge],
          [knowledge, %{backend | "path" => "/other/" <> Path.basename(backend["path"])}]
        ] do
      partial = JSON.encode!(%{"version" => 1, "runtime" => %{"files" => files}})
      File.write!(path, partial)
      assert catch_error(Runtime.reopen_evaluation!(path, Ipse.JSON.sha256(partial), []))
    end
  end

  test "source fixture handoff adopts both seal versions and matching loaded modules in a shared directory" do
    root = input_root()
    shared = Path.join(root, "shared")
    File.mkdir!(shared)

    Runtime.with_runtime(Scenarios.fixture!(:knowledge), options(), fn runtime ->
      for name <- File.ls!(runtime.harness),
          do: File.cp!(Path.join(runtime.harness, name), Path.join(shared, name))

      File.cp!(
        Application.app_dir(:ipse, "ebin/Elixir.Ipse.JSON.beam"),
        Path.join(shared, "Elixir.Ipse.JSON.beam")
      )

      files =
        for name <- File.ls!(shared) do
          path = Path.join(shared, name)
          bytes = File.read!(path)
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end

      seals =
        for version <- [1, 2] do
          path = Path.join(root, "source-v#{version}.json")
          bytes = JSON.encode!(%{"version" => version, "runtime" => %{"files" => files}})
          File.write!(path, bytes)
          {path, Ipse.JSON.sha256(bytes)}
        end

      program = """
      Code.require_file(#{inspect(Path.expand("../../dev/verification/scenarios.exs", __DIR__))})
      Code.require_file(#{inspect(Path.expand("../../dev/verification/runtime.exs", __DIR__))})
      false = :code.is_loaded(Ipse.Development.Fixtures.Knowledge)
      for {path, expected} <- #{inspect(seals)} do
        nil = Ipse.Development.Verification.Runtime.reopen_evaluation!(path, expected, [])
        for module <- [Ipse.Development.Fixtures.Knowledge, Ipse.Development.Fixtures.Knowledge.Backend] do
          true = :code.is_loaded(module) != false
          true = Path.dirname(to_string(:code.which(module))) == #{inspect(shared)}
        end
      end
      IO.puts("Adopted both fixture captures; full Freeze verification remains the caller's boundary.")
      """

      paths = Path.wildcard(Path.join([Path.dirname(Application.app_dir(:ipse)), "*", "ebin"]))

      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          Enum.flat_map(paths, &["-pa", &1]) ++ ["-e", program],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert output =~ "Adopted both fixture captures"
      refute output =~ "warning:"
    end)
  end

  test "retained runtimes survive callback failures and preserve the first failure" do
    parent = input_root()
    input = Path.join(parent, "input.json")
    File.write!(input, "original")
    spec = Map.put(Scenarios.fetch!("memory"), :retained, true)
    selected = Keyword.put(options(), :input, input)
    output = Path.join(parent, "success")

    runtime = Runtime.with_runtime(spec, Keyword.put(selected, :output, output), & &1)

    assert File.regular?(
             Path.join(runtime.harness, "Elixir.Ipse.Development.Verification.Memory.beam")
           )

    assert %{"reopened" => true} = Runtime.eval!(runtime, ~s(%{"reopened" => true}))
    before = Runtime.inventory(output)

    assert_raise File.Error, fn ->
      Runtime.with_runtime(spec, Keyword.put(selected, :output, output), fn _ ->
        flunk("existing evidence was reopened")
      end)
    end

    assert Runtime.inventory(output) == before
    failed = Path.join(parent, "failed")

    assert_raise RuntimeError, "original callback failure", fn ->
      Runtime.with_runtime(spec, Keyword.put(selected, :output, failed), fn _ ->
        File.write!(input, "changed")
        raise "original callback failure"
      end)
    end

    assert %{"callback_failed" => true, "inventories_unchanged" => false} =
             failed
             |> Path.join("runtime/verification-failure.json")
             |> File.read!()
             |> JSON.decode!()

    assert File.regular?(
             Path.join(failed, "runtime/harness/Elixir.Ipse.Development.Verification.Memory.beam")
           )

    File.write!(input, "original")
    incomplete = Path.join(parent, "incomplete")
    bad_spec = Map.update!(spec, :modules, &(&1 ++ [Ipse.Development.MissingVerificationProof]))

    assert_raise RuntimeError, ~r/Verification child exited/, fn ->
      Runtime.with_runtime(bad_spec, Keyword.put(selected, :output, incomplete), fn _ ->
        flunk("incomplete compiler closure was admitted")
      end)
    end

    assert File.dir?(Path.join(incomplete, "runtime/harness"))
  end

  test "temporary cleanup failure cannot replace the callback failure" do
    diagnostic =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise RuntimeError, "original callback failure", fn ->
          Runtime.with_runtime(Scenarios.fetch!("memory"), options(), fn runtime ->
            on_exit(fn ->
              File.chmod(runtime.root, 0o700)
              File.rm_rf(runtime.root)
            end)

            File.chmod!(runtime.root, 0o500)
            raise "original callback failure"
          end)
        end
      end)

    assert diagnostic =~ "Verification runtime cleanup failed"
  end

  test "declared clean source controls compilation and dirty source refuses before setup" do
    parent = input_root()
    repository = Path.join(parent, "repository ")
    source = Path.join(repository, "proof.exs")

    for directory <- [repository, Path.join(parent, "repository")] do
      File.mkdir!(directory)

      File.write!(Path.join(directory, "proof.exs"), """
      defmodule Ipse.Development.DeclaredRootProof do
        def source, do: __DIR__
      end
      """)

      for args <- [
            ~w(init -q),
            ~w(add proof.exs),
            [
              "-c",
              "user.name=Fixture",
              "-c",
              "user.email=fixture@example.test",
              "-c",
              "commit.gpgsign=false",
              "-c",
              "core.hooksPath=/dev/null",
              "commit",
              "-qm",
              "inert proof"
            ]
          ] do
        assert {_, 0} = System.cmd("git", args, cd: directory, stderr_to_stdout: true)
      end
    end

    for name <- ["evidence ", "evidence"], do: File.mkdir!(Path.join(parent, name))
    output = Path.join(parent, "evidence /run")

    spec = %{
      source: "proof.exs",
      module: Ipse.Development.DeclaredRootProof,
      modules: [Ipse.Development.DeclaredRootProof],
      retained: true
    }

    selected = options() |> Keyword.put(:repository, repository) |> Keyword.put(:output, output)
    runtime = Runtime.with_runtime(spec, selected, & &1)
    assert runtime.root == Path.join(output, "runtime")
    refute File.exists?(Path.join(parent, "evidence/run"))

    assert %{"compiled_source" => ^repository} =
             Runtime.eval!(
               runtime,
               ~s|%{"compiled_source" => Ipse.Development.DeclaredRootProof.source()}|
             )

    File.write!(source, "changed")
    refused = Path.join(parent, "dirty")

    assert_raise MatchError, fn ->
      Runtime.with_runtime(spec, Keyword.put(selected, :output, refused), fn _ ->
        flunk("dirty source reached compilation")
      end)
    end

    refute File.exists?(refused)
  end

  test "only an explicit manager runtime retains service connection variables" do
    parent = input_root()
    tools = Path.join(parent, "tools")
    File.mkdir!(tools)

    for name <- ~w(systemd-run systemctl) do
      path = Path.join(tools, name)
      File.write!(path, "#!/bin/sh\nexit 0\n")
      File.chmod!(path, 0o700)
    end

    names = ~w(PATH DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR)
    previous = Map.new(names, &{&1, System.get_env(&1)})
    System.put_env("PATH", tools <> ":" <> previous["PATH"])
    System.put_env("DBUS_SESSION_BUS_ADDRESS", "synthetic-manager")
    System.put_env("XDG_RUNTIME_DIR", parent)

    try do
      Runtime.with_runtime(Scenarios.fetch!("memory"), options(), fn runtime ->
        assert %{"manager_absent" => true} =
                 Runtime.eval!(
                   runtime,
                   ~s|%{"manager_absent" => Enum.all?(~w(DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR), &(System.get_env(&1) == nil))}|
                 )
      end)

      spec = Map.put(Scenarios.fetch!("memory"), :native_environment, :manager)

      Runtime.with_runtime(spec, options(), fn runtime ->
        assert %{"manager_selected" => true} =
                 Runtime.eval!(
                   runtime,
                   ~s|%{"manager_selected" => System.get_env("DBUS_SESSION_BUS_ADDRESS") == "synthetic-manager" and System.get_env("XDG_RUNTIME_DIR") == #{inspect(parent)}}|
                 )
      end)
    after
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end
  end

  test "wrong entering PATH cannot be normalized into a passing verification" do
    isolated(fn runtime ->
      marker = Path.join(runtime.tmp, "must-not-run")
      changed = %{runtime | env: List.keystore(runtime.env, "PATH", 0, {"PATH", "/usr/bin:/bin"})}

      assert_raise RuntimeError, ~r/Verification child exited/, fn ->
        Runtime.eval!(changed, "File.write!(#{inspect(marker)}, \"ran\")")
      end

      refute File.exists?(marker)
    end)
  end

  test "a precompiled evaluator without a compiled environment refuses before work" do
    Runtime.with_runtime(
      %{Scenarios.evaluator() | native_environment: nil},
      options(),
      fn runtime ->
        expression = """
        (fn ->
          {:ok, launch} = Ipse.Development.Evaluation.Freeze.runtime_launch()
          files = for directory <- :code.get_path(), name <- File.ls!(to_string(directory)), String.ends_with?(name, ".beam") do
          file = Path.join(Path.expand(to_string(directory)), name)
            %{"path" => file, "bytes" => File.stat!(file).size, "sha256" => Ipse.JSON.sha256(File.read!(file))}
          end
          verified = %{"manifest" => %{"version" => 2, "runtime" => %{"launch" => launch, "files" => files}}}
          refused = try do
            Ipse.Development.Evaluation.MeasuredExecution.execution_context!(verified)
            false
          catch
            {:measured_execution, :verification_environment} -> true
          end
          environment = Ipse.Development.Evaluation.MeasuredExecution.Environment
          Application.put_env(:ipse, :verification_environment, %{path: "runtime value must not enable authority"})
          false = environment.bound?()
          operations = [{:launch!, [%{}, []]}, {:enter!, []}, {:enter_manager!, []},
            {:build!, ["/missing-home", "/missing-tmp"]}, {:assert!, []}]
          all_refused = Enum.all?(operations, fn {operation, args} ->
            try do
              apply(environment, operation, args)
              false
            rescue
              error in ArgumentError -> Exception.message(error) == "No compiled verification environment"
            end
          end)
          %{"unbound_policy_refused" => refused, "all_operations_refused" => all_refused}
        end).()
        """

        assert %{"unbound_policy_refused" => true, "all_operations_refused" => true} =
                 Runtime.eval!(runtime, expression)
      end
    )
  end

  test "precompiled children reject changed utility bytes and wrong environment before effects" do
    root = input_root()
    tools = Path.join(root, "tools")
    File.mkdir!(tools)
    git = Path.join(tools, "git")
    File.cp!(System.find_executable("git"), git)
    File.chmod!(git, 0o700)
    dirname = Path.join(tools, "dirname")
    forwarding = "#!/bin/sh\nexec /usr/bin/dirname \"$@\"\n#" <> String.duplicate(" ", 4096)
    File.write!(dirname, forwarding)
    File.chmod!(dirname, 0o700)
    previous_path = System.fetch_env!("PATH")
    System.put_env("PATH", tools <> ":" <> previous_path)

    try do
      Runtime.with_runtime(Scenarios.evaluator(), options(), fn runtime ->
        expression = """
        (fn ->
          {:ok, launch} = Ipse.Development.Evaluation.Freeze.runtime_launch()
          files = for directory <- :code.get_path(), name <- File.ls!(to_string(directory)), String.ends_with?(name, ".beam") do
          file = Path.join(Path.expand(to_string(directory)), name)
            %{"path" => file, "bytes" => File.stat!(file).size, "sha256" => Ipse.JSON.sha256(File.read!(file))}
          end
          verified = %{"manifest" => %{"version" => 2, "runtime" => %{"launch" => launch, "files" => files}}}
          owner = Ipse.Development.Evaluation.MeasuredExecution
          context = owner.execution_context!(verified)
          marker = Path.join(#{inspect(runtime.tmp)}, "must-not-run")
          code = ~S'File.write!(hd(System.argv()), System.fetch_env!("IPSE_HOME"))'
          {command, args} = owner.precompiled_command(context, :inventory, code, [marker])
          {_, 0} = System.cmd(command, args, stderr_to_stdout: true, env: [{"IPSE_HOME", nil}, {"ERL_CRASH_DUMP", "/dev/null"}])
          #{inspect(Path.join(runtime.home, ".ipse"))} = File.read!(marker)
          File.rm!(marker)
          for override <- [[{"PATH", "/usr/bin:/bin"}], [{"IPSE_HOME", "/wrong"}], [{"DBUS_SESSION_BUS_ADDRESS", "synthetic"}]] do
            {_, status} = System.cmd(command, args, stderr_to_stdout: true, env: override ++ [{"ERL_CRASH_DUMP", "/dev/null"}])
            true = status != 0
            false = File.exists?(marker)
          end
          extra = Path.join(#{inspect(Path.join(runtime.root, "utilities"))}, "extra")
          File.write!(extra, "synthetic")
          try do
            {_, status} = System.cmd(command, args, stderr_to_stdout: true, env: [{"ERL_CRASH_DUMP", "/dev/null"}])
            true = status != 0
            false = File.exists?(marker)
          after
            File.rm!(extra)
          end
          git = #{inspect(git)}
          bytes = File.read!(git)
          <<first, rest::binary>> = bytes
          File.write!(git, <<Bitwise.bxor(first, 1), rest::binary>>)
          try do
            {_, status} = System.cmd(command, args, stderr_to_stdout: true, env: [{"ERL_CRASH_DUMP", "/dev/null"}])
            true = status != 0
            false = File.exists?(marker)
          after
            File.write!(git, bytes)
          end
          dirname = #{inspect(dirname)}
          bytes = File.read!(dirname)
          utility_marker = Path.join(#{inspect(runtime.tmp)}, "startup-utility-effect")
          replacement = "#!/bin/sh\\nprintf ran > '" <> utility_marker <> "'\\nexec /usr/bin/dirname \\\"$@\\\"\\n"
          replacement = replacement <> "#" <> String.duplicate(" ", byte_size(bytes) - byte_size(replacement) - 1)
          true = byte_size(replacement) == byte_size(bytes)
          try do
            File.write!(dirname, replacement)
            {_, 0} = System.cmd("/bin/sh", [dirname, "/synthetic/path"], stderr_to_stdout: true)
            "ran" = File.read!(utility_marker)
            File.rm!(utility_marker)
            {_, status} = System.cmd(command, args, stderr_to_stdout: true, env: [{"ERL_CRASH_DUMP", "/dev/null"}])
            true = status != 0
            false = File.exists?(marker)
            false = File.exists?(utility_marker)
          after
            File.write!(dirname, bytes)
          end
          false = :code.is_loaded(IpseKnowledge.Evidence)
          false = :code.is_loaded(IpseKnowledge.Store)
          %{"environment_refusals" => 6, "missing_ipse_home_restored" => true, "domain_modules_unloaded" => true}
        end).()
        """

        assert %{
                 "environment_refusals" => 6,
                 "missing_ipse_home_restored" => true,
                 "domain_modules_unloaded" => true
               } = Runtime.eval!(runtime, expression)

        marker = Path.join(runtime.tmp, "outer-startup-utility-effect")
        payload = "#!/bin/sh\nprintf ran > '" <> marker <> "'\nexec /usr/bin/dirname \"$@\"\n"

        payload =
          payload <> "#" <> String.duplicate(" ", byte_size(forwarding) - byte_size(payload) - 1)

        assert byte_size(payload) == byte_size(forwarding)

        try do
          File.write!(dirname, payload)

          assert_raise RuntimeError, ~r/Verification runtime changed before launch/, fn ->
            Runtime.eval!(runtime, ~s(%{"entered" => true}))
          end

          refute File.exists?(marker)
        after
          File.write!(dirname, forwarding)
        end
      end)
    after
      System.put_env("PATH", previous_path)
    end
  end

  test "precompiled fixture loading preserves application directory resolution" do
    before = Map.new([:ipse, :elixir, :stdlib], &{&1, Application.app_dir(&1)})
    assert :ok = Runtime.load_fixture!(:mcp)
    assert before == Map.new(Map.keys(before), &{&1, Application.app_dir(&1)})
    assert :ok = Runtime.load_fixture!(:mcp)

    for module <- Scenarios.fixture!(:mcp).modules do
      file = module |> :code.which() |> to_string()
      assert File.regular?(file)
      assert Path.extname(file) == ".beam"
    end
  end

  test "an absent harness refuses while all original sources remain present" do
    isolated(fn runtime ->
      absent = runtime.harness <> ".absent"
      File.rename!(runtime.harness, absent)

      try do
        assert_raise RuntimeError, ~r/Verification runtime changed before launch/, fn ->
          Runtime.eval!(runtime, ~s(%{"entered" => true}))
        end
      after
        File.rename!(absent, runtime.harness)
      end
    end)
  end

  test "a forbidden development executable refuses before the verification expression" do
    isolated(fn runtime ->
      tool = Path.join([runtime.root, "utilities", "elixir"])
      marker = Path.join(runtime.tmp, "must-not-run")
      File.ln_s!(System.find_executable("elixir"), tool)

      try do
        assert_raise RuntimeError, ~r/Verification runtime changed before launch/, fn ->
          Runtime.eval!(runtime, "File.write!(#{inspect(marker)}, \"ran\")")
        end

        refute File.exists?(marker)
      after
        File.rm!(tool)
      end
    end)
  end

  test "changed or extra precompiled bytes refuse before scenario effects" do
    isolated(fn runtime ->
      file = Path.join(runtime.harness, "Elixir.Ipse.Development.Verification.Memory.beam")
      original = File.read!(file)
      marker = Path.join(runtime.tmp, "must-not-run")
      expression = "File.write!(#{inspect(marker)}, \"ran\")"

      try do
        File.write!(file, original <> "changed")

        assert_raise RuntimeError, ~r/Verification runtime changed before launch/, fn ->
          Runtime.eval!(runtime, expression)
        end

        refute File.exists?(marker)
      after
        File.write!(file, original)
      end

      extra = Path.join(runtime.harness, "unexpected.beam")

      try do
        File.write!(extra, "unexpected")

        assert_raise RuntimeError, ~r/Verification runtime changed before launch/, fn ->
          Runtime.eval!(runtime, expression)
        end

        refute File.exists?(marker)
      after
        File.rm!(extra)
      end
    end)
  end

  test "changed inventoried utility state cannot become a successful result" do
    assert_raise MatchError, fn ->
      isolated(fn runtime ->
        File.write!(Path.join([runtime.root, "utilities", "unexpected"]), "changed")
        %{"entered" => false}
      end)
    end
  end

  test "source runtime inventories application private files alongside compiled code" do
    root = input_root()
    app = Path.join(root, "lib/ipse")
    File.mkdir_p!(app)
    sdk = Path.join(app, "ebin")
    File.cp_r!(Application.app_dir(:ipse, "ebin"), sdk)

    for dependency <- File.ls!(Path.dirname(Application.app_dir(:ipse))), dependency != "ipse" do
      File.ln_s!(
        Path.join(Path.dirname(Application.app_dir(:ipse)), dependency),
        Path.join([root, "lib", dependency])
      )
    end

    private = Path.join(app, "priv")
    File.mkdir!(private)
    helper = Path.join(private, "ipse-runner")
    File.write!(helper, "before")

    assert_raise MatchError, fn ->
      Runtime.with_runtime(
        Scenarios.fetch!("memory"),
        Keyword.put(options(), :sdk, sdk),
        fn _ ->
          File.write!(helper, "changed")
          %{"passed" => true}
        end
      )
    end
  end

  test "literal path characters and hidden files cannot bypass input change detection" do
    root = input_root()
    input = Path.join(root, "artifact[1]{2}?")
    nested = Path.join(input, ".hidden[actual]")
    File.mkdir_p!(nested)
    file = Path.join(nested, "proof.beam")
    File.write!(file, "before")
    before = Runtime.inventory(input)
    assert Map.has_key?(before, ".hidden[actual]/proof.beam")

    assert_raise MatchError, fn ->
      Runtime.with_runtime(
        Scenarios.fetch!("memory"),
        Keyword.put(options(), :input, input),
        fn _ ->
          File.write!(file, "changed")
          %{"passed" => true}
        end
      )
    end

    refute before == Runtime.inventory(input)
  end

  test "file, directory and nested symlinks preserve target content identity" do
    root = input_root()
    actual = Path.join(root, "actual")
    File.mkdir!(actual)
    file = Path.join(actual, "input.json")
    File.write!(file, "before")
    directory_link = Path.join(root, "directory-alias")
    file_link = Path.join(root, "file-alias")
    nested = Path.join(root, "nested")
    File.mkdir!(nested)
    File.ln_s!("actual", directory_link)
    File.ln_s!("actual/input.json", file_link)
    File.ln_s!("../actual", Path.join(nested, "alias"))

    for {input, index} <- Enum.with_index([directory_link, file_link, nested]) do
      before = Runtime.inventory(input)

      assert_raise MatchError, fn ->
        Runtime.with_runtime(
          Scenarios.fetch!("memory"),
          Keyword.put(options(), :input, input),
          fn _ ->
            File.write!(file, "changed-#{index}")
            %{"passed" => true}
          end
        )
      end

      refute before == Runtime.inventory(input)
    end

    assert %{type: :symlink, target: "actual", resolved: target} =
             Runtime.inventory(directory_link)["."]

    assert target["input.json"].sha256 == Runtime.digest(file)
  end

  test "cyclic symlink trees refuse instead of recursing indefinitely" do
    root = input_root()
    child = Path.join(root, "child")
    File.mkdir!(child)
    File.ln_s!("..", Path.join(child, "parent"))
    assert_raise ArgumentError, ~r/Cyclic verification input/, fn -> Runtime.inventory(root) end
  end

  test "symlink targets preserve filesystem resolution before parent traversal" do
    root = input_root()
    actual = Path.join(root, "actual/input.json")
    decoy = Path.join(root, "input.json")
    File.mkdir_p!(Path.join(root, "actual/child"))
    File.write!(actual, "before")
    File.write!(decoy, "decoy")
    File.ln_s!("actual/child", Path.join(root, "alias"))

    for {target, index} <-
          Enum.with_index(["alias/../input.json", Path.join(root, "alias/../input.json")]) do
      input = Path.join(root, "input-alias-#{index}")
      File.ln_s!(target, input)
      before = Runtime.inventory(input)
      assert before["."].resolved["."].sha256 == Runtime.digest(actual)
      refute before["."].resolved["."].sha256 == Runtime.digest(decoy)

      assert_raise MatchError, fn ->
        Runtime.with_runtime(
          Scenarios.fetch!("memory"),
          Keyword.put(options(), :input, input),
          fn _ ->
            File.write!(actual, "changed-#{index}")
            %{"passed" => true}
          end
        )
      end

      assert File.read!(input) == "changed-#{index}"
      refute before == Runtime.inventory(input)
    end
  end

  test "MCP uses its precompiled child after copied compile-time sources disappear" do
    assert :ok = Runtime.load_fixture!(:mcp)
    root = Path.join(System.tmp_dir!(), "ipse-mcp-prebuilt-" <> Ipse.Usage.id())
    File.mkdir!(root)

    try do
      source = Path.join(root, "source")
      File.mkdir!(source)

      for {original, relative} <- [
            {Path.expand("../../dev/verification/mcp.exs", __DIR__), "verification/mcp.exs"},
            {Path.expand("../../dev/fixtures/mcp.exs", __DIR__), "fixtures/mcp.exs"}
          ] do
        target = Path.join(source, relative)
        File.mkdir_p!(Path.dirname(target))
        File.cp!(original, target)
      end

      spec = %{Scenarios.fetch!("mcp") | source: Path.join(source, "verification/mcp.exs")}

      Runtime.with_runtime(spec, options(), fn runtime ->
        File.rename!(source, source <> ".absent")

        expression = """
        (fn ->
          {:ok, _} = Application.ensure_all_started(:ipse)
          root = #{inspect(runtime.tmp)}
          entry = IpseMCPExample.Fixture.stdio_config(root)
          path = Path.join(root, "mcp.json")
          File.write!(path, :json.encode(%{"servers" => [entry]}))
          {:ok, [server]} = Ipse.MCP.Config.load(path)
          {:ok, [tool]} = Ipse.MCP.discover_server(server, root)
          {:ok, text} = Ipse.MCP.call(tool, %{"text" => "synthetic"}, root)
          true = text == IpseMCPExample.Fixture.text()
          %{"precompiled_child" => true}
        end).()
        """

        assert %{"precompiled_child" => true} = Runtime.eval!(runtime, expression)

        child = Path.join(runtime.harness, "Elixir.IpseMCPExample.Fixture.beam")
        saved = Path.join(runtime.root, "saved-child.beam")
        File.rename!(child, saved)

        try do
          marker = Path.join(runtime.tmp, "must-not-run")

          assert_raise RuntimeError, ~r/Verification runtime changed before launch/, fn ->
            Runtime.eval!(runtime, "File.write!(#{inspect(marker)}, \"ran\")")
          end

          refute File.exists?(marker)
        after
          File.rename!(saved, child)
        end
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "knowledge storage and web subprocesses use compiled fixtures without source fallback" do
    root = input_root()
    source = Path.join(root, "knowledge.exs")
    File.cp!(Path.expand("../../dev/fixtures/knowledge.exs", __DIR__), source)
    spec = %{Scenarios.fixture!(:knowledge) | source: source}

    Runtime.with_runtime(spec, options(), fn runtime ->
      File.rename!(source, source <> ".absent")

      expression = """
      (fn ->
        {:ok, _} = Application.ensure_all_started(:ipse)
        fixture = Ipse.Development.Fixtures.Knowledge
        {:ok, backend} = fixture.start_backend("notes")

        try do
          hit = %{"source_id" => "manual:release", "uri" => "fixture:release",
                  "title" => "Release", "snippet" => "Release requires tests."}
          page = %{"text" => "Release requires tests.", "observed_uri" => "fixture:captured",
                   "media_type" => "text/plain", "observed_at_ms" => 1}
          :ok = fixture.configure_web_backend(backend, %{
            "searches" => %{"release" => [hit]}, "pages" => %{"fixture:release" => page}
          })
          entries = [fixture.stdio_config("notes", "normal", backend.port),
                     fixture.web_stdio_config("notes", "normal", backend.port)
                     |> Map.put("id", "knowledge_web")]
          path = Path.join(#{inspect(runtime.tmp)}, "mcp.json")
          File.write!(path, :json.encode(%{"servers" => entries}))
          {:ok, servers} = Ipse.MCP.Config.load(path)
          tools = Enum.flat_map(servers, fn server ->
            {:ok, descriptors} = Ipse.MCP.discover_server(server, #{inspect(runtime.tmp)})
            descriptors
          end) |> Map.new(&{&1.name, &1})
          call = fn name, args ->
            {:ok, text} = Ipse.MCP.call(Map.fetch!(tools, name), args, #{inspect(runtime.tmp)})
            :json.decode(text)
          end
          hash = fn text -> Base.encode16(:crypto.hash(:sha256, text), case: :lower) end
          source_key = hash.("synthetic")
          key = hash.(JSON.encode!(["ipse-knowledge", 1, "root", ["notes", source_key]]))
          value = %{"format" => 1, "kind" => "root", "partition" => "notes",
                    "source_key" => source_key, "generation" => 1, "state" => "staging",
                    "content_sha256" => hash.("body"), "draft" => nil}
          envelope = %{"version" => 3, "contract" => "ipse-cas-v3", "partition" => "notes",
                       "request_id" => String.duplicate("1", 32), "action" => "cas_root",
                       "args" => %{"key" => key, "expected_revision" => 0,
                         "expected_generation" => 0, "expected_source_generation" => nil,
                         "expected_content_sha256" => nil, "draft_id" => nil, "next_root" => value}}
          %{"status" => "ok", "generation" => 1} = call.("cas", envelope)
          snapshot = call.("cas", %{envelope | "request_id" => String.duplicate("2", 32),
                                    "action" => "snapshot", "args" => %{}})
          1 = snapshot["value"]["count"]
          [row] = snapshot["value"]["records"]
          ^key = row["key"]
          %{"status" => "ok", "hits" => [^hit]} = call.("search", %{
            "version" => 1, "contract" => "search-v1", "query" => "release", "limit" => 1})
          %{"status" => "ok", "text" => "Release requires tests.", "complete" => true} =
            call.("fetch", %{"version" => 1, "contract" => "fetch-v1", "uri" => "fixture:release"})
          %{"storage_write_read" => true, "web_search_fetch" => true}
        after
          :ok = fixture.stop_backend(backend)
        end
      end).()
      """

      assert %{"storage_write_read" => true, "web_search_fetch" => true} =
               Runtime.eval!(runtime, expression)

      for module <- spec.modules do
        child = Path.join(runtime.harness, Atom.to_string(module) <> ".beam")
        saved = Path.join(runtime.root, "saved-child.beam")
        File.rename!(child, saved)

        try do
          marker = Path.join(runtime.tmp, "must-not-run")

          assert_raise RuntimeError, ~r/Verification runtime changed before launch/, fn ->
            Runtime.eval!(runtime, "File.write!(#{inspect(marker)}, \"ran\")")
          end

          refute File.exists?(marker)
        after
          File.rename!(saved, child)
        end
      end
    end)
  end

  defp isolated(callback) do
    Runtime.with_runtime(
      Scenarios.fetch!("memory"),
      options(),
      callback
    )
  end

  for {verification, target} <- [{false, :daemon}, {true, :daemon}, {true, :environment}] do
    @verification verification
    @target target
    test "the scripted model daemon uses declared #{@target} bytes with verification #{@verification}" do
      root = input_root()
      source = Path.join(root, "fixture.exs")
      File.cp!(Path.expand("../../dev/fixtures/model_service.exs", __DIR__), source)

      spec =
        if @verification do
          evaluator = Scenarios.evaluator()

          %{
            evaluator
            | sources: evaluator.sources ++ [source],
              modules: evaluator.modules ++ Scenarios.fixture!(:model_service).modules
          }
        else
          %{Scenarios.fixture!(:model_service) | source: source}
        end

      target =
        if unquote(target == :daemon),
          do: Ipse.Development.Fixtures.ModelService.Daemon,
          else: Ipse.Development.Evaluation.MeasuredExecution.Environment

      beam_name = Atom.to_string(target) <> ".beam"
      replacement = Path.join(root, "replacement.beam")

      compiler = """
      [{_, bytes}] = Code.compile_string(~S'''
      defmodule #{inspect(target)} do
        @on_load :effect
        def effect do
          File.write!(Path.join(System.fetch_env!("HOME"), "on-load-marker"), "ran")
          :ok
        end
        def main(_), do: :ok
      end
      ''')
      File.write!(#{inspect(replacement)}, bytes)
      """

      compiler_env = [{"HOME", root}, {"IPSE_HOME", Path.join(root, ".ipse")}]

      assert {_, 0} =
               System.cmd(System.find_executable("elixir"), ["-e", compiler], env: compiler_env)

      assert File.read!(Path.join(root, "on-load-marker")) == "ran"
      File.rm!(Path.join(root, "on-load-marker"))

      Runtime.with_runtime(spec, options(), fn runtime ->
        File.rename!(source, source <> ".absent")

        original = Path.join(runtime.harness, beam_name)

        bytes = File.read!(replacement)
        {:ok, _, chunks} = :beam_lib.all_chunks(bytes)
        padding = File.stat!(original).size - byte_size(bytes) - 8
        assert padding >= 0

        {:ok, bytes} =
          :beam_lib.build_module(chunks ++ [{~c"IPSE", :binary.copy(<<0>>, padding)}])

        assert byte_size(bytes) == File.stat!(original).size
        File.write!(replacement, bytes)

        load = """
        module = #{inspect(target)}
        {:module, ^module} = :code.load_binary(module, ~c"replacement.beam", File.read!(#{inspect(replacement)}))
        """

        assert {_, 0} =
                 System.cmd(System.find_executable("elixir"), ["-e", load], env: compiler_env)

        assert File.read!(Path.join(root, "on-load-marker")) == "ran"
        File.rm!(Path.join(root, "on-load-marker"))

        expression = """
        (fn ->
          fixture = Ipse.Development.Fixtures.ModelService
          launch = %{
            "executable" => #{inspect(runtime.erl)}, "boot" => #{inspect(runtime.boot)},
            "root" => to_string(:code.root_dir()),
            "code_paths" => Enum.map(:code.get_path(), &(Path.expand(to_string(&1)))),
            "files" => for path <- #{inspect([runtime.erl, Path.join(Path.dirname(runtime.erl), "erlexec"), runtime.boot <> ".boot"])} do
              %{"path" => path, "bytes" => File.stat!(path).size, "sha256" => Ipse.JSON.sha256(File.read!(path))}
            end
          }
          {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
          {:ok, selected_port} = :inet.port(listener)
          :ok = :gen_tcp.close(listener)
          base = #{inspect(Path.join(runtime.tmp, "fixture"))}
          config = fixture.configuration(base, launch, "http://127.0.0.1:" <> Integer.to_string(selected_port), verification: #{inspect(@verification)})
          modes = [:present, :changed, :missing, :replacement] ++ if(#{inspect(@verification)}, do: [:control_downgrade], else: [])
          results = for mode <- modes do
            stage = Path.join(base, Atom.to_string(mode))
            for directory <- [stage, Path.join(stage, "home"), Path.join(stage, "tmp")] do
              File.mkdir!(directory)
              File.chmod!(directory, 0o700)
            end
            for file <- config["runtime"]["files"] do
              target = Path.join(stage, file["path"])
              File.mkdir_p!(Path.dirname(target))
              File.cp!(file["source"], target)
              File.chmod!(target, if(file["executable"], do: 0o500, else: 0o400))
            end
            beam = Path.join(stage, "lib/ollama/" <> #{inspect(beam_name)})
            case mode do
              :present -> :ok
              :changed -> File.chmod!(beam, 0o600); File.write!(beam, "changed", [:append])
              :missing -> File.rm!(beam)
              :replacement -> File.chmod!(beam, 0o600); File.cp!(#{inspect(replacement)}, beam)
              :control_downgrade ->
                control = Path.join(stage, "lib/ollama/control.json")
                bytes = File.read!(control) |> JSON.decode!() |> Map.put("verification_environment", false) |> JSON.encode!()
                File.chmod!(control, 0o600)
                File.write!(control, bytes)
            end
            home = Path.join(stage, "home")
            env = %{"PATH" => #{inspect(runtime.path)}, "HOME" => home,
              "IPSE_HOME" => Path.join(home, ".ipse"), "TMPDIR" => Path.join(stage, "tmp"),
              "ERL_CRASH_DUMP" => "/dev/null", "OLLAMA_HOST" => config["origin"],
              "CUDA_VISIBLE_DEVICES" => "-1", "ROCR_VISIBLE_DEVICES" => "-1",
              "OLLAMA_VULKAN" => "0", "GGML_VK_VISIBLE_DEVICES" => "-1", "OLLAMA_NO_CLOUD" => "1"}
            {:ok, port} = Ipse.Runner.open_stdio(Path.join(stage, "bin/ollama"), ["serve"], stage, env, 10_000)
            try do
              if mode == :present do
                connect = fn connect, deadline ->
                  case :gen_tcp.connect({127, 0, 0, 1}, selected_port, [:binary, active: false], 100) do
                    {:ok, socket} -> socket
                    {:error, :econnrefused} ->
                      true = System.monotonic_time(:millisecond) < deadline
                      Process.sleep(10)
                      connect.(connect, deadline)
                  end
                end
                socket = connect.(connect, System.monotonic_time(:millisecond) + 5000)
                :ok = :gen_tcp.send(socket, "GET /api/tags HTTP/1.1\\r\\nhost: 127.0.0.1\\r\\n\\r\\n")
                read = fn read, bytes ->
                  case :gen_tcp.recv(socket, 0, 2000) do
                    {:ok, chunk} -> read.(read, bytes <> chunk)
                    {:error, :closed} -> bytes
                  end
                end
                response = read.(read, <<>>)
                ["HTTP/1.1 200 OK" <> _, body] = :binary.split(response, "\\r\\n\\r\\n")
                true = Enum.sort(Enum.map(JSON.decode!(body)["models"], & &1["name"])) == ~w(fixture-embedding:latest fixture-text:latest)
                true = File.regular?(Path.join(home, "fixture-daemon.pid"))
                if #{inspect(@verification)} do
                  expected = Map.take(env, ~w(PATH HOME IPSE_HOME TMPDIR)) |> Map.put("LANG", "C.UTF-8")
                  true = JSON.decode!(File.read!(Path.join(home, "fixture-environment.json"))) == expected
                end
                [%{"operation" => "tags"}] = File.read!(Path.join(home, "fixture-requests.jsonl")) |> String.split("\\n", trim: true) |> Enum.map(&JSON.decode!/1)
                :ok = Ipse.Runner.close_stdio(port)
              else
                :ok = Ipse.Runner.close_stdio(port, :completed)
                false = File.exists?(Path.join(home, "fixture-daemon.pid"))
                false = File.exists?(Path.join(home, "fixture-requests.jsonl"))
                false = File.exists?(Path.join(home, "on-load-marker"))
              end
            after
              if Port.info(port), do: Ipse.Runner.close_stdio(port)
            end
            Atom.to_string(mode)
          end
          %{"precompiled_daemon_cases" => results}
        end).()
        """

        expected =
          ~w(present changed missing replacement) ++
            if(@verification, do: ["control_downgrade"], else: [])

        assert %{"precompiled_daemon_cases" => ^expected} = Runtime.eval!(runtime, expression)
      end)
    end
  end

  test "frozen commands are identical across fresh VM atom allocation orders" do
    Runtime.with_runtime(Scenarios.evaluator(), options(), fn runtime ->
      expression = """
      (fn ->
        owner = Ipse.Development.Evaluation.MeasuredExecution
        command = ~S'''
        {:ok, launch} = Ipse.Development.Evaluation.Freeze.runtime_launch()
        files = for directory <- :code.get_path(), name <- File.ls!(to_string(directory)), String.ends_with?(name, ".beam") do
          file = Path.join(Path.expand(to_string(directory)), name)
          %{"path" => file, "bytes" => File.stat!(file).size, "sha256" => Ipse.JSON.sha256(File.read!(file))}
        end
        owner = Ipse.Development.Evaluation.MeasuredExecution
        context = owner.execution_context!(%{"manifest" => %{"version" => 2, "runtime" => %{"launch" => launch, "files" => files}}})
        generated = owner.precompiled_command(context, :evaluator, "nil", [])
        IO.puts(Base.encode64(:erlang.term_to_binary(generated)))
        '''
        {:ok, launch} = Ipse.Development.Evaluation.Freeze.runtime_launch()
        files = for directory <- :code.get_path(), name <- File.ls!(to_string(directory)), String.ends_with?(name, ".beam") do
          file = Path.join(Path.expand(to_string(directory)), name)
          %{"path" => file, "bytes" => File.stat!(file).size, "sha256" => Ipse.JSON.sha256(File.read!(file))}
        end
        context = owner.execution_context!(%{"manifest" => %{"version" => 2, "runtime" => %{"launch" => launch, "files" => files}}})
        {executable, arguments} = owner.precompiled_command(context, :inventory, command, [])
        index = Enum.find_index(arguments, &(&1 == "-eval")) + 1
        roles = ~w(author evaluator input inventory cli)
        commands = for order <- [roles, Enum.reverse(roles)] do
          seeds = Enum.map_join(order, ",", fn role -> "binary_to_atom(<<" <> Enum.map_join(:binary.bin_to_list(role), ",", &Integer.to_string/1) <> ">>,utf8)" end)
          arguments = List.update_at(arguments, index, &(seeds <> ",ok=io:setopts(standard_io,[{encoding,latin1}])," <> &1))
          {output, 0} = System.cmd(executable, arguments, stderr_to_stdout: true, env: [{"ERL_CRASH_DUMP", "/dev/null"}])
          Base.decode64!(String.trim(output))
        end
        %{"identical_commands" => length(Enum.uniq(commands)) == 1}
      end).()
      """

      assert %{"identical_commands" => true} = Runtime.eval!(runtime, expression)
    end)
  end

  test "frozen precompiled roles launch without loading authoring in the host" do
    Runtime.with_runtime(Scenarios.evaluator(), options(), fn runtime ->
      expression = """
      (fn ->
        false = :code.is_loaded(IpseKnowledge.Evidence)
        false = :code.is_loaded(IpseKnowledge.Store)
        {:ok, launch} = Ipse.Development.Evaluation.Freeze.runtime_launch()
        files = for directory <- :code.get_path(), name <- File.ls!(to_string(directory)), String.ends_with?(name, ".beam") do
          file = Path.join(Path.expand(to_string(directory)), name)
          %{"path" => file, "bytes" => File.stat!(file).size, "sha256" => Ipse.JSON.sha256(File.read!(file))}
        end
        verified = %{"manifest" => %{"version" => 2, "runtime" => %{"launch" => launch, "files" => files}}}
        owner = Ipse.Development.Evaluation.MeasuredExecution
        {:precompiled, _} = context = owner.execution_context!(verified)
        false = :code.is_loaded(IpseKnowledge.Evidence)
        nested_refused = try do
          owner.execution_context!(put_in(verified, ["manifest", "runtime"], launch))
          false
        catch
          {:measured_execution, :precompiled_runtime} -> true
        end
        true = nested_refused
        owner_file = to_string(:code.which(owner))
        owner_bytes = File.read!(owner_file)
        {:module, ^owner} = :code.load_binary(owner, ~c"", owner_bytes)
        downgrade_refused = try do
          owner.execution_context!(verified)
          false
        catch
          {:measured_execution, :precompiled_module} -> true
        after
          {:module, ^owner} = :code.load_binary(owner, String.to_charlist(owner_file), owner_bytes)
        end
        true = downgrade_refused
        argument_limit_refused = try do
          owner.precompiled_command(context, :inventory, String.duplicate(" ", 65_536), [])
          false
        catch
          {:measured_execution, :precompiled_argument_limit} -> true
        end
        true = argument_limit_refused

        run = fn role, code, argv ->
          {command, args} = owner.precompiled_command(context, role, code, argv)
          eval_index = Enum.find_index(args, &(&1 == "-eval")) + 1
          args = List.update_at(args, eval_index, &("ok=io:setopts(standard_io,[{encoding,latin1}])," <> &1))
          {bytes, status} = System.cmd(command, args, stderr_to_stdout: true, env: [{"ERL_CRASH_DUMP", "/dev/null"}])
          {status, JSON.decode!(String.trim(bytes))}
        end
        {0, %{"host_domains_unloaded" => true}} = run.(:evaluator,
          "IO.puts(JSON.encode!(%{host_domains_unloaded: :code.is_loaded(IpseKnowledge.Evidence) == false and :code.is_loaded(IpseKnowledge.Store) == false}))", [])
        author = ~S'''
        attrs = %{"source_id" => "synthetic", "partition" => "notes", "generation" => 1,
          "title" => "Release", "text" => "Release requires tests.", "uri" => "fixture:release",
          "observed_at_ms" => 1, "event_at_ms" => nil, "expires_at_ms" => nil,
          "origin" => %{"kind" => "provided", "store_profile" => nil, "partition_or_scope" => nil,
            "receipt" => nil, "historical" => false}}
        [row] = Ipse.Development.Evaluation.Author.prepare([%{"key" => "synthetic", "attrs" => attrs}])
        [[fact]] = Map.values(row["facts"])
        IO.puts(JSON.encode!(Map.take(fact, ~w(subject predicate object))))
        '''
        {0, %{"subject" => "Release", "predicate" => "requires", "object" => "tests"}} = run.(:author, author, [])
        input = ~S'''
        bytes = JSON.encode!(%{"schema_version" => 1, "queries" => [%{"query_id" => "q", "project" => "alpha", "query" => "Release?", "split" => "tuning", "expected_answer" => "must be excluded"}]})
        {:ok, result} = Ipse.Development.Evaluation.Dataset.queries(bytes, "tuning")
        IO.puts(JSON.encode!(%{queries: result["queries"], argv: System.argv()}))
        '''
        marker_arg = "untrusted \\\"quote\\\"; System.halt(99) 雪"
        {0, %{"queries" => [%{"query_id" => "q", "project" => "alpha", "query" => "Release?"}], "argv" => [^marker_arg]}} = run.(:input, input, [marker_arg])
        {0, %{"inventory_host_unloaded" => true}} = run.(:inventory,
          "IO.puts(JSON.encode!(%{inventory_host_unloaded: :code.is_loaded(IpseKnowledge.Store) == false}))", [])
        {1, %{"status" => "failed", "reason" => %{"code" => "invalid_options"}}} = run.(:cli,
          "Ipse.Development.Evaluation.Runner.main(System.argv())", ["--phase", "invalid"])

        marker = Path.join(#{inspect(runtime.tmp)}, "must-not-run")
        {command, args} = owner.precompiled_command(context, :inventory, ~S'File.write!(hd(System.argv()), "ran")', [marker])
        {_, 0} = System.cmd(command, args, stderr_to_stdout: true, env: [{"ERL_CRASH_DUMP", "/dev/null"}])
        "ran" = File.read!(marker)
        File.rm!(marker)
        beam = Path.join(#{inspect(runtime.harness)}, "Elixir.Ipse.Development.Evaluation.Author.beam")
        bytes = File.read!(beam)
        try do
          File.write!(beam, bytes <> "changed")
          {_, status} = System.cmd(command, args, stderr_to_stdout: true, env: [{"ERL_CRASH_DUMP", "/dev/null"}])
          true = status != 0
          false = File.exists?(marker)
        after
          File.write!(beam, bytes)
        end
        saved = Path.join(#{inspect(runtime.tmp)}, "author.beam")
        File.rename!(beam, saved)
        try do
          {_, status} = System.cmd(command, args, stderr_to_stdout: true, env: [{"ERL_CRASH_DUMP", "/dev/null"}])
          true = status != 0
          false = File.exists?(marker)
        after
          File.rename!(saved, beam)
        end
        false = :code.is_loaded(IpseKnowledge.Evidence)
        %{"roles" => 5, "nested_runtime_refused" => true, "downgrade_refused" => true, "argument_limit_refused" => true, "tamper_refused_before_effect" => true, "host_domains_unloaded" => true}
      end).()
      """

      assert %{
               "roles" => 5,
               "nested_runtime_refused" => true,
               "downgrade_refused" => true,
               "argument_limit_refused" => true,
               "tamper_refused_before_effect" => true,
               "host_domains_unloaded" => true
             } =
               Runtime.eval!(runtime, expression)
    end)
  end

  defp options do
    [
      sdk: Application.app_dir(:ipse, "ebin"),
      input: Path.expand("../../examples/memory-corpus.json", __DIR__)
    ]
  end

  defp input_root do
    root = Path.join(System.tmp_dir!(), "ipse-verification-input-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
