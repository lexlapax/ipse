[descriptor, expected] = System.argv()
bytes = File.read!(descriptor)
true = Ipse.JSON.sha256(bytes) === expected
d = Jason.decode!(bytes)

for {key, env} <- [
      {"package", "IPSE_PAIRED_PACKAGE"},
      {"pty", "IPSE_PAIRED_PTY"},
      {"archive", "IPSE_PAIRED_ARCHIVE"},
      {"ex_unit", "IPSE_PAIRED_EX_UNIT"}
    ] do
  true = is_binary(d[key]) and d[key] === System.fetch_env!(env)
end

true = d["storage"] === "/run/user/1000/ipse-p30-paired-v2-current-20261106-01"
base = Path.dirname(__ENV__.file)
out = Path.join(base, "prepared-current-02")
true = d["prepared"] === true
true = Path.expand(Application.app_dir(:ipse)) === Path.join(d["package"], "lib/ipse-0.1.0")
true = Code.prepend_path(Path.join(d["ex_unit"], "ebin"))
true = Code.prepend_path(Path.join(out, "verification-ebin"))

for name <- ~w(helpers.sha256 verification.sha256) do
  content = File.read!(Path.join(out, name))

  key =
    if name === "helpers.sha256",
      do: "helper_inventory_sha256",
      else: "verification_inventory_sha256"

  true = Ipse.JSON.sha256(content) === d[key]
  {"", 0} = System.cmd("/usr/bin/sha256sum", ["--check", "--status", Path.join(out, name)])
end

Code.ensure_loaded!(Ipse.Development.Verification.Runtime)
original = File.read!(Path.join(out, "before.term"))
true = Ipse.JSON.sha256(original) === d["before_sha256"]
before = :erlang.binary_to_term(original, [:safe])

for name <- ~w(package ex_unit artifact),
    do: true = Ipse.Development.Verification.Runtime.inventory(d[name]) === before[name]

true = Ipse.Development.Verification.Runtime.digest(d["archive"]) === d["archive_sha256"]
true = Ipse.Development.Verification.Runtime.digest(d["sidecar"]) === d["sidecar_sha256"]
true = Ipse.Development.Verification.Runtime.digest(d["pty"]) === d["pty_sha256"]
reference_bytes = File.read!(d["references"])
true = Ipse.JSON.sha256(reference_bytes) === d["reference_sha256"]

case Application.load(:ipse) do
  :ok -> :ok
  {:error, {:already_loaded, :ipse}} -> :ok
end

for module <- Application.spec(:ipse, :modules) do
  true =
    to_string(:code.which(module)) ===
      Path.join([d["package"], "lib/ipse-0.1.0/ebin", Atom.to_string(module) <> ".beam"])
end

{"", 0} =
  System.cmd("/usr/bin/sha256sum", ["--check", "--status", Path.join(base, "inputs.sha256")])

false = Enum.any?(Application.started_applications(), &(elem(&1, 0) === :ipse))
IO.puts("PACKAGED_PAIRED_GUARD_PASSED")
