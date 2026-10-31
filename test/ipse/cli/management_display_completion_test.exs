defmodule Ipse.CLI.ManagementDisplayCompletionTest do
  use ExUnit.Case, async: false
  alias Ipse.CLI.Knowledge.Management

  test "only a timely closed display remains known after all cleanup" do
    now_mono = System.monotonic_time(:millisecond)
    now_wall = System.system_time(:millisecond)
    result = {:closed, {:ok, %{synthetic: true}}}

    assert Management.management_display_completion(result, now_mono + 10_000, now_wall + 10_000) ==
             result

    assert Management.management_display_completion(result, now_mono - 1, now_wall + 10_000) ==
             {:unknown, :management_display_unconfirmed}

    assert Management.management_display_completion(result, now_mono + 10_000, now_wall - 1) ==
             {:unknown, :management_display_unconfirmed}

    assert Management.management_display_completion(result, nil, now_wall + 10_000) ==
             {:unknown, :management_display_unconfirmed}

    assert Management.management_display_completion(
             {:unknown, :prior_loss},
             now_mono + 10_000,
             now_wall + 10_000
           ) == {:unknown, :prior_loss}
  end
end
