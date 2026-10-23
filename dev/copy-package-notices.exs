# Called through Mix after release assembly; only resolved packages are considered.
[destination] = System.argv()
File.mkdir_p!(destination)

for {app, directory} <- Mix.Project.deps_paths() |> Enum.sort() do
  notices =
    File.ls!(directory) |> Enum.filter(&Regex.match?(~r/\A(LICENSE|COPYING|NOTICE)(\.|\z)/i, &1))

  notices =
    if notices == [] do
      # NimblePool 1.1.0 ships its copyright/license notice only in README.md.
      readme = Path.join(directory, "README.md")
      text = if File.regular?(readme), do: File.read!(readme), else: ""

      if String.contains?(text, ["## License", "## LICENSE"]) and
           String.contains?(text, "Copyright"),
         do: ["README.md"],
         else: raise("Missing upstream license notices for #{app}")
    else
      notices
    end

  for name <- notices do
    File.cp!(Path.join(directory, name), Path.join(destination, "#{app}-#{name}"))
  end
end
