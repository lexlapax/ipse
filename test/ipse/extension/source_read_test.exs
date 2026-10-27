defmodule Ipse.Extension.SourceReadTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.{SourceRead, Catalog, Actions}
  alias Ipse.Session.{SourceIndex, Input}

  defp index(session, text) do
    {:ok, index} = SourceIndex.new(session)
    input = Input.received(session, Ipse.Usage.id(), text, text, nil)
    message = %{"type" => "message", "message" => %{"role" => "user", "content" => text}}
    {:ok, index} = SourceIndex.admit_input(index, input, message)

    counters =
      Map.new(
        ~w(observed indexed unavailable capacity_refused legacy_unverified pending_gaps refused),
        &{&1, if(&1 in ~w(observed indexed), do: 1, else: 0)}
      )

    {:ok, index} = SourceIndex.coverage(index, counters)
    {index, input, message, counters}
  end

  test "closed source operations require an explicit host grant and retain read budgets" do
    exports = Catalog.empty()
    assert {:error, _} = Catalog.validate(exports, ["host.sources"])
    assert :ok = Catalog.validate(exports, ~w(host.actions host.sources))
    identity = %{"capabilities" => ~w(host.actions host.sources)}
    assert Actions.limit(identity, %{"op" => "source.list"}) == 512
    assert Actions.limit(identity, %{"op" => "state.put"}) == 16
    assert Actions.capability(%{"op" => "source.read"}) == "host.sources"
    refute Actions.mutating?(%{"op" => "source.quote"})
    assert :ok = SourceRead.validate(%{"op" => "source.list", "limit" => 32, "cursor" => nil})

    for bad <- [
          %{"op" => "source.list", "limit" => 33},
          %{"op" => "source.list", "limit" => 1, "origin" => "interactive_operator"},
          %{"op" => "source.read", "handle" => "x", "journal_path" => "/tmp/arbitrary"},
          %{"op" => "source.quote", "handle" => "x", "quote" => ""},
          %{"op" => "source.quote", "handle" => "x", "quote" => String.duplicate("x", 8193)}
        ],
        do: assert({:error, _} = SourceRead.validate(bad))
  end

  test "historical read proof recomputes exact bytes and rejects future, mixed and changed claims" do
    session = Ipse.Usage.id()
    text = "Unique café 雪 " <> String.duplicate("control\n\t雪 ", 1500)
    {original, input, message, counters} = index(session, text)
    {:ok, fresh} = SourceIndex.new(session)
    {:ok, fresh} = SourceIndex.admit_input(fresh, input, message)
    {:ok, fresh} = SourceIndex.coverage(fresh, counters)
    request = %{"limit" => 32}
    assert {:ok, list} = SourceIndex.list(original, request)

    assert SourceRead.valid_outcome?(
             Map.put(request, "op", "source.list"),
             "ok",
             list,
             Ipse.Usage.id()
           )

    assert byte_size(Jason.encode!(list)) <= 4096

    assert :ok =
             SourceIndex.validate_saved_read(
               fresh,
               "source.list",
               request,
               list,
               original.window_id
             )

    handle = hd(list["sources"])["read_handle"]
    assert {:error, _} = SourceIndex.read(fresh, %{"handle" => handle})
    assert {:ok, page} = SourceIndex.read(original, %{"handle" => handle})
    assert byte_size(Jason.encode!(page)) <= 8192

    assert SourceRead.valid_outcome?(
             %{"op" => "source.read", "handle" => handle},
             "ok",
             page,
             Ipse.Usage.id()
           )

    assert :ok =
             SourceIndex.validate_saved_read(
               fresh,
               "source.read",
               %{"handle" => handle},
               page,
               original.window_id
             )

    assert :ok =
             SourceIndex.validate_saved_read(
               fresh,
               "source.quote",
               %{"handle" => handle, "quote" => "Unique café 雪"},
               elem(
                 SourceIndex.quote(original, %{"handle" => handle, "quote" => "Unique café 雪"}),
                 1
               ),
               original.window_id
             )

    for damaged <- [
          Map.put(page, "text", "forged"),
          Map.put(page, "offset", 1),
          put_in(page, ["window", "coverage", "unavailable"], 1),
          put_in(page, ["window", "window_id"], Ipse.Usage.id()),
          Map.put(page, "origin", "interactive_operator")
        ] do
      assert {:error, _} =
               SourceIndex.validate_saved_read(
                 fresh,
                 "source.read",
                 %{"handle" => handle},
                 damaged,
                 original.window_id
               )
    end

    assert {:error, _} =
             SourceIndex.validate_saved_read(
               fresh,
               "source.read",
               %{"handle" => handle},
               page,
               Ipse.Usage.id()
             )

    [body, signature] = String.split(handle, ".")

    claim =
      body
      |> Base.url_decode64!(padding: false)
      |> Jason.decode!()
      |> Map.update!("generation", &(&1 + 1))

    future = Base.url_encode64(Jason.encode!(claim), padding: false) <> "." <> signature

    assert {:error, _} =
             SourceIndex.validate_saved_read(
               fresh,
               "source.read",
               %{"handle" => future},
               page,
               original.window_id
             )

    assert {:ok, changed} =
             SourceIndex.coverage(original, %{counters | "observed" => 2, "unavailable" => 1})

    assert {:error, _} = SourceIndex.read(changed, %{"handle" => handle})
    assert {:ok, next} = SourceIndex.read(original, %{"handle" => page["next"]})
    assert byte_size(Jason.encode!(next)) <= 8192

    assert :ok =
             SourceIndex.validate_saved_read(
               fresh,
               "source.read",
               %{"handle" => page["next"]},
               next,
               original.window_id
             )
  end

  test "stable evidence agrees with independently resolved host proof and refuses mixed receipts" do
    {index, _, _, _} = index(Ipse.Usage.id(), "Exact café 雪 evidence")
    {:ok, list} = SourceIndex.list(index, %{"limit" => 1})
    handle = hd(list["sources"])["read_handle"]
    {:ok, page} = SourceIndex.read(index, %{"handle" => handle})
    request = %{"handle" => page["handle"], "quote" => "café 雪"}
    {:ok, quote} = SourceIndex.quote(index, request)
    {:ok, resolved} = SourceIndex.resolve_proof(index, request)
    assert {:ok, proof} = SourceRead.stable_proof(page, quote, "café 雪")
    assert proof == resolved["proof"]
    assert map_size(proof) == 14
    assert {:error, _} = SourceRead.stable_proof(page, quote, "café")

    assert {:error, _} =
             SourceRead.stable_proof(
               Map.put(page, "occurrence_id", Ipse.Usage.id()),
               quote,
               "café 雪"
             )

    assert {:error, _} =
             SourceRead.stable_proof(Map.put(page, "kind", "tool.content"), quote, "café 雪")

    assert {:error, _} = SourceRead.stable_proof(page, Map.put(quote, "start_byte", 0), "café 雪")
  end
end
