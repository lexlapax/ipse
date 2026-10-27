alias Ipse.JSON
[output]=System.argv()
archive="docs/archive/2026-10-26-p30-p31-implementation/"
runtime=Jason.decode!(File.read!(archive<>"managed-continuation-runtime.json"))
sha=fn p->JSON.sha256(File.read!(p))end
Enum.each(runtime["original_runtime"]["beams"],fn {p,expected}->true=sha.(p)==expected end)
Enum.each(runtime["original_runtime"]["sources"],fn {p,expected}->true=sha.(Path.join("/tmp/ipse-managed-storage-20261026-01/project",p))==expected end)
helper="/tmp/ipse-managed-storage-20261026-01/project/priv/ipse-runner"
true=sha.(helper)==runtime["native_helper_sha256"]
files=Path.wildcard("dev/knowledge/managed_metadata_binary*.*")++["test/dev/managed_metadata_binary_test.exs",archive<>"managed-metadata-calculation-final.json",archive<>"managed-metadata-proof-artifacts.json",archive<>"managed-continuation-runtime.json"]
report=%{kind: "pure_binary_metadata_frozen_sources",elixir: System.version(),otp: System.otp_release(),erts: to_string(:erlang.system_info(:version)),sources: Map.new(files,fn p->{p,sha.(p)}end),dependency_beams_verified: map_size(runtime["original_runtime"]["beams"]),dependency_sources_verified: map_size(runtime["original_runtime"]["sources"]),helper_sha256: sha.(helper),helper_invocations: 0}
File.write!(output,Jason.encode!(report,pretty: true)<>"\n")
IO.puts("Source freeze and560dependencyBEAM/126source/uninvokedhelper verification complete")
