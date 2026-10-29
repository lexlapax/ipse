#!/usr/bin/env elixir

defmodule Ipse.DocsCheck do
  @moduledoc false

  def run do
    {listed, 0} =
      System.cmd("git", ["ls-files", "--cached", "--others", "--exclude-standard", "--", "*.md"])

    files =
      listed |> String.split("\n", trim: true) |> Enum.uniq() |> Enum.filter(&File.regular?/1)

    documents = Map.new(files, &{Path.expand(&1), read(&1)})

    {links, link_errors} =
      Enum.reduce(documents, {0, []}, fn {path, doc}, {count, errors} ->
        Enum.reduce(doc.links, {count, errors}, fn {target, line}, {n, acc} ->
          if external?(target) do
            {n, acc}
          else
            [file | fragment] = String.split(target, "#", parts: 2)

            resolved =
              if file == "", do: path, else: Path.expand(URI.decode(file), Path.dirname(path))

            error =
              cond do
                file != "" and Path.type(URI.decode(file)) == :absolute ->
                  "absolute filesystem target #{target}; use a repository-relative link"

                Path.type(Path.relative_to(resolved, File.cwd!())) != :relative ->
                  "target escapes the repository: #{target}"

                not File.exists?(resolved) ->
                  "missing target #{target}"

                fragment != [] and hd(fragment) != "" and Map.has_key?(documents, resolved) and
                    not MapSet.member?(documents[resolved].anchors, URI.decode(hd(fragment))) ->
                  "missing heading #{target}"

                true ->
                  nil
              end

            {n + 1,
             if(error, do: ["#{Path.relative_to_cwd(path)}:#{line}: #{error}" | acc], else: acc)}
          end
        end)
      end)

    manual_errors =
      for {path, doc} <- documents,
          Path.dirname(Path.relative_to_cwd(path)) in ["docs/operator", "docs/developer"],
          error <- manual_errors(doc),
          do: "#{Path.relative_to_cwd(path)}: #{error}"

    archive_errors = archive_errors()

    example_errors =
      for {path, doc} <- documents,
          not String.starts_with?(Path.relative_to_cwd(path), "docs/archive/"),
          error <- doc.errors,
          do: "#{Path.relative_to_cwd(path)}:#{error}"

    errors =
      Enum.reverse(link_errors) ++
        manual_errors ++
        example_errors ++
        index_errors(documents) ++
        test_example_errors(documents) ++
        archive_errors

    Enum.each(errors, &IO.puts(:stderr, &1))

    IO.puts(
      "Checked #{length(files)} Markdown files, #{links} local links and manual/archive rules; #{length(errors)} errors"
    )

    if errors != [], do: System.halt(1)
  end

  defp read(path) do
    initial = %{
      anchors: MapSet.new(),
      counts: %{},
      links: [],
      fence: nil,
      examples: 0,
      prose: [],
      errors: []
    }

    state =
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce(initial, fn {line, number}, state ->
        case state.fence do
          {marker, size, language, opening, contents} ->
            closing = Regex.run(~r/^\s{0,3}(`{3,}|~{3,})\s*$/, line)

            if closing && String.first(Enum.at(closing, 1)) == marker &&
                 String.length(Enum.at(closing, 1)) >= size do
              errors =
                if language == "json" do
                  try do
                    :json.decode(contents |> Enum.reverse() |> Enum.join("\n"))
                    state.errors
                  catch
                    _, _ -> ["#{opening}: invalid JSON example" | state.errors]
                  end
                else
                  state.errors
                end

              %{state | fence: nil, errors: errors}
            else
              %{state | fence: {marker, size, language, opening, [line | contents]}}
            end

          nil ->
            case Regex.run(~r/^\s{0,3}(`{3,}|~{3,})\s*([^\s]*)/, line) do
              [_, marker, language] ->
                %{
                  state
                  | fence: {String.first(marker), String.length(marker), language, number, []},
                    examples: state.examples + 1
                }

              _ ->
                read_prose(state, line, number)
            end
        end
      end)

    case state.fence do
      nil ->
        state

      {_, _, _, opening, _} ->
        %{state | errors: ["#{opening}: unclosed code fence" | state.errors]}
    end
  end

  defp read_prose(state, line, number) do
    links =
      for [_, target] <- Regex.scan(~r/\]\((<[^>\n]+>|[^\s)]+)(?:\s+"[^"\n]*")?\)/, line),
          do: {target |> String.trim_leading("<") |> String.trim_trailing(">"), number}

    state = %{state | links: links ++ state.links, prose: [line | state.prose]}

    case Regex.run(~r/^\s{0,3}\#{1,6}\s+(.+?)(?:\s+\#+)?$/, line) do
      [_, title] ->
        base =
          title
          |> String.downcase()
          |> String.replace(~r/[^\p{L}\p{M}\p{N}_\- ]/u, "")
          |> String.replace(" ", "-")

        count = Map.get(state.counts, base, 0)
        anchor = if count == 0, do: base, else: base <> "-" <> Integer.to_string(count)

        %{
          state
          | anchors: MapSet.put(state.anchors, anchor),
            counts: Map.put(state.counts, base, count + 1)
        }

      _ ->
        state
    end
  end

  defp manual_errors(doc) do
    prose = Enum.join(doc.prose, "\n")

    [
      {doc.examples == 0, "include a worked usage, code or verification example"},
      {Regex.match?(~r/\bP\d{1,2}[A-Z]?\d*\b/, prose),
       "move milestone status/history to the plan or archive"},
      {Regex.match?(~r/https:\/\/github\.com\/[^\s)]+\/actions\/runs\/\d+/, prose),
       "move dated CI receipts to the archive"},
      {Regex.match?(~r/^\#{1,6}.*\b20\d{2}-\d{2}-\d{2}\b/m, prose),
       "move dated report sections to the archive"}
    ]
    |> Enum.flat_map(fn {failed, message} -> if failed, do: [message], else: [] end)
  end

  defp external?(target),
    do: String.starts_with?(target, "//") or Regex.match?(~r/^[A-Za-z][A-Za-z0-9+.-]*:/, target)

  defp index_errors(documents) do
    for directory <- ["docs/operator", "docs/developer"],
        index = Path.expand(Path.join(directory, "index.md")),
        {path, _doc} <- documents,
        Path.dirname(path) == Path.expand(directory),
        path != index,
        not Enum.any?(Map.get(documents, index, %{links: []}).links, fn {target, _line} ->
          not external?(target) and
            Path.expand(target |> String.split("#", parts: 2) |> hd(), Path.dirname(index)) ==
              path
        end),
        do: "#{directory}/index.md: include #{Path.basename(path)} in the audience learning path"
  end

  defp archive_errors do
    {listed, 0} =
      System.cmd("git", [
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
        "--",
        "docs/archive/2026-10-18-before-manual-rewrite/manifest.json",
        "docs/archive/**/manual-provenance.json"
      ])

    manifests =
      listed |> String.split("\n", trim: true) |> Enum.uniq() |> Enum.filter(&File.regular?/1)

    for manifest <- manifests,
        item <- :json.decode(File.read!(manifest))["files"],
        snapshot =
          if(String.starts_with?(item["snapshot"], "docs/archive/"),
            do: item["snapshot"],
            else: Path.expand(item["snapshot"], Path.dirname(manifest))
          ),
        not File.regular?(snapshot) or
          Base.encode16(:crypto.hash(:sha256, File.read!(snapshot)), case: :lower) !=
            item["snapshot_sha256"],
        do: "#{snapshot}: archived snapshot differs from its provenance manifest"
  end

  defp test_example_errors(documents) do
    for {path, _doc} <- documents,
        Path.dirname(Path.relative_to_cwd(path)) in ["docs/operator", "docs/developer"],
        {line, number} <- File.read!(path) |> String.split("\n") |> Enum.with_index(1),
        [_, target] <- Regex.scan(~r/\b(test\/[A-Za-z0-9_.*\/-]+\.exs)\b/, line),
        not Enum.any?(Path.wildcard(target), &File.regular?/1),
        do: "#{Path.relative_to_cwd(path)}:#{number}: missing test example target #{target}"
  end
end

Ipse.DocsCheck.run()
