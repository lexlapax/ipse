ExUnit.start(autorun: false)
[path, digest] = System.argv()
true = Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) == digest
d = :json.decode(File.read!(path))
true = d["reviewed"] === true
true = d["kind"] == "research_origin_coherent_sdk_v1"
true = File.dir?(d["root"]) and File.ls!(d["root"]) == []

for module <- [Ipse.Development.Fixtures.Knowledge, Ipse.Test.ResearchOriginJourney] do
  Code.ensure_loaded!(module)
  true = Path.dirname(to_string(:code.which(module))) == d["helper_ebin"]
end

try do
  result =
    Ipse.Test.ResearchOriginJourney.main(
      d["root"],
      d["research"]["root"],
      d["corpus"]["root"],
      d["options"]
    )

  File.write!(d["result"], :json.encode(result), [:exclusive])
after
  input = Process.whereis(Ipse.Session.Input)
  input_empty = if input, do: :sys.get_state(input).entries === %{}, else: true

  File.write!(d["result"] <> ".input.json", :json.encode(%{input_entries_empty: input_empty}), [
    :exclusive
  ])
end
