parent = Path.expand("_build/document-embedding-admission-inventory-sol-20261029")
target = Path.expand("_build/document-embedding-gate-diagnostic-sol-20261029")
false = File.exists?(target)
{:ok, _} = File.cp_r(parent, target)
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)

diag = """
  defp document_diag(stage, value) do
    status = case value do
      {:ok, _} -> :ok
      {:reply, :ok, _} -> :ok
      {:reply, {:error, _}, _} -> :error
      {:error, _} -> :error
      value when is_boolean(value) -> value
      value when value in [:ok, :error, :authorized, :pending, :checking, :denied, :unknown, :invalid] -> value
      _ -> :other
    end
    IO.puts("DOCUMENT_GATE_DIAGNOSTIC " <> inspect(%{stage: stage, status: status}))
    value
  end
"""

with_diag = fn source ->
  source = String.trim_trailing(source)
  true = String.ends_with?(source, "end")
  binary_part(source, 0, byte_size(source) - 3) <> diag <> "end\n"
end

replace_once = fn source, before, after_text ->
  true = String.contains?(source, before)
  String.replace(source, before, after_text, global: false)
end

module_file = "lib/ipse/session/document_embedding.ex"
source = File.read!(Path.join(target, module_file))

source =
  replace_once.(
    source,
    "  def before_dispatch(data, wire_facts) do\n",
    "  def before_dispatch(data, wire_facts) do\n    document_diag(:before_entry, :ok)\n"
  )

source =
  replace_once.(
    source,
    "        fn _ ->\n",
    "        fn _ ->\n          document_diag(:identity_callback, :ok)\n"
  )

source =
  replace_once.(
    source,
    "            fn _, read ->\n",
    "            fn _, read ->\n              document_diag(:native_callback, :ok)\n"
  )

source =
  replace_once.(
    source,
    "                     DocumentSourceUse.authenticate(\n",
    "                     document_diag(:native_auth, DocumentSourceUse.authenticate(\n"
  )

source =
  replace_once.(
    source,
    "                       data.document_source.selection\n                     ),",
    "                       data.document_source.selection\n                     )),"
  )

source =
  replace_once.(
    source,
    "                     GenServer.call(\n",
    "                     document_diag(:admit_rpc, GenServer.call(\n"
  )

source =
  replace_once.(
    source,
    "                       5_000\n                     ),",
    "                       5_000\n                     )),"
  )

source = with_diag.(source)
File.write!(Path.join(target, module_file), source)

dispatch_file = "lib/ipse/session/inference_dispatch.ex"
source = File.read!(Path.join(target, dispatch_file))

source =
  replace_once.(
    source,
    "true <- s.task != nil,",
    "true <- document_diag(:wire_task, s.task != nil),"
  )

source =
  replace_once.(
    source,
    "true <- caller == s.task.pid or Session.Resources.authorized_effect?(s.task.pid, caller),",
    "true <- document_diag(:wire_caller, caller == s.task.pid or Session.Resources.authorized_effect?(s.task.pid, caller)),"
  )

source =
  replace_once.(
    source,
    "{:ok, runtime, input, tools, ^admission} <- view(s, phase),",
    "{:ok, runtime, input, tools, ^admission} <- document_diag(:wire_view, view(s, phase)),"
  )

source =
  replace_once.(
    source,
    "true <- binding_current?(s, phase, expected),",
    "true <- document_diag(:wire_binding_current, binding_current?(s, phase, expected)),"
  )

source =
  replace_once.(
    source,
    "true <- is_map(facts) and facts === wire(runtime, input, tools, phase),",
    "true <- document_diag(:wire_equal, is_map(facts) and facts === wire(runtime, input, tools, phase)),"
  )

source =
  replace_once.(
    source,
    "    with true <- phase == \"embedding.create\" and not is_nil(document_source(s, phase)),",
    "    document_diag(:document_admit_entry, :ok)\n    with true <- document_diag(:document_admit_source, phase == \"embedding.create\" and not is_nil(document_source(s, phase))),"
  )

source = with_diag.(source)
File.write!(Path.join(target, dispatch_file), source)

session_file = "lib/ipse/session.ex"
source = File.read!(Path.join(target, session_file))

before = """
    if caller == worker or Ipse.Session.Resources.authorized_effect?(worker, caller),
      do: Ipse.Session.InferenceDispatch.document_admit(s, caller, phase, admission, expected, wire, sources),
"""

after_text = """
    if document_diag(:session_caller_authorized, caller == worker or Ipse.Session.Resources.authorized_effect?(worker, caller)),
      do: Ipse.Session.InferenceDispatch.document_admit(s, caller, phase, admission, expected, wire, sources),
"""

source = replace_once.(source, before, after_text)
source = with_diag.(source)
File.write!(Path.join(target, session_file), source)

global_file = "lib/ipse/inference_dispatch.ex"
source = File.read!(Path.join(target, global_file))

source =
  replace_once.(
    source,
    "      {^ref, :document_wire, worker, challenge, facts} ->\n",
    "      {^ref, :document_wire, worker, challenge, facts} ->\n        document_diag(:await_document_wire, :ok)\n"
  )

source =
  replace_once.(
    source,
    "      context[:document_source] != nil ->\n",
    "      context[:document_source] != nil ->\n        document_diag(:document_transport_entry, :ok)\n"
  )

source =
  replace_once.(
    source,
    "          if status == :authorized,\n",
    "          document_diag(:capture_status, status)\n          if status == :authorized,\n"
  )

source = with_diag.(source)
File.write!(Path.join(target, global_file), source)

files = Enum.map([module_file, dispatch_file, session_file, global_file], &Path.join(target, &1))

Enum.each(files, fn file ->
  File.write!(file, IO.iodata_to_binary(Code.format_file!(file)) <> "\n")
end)

Code.compiler_options(ignore_module_conflict: true)

{:ok, _, %{compile_warnings: [], runtime_warnings: []}} =
  Kernel.ParallelCompiler.compile_to_path(files, target <> "/_build/dev/lib/ipse/ebin",
    return_diagnostics: true
  )

IO.puts(
  "PRIVATE_DIAGNOSTIC_FORK strict compile empty diagnostics; four source owners logging bounded stages only; no production edits/effects"
)
