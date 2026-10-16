defmodule Ipse.SandboxVisibilityTest do
  use ExUnit.Case, async: true
  alias Ipse.Sandbox

  test "Linux facts explain private paths, minimal environment, and host absence inference" do
    text = Sandbox.describe(:native, {:unix, :linux})
    assert text =~ "Requested policy is not proof of activation"
    assert text =~ "Sibling repositories"
    assert text =~ "not mounted"
    assert text =~ "HOME and TMPDIR refer to private"
    assert text =~ "Do not assume USER is set"
    assert text =~ "Host /proc is absent"
    assert text =~ "/dev/fd"
    assert text =~ "not host absence"
    assert text =~ "Do not silently switch"
  end

  test "macOS facts do not claim Linux namespaces or mounts" do
    text = Sandbox.describe(:native, {:unix, :darwin})
    assert text =~ "signed App Sandbox"
    assert text =~ "fixed Homebrew roots"
    assert text =~ "no Linux PID namespace"
    assert text =~ "Detached descendants may survive"
    refute text =~ "Sibling repositories and host home/configuration paths are not mounted"
  end

  test "unsupported and trusted policies do not claim native confinement" do
    assert Sandbox.describe(:native, {:win32, :nt}) =~ "unavailable"
    text = Sandbox.describe(:off, {:unix, :linux})
    assert text =~ "without an OS sandbox"
    refute text =~ "not mounted"
    refute text =~ "not inherited"
  end

  test "session info and model context use the same allowlisted facts" do
    facts = Sandbox.info(:native).visibility
    assert facts == Sandbox.visibility(:native)
    runtime = Ipse.RuntimeInfo.snapshot(%{provider: :demo, model: "scripted"})
    context = Ipse.Context.system("/synthetic/workspace", [], runtime, nil, :native)
    assert Enum.all?(facts, &String.contains?(context, &1))
    refute inspect(facts) =~ "OPENAI_API_KEY="
  end
end
