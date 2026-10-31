Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Provider.Ollama.ModelsTest do
  use ExUnit.Case, async: true
  alias Ipse.Provider.Ollama.Models
  alias Ipse.Test.ProviderFixture
  @model "fixture:fixed"
  @sha String.duplicate("a", 64)
  @other String.duplicate("b", 64)

  defp row, do: %{"name" => @model, "model" => @model, "digest" => @sha, "size" => 4096}
  defp version, do: %{"version" => "0.40.13"}
  defp tags, do: %{"models" => [row()]}

  defp show,
    do: %{
      "details" => %{"context_length" => 32768},
      "model_info" => %{
        "general.architecture" => "fixture",
        "fixture.context_length" => 32768,
        "fixture.embedding_length" => 1024
      },
      "capabilities" => ["embedding"],
      "template" => "synthetic template",
      "parameters" => nil,
      "license" => "synthetic upstream license value"
    }

  defp sequence(bodies) do
    ProviderFixture.sequence(
      Enum.map(bodies, fn body ->
        if is_binary(body), do: body, else: Jason.encode!(body)
      end)
    )
  end

  test "read-only scan pins exact metadata and distinguishes an unloaded model" do
    {base, server} = sequence([version(), tags(), show(), %{"models" => []}, tags(), version()])
    assert {:ok, report} = Models.read(base, @model)
    assert report["manifest_sha256"] == @sha
    assert report["artifact_bytes"] == 4096
    assert report["loaded"] == nil
    assert report["effective_context"] == "unverified_not_loaded"
    assert report["local_execution"] == "not_attested"
    assert report["inference_calls"] == 0
    assert report["template_sha256"] == Ipse.JSON.sha256("synthetic template")
    refute Jason.encode!(report) =~ "synthetic upstream license value"
    requests = Task.await(server)

    assert Enum.map(requests, fn {headers, body} ->
             [request | _] = String.split(headers, "\r\n")
             {request, body}
           end) == [
             {"GET /api/version HTTP/1.1", nil},
             {"GET /api/tags HTTP/1.1", nil},
             {"POST /api/show HTTP/1.1", %{"model" => @model, "verbose" => false}},
             {"GET /api/ps HTTP/1.1", nil},
             {"GET /api/tags HTTP/1.1", nil},
             {"GET /api/version HTTP/1.1", nil}
           ]
  end

  test "loaded context remains a service claim tied to the installed manifest" do
    loaded = Map.merge(row(), %{"context_length" => 4096, "size_vram" => 2048})

    {base, server} =
      sequence([version(), tags(), show(), %{"models" => [loaded]}, tags(), version()])

    assert {:ok, report} = Models.read(base, @model)
    assert report["loaded"]["context_length"] == 4096
    assert report["effective_context"] == "reported_by_service"
    assert report["declared_limits"]["model_info"]["fixture.context_length"] == 32768
    assert report["local_execution"] == "not_attested"
    assert length(Task.await(server)) == 6
  end

  test "changed model or runtime during the scan refuses without retry" do
    cases = [
      [
        version(),
        tags(),
        show(),
        %{"models" => []},
        %{"models" => [Map.put(row(), "digest", @other)]}
      ],
      [version(), tags(), show(), %{"models" => []}, tags(), %{"version" => "0.40.14"}]
    ]

    for bodies <- cases do
      {base, server} = sequence(bodies)
      assert {:error, :ollama_metadata_changed} = Models.read(base, @model)
      assert length(Task.await(server)) == length(bodies)
    end
  end

  test "a resident different digest cannot qualify as this installed model" do
    loaded = row() |> Map.put("digest", @other) |> Map.put("context_length", 4096)
    {base, server} = sequence([version(), tags(), show(), %{"models" => [loaded]}])
    assert {:error, :ollama_loaded_model_mismatch} = Models.read(base, @model)
    assert length(Task.await(server)) == 4
  end

  test "missing, ambiguous or aliased selected identities refuse before show" do
    for {rows, error} <- [
          {[], :ollama_model_not_installed},
          {[row(), row()], :ollama_metadata_invalid},
          {[row(), Map.put(row(), "name", "different:fixed")], :ollama_metadata_invalid}
        ] do
      {base, server} = sequence([version(), %{"models" => rows}])
      assert {:error, ^error} = Models.read(base, @model)
      assert length(Task.await(server)) == 2
    end
  end

  test "duplicate JSON fields, invalid declarations and overdeep responses refuse" do
    for body <- [
          ~s({"version":"0.40.13","version":"0.40.14"}),
          %{"version" => "not a version"},
          %{
            "version" => "0.40.13",
            "nested" => Enum.reduce(1..17, nil, fn _, acc -> %{"x" => acc} end)
          }
        ] do
      {base, server} = sequence([body])
      assert {:error, _} = Models.read(base, @model)
      assert length(Task.await(server)) == 1
    end

    invalid = put_in(show(), ["model_info", "fixture.context_length"], "untrusted-private-value")
    {base, server} = sequence([version(), tags(), invalid])
    assert {:error, :ollama_metadata_invalid} = Models.read(base, @model)
    assert length(Task.await(server)) == 3
  end

  test "invalid and nonloopback selections make no request" do
    for {base, model, timeout} <- [
          {nil, @model, 1000},
          {"https://example.com", @model, 1000},
          {"http://127.0.0.1:1?secret=value", @model, 1000},
          {"http://127.0.0.1:1", nil, 1000},
          {"http://127.0.0.1:1", @model, 0},
          {"http://127.0.0.1:1", @model, 30001}
        ] do
      assert {:error, :invalid_ollama_inspection} = Models.read(base, model, timeout)
    end
  end

  test "credential-like metadata labels are withheld without losing the metadata binding" do
    private = "sk-synthetic-private-upstream-value"

    metadata =
      show()
      |> put_in(["details", "family"], private)
      |> put_in(["model_info", "general.license"], private)

    {base, server} = sequence([version(), tags(), metadata, %{"models" => []}, tags(), version()])
    assert {:ok, report} = Models.read(base, @model)
    refute Jason.encode!(report) =~ private
    assert report["declared_license"] == nil
    assert report["declared_details"]["family"] == nil
    assert report["license_claim_sha256"] == Ipse.JSON.sha256(private)
    assert Ipse.JSON.sha256?(report["metadata_sha256"])
    assert length(Task.await(server)) == 6
  end
end
