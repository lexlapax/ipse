defmodule CompareExistingWordExtractor do
  @base "_build/verification/word-independent-oracle-20261105-01"
  @artifact @base <> "/comparison/corpus-state-documents"
  @body "word/document.xml"

  def run do
    oracle_bytes = File.read!(@base <> "/author/expected-oracle-v2.json")
    true = sha(oracle_bytes) == "e2af13b29bacd36da26490053f1f2b86b6ab37f0c418d43f553537ceb7851a47"
    true = sha(File.read!(@base <> "/checker/ORACLE-VERDICT-V2.md")) == "24aab8d8d6eccabca80a49769ab8a654b93f2792565569262131bf8095fadee7"
    true = sha(File.read!(@base <> "/checker/pure-check-receipt-v2.json")) == "0161cbbab7313e5f8d52926067903010c075ae389e37b75386a4b7299133eb71"
    oracle = :json.decode(oracle_bytes)
    artifact_before = inventory!()
    false = Enum.any?(Application.started_applications(), fn {name, _, _} -> name == :ipse end)
    Code.prepend_path(Path.expand(@artifact <> "/ebin"))
    Code.ensure_loaded!(IpseKnowledge.Documents)
    true = String.starts_with?(IpseKnowledge.Documents |> :code.which() |> List.to_string(), Path.expand(@artifact <> "/ebin/"))
    out = @base <> "/comparison/first-outcomes"
    :ok = File.mkdir(out)
    :ok = File.chmod(out, 0o700)
    results = Enum.map(oracle["sources"], fn expected ->
      original = File.read!(expected["original_path"])
      true = byte_size(original) == expected["original_bytes"] and sha(original) == expected["original_sha256"]
      extraction = IpseKnowledge.Documents.extract(original, expected["id"] <> ".docx")
      raw = case extraction do
        {:ok, document} -> %{"kind" => "extracted", "document" => document}
        {:error, reason} -> %{"kind" => "refused", "reason" => inspect(reason)}
        other -> %{"kind" => "unexpected_result", "result" => inspect(other)}
      end
      write!(out <> "/" <> expected["id"] <> "-extraction.json", raw)
      result = case extraction do
        {:ok, document} -> compare_document(expected, document, out)
        _ -> %{"id" => expected["id"], "bounded_logical_agreement" => false, "outcome" => raw}
      end
      true = sha(File.read!(expected["original_path"])) == expected["original_sha256"]
      result
    end)
    true = length(results) == 12
    artifact_after = inventory!()
    true = artifact_before == artifact_after
    false = Enum.any?(Application.started_applications(), fn {name, _, _} -> name == :ipse end)
    complete = Enum.all?(results, & &1["bounded_logical_agreement"])
    report = %{"scope" => "all-12 exposed-remediation pure extraction and State/Collection payload comparisons; no commit/installed/model/renderer",
      "oracle_sha256" => sha(oracle_bytes), "artifact_manifest_sha256" => sha(File.read!(@artifact <> "/extension.json")),
      "artifact_inventory" => artifact_before, "artifact_unchanged" => true, "runtime" => %{"elixir" => System.version(), "otp" => List.to_string(:erlang.system_info(:otp_release))},
      "sources" => results, "source_count" => 12, "bounded_logical_agreement" => complete,
      "historical_full_locators_unchanged_unverified" => 62, "revision_kind_id_product_fields" => "unrepresented/unverified",
      "fresh_held_out_quality" => false, "installed_qualification" => false, "semantic_answer_quality" => "not_measured"}
    write!(@base <> "/comparison/first-comparison-receipt.json", report)
    IO.puts("RECORDED all 12 first outcomes; bounded logical matches #{Enum.count(results, & &1["bounded_logical_agreement"])}/12; installed and answer quality unmeasured")
    System.halt(if complete, do: 0, else: 1)
  end

  defp compare_document(expected, document, out) do
    wanted = Enum.map(expected["blocks"], fn block ->
      segment = %{"text" => block["text"], "locator" => locator(block)}
      case block["locator_basis"]["heading_style"] do
        "Heading1" -> Map.put(segment, "style", "Heading1")
        _ -> segment
      end
    end)
    segments = document["segments"]
    text = if is_list(segments), do: Enum.map_join(segments, "\n", & &1["text"]), else: ""
    checks = %{"exact_original_identity" => document["original_sha256"] == expected["original_sha256"] and document["original_bytes"] == expected["original_bytes"],
      "exact_recipe" => document["extraction_version"] == "ipse-documents-v17", "all_ordered_text_blocks" => is_list(segments) and Enum.map(segments, & &1["text"]) == Enum.map(wanted, & &1["text"]),
      "all_exact_segments_and_locators" => segments === wanted, "complete_joined_text" => text === expected["text"],
      "revision_policy" => document["revision_policy"] == "insertions_included_deletions_excluded", "visibility_policy" => document["visibility_policy"] == "bounded_style_and_direct_hidden_excluded"}
    payloads = for {profile, maximum, chunking} <- [{"state", 8192, 1}, {"collection", 65536, 2}] do
      actual = IpseKnowledge.Documents.source_payload(document, maximum, chunking)
      raw = case actual do
        {:ok, payload} -> %{"kind" => "payload", "value" => payload}
        {:error, reason} -> %{"kind" => "refused", "reason" => inspect(reason)}
      end
      write!(out <> "/" <> expected["id"] <> "-" <> profile <> "-payload.json", raw)
      case actual do
        {:ok, payload} ->
          spans = Enum.map(expected["blocks"], fn block ->
            [start, finish] = block["document_span"]
            %{"start_byte" => start, "end_byte" => finish, "text_sha256" => sha(block["text"]), "locator" => locator(block)}
          end)
          receipt = payload["document"]
          equal = payload["text"] === expected["text"] and receipt["segments"] === spans and receipt["original_sha256"] == expected["original_sha256"] and receipt["original_bytes"] == expected["original_bytes"] and receipt["extraction_version"] == "ipse-documents-v17" and receipt["status"] == document["status"] and receipt["warnings"] == document["warnings"]
          %{"profile" => profile, "exact_payload_text_spans_locators_and_identity" => equal, "outcome" => "payload"}
        _ -> %{"profile" => profile, "exact_payload_text_spans_locators_and_identity" => false, "outcome" => raw}
      end
    end
    %{"id" => expected["id"], "checks" => checks, "payload_profiles" => payloads,
      "expected_blocks" => length(wanted), "observed_blocks" => if(is_list(segments), do: length(segments), else: 0),
      "extraction_status" => document["status"], "warnings" => document["warnings"],
      "bounded_logical_agreement" => Enum.all?(checks, &elem(&1, 1)) and Enum.all?(payloads, & &1["exact_payload_text_spans_locators_and_identity"])}
  end

  defp locator(block) do
    basis = block["locator_basis"]
    base = %{"kind" => if(Map.has_key?(basis, "table"), do: "table_cell", else: "paragraph"), "part" => block["part"], "paragraph" => basis["part_paragraph"]}
    base = Map.merge(base, Map.take(basis, ~w(table row cell)))
    anchor = %{"kind" => "paragraph", "part" => @body, "paragraph" => 10}
    cond do
      block["part"] == "word/footnotes.xml" -> Map.merge(base, %{"annotation_id" => basis["note_id"], "reference_site" => Map.put(anchor, "byte_offset", 17)})
      block["part"] == "word/comments.xml" -> Map.merge(base, %{"annotation_id" => basis["comment_id"], "reference_site" => Map.put(anchor, "byte_offset", 32), "reference_range" => Map.merge(anchor, %{"start_byte" => 17, "end_byte" => 32})})
      true -> base
    end
  end

  defp inventory! do
    pins = File.read!(@base <> "/comparison/artifact-preimages.sha256")
    true = sha(pins) == "ea044a224dd10e2c2b95831bda94a9dcab3d61fb05d4d36f514f42c60522d996"
    rows = pins |> String.split("\n", trim: true) |> Enum.map(fn line ->
      [digest, path] = String.split(line, "  ", parts: 2)
      true = String.starts_with?(path, @artifact <> "/") and sha(File.read!(path)) == digest
      %{"path" => path, "sha256" => digest}
    end)
    true = length(rows) == 28
    rows
  end
  defp sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp write!(path, value), do: File.write!(path, [Jason.encode!(value), "\n"], [:exclusive])
end

CompareExistingWordExtractor.run()
