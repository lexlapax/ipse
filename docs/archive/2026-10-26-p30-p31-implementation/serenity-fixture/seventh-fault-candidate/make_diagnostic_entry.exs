# Generate a review-only candidate from the disabled fixture. The compiler
# must be passed --cfg ipse_live_reviewed to permit any device operation.
source = File.read!("controller.rs")
old = """
fn main() {
    eprintln!("Live Serenity fault control is disabled: the unreviewed backend is not connected to an entry point.");
    std::process::exit(2);
}
"""
new = ~S'''
fn main() {
    if !cfg!(ipse_live_reviewed) {eprintln!("diagnostic entry disabled");std::process::exit(2)}
    if let Err(e)=diagnostic_entry() {eprintln!("DIAGNOSTIC_UNKNOWN: {e}");std::process::exit(3)}
}
fn diagnostic_entry()->Result<(),String> {
    use std::os::fd::FromRawFd;
    use std::os::unix::fs::{OpenOptionsExt,PermissionsExt};
    use std::process::{Command,Stdio};
    unsafe extern "C" {fn fcntl(fd:i32,cmd:i32,...)->i32;}
    let a:Vec<_>=std::env::args().collect();if a.len()!=9{return Err("arguments".into())}
    let nonce=&a[1];let loop_minor:u64=a[2].parse().map_err(|_|"loop minor")?;
    let dm_major:u64=a[3].parse().map_err(|_|"mapper major")?;let dm_minor:u64=a[4].parse().map_err(|_|"mapper minor")?;
    let host_ns:u64=a[5].parse().map_err(|_|"host namespace")?;let container_id=&a[6];
    let boundary=owner_launcher::LaunchBoundary::validate(container_id,host_ns).map_err(|_|"boundary")?;
    boundary.validate_runtime().map_err(|_|"runtime mounts")?;
    let ledger=std::fs::OpenOptions::new().read(true).custom_flags(0x30000).open("/work/fixture-ledger").map_err(|_|"ledger")?;
    let host_dev:u64=a[7].parse().map_err(|_|"host dev")?;let host_ino:u64=a[8].parse().map_err(|_|"host dev inode")?;
    let boot=std::fs::read_to_string("/proc/sys/kernel/random/boot_id").map_err(|_|"boot id")?;
    let index=index_receipt::read(&ledger,nonce,boot.trim_end_matches('\n'),u32::try_from(loop_minor).map_err(|_|"loop minor")?).map_err(|_|"index receipt")?;
    private_loop_node::create(&index,&ledger,nonce,host_ns,(host_dev,host_ino)).map_err(|_|"private node pending")?;
    let dup=||->Result<std::fs::File,String>{let n=unsafe{fcntl(2,1030,3)};if n<0{return Err("stderr pipe".into())}Ok(unsafe{std::fs::File::from_raw_fd(n)})};
    let mut backend=real_backend::RealBackend::new(nonce,loop_minor,dm_major,dm_minor,host_ns,(host_dev,host_ino),120).map_err(|_|"backend preflight")?;
    backend.set_arm_inputs(boundary,ledger,dup()?,dup()?).map_err(|_|"owner inputs")?;
    let mut expected=Expected {loop_major:7,loop_minor,backing_major:0,backing_minor:0,backing_inode:0,loop_ref:format!("ipse-q-{nonce}"),dm_name:format!("ipse-q-{nonce}"),dm_uuid:format!("IPSE-Q-{nonce}"),dm_major,dm_minor,sectors:1_048_576};
    if provisioning::provision(&mut backend,&mut expected,provisioning::Status::Empty)!=provisioning::Status::Mounted{return Err("provision pending; inspect receipt".into())}
    backend.record_diagnostic(diagnostic_receipt::Record::Pending(diagnostic_receipt::Effect::PrepareStage)).map_err(|_|"stage intent")?;
    backend.set_fixture_root_private(&expected).map_err(|_|"mount root permissions")?;
    std::fs::create_dir("/work/mount/transaction").map_err(|_|"stage directory")?;
    std::fs::set_permissions("/work/mount/transaction",std::fs::Permissions::from_mode(0o700)).map_err(|_|"stage permissions")?;
    let mut peer=peer_channel_container::Channel::start("/work/mount/transaction").map_err(|_|"listener")?;
    let child=Command::new("/usr/lib/elixir/bin/elixir").env_clear().env("PATH","/usr/lib/erlang/bin:/usr/lib/elixir/bin:/usr/bin").env("ERL_FLAGS","+S 2:2 +A 1").args(["-pa","/work/runtime/lib/*/ebin","-e","Application.ensure_all_started(:ipse); Code.eval_file(\"/work/tools/share/diagnostic-stage.exs\")"]).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().map_err(|_|"stage launch")?;
    let mut stage=diagnostic_stage_channel::Stage::from_child(child).map_err(|_|"stage pipes")?;
    let beam=std::fs::File::open("/usr/lib/erlang/erts-17.1/bin/beam.smp").map_err(|_|"beam executable")?;
    stage.attest_and_activate(&beam).map_err(|_|"stage attestation")?;
    let report=diagnostic_fault::run(&mut backend,&expected,&mut peer,&mut stage).map_err(|_|"fault pending; inspect receipt")?;
    println!("DIAGNOSTIC_FRAME {report}");println!("DEVICE_TEARDOWN_UNCONFIRMED: retain and inspect exact recorded resources");Ok(())
}
'''
if not String.contains?(source, old), do: raise("disabled main not found")
File.write!("diagnostic_entry.rs", String.replace(source, old, new), [:exclusive])
