# Synthetic framed peer for host deadline testing; it performs no file effect.
trace = System.fetch_env!("IPSE_HEADER_PEER_TRACE")
mode = System.fetch_env!("IPSE_HEADER_PEER_MODE")
IO.binwrite(:stdio, <<?R, 0::32>>)

loop = fn loop ->
  case IO.binread(:stdio, 5) do
    <<tag, size::32>> when size <= 16_393 ->
      case IO.binread(:stdio, size) do
        <<seq::binary-size(9), _::binary>> ->
          File.write!(trace, <<tag>>, [:append])
          if mode == "stall", do: Process.sleep(2_000), else: Process.sleep(120)

          if tag == ?B,
            do: IO.binwrite(:stdio, <<tag, 29::32, seq::binary, 0::64, 1::64, 2::32>>),
            else: IO.binwrite(:stdio, <<tag, 9::32, seq::binary>>)

          loop.(loop)

        _ ->
          :ok
      end

    _ ->
      :ok
  end
end

loop.(loop)
