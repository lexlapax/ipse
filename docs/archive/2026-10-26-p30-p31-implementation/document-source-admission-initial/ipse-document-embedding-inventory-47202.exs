source = "_build/document-embedding-admission-clock-sol-20261029"
target = "_build/document-embedding-admission-inventory-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
app = target <> "/_build/dev/lib/ipse/ebin/ipse.app"
{:ok, [{:application, :ipse, props}]} = :file.consult(String.to_charlist(app))
modules = Path.wildcard(Path.dirname(app) <> "/*.beam") |> Enum.map(fn path ->
  info = :beam_lib.info(String.to_charlist(path))
  Keyword.fetch!(info, :module)
end) |> Enum.sort()
true = length(Enum.uniq(modules)) === length(modules)
added = modules -- props[:modules]
removed = props[:modules] -- modules
true = Enum.sort(added) === Enum.sort([Ipse.Extension.Collection.DocumentSourceUse, Ipse.Session.DocumentEmbedding])
true = removed === []
File.cp!(app, target <> "/ipse.app-before-inventory")
File.write!(app, :io_lib.format(~c"~p.~n", [{:application, :ipse, Keyword.put(props, :modules, modules)}]))
{:ok, [{:application, :ipse, after_props}]} = :file.consult(String.to_charlist(app))
true = Keyword.delete(props, :modules) === Keyword.delete(after_props, :modules)
true = after_props[:modules] === modules
IO.puts("Application inventory regenerated: #{length(modules)} exact host BEAM modules, #{length(added)} new owners, no removed modules or other property change")
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
{:ok, _} = Application.ensure_all_started(:ipse)
true = Application.spec(:ipse, :modules) === modules
IO.puts("Actual loaded application uses the regenerated complete host inventory")
