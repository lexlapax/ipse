defmodule Ipse.Runner.LeasedTerminalDeadlineTest do
  use ExUnit.Case, async: true

  alias Ipse.Runner.LeasedTerminal

  test "fractional clock origins cannot extend either native review deadline" do
    # Same-rate clocks with different fractional origins: native samples at
    # 100.2 ms, then BEAM samples at native 100.3 ms with BEAM time 5.9 ms.
    native_sample_ns = 100_200_000
    host_sample_native_ns = 100_300_000
    beam_sample_ns = 5_900_000
    display_deadline_ns = 7_000_000
    overall_deadline_ns = 9_000_000

    true_display_ns = host_sample_native_ns + display_deadline_ns - beam_sample_ns
    true_overall_ns = host_sample_native_ns + overall_deadline_ns - beam_sample_ns
    native_clock_ms = div(native_sample_ns, 1_000_000)
    beam_now_ms = div(beam_sample_ns, 1_000_000)

    # The former conversion could give native an extra fraction of a
    # millisecond for each deadline, even though its clock was sampled first.
    old_display_ms = native_clock_ms + div(display_deadline_ns, 1_000_000) - beam_now_ms
    old_overall_ms = native_clock_ms + div(overall_deadline_ns, 1_000_000) - beam_now_ms
    assert old_display_ms * 1_000_000 > true_display_ns
    assert old_overall_ms * 1_000_000 > true_overall_ns

    assert {:ok, {display, overall}} =
             LeasedTerminal.native_review_deadlines(native_clock_ms, 7, 9, beam_now_ms)

    assert display * 1_000_000 <= true_display_ns
    assert overall * 1_000_000 <= true_overall_ns

    # The native parser rounds its current reading upward. At this instant the
    # old deadline would admit, while the corrected display deadline expires.
    native_parser_now_ns = 100_999_000
    parser_now_ms = div(native_parser_now_ns + 999_999, 1_000_000)
    assert old_display_ms > parser_now_ms
    assert display <= parser_now_ms
  end

  test "expired, one-millisecond, inconsistent and overflowing bounds refuse" do
    assert {:error, :cleanup_unconfirmed} = LeasedTerminal.native_review_deadlines(100, 4, 9, 5)
    assert {:error, :cleanup_unconfirmed} = LeasedTerminal.native_review_deadlines(100, 5, 9, 5)
    assert {:error, :cleanup_unconfirmed} = LeasedTerminal.native_review_deadlines(100, 6, 9, 5)
    assert {:error, :cleanup_unconfirmed} = LeasedTerminal.native_review_deadlines(100, 9, 8, 5)

    assert {:error, :cleanup_unconfirmed} =
             LeasedTerminal.native_review_deadlines(18_446_744_073_709_551_615, 9, 9, 5)

    # BEAM's monotonic epoch may be negative.
    assert {:ok, {101, 103}} = LeasedTerminal.native_review_deadlines(100, -3, -1, -5)
  end
end
