Code.compiler_options(ignore_module_conflict: true)

source_at = fn path ->
  {source, 0} = System.cmd("git", ["show", "4981862:#{path}"])
  source
end

for name <- ~w(profiles notes knowledge/contracts knowledge/records knowledge/decision_policy) do
  path = "extensions/knowledge/src/#{name}.ex"
  Code.compile_string(source_at.(path), "frozen-#{name}.ex")
end

path = "extensions/knowledge/src/knowledge.ex"
source = source_at.(path)
true = length(:binary.matches(source, "@recall_candidates 32")) == 1

Code.compile_string(
  String.replace(source, "@recall_candidates 32", "@recall_candidates 96"),
  path
)

results =
  for variant <- [:original, :short], selected <- [32, 33] do
    notes =
      for n <- 1..33 do
        suffix = String.pad_leading(Integer.to_string(n), 2, "0")

        text =
          if variant == :original, do: "Synthetic note " <> suffix, else: "~N" <> suffix <> "~"

        id = Ipse.JSON.sha256(Integer.to_string(n))

        attrs = %{
          "id" => id,
          "lineage" => id,
          "text" => text,
          "evidence" => %{"quote" => text, "source" => "synthetic-only"},
          "category" => "ordinary",
          "reason" => "admitted fixture",
          "observed_at_ms" => 0,
          "event_at_ms" => nil
        }

        {:ok, note} = IpseKnowledge.Notes.new(attrs, 0)
        {%{"key" => "note." <> id, "revision" => 1, "value" => note}, String.duplicate("a", 32)}
      end

    context = %{
      notes: notes,
      index: Enum.map(notes, fn {row, _} -> Map.take(row, ~w(key revision)) end),
      total: 33,
      next: nil,
      coverage: "complete",
      unavailable: 0
    }

    {:ok, result} =
      IpseKnowledge.Knowledge.recall_projection(
        context,
        Enum.take(notes, selected),
        "knowledge",
        8192
      )

    %{
      "variant" => Atom.to_string(variant),
      "selected" => selected,
      "fits" => result.fits,
      "rendered_bytes" => result.rendered_bytes,
      "items" => length(result.items)
    }
  end

IO.puts(Jason.encode!(results))
