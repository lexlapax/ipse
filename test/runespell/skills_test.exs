defmodule Runespell.SkillsTest do
  use ExUnit.Case, async: true

  alias Runespell.Skills

  setup do
    root = Path.join(System.tmp_dir!(), "runespell-skills-#{System.unique_integer([:positive])}")
    project = Path.join(root, "project")
    user = Path.join(root, "user")
    File.mkdir_p!(Path.join(project, ".agents/skills/review"))
    File.mkdir_p!(Path.join(user, "review"))

    on_exit(fn -> File.rm_rf!(root) end)
    %{project: project, user: user}
  end

  test "project skills take precedence and explicit references match known names", %{
    project: project,
    user: user
  } do
    project_file = Path.join(project, ".agents/skills/review/SKILL.md")
    user_file = Path.join(user, "review/SKILL.md")

    File.write!(
      project_file,
      "---\nname: review\ndescription: Project review\n---\nProject instructions\n"
    )

    File.write!(
      user_file,
      "---\nname: review\ndescription: User review\n---\nUser instructions\n"
    )

    skills = Skills.discover(project, user)
    review = Enum.find(skills, &(&1["name"] == "review"))

    assert review["path"] == Path.expand(project_file)
    assert review["description"] == "Project review"
    assert Skills.explicit("Use $review, then $missing and $review.", skills) == ["review"]
    assert {:ok, loaded} = Skills.load(skills, "review")
    assert loaded =~ "Source: #{Path.expand(project_file)}"
    assert loaded =~ "Project instructions"
  end

  test "oversized and malformed skill documents are skipped", %{project: project, user: user} do
    skills_dir = Path.join(project, ".agents/skills")
    File.mkdir_p!(Path.join(skills_dir, "bad"))
    File.write!(Path.join(skills_dir, "bad/SKILL.md"), "---\nname: bad\n---\nNo description")
    File.mkdir_p!(Path.join(skills_dir, "huge"))
    File.write!(Path.join(skills_dir, "huge/SKILL.md"), String.duplicate("x", 65_537))

    refute Enum.any?(Skills.discover(project, user), &(&1["name"] in ["bad", "huge"]))
  end

  test "load reports the hash of the bytes read after discovery", %{project: project, user: user} do
    path = Path.join(project, ".agents/skills/review/SKILL.md")
    File.write!(path, "---\nname: review\ndescription: Original\n---\nOriginal body\n")
    [skill] = Skills.discover(project, user) |> Enum.filter(&(&1["name"] == "review"))

    updated = "---\nname: review\ndescription: Updated\n---\nUpdated body\n"
    File.write!(path, updated)

    assert {:ok, loaded} = Skills.load([skill], "review")
    expected_hash = :crypto.hash(:sha256, updated) |> Base.encode16(case: :lower)
    assert loaded =~ "SHA-256: #{expected_hash}"
    refute loaded =~ "SHA-256: #{skill["sha256"]}"
  end
end
