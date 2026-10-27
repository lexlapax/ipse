[job, output | input] = System.argv()
started = System.monotonic_time(:millisecond)
Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
peak = :atomics.new(1, [])

spawn_link(fn ->
  Enum.each(1..600, fn _ ->
    Process.sleep(50)
    n = :erlang.memory(:total)
    :atomics.put(peak, 1, max(n, :atomics.get(peak, 1)))

    if n > 536_870_912 do
      File.write!(
        output <> ".failure.json",
        Jason.encode!(%{
          guard: "sampled_memory",
          qualification_passed: false,
          elapsed_ms: System.monotonic_time(:millisecond) - started,
          bytes: n
        })
      )

      System.halt(137)
    end
  end)
end)

spawn_link(fn ->
  Process.sleep(max(0, 30_000 - (System.monotonic_time(:millisecond) - started)))

  File.write!(
    output <> ".failure.json",
    Jason.encode!(%{
      guard: "30_second_deadline",
      qualification_passed: false,
      elapsed_ms: System.monotonic_time(:millisecond) - started
    })
  )

  System.halt(124)
end)

for path <-
      ~w(managed_metadata.ex managed_metadata_shapes.exs managed_metadata_binary.ex managed_metadata_binary_shapes.exs managed_metadata_adaptive.ex managed_metadata_adaptive_leaves.ex) do
  Code.require_file(path, __DIR__)
end

Code.require_file("../../extensions/knowledge/src/notes.ex", __DIR__)
Code.require_file("storage_workload.ex", __DIR__)
Code.require_file("managed_metadata_adaptive_cases.ex", __DIR__)

if job == "msgpax_controls" or (job == "pages" and List.last(input) == "msgpax") do
  true = Code.ensure_loaded?(Msgpax)

  for path <- Path.wildcard(Path.join(Path.dirname(:code.which(Msgpax)), "Elixir.Msgpax*.beam")) do
    {:module, module} =
      Enum.find(:beam_lib.info(String.to_charlist(path)), &match?({:module, _}, &1))

    Code.ensure_loaded!(module)
  end

  Code.require_file("managed_metadata_adaptive_msgpax.ex", __DIR__)
end

if job == "tests" do
  ExUnit.start(autorun: false, max_cases: 1)
  Code.require_file("../../test/dev/managed_metadata_adaptive_test.exs", __DIR__)
end

files =
  Path.wildcard(Path.join(__DIR__, "managed_metadata*.ex*")) ++
    [__ENV__.file, Path.expand("../../test/dev/managed_metadata_adaptive_test.exs", __DIR__)] ++
    if(job == "model",
      do: [
        Path.join(__DIR__, "storage_workload.ex"),
        Path.expand("../../extensions/knowledge/src/notes.ex", __DIR__)
      ],
      else: []
    ) ++ if(job == "pages", do: [hd(input)], else: [])

modules =
  :code.all_loaded()
  |> Enum.map(&elem(&1, 0))
  |> Enum.filter(fn m ->
    String.starts_with?(Atom.to_string(m), [
      "Elixir.Ipse.Development.ManagedMetadata",
      "Elixir.Msgpax",
      "Elixir.IpseKnowledge.Notes"
    ])
  end)

modules =
  Enum.uniq(
    modules ++
      [
        Ipse.JSON,
        Ipse.Extension.Collection.Migration,
        Ipse.Extension.ManagedRecipe,
        Jason,
        Ipse.Development.StorageWorkload
      ]
  )

Enum.each(modules, &Code.ensure_loaded!/1)

binding = fn ->
  %{
    source_sha256: Map.new(files, &{&1, Ipse.JSON.sha256(File.read!(&1))}),
    module_md5:
      Map.new(modules, &{Atom.to_string(&1), Base.encode16(&1.module_info(:md5), case: :lower)}),
    elixir: System.version(),
    otp: System.otp_release(),
    schedulers: System.schedulers_online()
  }
end

before = binding.()
File.write!(output <> ".started.json", Jason.encode!(%{job: job, input: input, binding: before}))

try do
  result =
    case job do
      "deadline_control" ->
        Process.sleep(31_000)
        raise "deadline guard failed"

      "msgpax_controls" ->
        apply(Ipse.Development.ManagedMetadata.AdaptiveMsgpax, :controls, [])

      "model" ->
        Ipse.Development.ManagedMetadata.AdaptiveCases.model()

      "tests" ->
        ExUnit.run()

      "pages" ->
        [model_file, population, kind, clock, retirement, dictionary, compare] = input
        model = File.read!(model_file) |> Jason.decode!()

        config =
          Ipse.Development.ManagedMetadata.AdaptiveCases.config(population, model["result"])

        kind =
          Enum.find(
            [:live, :anchor_full, :anchor_native_candidate],
            &(Atom.to_string(&1) == kind)
          )

        clock =
          Enum.find(
            [:calendar_2026, :safe_width, :bounded_fixture, :four_safe_clocks],
            &(Atom.to_string(&1) == clock)
          )

        retirement =
          Enum.find([:none, :sticky_clock, :target_witness], &(Atom.to_string(&1) == retirement))

        {rows, catalog} =
          if kind == :live,
            do: Ipse.Development.ManagedMetadata.AdaptiveCases.live(config, clock, dictionary),
            else:
              {Ipse.Development.ManagedMetadata.AdaptiveCases.anchors(
                 config,
                 clock,
                 retirement,
                 kind
               ), nil}

        Ipse.Development.ManagedMetadata.AdaptiveCases.measure(
          kind,
          rows,
          catalog,
          compare == "msgpax"
        )
        |> Map.merge(%{
          population: population,
          config: config,
          public_payload_accounting_bytes_each: 6144,
          public_payloads_materialized: false,
          model_input_sha256: Ipse.JSON.sha256(File.read!(model_file))
        })
    end

  after_binding = binding.()
  true = before == after_binding

  report = %{
    job: job,
    input: input,
    result: result,
    elapsed_ms: System.monotonic_time(:millisecond) - started,
    peak_sampled_memory_bytes: :atomics.get(peak, 1),
    binding_before: before,
    binding_after: after_binding,
    model_calls: 0,
    native_calls: 0,
    actual_publications: 0,
    qualification_passed: false
  }

  File.write!(output, Jason.encode!(report, pretty: true) <> "\n")
  if job == "tests" and result.failures > 0, do: System.halt(1)
rescue
  error ->
    File.write!(
      output <> ".failure.json",
      Jason.encode!(%{
        error: Exception.message(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__),
        binding: before,
        qualification_passed: false
      })
    )

    reraise error, __STACKTRACE__
end
