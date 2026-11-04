import ExUnit.Assertions
ExUnit.start(autorun: false)
cohort = __DIR__
Code.require_file(Path.join(cohort,"source/test/support/research_managed_wire.exs"))
helper = Path.join(cohort,"source/test/support/research_managed_coexistence.exs")
{:__block__, _, items} = Code.string_to_quoted!(File.read!(helper))
modules = Enum.filter(items, &match?({:defmodule, _, _}, &1))
[mod] = modules
Code.compile_quoted(mod)
body = {:__block__, [], Enum.reject(items, &match?({:defmodule, _, _}, &1))}
quoted = quote do
  defmodule MixedWireDeferredFixture do
    def never_called do
      unquote(body)
    end
  end
end
source = Path.join(cohort, "deferred-helper.ex")
File.write!(source, Macro.to_string(quoted))
out = Path.join(cohort,"compile-helper/ebin")
File.mkdir_p!(out)
{:ok, _, diagnostics} = Kernel.ParallelCompiler.compile_to_path([source],out,return_diagnostics: true)
assert diagnostics == [] or diagnostics == %{compile_warnings: [],runtime_warnings: []}
canonical = Path.expand("test/support/managed_literal_ab_seed.exs") |> File.read!() |> Code.string_to_quoted!()
changed = Path.join(cohort,"source/test/support/managed_literal_ab_seed.exs") |> File.read!() |> Code.string_to_quoted!()
{:__block__, meta, original_items} = canonical
{:__block__, _, changed_items} = changed
index = Enum.find_index(original_items, fn
  {{:., _, [{:__aliases__, _, [:File]}, :write!]}, _, [{:config_path, _, _} | _]} -> true
  _ -> false
end)
true = is_integer(index)
reconstructed = Enum.take(changed_items,index) ++ [Enum.at(original_items,index)] ++ Enum.drop(changed_items,index+2)
assert Macro.to_string({:__block__,meta,reconstructed}) == Macro.to_string(canonical)
assert ResearchMixedWire.message(1)["tool_calls"] |> hd() |> get_in(["function","arguments"]) == ResearchMixedWire.query_args()
assert ResearchMixedWire.message(3)["tool_calls"] |> hd() |> get_in(["function","arguments"]) == ResearchMixedWire.negative_args()
refute File.read!(helper) =~ "provider_module:"
assert File.read!(helper) =~ "refute Map.has_key?(config, :provider_module)"
refute Enum.any?(Application.started_applications(),fn {name,_,_}->name==:ipse end)
IO.puts("full_helper_deferred_strict_compile=pass seed_default_reconstruction_AST_identical=true source_and_quote_literal_protocol=true provider_module_absent=true app_started=false native_calls=0 actual_runs=0")
