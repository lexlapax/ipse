defmodule Ipse.SkillsTest do
  use ExUnit.Case, async: true

  alias Ipse.Skills

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-skills-#{System.unique_integer([:positive])}")
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

  test "explicit resources use the selected skill root and remain inert", ctx do
    project_root = Path.join(ctx.project, ".agents/skills/review")

    File.write!(
      Path.join(project_root, "SKILL.md"),
      "---\nname: review\ndescription: Review\n---\nBody"
    )

    File.write!(
      Path.join(ctx.user, "review/SKILL.md"),
      "---\nname: review\ndescription: User\n---\nBody"
    )

    File.mkdir!(Path.join(project_root, "references"))
    resource = Path.join(project_root, "references/check.sh")
    content = "touch must-not-run\n[another resource](missing.txt)\n"
    File.write!(resource, content)
    File.write!(Path.join(ctx.user, "review/check.sh"), "wrong source")
    skills = Skills.discover(ctx.project, ctx.user)
    assert {:ok, result} = Skills.load_resource(skills, "review", "references/check.sh")
    assert result =~ "Source: #{resource}"
    assert result =~ "SHA-256: #{Base.encode16(:crypto.hash(:sha256, content), case: :lower)}"
    assert String.ends_with?(result, content)
    refute File.exists?(Path.join(project_root, "must-not-run"))
    assert {:error, _} = Skills.load_resource(skills, "missing", "references/check.sh")
  end

  test "resource reads reject escapes, sensitive names, symlinks, invalid text and excess bytes",
       ctx do
    root = Path.join(ctx.user, "review")
    File.write!(Path.join(root, "SKILL.md"), "---\nname: review\ndescription: Review\n---\nBody")
    File.write!(Path.join(root, "good.txt"), "safe")
    File.write!(Path.join(root, ".env"), "secret")
    File.write!(Path.join(root, "bad.txt"), <<255>>)
    File.write!(Path.join(root, "large.txt"), String.duplicate("x", 32_769))
    File.ln_s!(Path.join(root, "good.txt"), Path.join(root, "link.txt"))
    File.ln_s!(root, Path.join(root, "linked-dir"))
    skills = Skills.discover(ctx.project, ctx.user)

    for path <- [
          "../review/good.txt",
          "/etc/passwd",
          ".env",
          ".env.local",
          "auth/token.txt",
          "bad.txt",
          "large.txt",
          "link.txt",
          "linked-dir/good.txt",
          "missing.txt",
          "a/b/c/d/e/f/g/h/i.txt",
          "key.pem",
          "https://example.com/file",
          "x\\y",
          nil
        ] do
      assert {:error, _} = Skills.load_resource(skills, "review", path)
    end

    assert {:ok, loaded} = Skills.load_resource(skills, "review", "good.txt")
    assert loaded =~ "safe"
    File.write!(Path.join(root, "good.txt"), "changed")
    assert {:ok, changed} = Skills.load_resource(skills, "review", "good.txt")
    assert changed != loaded
  end
end
