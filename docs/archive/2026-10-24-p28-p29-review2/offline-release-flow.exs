Code.require_file("dev/release.exs")
alias Ipse.Development.Release
source = File.read!(".github/workflows/release.yml")
blocks = String.split(source, "\n      - name: ")

commands =
  for name <- [
        "Admit the complete asset set before creating any draft",
        "Create or recover an unpublished draft and attach all verified assets",
        "Re-download and inspect the complete draft asset set"
      ] do
    block = Enum.find(blocks, &String.starts_with?(&1, name <> "\n"))
    [_, body] = String.split(block, "        run: |\n", parts: 2)
    String.replace(body, ~r/^          /m, "")
  end

root =
  Path.join(
    System.tmp_dir!(),
    "ipse-offline-draft-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  )

File.mkdir!(root)
File.chmod!(root, 0o700)

try do
  stub_source = ~S"""
  root = System.fetch_env!("IPSE_DRAFT_FIXTURE_ROOT")
  args = System.argv()
  File.write!(Path.join(root, "calls.jsonl"), [:json.encode(args), "\n"], [:append])
  state = Path.join(root, "state")
  case args do
    ["--version"] -> IO.puts("synthetic gh fixture")
    ["release", "view", _tag, "--json", "isDraft" | rest] ->
      case File.read!(state) do
        "absent" -> System.halt(1)
        value ->
          if rest == [], do: IO.puts(:json.encode(%{isDraft: value == "draft"})), else: IO.puts(value == "draft")
      end
    ["release", "create" | _] -> File.write!(state, "draft")
    ["release", "upload" | _] -> true = File.read!(state) == "draft"
    ["release", "download", _tag, "--dir", destination] ->
      true = File.read!(state) == "draft"
      for file <- Path.wildcard(Path.join(root, "ipse-release-assets/*")), do: File.cp!(file, Path.join(destination, Path.basename(file)))
    _ -> raise "Unexpected fake CLI invocation"
  end
  """

  stub = Path.join(root, "stub.exs")
  File.write!(stub, stub_source)
  bin = Path.join(root, "bin")
  File.mkdir!(bin)
  gh = Path.join(bin, "gh")

  File.write!(
    gh,
    "#!/bin/sh\nexec \"$IPSE_DRAFT_FIXTURE_ELIXIR\" \"$IPSE_DRAFT_FIXTURE_ROOT/../stub.exs\" \"$@\"\n"
  )

  File.chmod!(gh, 0o700)

  rows =
    for {name, tag, state, valid} <- [
          {"new stable draft", "v0.1.0", "absent", true},
          {"new RC draft", "v0.1.0-rc.2", "absent", true},
          {"recover unpublished draft", "v0.1.0", "draft", true},
          {"refuse published release", "v0.1.0", "published", true},
          {"refuse missing platform before mutation", "v0.1.0", "absent", false}
        ] do
      fixture = Path.join(root, name)
      assets = Path.join(fixture, "ipse-release-assets")
      File.mkdir_p!(assets)
      File.write!(Path.join(fixture, "state"), state)

      for platform <-
            if(valid,
              do: ["linux-x86_64-glibc-2.39", "darwin-arm64"],
              else: ["linux-x86_64-glibc-2.39"]
            ) do
        path = Path.join(assets, "ipse-0.1.0-#{platform}.tar.gz")
        File.write!(path, "synthetic fixture bytes")
        Release.write_checksum!(path)
      end

      env = [
        {"RUNNER_TEMP", fixture},
        {"IPSE_RELEASE_TAG", tag},
        {"PATH", bin <> ":" <> System.fetch_env!("PATH")},
        {"IPSE_DRAFT_FIXTURE_ROOT", fixture},
        {"IPSE_DRAFT_FIXTURE_ELIXIR", System.find_executable("elixir")},
        {"ERL_FLAGS", "+S 2:2"},
        {"ERL_CRASH_DUMP", "/dev/null"}
      ]

      {output, status} =
        System.cmd("/bin/sh", ["-ec", Enum.join(commands, "\n")],
          env: env,
          stderr_to_stdout: true
        )

      call_path = Path.join(fixture, "calls.jsonl")

      calls =
        if File.exists?(call_path),
          do:
            File.read!(call_path) |> String.split("\n", trim: true) |> Enum.map(&:json.decode/1),
          else: []

      writes =
        Enum.filter(calls, fn args ->
          Enum.take(args, 2) in [["release", "create"], ["release", "upload"]]
        end)

      cond do
        not valid ->
          true = status != 0 and writes == [] and calls == []

        state == "published" ->
          true = status != 0 and writes == []

        state == "draft" ->
          true = status == 0
          [["release", "upload", ^tag | args]] = writes
          true = "--clobber" in args
          true = length(Enum.filter(args, &String.starts_with?(&1, assets <> "/"))) == 4

        true ->
          true = status == 0
          [["release", "create", ^tag | args]] = writes
          true = "--draft" in args and "--verify-tag" in args
          true = "--prerelease" in args == String.contains?(tag, "-rc.")
          true = length(Enum.filter(args, &String.starts_with?(&1, assets <> "/"))) == 4
          notes = File.read!(Path.join(fixture, "ipse-release-notes.md"))
          true = String.contains?(notes, "/blob/#{tag}/")
      end

      %{
        case: name,
        status: "passed",
        exit_code: status,
        fixture_cli_calls: length(calls),
        mutation_commands: Enum.map(writes, &Enum.take(&1, 2)),
        output_sha256: :crypto.hash(:sha256, output) |> Base.encode16(case: :lower)
      }
    end

  File.write!("/tmp/ipse-release-offline-draft-rehearsal.json", [
    :json.encode(%{
      source: "5d9650e6642666d1da38c14cb0f6e4f768e67011",
      workflow_sha256: Release.checksum(".github/workflows/release.yml"),
      scope:
        "Exact workflow shell bodies against synthetic gh stub; no GitHub API or model request; not a real tag-push release proof",
      checks: rows
    }),
    "\n"
  ])

  IO.puts("Five offline release-flow controls passed")
after
  File.rm_rf!(root)
end
