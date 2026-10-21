defmodule Ipse.Development.Evaluation.Gateway do
  @moduledoc "Controlled loopback search/fetch provider for the frozen corpus comparison."
  use GenServer
  @max_calls 1024 * 11

  def start(port, max_calls \\ 512)

  def start(port, max_calls)
      when is_integer(port) and port in 0..65535 and is_integer(max_calls) and
             max_calls in 1..@max_calls,
      do: GenServer.start(__MODULE__, {self(), port, max_calls})

  def start(_, _), do: {:error, :invalid_gateway_limit}
  def select(pid, documents), do: GenServer.call(pid, {:select, documents})
  def calls(pid), do: GenServer.call(pid, :calls)
  def summary(pid), do: GenServer.call(pid, :summary)
  def port(pid), do: GenServer.call(pid, :port)
  def selected_uris(pid), do: GenServer.call(pid, :selected_uris)
  def begin_query(pid), do: GenServer.call(pid, :begin_query)

  def stop(pid) do
    acceptor = GenServer.call(pid, :acceptor)
    monitor = Process.monitor(acceptor)
    :ok = GenServer.stop(pid)

    receive do
      {:DOWN, ^monitor, :process, ^acceptor, _} -> :ok
    after
      5000 -> {:error, :gateway_cleanup_unconfirmed}
    end
  end

  def init({owner, port, max_calls}) do
    {:ok, listener} =
      :gen_tcp.listen(port, [
        :binary,
        packet: 4,
        packet_size: 60_000,
        active: false,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    server = self()
    acceptor = spawn_link(fn -> accept(listener, server) end)

    {:ok,
     %{
       listener: listener,
       acceptor: acceptor,
       owner: Process.monitor(owner),
       docs: [],
       calls: [],
       call_limit: max_calls,
       call_count: 0,
       over_limit: 0,
       selected: []
     }}
  end

  def handle_call({:select, documents}, _from, state) do
    {:reply, :ok, %{state | docs: documents, selected: []}}
  end

  def handle_call(:calls, _from, state), do: {:reply, Enum.reverse(state.calls), state}

  def handle_call(:summary, _from, state) do
    {:reply,
     %{
       "call_limit" => state.call_limit,
       "recorded_calls" => state.call_count,
       "rejected_over_limit" => state.over_limit,
       "request_count" => state.call_count + state.over_limit
     }, state}
  end

  def handle_call(:acceptor, _from, state), do: {:reply, state.acceptor, state}

  def handle_call(:port, _from, state) do
    {:ok, {_, port}} = :inet.sockname(state.listener)
    {:reply, port, state}
  end

  def handle_call(:selected_uris, _from, state), do: {:reply, state.selected, state}
  def handle_call(:begin_query, _from, state), do: {:reply, :ok, %{state | selected: []}}

  def handle_call({:request, request}, _from, state) do
    within_limit = state.call_count < state.call_limit

    {reply, selected} =
      try do
        true =
          is_map(request) and Enum.sort(Map.keys(request)) == ~w(arguments partition tool version)

        args = request["arguments"]
        tool = request["tool"]
        true = request["version"] == 1 and request["partition"] == "evaluation"
        true = tool in ~w(search fetch) and is_map(args)
        true = within_limit
        if tool == "fetch", do: true = args["uri"] in state.selected
        reply = if tool == "search", do: search(state.docs, args), else: fetch(state.docs, args)
        true = byte_size(JSON.encode!(reply)) <= 60_000

        selected =
          if tool == "search", do: Enum.map(reply["hits"], & &1["uri"]), else: state.selected

        {reply, selected}
      rescue
        _ -> {%{"status" => "refused", "code" => "gateway_request_refused"}, []}
      end

    encoded = JSON.encode!(reply)

    call = %{
      "tool" =>
        if(is_map(request) and request["tool"] in ~w(search fetch),
          do: request["tool"],
          else: "other"
        ),
      "response_sha256" => sha(encoded),
      "status" => reply["status"]
    }

    calls = if within_limit, do: [call | state.calls], else: state.calls

    {:reply, encoded,
     %{
       state
       | calls: calls,
         selected: selected,
         call_count: state.call_count + if(within_limit, do: 1, else: 0),
         over_limit: state.over_limit + if(within_limit, do: 0, else: 1)
     }}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{owner: ref} = state),
    do: {:stop, :normal, state}

  def terminate(_, state) do
    :gen_tcp.close(state.listener)
    Process.exit(state.acceptor, :shutdown)
  end

  defp accept(listener, server) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        try do
          with {:ok, bytes} <- :gen_tcp.recv(socket, 0, 5000),
               {:ok, request} <- JSON.decode(bytes) do
            response = GenServer.call(server, {:request, request}, 5000)
            :gen_tcp.send(socket, response)
          end
        after
          :gen_tcp.close(socket)
        end

        accept(listener, server)

      {:error, :closed} ->
        :ok

      {:error, _} ->
        :ok
    end
  end

  defp search(documents, args) do
    true = Enum.sort(Map.keys(args)) == ~w(contract limit query version)
    true = args["version"] == 1 and args["contract"] == "search-v1"
    true = is_integer(args["limit"]) and args["limit"] in 1..10

    true =
      is_binary(args["query"]) and String.valid?(args["query"]) and
        byte_size(args["query"]) in 1..1024

    terms = terms(args["query"])

    hits =
      documents
      |> Enum.map(fn doc ->
        words = terms(doc["source"]["title"] <> " " <> doc["source"]["text"])
        {MapSet.intersection(terms, words) |> MapSet.size(), doc}
      end)
      |> Enum.filter(fn {score, _} -> score > 0 end)
      |> Enum.sort_by(fn {score, doc} -> {-score, doc["source"]["source_id"]} end)
      |> Enum.take(args["limit"])
      |> Enum.map(fn {_score, doc} ->
        source = doc["source"]

        %{
          "source_id" => source["source_id"],
          "uri" => source["uri"],
          "title" => source["title"],
          "snippet" => source["title"]
        }
      end)

    %{
      "version" => 1,
      "contract" => "search-v1",
      "status" => "ok",
      "hits" => hits,
      "coverage" => %{"complete" => true, "algorithm" => "source_term_overlap_v1"},
      "next" => nil
    }
  end

  defp fetch(documents, args) do
    true = Enum.sort(Map.keys(args)) == ~w(contract uri version)
    true = args["version"] == 1 and args["contract"] == "fetch-v1"
    doc = Enum.find(documents, &(&1["source"]["uri"] == args["uri"]))
    source = if doc, do: doc["source"], else: %{}
    text = source["text"] || ""
    ok = doc != nil and byte_size(text) <= 49_152
    text = if ok, do: text, else: ""

    %{
      "version" => 1,
      "contract" => "fetch-v1",
      "status" => if(ok, do: "ok", else: "refused"),
      "requested_uri" => args["uri"],
      "observed_uri" => args["uri"],
      "media_type" => "text/plain",
      "observed_at_ms" => source["observed_at_ms"] || 0,
      "text" => text,
      "body_sha256" => sha(text),
      "complete" => ok,
      "start_byte" => 0,
      "end_byte" => byte_size(text)
    }
  end

  defp terms(text),
    do: text |> String.downcase() |> String.split(~r/[^[:alnum:]_]+/u, trim: true) |> MapSet.new()

  defp sha(text), do: Base.encode16(:crypto.hash(:sha256, text), case: :lower)
end
