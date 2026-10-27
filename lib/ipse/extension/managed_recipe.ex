defmodule Ipse.Extension.ManagedRecipe do
  @moduledoc """
  Closed declarative extraction for explicitly reviewed managed publications.

  Paths select JSON fields, never files or code. A schema and proof-shaped JSON
  grant no authority: the caller must authenticate every supplied source receipt
  and check the pinned constraint under the publication lock. Extraction ignores
  worker clocks and returns a candidate for host normalization, not eligibility.
  Typed operator choices require a separate exact host receipt; a native answer
  does not approve an assistant's premise or a worker-selected retention policy.
  """
  alias Ipse.JSON

  @keys ~w(version kind key_prefix constraints_sha256 evidence_path lineage_path text_path category_path rules override_prefix)
  @proof ~w(version session_id occurrence_id version_id kind origin coverage path start_byte end_byte quote quote_sha256 content_sha256 receipt_sha256)
  @identity ~w(session_id occurrence_id version_id start_byte end_byte quote_sha256 content_sha256)
  @origins ~w(interactive_operator native_operator_answer unattended_input assistant_proposal typed_host_outcome)
  @strong ~w(interactive_operator native_operator_answer typed_host_outcome)
  @kinds ~w(literal_source proposal operator_override)
  @week 604_800_000
  @error {:error, :managed_recipe_refused}

  def valid?(recipe) do
    keys?(recipe, @keys) and recipe["version"] === 1 and recipe["kind"] in @kinds and
      prefix?(recipe["key_prefix"]) and prefix?(recipe["override_prefix"]) and
      JSON.sha256?(recipe["constraints_sha256"]) and path?(recipe["evidence_path"]) and
      path?(recipe["lineage_path"]) and fields?(recipe) and rules?(recipe) and
      byte_size(Jason.encode!(recipe)) <= 4096
  rescue
    _ -> false
  end

  @doc "The fixed source.identity.v1 projection, byte-identical to the original capture identity."
  def source_identity(proof) do
    if proof?(proof), do: {:ok, pair_hash(Map.take(proof, @identity))}, else: @error
  rescue
    _ -> @error
  end

  @doc "Proposal identity includes exact text; quoting a source never silently accepts a paraphrase."
  def proposal_identity(lineage, text) do
    if JSON.sha256?(lineage) and text?(text, 2048),
      do: {:ok, pair_hash(%{"lineage" => lineage, "text" => text})},
      else: @error
  rescue
    _ -> @error
  end

  @doc "Extract only from closed values and host-authenticated receipt members. No timestamps are trusted."
  def extract(recipe, key, value, verified_sources) do
    with true <- valid?(recipe) and is_map(value),
         :ok <- JSON.validate_object(value),
         true <- is_list(verified_sources) and length(verified_sources) in 1..8,
         true <- length(Enum.uniq(verified_sources)) == length(verified_sources),
         true <- Enum.all?(verified_sources, &proof?/1),
         [proof] <- field(value, recipe["evidence_path"]),
         true <- proof in verified_sources do
      extract_kind(recipe, key, value, proof)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp extract_kind(%{"kind" => "operator_override"}, _key, _value, _proof),
    do: {:error, :managed_recipe_requires_typed_choice}

  defp extract_kind(recipe, key, value, proof) do
    with {:ok, lineage} <- source_identity(proof),
         true <- field(value, recipe["lineage_path"]) == lineage,
         text = field(value, recipe["text_path"]),
         true <- text?(text, 2048),
         category = field(value, recipe["category_path"]),
         rule when is_map(rule) <- Enum.find(recipe["rules"], &(&1["category"] == category)),
         true <- proof["origin"] in rule["origins"],
         {:ok, suffix} <- suffix(recipe["kind"], lineage, text),
         true <- key == recipe["key_prefix"] <> suffix,
         true <- supported?(recipe["kind"], text, category, proof) do
      {:ok,
       %{
         "version" => 1,
         "kind" => recipe["kind"],
         "recipe_sha256" => JSON.digest([recipe]),
         "lineage" => lineage,
         "key" => key,
         "text" => text,
         "category" => category,
         "max_age_ms" => rule["max_age_ms"],
         "sources" => [proof],
         "eligibility" =>
           if(recipe["kind"] == "proposal", do: "never_current", else: "pending_host")
       }}
    else
      _ -> @error
    end
  end

  defp suffix("literal_source", lineage, _text), do: {:ok, lineage}
  defp suffix("proposal", lineage, text), do: proposal_identity(lineage, text)

  defp supported?("proposal", _text, _category, _proof), do: true

  defp supported?("literal_source", text, category, proof) do
    proof["origin"] in @strong and text == proof["quote"] and
      (proof["origin"] != "typed_host_outcome" or category == "ordinary")
  end

  defp fields?(%{"kind" => "operator_override"} = r),
    do: is_nil(r["text_path"]) and is_nil(r["category_path"])

  defp fields?(r), do: path?(r["text_path"]) and path?(r["category_path"])

  defp rules?(%{"kind" => "operator_override", "rules" => rules}), do: rules === []

  defp rules?(r) do
    rules = r["rules"]

    is_list(rules) and length(rules) in 1..8 and
      Enum.all?(rules, fn rule ->
        keys?(rule, ~w(category max_age_ms origins)) and identifier?(rule["category"]) and
          rule["category"] not in ~w(pin history) and origins?(rule["origins"]) and
          age?(r["kind"], rule)
      end) and
      rules == Enum.sort_by(rules, & &1["category"]) and
      length(Enum.uniq_by(rules, & &1["category"])) == length(rules)
  end

  defp age?("proposal", rule),
    do: is_integer(rule["max_age_ms"]) and rule["max_age_ms"] in 1..@week

  defp age?("literal_source", %{"max_age_ms" => nil, "category" => category}),
    do: category in ~w(preference current)

  defp age?("literal_source", rule),
    do: JSON.safe_uint?(rule["max_age_ms"]) and rule["max_age_ms"] > 0

  defp proof?(proof) do
    keys?(proof, @proof) and proof["version"] === 1 and
      Enum.all?(~w(session_id occurrence_id version_id), &id?(proof[&1])) and
      proof["coverage"] in ~w(available partial) and proof["path"] === nil and
      JSON.safe_uint?(proof["start_byte"]) and JSON.safe_uint?(proof["end_byte"]) and
      text?(proof["quote"], 1024) and
      proof["end_byte"] - proof["start_byte"] == byte_size(proof["quote"]) and
      proof["quote_sha256"] == JSON.sha256(proof["quote"]) and
      Enum.all?(~w(content_sha256 receipt_sha256), &JSON.sha256?(proof[&1])) and
      origin_kind?(proof) and byte_size(Jason.encode!(proof)) <= 2048
  end

  defp origin_kind?(%{"kind" => "input.original", "origin" => origin}),
    do: origin in ~w(interactive_operator unattended_input)

  defp origin_kind?(%{"kind" => "input.operator_answer", "origin" => "native_operator_answer"}),
    do: true

  defp origin_kind?(%{"kind" => "answer.original", "origin" => "assistant_proposal"}), do: true
  defp origin_kind?(%{"kind" => "tool.outcome", "origin" => "typed_host_outcome"}), do: true
  defp origin_kind?(_), do: false

  defp pair_hash(value) do
    value
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, item} -> [key, item] end)
    |> Jason.encode!()
    |> JSON.sha256()
  end

  defp field(value, []), do: value
  defp field(value, [key | tail]) when is_map(value), do: field(value[key], tail)
  defp field(_, _), do: nil
  defp path?(path), do: is_list(path) and length(path) in 1..8 and Enum.all?(path, &identifier?/1)

  defp origins?(values),
    do:
      is_list(values) and values != [] and values == Enum.sort(Enum.uniq(values)) and
        Enum.all?(values, &(&1 in @origins))

  defp prefix?(v), do: is_binary(v) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,31}\z/, v)
  defp identifier?(v), do: is_binary(v) and Regex.match?(~r/\A[a-zA-Z0-9_]{1,64}\z/, v)
  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp text?(v, n), do: is_binary(v) and String.valid?(v) and byte_size(v) in 1..n
  defp keys?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
end
