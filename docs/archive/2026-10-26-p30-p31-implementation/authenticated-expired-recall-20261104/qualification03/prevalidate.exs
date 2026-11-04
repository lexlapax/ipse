root = Path.expand("../..", __DIR__)

defmodule RenewalHelperClosure do
  def visit(path, seen) do
    path = Path.expand(path)

    if MapSet.member?(seen, path) do
      seen
    else
      true = File.regular?(path)
      {:ok, ast} = path |> File.read!() |> Code.string_to_quoted(file: path)

      {_, dependencies} =
        Macro.prewalk(ast, [], fn
          {{:., _, [{:__aliases__, _, [:Code]}, :require_file]}, _, [relative, {:__DIR__, _, _}]} =
              node,
          dependencies
          when is_binary(relative) ->
            {node, [Path.expand(relative, Path.dirname(path)) | dependencies]}

          node, dependencies ->
            {node, dependencies}
        end)

      Enum.reduce(dependencies, MapSet.put(seen, path), &visit/2)
    end
  end
end

paths =
  [
    Path.join(root, "test/support/managed_clock_late_seed.exs"),
    Path.join(__DIR__, "renewal-fixtures/managed_clock_recall_renewal.exs")
  ]
  |> Enum.reduce(MapSet.new(), &RenewalHelperClosure.visit/2)
  |> MapSet.to_list()
  |> Enum.sort()

for name <- ["focused-clock-test.exs", "renewal-entry.exs"] do
  {:ok, _} = __DIR__ |> Path.join(name) |> File.read!() |> Code.string_to_quoted()
end

beams =
  Path.wildcard(Path.join([__DIR__, "helper-ebin", "*.beam"]))
  |> Enum.map(&Path.basename/1)

true = length(beams) == 3
{:module, Jason} = Code.ensure_loaded(Jason)

File.write!(Path.join(__DIR__, "helper-closure.paths"), Enum.join(paths, "\n") <> "\n", [
  :exclusive
])

File.write!(
  Path.join(__DIR__, "prevalidation-result.json"),
  Jason.encode!(%{
    "static_literal_require_file_closure_count" => length(paths),
    "strict_compiled_helper_modules" => beams,
    "application_started" => false,
    "session_or_native_or_provider_started" => false,
    "retained_cohort_access" => false
  }),
  [:exclusive]
)

IO.puts("HELPER_CLOSURE_PREVALIDATION_PASS")
