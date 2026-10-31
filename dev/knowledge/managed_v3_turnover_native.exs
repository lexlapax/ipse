defmodule Ipse.Development.ManagedV3TurnoverNative do
  @moduledoc """
  Map real, signed native review times to an explicit simulated timeline.

  This development-only mapping never changes an Ipse runtime clock. Native
  permits and publications retain their real wall times; future expiry checks
  use the test fixture's explicit as-of argument. It is not annual qualification.
  """
  @day 86_400_000
  @virtual_epoch 1_800_000_000_000

  def frame(real_anchor) when is_integer(real_anchor) and real_anchor >= @day do
    %{
      "real_anchor_ms" => real_anchor,
      "virtual_anchor_ms" => @virtual_epoch + 90 * @day,
      "virtual_day_ms" => @day,
      "virtual_epoch_ms" => @virtual_epoch
    }
  end

  def virtual(frame, real_timestamp) when is_integer(real_timestamp) do
    frame["virtual_anchor_ms"] + real_timestamp - frame["real_anchor_ms"]
  end

  def event(frame, kind, timestamp, fields) do
    Map.merge(fields, %{
      "kind" => kind,
      "real_or_as_of_ms" => timestamp,
      "virtual_ms" => virtual(frame, timestamp),
      "clock_frame" => frame,
      "qualification" => false
    })
  end
end
