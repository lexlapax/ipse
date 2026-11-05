defmodule WordRawPackageReader do
  require Record
  Record.defrecordp(:element, :xmlElement, Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl"))
  Record.defrecordp(:attribute, :xmlAttribute, Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl"))
  Record.defrecordp(:text_node, :xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl"))

  @base "_build/verification/word-independent-oracle-20261105-01/author"
  @pins "docs/archive/2026-10-26-p30-p31-implementation/word-independent-extraction-20261104/first-v16/input-pins.json"
  @fixed ["[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/styles.xml", "word/numbering.xml", "word/comments.xml", "word/footnotes.xml", "word/endnotes.xml", "word/_rels/document.xml.rels"]

  def run do
    false = File.exists?(Path.join(@base, "raw"))
    false = File.exists?(Path.join(@base, "raw-package-index.json"))
    pins = @pins |> File.read!() |> :json.decode()
    sources = pins["sources"]
    true = length(sources) == 12
    true = Enum.map(sources, & &1["id"]) == Enum.map(21..30, &"D0#{&1}") ++ ["V003-v1", "V003-v2"]
    :ok = File.mkdir(Path.join(@base, "raw"))
    rows = Enum.map(sources, &read_source/1)
    write_json(Path.join(@base, "raw-package-index.json"), %{"version" => 1, "reader" => "raw-package-reader-1", "scope" => "12 exposed public remediation inputs; no candidate or gold", "sources" => rows})
  end

  defp read_source(pin) do
    true = pin["path"] == "dev/fixtures/knowledge-qualification/documents/sources/#{pin["id"]}.docx"
    true = pin["bytes"] <= 16_384
    bin = File.read!(pin["path"])
    true = byte_size(bin) == pin["bytes"]
    true = sha(bin) == pin["sha256"]
    {:ok, table} = :zip.table(bin)
    entries = Enum.filter(table, &(elem(&1, 0) == :zip_file))
    true = length(entries) <= 32
    names = Enum.map(entries, &(elem(&1, 1) |> List.to_string()))
    true = length(Enum.uniq(names)) == length(names)
    true = Enum.all?(names, &allowed_part?/1)
    true = Enum.all?(entries, &(elem(elem(&1, 2), 1) <= 65_536))
    true = Enum.sum(Enum.map(entries, &elem(elem(&1, 2), 1))) <= 1_048_576
    {:ok, extracted} = :zip.extract(bin, [:memory])
    parts = Enum.map(extracted, fn {name, xml} ->
      part = List.to_string(name)
      true = allowed_part?(part)
      true = byte_size(xml) <= 65_536
      true = String.valid?(xml)
      false = Regex.match?(~r/<!\s*(?:DOCTYPE|ENTITY)/i, xml)
      fetch = fn _, _ -> raise "external XML fetch refused" end
      {tree, tail} = :xmerl_scan.string(:binary.bin_to_list(xml), [{:quiet, true}, {:validation, false}, {:fetch_fun, fetch}])
      true = String.trim(List.to_string(tail)) == ""
      raw_path = Path.join([@base, "raw", pin["id"] <> "--" <> String.replace(part, "/", "__")])
      File.write!(raw_path, xml, [:exclusive])
      nodes = walk(tree, "", 1)
      node_path = raw_path <> ".nodes.json"
      write_json(node_path, nodes)
      %{"part" => part, "bytes" => byte_size(xml), "sha256" => sha(xml), "raw_path" => raw_path, "nodes_path" => node_path}
    end)
    IO.puts("#{pin["id"]}: original #{pin["bytes"]} bytes; #{length(parts)} raw XML parts")
    Map.put(pin, "parts", parts)
  end

  defp walk(node, parent, ordinal) when elem(node, 0) == :xmlElement do
    name = node |> element(:name) |> Atom.to_string()
    path = parent <> "/" <> name <> "[#{ordinal}]"
    attrs = Enum.map(element(node, :attributes), fn attr -> %{"name" => attribute(attr, :name) |> Atom.to_string(), "value" => attribute(attr, :value) |> List.to_string()} end)
    {children, _} = Enum.map_reduce(element(node, :content), %{}, fn child, counts ->
      kind = case elem(child, 0) do
        :xmlElement -> child |> element(:name) |> Atom.to_string()
        :xmlText -> "text()"
        other -> Atom.to_string(other)
      end
      n = Map.get(counts, kind, 0) + 1
      {walk(child, path, n), Map.put(counts, kind, n)}
    end)
    %{"node" => path, "name" => name, "attributes" => attrs, "children" => children}
  end

  defp walk(node, parent, ordinal) when elem(node, 0) == :xmlText do
    %{"node" => parent <> "/text()[#{ordinal}]", "text" => text_node(node, :value) |> List.to_string()}
  end

  defp walk(node, parent, ordinal), do: %{"node" => parent <> "/#{elem(node, 0)}[#{ordinal}]", "kind" => Atom.to_string(elem(node, 0))}
  defp allowed_part?(part), do: part in @fixed or Regex.match?(~r/\Aword\/(?:header|footer)[1-9][0-9]?\.xml\z/, part)
  defp sha(bin), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)
  defp write_json(path, value), do: File.write!(path, [:json.encode(value), "\n"], [:exclusive])
end

WordRawPackageReader.run()
