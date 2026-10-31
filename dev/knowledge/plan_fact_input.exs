defmodule Ipse.Development.PlanFactInput do
  @moduledoc false
  @max_bytes 256 * 1024

  def run([artifact, source_path, rows_path]) do
    path = Path.join(Path.expand(artifact), "ebin")
    true = File.dir?(path)
    Code.prepend_path(path)

    source_input = read_json!(source_path)
    rows = read_json!(rows_path)
    evidence = IpseKnowledge.Evidence
    projection = IpseKnowledge.Store.Collection.Projection

    source =
      if apply(evidence, :valid_source?, [source_input]) do
        source_input
      else
        {:ok, value} = apply(evidence, :collection_source, [source_input])
        value
      end

    {:ok, %{pages: pages, manifest: manifest}} =
      apply(projection, :fact_input_pages, [source, rows])

    true = pages != []

    output = %{
      "version" => 1,
      "draft_id" => :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower),
      "source_id" => source["source_id"],
      "manifest" => manifest,
      "pages" => pages
    }

    IO.puts(IO.iodata_to_binary(JSON.encode!(output)))
  end

  def run(_),
    do:
      raise(
        "usage: mix run --no-start dev/knowledge/plan_fact_input.exs ARTIFACT SOURCE_JSON ROWS_JSON"
      )

  defp read_json!(path) do
    stat = File.stat!(path)
    true = stat.type == :regular and stat.size <= @max_bytes
    bytes = File.read!(path)
    true = byte_size(bytes) <= @max_bytes
    {:ok, value} = Ipse.JSON.decode_unique(bytes)
    value
  end
end

Ipse.Development.PlanFactInput.run(System.argv())
