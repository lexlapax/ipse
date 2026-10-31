ExUnit.start(autorun: false)
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/ipse/extension/collection_normalizer_v3_integration_test.exs")

alias Ipse.Extension.{ManagedRecipe, ProjectIdentity}
alias Ipse.Extension.Collection.ObservedRead
alias Ipse.Extension.CollectionNormalizerV3IntegrationTest, as: Fixture
alias Ipse.Test.NormalizerV3Fixture, as: Values
alias Ipse.Usage

base = Path.join(System.tmp_dir!(), "ipse-historical-answer-" <> Usage.id())

for path <- [base, base <> "/home", base <> "/work"] do
  File.mkdir!(path)
  File.chmod!(path, 0o700)
end

try do
  {:ok, binding} = ProjectIdentity.admit(base <> "/home", base <> "/work", :folder)

  c = %{
    home: base <> "/home",
    cwd: base <> "/work",
    root: base <> "/collections",
    namespace: Values.namespace(),
    binding: binding
  }

  scope = fn initialize ->
    %{
      namespace: c.namespace,
      format: "managed-metadata-v3",
      operation_id: Usage.id(),
      initialize: initialize
    }
  end

  {:ok, _} = Fixture.publish(c, Fixture.options(1, 0), scope.(true), first: true)
  opts = Fixture.options(2, 1)
  [original] = opts.verified_sources
  source = %{original | "origin" => "native_operator_answer", "kind" => "input.operator_answer"}
  {:ok, lineage} = ManagedRecipe.source_identity(source)
  [change] = opts.request["changes"]

  value =
    change["value"]
    |> Map.put("id", lineage)
    |> Map.put("lineage", lineage)
    |> put_in(["evidence", "sources"], [source])

  request =
    put_in(opts.request, ["changes"], [%{change | "key" => "note." <> lineage, "value" => value}])

  # Reconstruct an explicitly permissive historical recipe as well as its
  # interpreter. A present-day recipe must not mint the legacy literal first.
  constraints =
    Map.update!(
      opts.constraints,
      "source_categories",
      &Enum.sort(Enum.uniq(["native_operator_answer" | &1]))
    )

  recipe =
    opts.recipe
    |> Map.put("constraints_sha256", Ipse.JSON.digest([constraints]))
    |> Map.update!("rules", fn rules ->
      Enum.map(rules, fn rule ->
        Map.update!(rule, "origins", &Enum.sort(Enum.uniq(["native_operator_answer" | &1])))
      end)
    end)

  opts = %{
    opts
    | request: request,
      verified_sources: [source],
      constraints: constraints,
      recipe: recipe
  }

  path = "lib/ipse/extension/managed_recipe.ex"
  current = File.read!(path)
  guard = "@strong ~w(native_operator_assertion typed_host_outcome)"
  1 = length(:binary.matches(current, guard))

  old =
    String.replace(
      current,
      guard,
      "@strong ~w(native_operator_assertion native_operator_answer typed_host_outcome)"
    )

  fragment_guard =
    "proof[\"coverage\"] == \"available\" and proof[\"start_byte\"] == 0 and\n      proof[\"content_sha256\"] == proof[\"quote_sha256\"] and\n      "

  1 = length(:binary.matches(old, fragment_guard))
  old = String.replace(old, fragment_guard, "")

  category_guard =
    "((proof[\"origin\"] == \"typed_host_outcome\" and category == \"ordinary\") or\n         Ipse.Session.OperatorAssertion.asserted_category?(proof, category))"

  1 = length(:binary.matches(old, category_guard))
  old = String.replace(old, category_guard, "is_binary(category)")

  Code.compiler_options(ignore_module_conflict: true)
  Code.compile_string(old, path)
  {:ok, _} = Fixture.publish(c, opts, scope.(false))

  fragment = Fixture.options(3, 2)
  [fragment_original] = fragment.verified_sources

  fragment_source = %{
    fragment_original
    | "start_byte" => 7,
      "end_byte" => 7 + byte_size(fragment_original["quote"]),
      "content_sha256" => Ipse.JSON.sha256("prefix " <> fragment_original["quote"])
  }

  {:ok, fragment_lineage} = ManagedRecipe.source_identity(fragment_source)
  [fragment_change] = fragment.request["changes"]

  fragment_value =
    fragment_change["value"]
    |> Map.put("id", fragment_lineage)
    |> Map.put("lineage", fragment_lineage)
    |> put_in(["evidence", "sources"], [fragment_source])

  fragment_request =
    put_in(fragment.request, ["changes"], [
      %{fragment_change | "key" => "note." <> fragment_lineage, "value" => fragment_value}
    ])

  fragment = %{
    fragment
    | request: fragment_request,
      verified_sources: [fragment_source],
      constraints: opts.constraints,
      recipe: opts.recipe
  }

  {:ok, _} = Fixture.publish(c, fragment, scope.(false))

  selected = %{"op" => "get_record", "key" => "note." <> lineage}

  read = fn selected ->
    ProjectIdentity.with_existing_domain_auth(
      c.home,
      c.cwd,
      c.binding,
      %{namespace: c.namespace, format: "managed-metadata-v3"},
      fn cap, catalog ->
        ObservedRead.managed_record(c.root, c.namespace, selected, cap, catalog, opts.recipe)
      end
    )
  end

  {:ok, historical} = read.(selected)

  [^source] =
    get_in(historical, ["observation", "value", "record", "value", "evidence", "sources"])

  fragment_selected = %{"op" => "get_record", "key" => "note." <> fragment_lineage}
  {:ok, historical_fragment} = read.(fragment_selected)

  [^fragment_source] =
    get_in(historical_fragment, ["observation", "value", "record", "value", "evidence", "sources"])

  Code.compile_string(current, path)
  {:error, :collection_observation_refused} = read.(selected)
  {:error, :collection_observation_refused} = read.(fragment_selected)
  IO.puts("HISTORICAL_SIGNED_RECORDS_REFUSED")
after
  File.rm_rf!(base)
end
