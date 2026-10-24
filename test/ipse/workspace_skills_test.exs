defmodule Ipse.SkillsTest do
  use ExUnit.Case, async: false

  alias Ipse.Workspace

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

    skills = Workspace.discover_skills(project, user)
    review = Enum.find(skills, &(&1["name"] == "review"))

    assert review["path"] == Path.expand(project_file)
    assert review["description"] == "Project review"

    assert Workspace.explicit_skills("Use $review, then $missing and $review.", skills) == [
             "review"
           ]

    assert {:ok, loaded} = Workspace.load_skill(skills, "review")
    assert loaded =~ "Source: #{Path.expand(project_file)}"
    assert loaded =~ "Project instructions"
  end

  test "oversized and malformed skill documents are skipped", %{project: project, user: user} do
    skills_dir = Path.join(project, ".agents/skills")
    File.mkdir_p!(Path.join(skills_dir, "bad"))
    File.write!(Path.join(skills_dir, "bad/SKILL.md"), "---\nname: bad\n---\nNo description")
    File.mkdir_p!(Path.join(skills_dir, "huge"))
    File.write!(Path.join(skills_dir, "huge/SKILL.md"), String.duplicate("x", 65_537))

    refute Enum.any?(Workspace.discover_skills(project, user), &(&1["name"] in ["bad", "huge"]))
  end

  test "discovery skips a FIFO skill and a selected skill replaced with a FIFO refuses", ctx do
    path = install(Path.join(ctx.project, ".agents/skills"), "pipe", "pipe")
    skills = Workspace.discover_skills(ctx.project, ctx.user)
    File.rm!(path)
    :ok = Ipse.Test.FileEffectProbe.fifo!(path)

    for operation <- [
          fn -> Workspace.discover_skills(ctx.project, ctx.user) end,
          fn -> Workspace.load_skill(skills, "pipe") end
        ] do
      task = Task.async(operation)
      result = Task.yield(task, 1000)

      if result == nil do
        System.cmd("sh", ["-c", "printf x > \"$1\"", "sh", path])
        Task.await(task)
      end

      assert {:ok, value} = result

      if is_list(value),
        do: refute(Enum.any?(value, &(&1["name"] == "pipe"))),
        else: assert(match?({:error, _}, value))
    end
  end

  test "quoted Unicode metadata removes exactly the ASCII delimiters", ctx do
    for {quote, name, description} <- [
          {"\"", "雪", "Review café 🙂"},
          {"'", "é🙂", "説明 é"}
        ] do
      path = Path.join(ctx.project, ".agents/skills/review/SKILL.md")

      File.write!(
        path,
        "---\nname: #{quote}#{name}#{quote}\ndescription: #{quote}#{description}#{quote}\n---\nBody"
      )

      skills = Workspace.discover_skills(ctx.project, ctx.user)
      assert %{"description" => ^description} = Enum.find(skills, &(&1["name"] == name))
      assert {:ok, _} = Workspace.load_skill(skills, name)
    end
  end

  test "load refuses changed bytes until discovery is explicitly refreshed", %{
    project: project,
    user: user
  } do
    path = Path.join(project, ".agents/skills/review/SKILL.md")
    File.write!(path, "---\nname: review\ndescription: Original\n---\nOriginal body\n")
    [skill] = Workspace.discover_skills(project, user) |> Enum.filter(&(&1["name"] == "review"))

    updated = "---\nname: review\ndescription: Updated\n---\nUpdated body\n"
    File.write!(path, updated)

    assert {:error, error} = Workspace.load_skill([skill], "review")
    assert error =~ "skill_catalog_changed"
    assert {:error, _} = Workspace.load_skill_resource([skill], "review", "SKILL.md")

    assert {:ok, loaded} =
             Workspace.load_skill(Workspace.discover_skills(project, user), "review")

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
    skills = Workspace.discover_skills(ctx.project, ctx.user)
    assert {:ok, result} = Workspace.load_skill_resource(skills, "review", "references/check.sh")
    assert result =~ "Source: #{resource}"
    assert result =~ "SHA-256: #{Base.encode16(:crypto.hash(:sha256, content), case: :lower)}"
    assert String.ends_with?(result, content)
    refute File.exists?(Path.join(project_root, "must-not-run"))
    assert {:error, _} = Workspace.load_skill_resource(skills, "missing", "references/check.sh")
  end

  test "workspace failure descriptions retain known causes and withhold arbitrary details" do
    assert Workspace.failure_message(:enoent) == "target does not exist"
    assert Workspace.failure_message(:skill_catalog_changed) =~ "skill_catalog_changed"

    for reason <- [
          "/home/private/secret",
          {:unexpected, "/home/private/secret"},
          %{secret: self()}
        ] do
      text = Workspace.failure_message(reason)
      assert text == "workspace source unavailable; inspect access and selected paths"
      refute text =~ "/home/"
      refute text =~ "#PID"
      refute text =~ "%{"
    end
  end

  defp install(root, directory, name, body \\ "Inert body") do
    dir = Path.join(root, directory)
    File.mkdir_p!(dir)
    path = Path.join(dir, "SKILL.md")
    File.write!(path, "---\nname: #{name}\ndescription: #{directory}\n---\n#{body}\n")
    path
  end

  test "default discovery uses HOME independently of IPSE_HOME", ctx do
    previous_home = System.get_env("HOME")
    previous_ipse = System.get_env("IPSE_HOME")
    operator = Path.join(ctx.project, "operator-home")
    System.put_env("HOME", operator)
    System.put_env("IPSE_HOME", ctx.user)

    on_exit(fn ->
      System.put_env("HOME", previous_home)
      System.put_env("IPSE_HOME", previous_ipse)
    end)

    shared_path =
      install(Path.join(operator, ".agents/skills"), "shared-default", "shared-default")

    user_path = install(Path.join(ctx.user, "skills"), "ipse-default", "ipse-default")
    skills = Workspace.discover_skills(ctx.project)
    assert Enum.find(skills, &(&1["name"] == "shared-default"))["path"] == shared_path
    assert Enum.find(skills, &(&1["name"] == "ipse-default"))["path"] == user_path
  end

  test "shared skills are discovered in place with all four precedence levels", ctx do
    operator = Path.join(ctx.user, "operator-home")
    shared = Path.join(operator, ".agents/skills")
    project = Path.join(ctx.project, ".agents/skills")
    shared_path = install(shared, "review", "review")
    user_path = install(ctx.user, "review", "review")
    project_path = install(project, "review", "review")
    opts = [operator_home: operator]

    [selected] =
      Workspace.discover_skills(ctx.project, ctx.user, opts)
      |> Enum.filter(&(&1["name"] == "review"))

    assert selected["path"] == project_path
    assert [^user_path, ^shared_path, bundled] = selected["shadowed_paths"]
    assert String.ends_with?(bundled, "/skills/review/SKILL.md")
    catalog = Workspace.skill_catalog([selected])
    assert catalog =~ "Source: #{project_path}"
    assert catalog =~ "Shadowed: #{shared_path}"

    File.rm!(project_path)

    selected =
      Enum.find(Workspace.discover_skills(ctx.project, ctx.user, opts), &(&1["name"] == "review"))

    assert selected["path"] == user_path
    File.rm!(user_path)

    selected =
      Enum.find(Workspace.discover_skills(ctx.project, ctx.user, opts), &(&1["name"] == "review"))

    assert selected["path"] == shared_path
    assert selected["shadowed_paths"] == [bundled]
    File.rm!(shared_path)

    selected =
      Enum.find(Workspace.discover_skills(ctx.project, ctx.user, opts), &(&1["name"] == "review"))

    assert selected["path"] == bundled
    assert selected["shadowed_paths"] == []
  end

  test "operator home is independent of Ipse user skills and explicit roots can disable sharing",
       ctx do
    operator = Path.join(ctx.project, "operator")
    shared = Path.join(operator, ".agents/skills")
    path = install(shared, "only-shared", "only-shared", "touch must-not-run")
    install(Path.join(ctx.user, ".agents/skills"), "wrong", "wrong-home")
    skills = Workspace.discover_skills(ctx.project, ctx.user, operator_home: operator)
    assert Enum.find(skills, &(&1["name"] == "only-shared"))["path"] == path
    refute Enum.any?(skills, &(&1["name"] == "wrong-home"))
    assert {:ok, loaded} = Workspace.load_skill(skills, "only-shared")
    assert loaded =~ "touch must-not-run"
    assert loaded =~ "Source: #{path}"
    assert File.exists?(path)
    refute File.exists?(Path.join(Path.dirname(path), "must-not-run"))

    assert {:error, _} =
             Workspace.load_skill(Workspace.discover_skills(ctx.project, ctx.user), "only-shared")

    assert {:error, _} =
             Workspace.load_skill(
               Workspace.discover_skills(ctx.project, ctx.user,
                 operator_home: operator,
                 shared_root: nil
               ),
               "only-shared"
             )

    assert {:ok, _} =
             Workspace.load_skill(
               Workspace.discover_skills(ctx.project, ctx.user, shared_root: shared),
               "only-shared"
             )

    resource = Path.join(Path.dirname(path), "guide.txt")
    File.write!(resource, "Shared resource, no automatic link traversal")
    assert {:ok, text} = Workspace.load_skill_resource(skills, "only-shared", "guide.txt")
    assert text =~ "Source: #{resource}"
    assert text =~ "SHA-256:"
    File.ln_s!(resource, Path.join(Path.dirname(path), "alias.txt"))
    assert {:error, _} = Workspace.load_skill_resource(skills, "only-shared", "alias.txt")
    assert {:error, _} = Workspace.load_skill_resource(skills, "only-shared", "../guide.txt")
  end

  test "root aliases deduplicate canonical files but retain deterministic selected provenance",
       ctx do
    shared = Path.join(ctx.user, "shared")
    path = install(shared, "a", "alias-fixture")
    alias_root = Path.join(ctx.user, "alias")
    File.ln_s!(shared, alias_root)
    skills = Workspace.discover_skills(ctx.project, alias_root, shared_root: shared)
    selected = Enum.find(skills, &(&1["name"] == "alias-fixture"))
    assert selected["path"] == Path.join(alias_root, "a/SKILL.md")
    assert selected["canonical_path"] == path
    assert selected["shadowed_paths"] == []
    assert skills == Workspace.discover_skills(ctx.project, alias_root, shared_root: shared)
    File.write!(Path.join(shared, "a/guide.txt"), "root alias works")
    assert {:ok, text} = Workspace.load_skill_resource(skills, "alias-fixture", "guide.txt")
    assert text =~ "root alias works"

    File.ln_s!(Path.join(shared, "a"), Path.join(shared, "b"))
    # Directory aliases are accepted for metadata, but cannot be resource roots.
    skill_alias = Map.put(selected, "path", Path.join(shared, "b/SKILL.md"))

    assert {:error, _} =
             Workspace.load_skill_resource([skill_alias], "alias-fixture", "guide.txt")
  end

  test "shared discovery skips malformed oversized and invalid UTF-8 files", ctx do
    shared = Path.join(ctx.user, "shared")
    good = install(shared, "good", "valid-shared")
    bad = install(shared, "bad", "bad-shared")
    huge = install(shared, "huge", "huge-shared")
    invalid = install(shared, "invalid", "invalid-shared")
    File.write!(bad, "---\nname: bad-shared\n---\nNo description")
    File.write!(huge, String.duplicate("x", 65_537))
    File.write!(invalid, <<255>>)
    skills = Workspace.discover_skills(ctx.project, ctx.user, shared_root: shared)
    assert Enum.find(skills, &(&1["name"] == "valid-shared"))["path"] == good
    refute Enum.any?(skills, &(&1["name"] in ["bad-shared", "huge-shared", "invalid-shared"]))
    File.write!(good, String.duplicate("x", 65_537))
    assert {:error, _} = Workspace.load_skill(skills, "valid-shared")
    File.write!(good, <<255>>)
    assert {:error, _} = Workspace.load_skill(skills, "valid-shared")
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
    skills = Workspace.discover_skills(ctx.project, ctx.user)

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
      assert {:error, _} = Workspace.load_skill_resource(skills, "review", path)
    end

    assert {:ok, loaded} = Workspace.load_skill_resource(skills, "review", "good.txt")
    assert loaded =~ "safe"
    File.write!(Path.join(root, "good.txt"), "changed")
    assert {:ok, changed} = Workspace.load_skill_resource(skills, "review", "good.txt")
    assert changed != loaded
  end
end
