# Generate an unprivileged, no-device diagnostic preflight probe.
source = File.read!("controller.rs")
old = """
fn main() {
    eprintln!("Live Serenity fault control is disabled: the unreviewed backend is not connected to an entry point.");
    std::process::exit(2);
}
"""
new = """
fn main() {
    let args:Vec<_>=std::env::args().collect();
    if args.len()!=3 {std::process::exit(2)}
    let host:u64=match args[2].parse(){Ok(v)=>v,Err(_)=>std::process::exit(2)};
    match owner_launcher::LaunchBoundary::validate(&args[1],host) {
        Ok(_) => println!("PREFLIGHT_OK"),
        Err(e) => { eprintln!("PREFLIGHT_REFUSED: {e}"); std::process::exit(3) }
    }
}
"""
if not String.contains?(source, old), do: raise("disabled main not found")
File.write!("boundary_preflight.rs", String.replace(source, old, new), [:exclusive])
