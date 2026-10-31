source = "_build/document-inline-v4-complete-sol-20261029"
target = "_build/combined-notes-assets-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
IO.puts("Forked exact combined Host graph; only new explicit knowledge artifact/catalog will change")
