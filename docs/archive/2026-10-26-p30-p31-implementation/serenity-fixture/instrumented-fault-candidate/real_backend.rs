//! Unreviewed process backend for the disabled Serenity controller.
//! Do not enable or run against devices before independent audit and approval.
use super::{Action, Backend, Expected, Observation, State};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt,FileTypeExt};
use std::os::unix::process::CommandExt;
use std::os::fd::{AsRawFd,FromRawFd};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

#[repr(C)] struct Rlimit { current: u64, maximum: u64 }
unsafe extern "C" { fn setpgid(pid: i32, pgid: i32) -> i32; fn setrlimit(resource: i32, r: *const Rlimit) -> i32; fn kill(pid: i32, sig: i32) -> i32; fn openat(fd:i32,path:*const i8,flags:i32,...)->i32; fn geteuid()->u32; }
const LIMIT: u64 = 65_536;
const MAX_COMMANDS: u64 = 128;
const WORK_COMMANDS: u64 = 96;

/// This backend presumes a separately validated private mount namespace,
/// fixture directory, staged tool image and device-cgroup configuration. Its
/// constructor cannot itself establish those properties and is not called by
/// the disabled main program.
pub(super) struct RealBackend {
    work: PathBuf,
    mount: PathBuf,
    loop_node: PathBuf,
    losetup: PathBuf,
    dmsetup: PathBuf,
    umount: PathBuf,
    mount_tool: PathBuf,
    mkfs: PathBuf,
    blkid:PathBuf,
    observed_fsuuid:Option<String>,
    original_bind:Option<super::bind_mount::Bind>,
    sysroot: PathBuf,
    expected: Expected,
    deadline: Instant,
    next: u64,
    image: Option<File>,
    // Injected only by a future authenticated guardian; constructor refuses live setup.
    loop_owner: Option<super::owner_launcher::Owner>,
    boundary:Option<super::owner_launcher::LaunchBoundary>,
    arm_inputs:Option<ArmInputs>,
    guarded_failure:Option<GuardedOwnerFailure>,
    diagnostic:Option<super::diagnostic_receipt::Receipt>,
    command_limit: u64,
    cleanup_reserved: bool,
    fixture_fsid: Option<[u8;16]>,
    fixture_mount_id:Option<u64>, fixture_ns_inode:u64,
}

struct ArmInputs {boundary:super::owner_launcher::LaunchBoundary,ledger:File,owner_stderr:File,guardian_stderr:File}
fn guardian_budget(remaining:Duration)->Result<u32,()> {let millis=remaining.as_millis();if millis==0||millis>120_000{return Err(())}u32::try_from(millis+35_000).map_err(|_| ())}
enum GuardedOwnerFailure {Owner(super::owner_launcher::LaunchFailure),Deadline(super::owner_launcher::PreparedOwner),Guardian(super::owner_launcher::PreparedOwner,super::guardian_launcher::Failure),Activate(super::owner_launcher::PreparedOwner,super::guardian_launcher::GuardianReady,std::io::Error),Install(super::owner_launcher::Owner)}

impl RealBackend {
    /// Strict constructor for a *future* container harness. This has not been
    /// exercised with real devices; main is disabled. The caller must obtain
    /// `host_mount_namespace_inode` from the host before creating the container,
    /// pin and independently attest every staged tool/library, establish device
    /// cgroup restrictions and validate the actual host's kernel/profile.
    pub(super) fn new(nonce: &str, loop_minor: u64, dm_major: u64, dm_minor: u64,
           host_mount_namespace_inode: u64, seconds: u64) -> Result<Self, ()> {
        if nonce.len()!=32 || !nonce.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase()) ||
            loop_minor>4095 || dm_major==0 || dm_major==7 || dm_minor>65535 ||
            host_mount_namespace_inode==0 || !(1..=120).contains(&seconds) { return Err(()); }
        let here=fs::metadata("/proc/self/ns/mnt").map_err(|_| ())?.ino();
        if here==host_mount_namespace_inode { return Err(()); }
        let work=PathBuf::from("/work/fixture"); let mount=PathBuf::from("/work/mount");
        for path in [&work,&mount] {
            let meta=fs::symlink_metadata(path).map_err(|_| ())?;
            if !meta.is_dir() || meta.mode()&0o777!=0o700 { return Err(()); }
        }
        if fs::read_dir(&work).map_err(|_| ())?.next().is_some() ||
            fs::read_dir(&mount).map_err(|_| ())?.next().is_some() { return Err(()); }
        let original_bind=super::bind_mount::Bind::capture(&mount).map_err(|_| ())?;
        let name=format!("ipse-q-{nonce}");
        Ok(Self { work, mount, loop_node:PathBuf::from(format!("/dev/loop{loop_minor}")),
            losetup:"/work/tools/bin/losetup".into(), dmsetup:"/work/tools/bin/dmsetup".into(),
            umount:"/work/tools/bin/umount".into(), mount_tool:"/work/tools/bin/mount".into(),
            mkfs:"/work/tools/bin/mkfs.btrfs".into(),blkid:"/work/tools/bin/blkid".into(),observed_fsuuid:None,original_bind:Some(original_bind), sysroot:"/sys".into(),
            expected:Expected { loop_major:7,loop_minor,backing_major:0,backing_minor:0,
                backing_inode:0,loop_ref:name.clone(),dm_name:name,dm_uuid:format!("IPSE-Q-{nonce}"),
                dm_major,dm_minor,sectors:1_048_576 },
            deadline:Instant::now()+Duration::from_secs(seconds), next:0, image:None,loop_owner:None,boundary:None,arm_inputs:None,guarded_failure:None,diagnostic:None,
            command_limit:WORK_COMMANDS, cleanup_reserved:false, fixture_fsid:None, fixture_mount_id:None, fixture_ns_inode:here })
    }
    pub(super) fn set_arm_inputs(&mut self,boundary:super::owner_launcher::LaunchBoundary,ledger:File,owner_stderr:File,guardian_stderr:File)->Result<(),()> {
      if self.arm_inputs.is_some()||self.loop_owner.is_some()||boundary.recheck().is_err(){return Err(())}
      self.arm_inputs=Some(ArmInputs{boundary,ledger,owner_stderr,guardian_stderr});Ok(())
    }
    pub(super) fn record_diagnostic(&mut self,r:super::diagnostic_receipt::Record)->Result<(),()> {super::diagnostic_fault::RecordedBackend::diagnostic_record(self,r)}
    /// Return every started process on
    /// failure so the external supervisor can preserve unknown state.
    fn start_guarded_owner(&mut self,boundary:&super::owner_launcher::LaunchBoundary,ledger:File,owner_stderr:File,guardian_stderr:File)->Result<(),GuardedOwnerFailure> {
        let image=match self.image.as_ref().and_then(|f|f.metadata().ok()){Some(v)=>v,None=>return Err(GuardedOwnerFailure::Owner(super::owner_launcher::LaunchFailure{child:None,error:std::io::ErrorKind::InvalidInput.into()}))};
        let nonce=match self.expected.loop_ref.strip_prefix("ipse-q-"){Some(v)=>v,None=>return Err(GuardedOwnerFailure::Owner(super::owner_launcher::LaunchFailure{child:None,error:std::io::ErrorKind::InvalidInput.into()}))};
        let minor=match u32::try_from(self.expected.loop_minor){Ok(v)=>v,Err(_)=>return Err(GuardedOwnerFailure::Owner(super::owner_launcher::LaunchFailure{child:None,error:std::io::ErrorKind::InvalidInput.into()}))};
        let setup=(||->std::io::Result<(super::diagnostic_receipt::Receipt,super::index_receipt::Index)>{
            if image.nlink()!=1||image.len()!=536_870_912{return Err(std::io::ErrorKind::InvalidInput.into())}
            let node=std::fs::symlink_metadata(&self.loop_node)?;if !node.file_type().is_block_device()||Self::block_device_matches(&self.loop_node,self.expected.loop_major,self.expected.loop_minor)!=Ok(true){return Err(std::io::ErrorKind::InvalidInput.into())}
            let mut boot=String::new();File::open("/proc/sys/kernel/random/boot_id")?.take(64).read_to_string(&mut boot)?;let boot=boot.trim_end_matches('\n').to_owned();
            let index=super::index_receipt::read(&ledger,nonce,&boot,minor)?;
            let mut receipt=super::diagnostic_receipt::Receipt::create(ledger.try_clone()?,nonce)?;
            receipt.bind_initial(&super::diagnostic_receipt::InitialIdentity{nonce:nonce.into(),boot_id:boot,backing_dev:image.dev(),backing_inode:image.ino(),loop_minor:minor,loop_node_dev:node.dev(),loop_node_inode:node.ino()})?;Ok((receipt,index))
        })();
        let (receipt,index)=setup.map_err(|error|GuardedOwnerFailure::Owner(super::owner_launcher::LaunchFailure{child:None,error}))?;self.diagnostic=Some(receipt);
        let prepared=super::owner_launcher::launch(boundary,Path::new("/work/tools/bin/ipse-loop-owner"),index,nonce,image.dev(),image.ino(),owner_stderr).map_err(GuardedOwnerFailure::Owner)?;
        let remaining=self.deadline.saturating_duration_since(Instant::now());let guardian_timeout=match guardian_budget(remaining){Ok(v)=>v,Err(_)=>return Err(GuardedOwnerFailure::Deadline(prepared))};
        let guardian=match super::guardian_launcher::launch(boundary,ledger,prepared.pid(),nonce,guardian_timeout,guardian_stderr){Ok(v)=>v,Err(f)=>return Err(GuardedOwnerFailure::Guardian(prepared,f))};
        let owner=match prepared.activate(guardian){Ok(v)=>v,Err((p,g,e))=>return Err(GuardedOwnerFailure::Activate(p,g,e))};
        match self.install_owner(owner){Ok(())=>{self.boundary=Some(boundary.clone());Ok(())},Err((owner,_))=>Err(GuardedOwnerFailure::Install(owner))}
    }
    /// Called only after a guardian has launched and attested the exact owner.
    fn install_owner(&mut self,owner:super::owner_launcher::Owner)->Result<(),(super::owner_launcher::Owner,())> {
        let valid=(||->Result<bool,()> {let backing=self.image.as_ref().ok_or(())?.metadata().map_err(|_| ())?;Ok(self.loop_owner.is_none()&&owner.matches(u32::try_from(self.expected.loop_minor).map_err(|_| ())?,&self.expected.loop_ref,backing.dev(),backing.ino()))})();
        if valid!=Ok(true){return Err((owner,()))}
        self.loop_owner=Some(owner);Ok(())
    }
    /// Explicitly reserve a separately bounded cleanup window after a known
    /// restored state. Never invoke this automatically after an unknown effect.
    /// State provenance and container/cgroup cleanup remain caller obligations.
    fn reserve_cleanup(&mut self, state: State) -> Result<(), ()> {
        if state != State::LinearActive || self.cleanup_reserved { return Err(()); }
        self.cleanup_reserved=true;
        self.command_limit=self.next.saturating_add(32).min(MAX_COMMANDS);
        self.deadline=Instant::now()+Duration::from_secs(30);
        Ok(())
    }
    fn capture(&mut self, binary: &Path, args: &[String]) -> Result<String, ()> {
        let capture_step=if binary==self.mkfs {"Format"}else{"Other"};
        if self.loop_owner.as_ref().is_some_and(|owner|!owner.guardian_live()){self.report_refusal(&format!("step={capture_step} capture guardian_not_live"));return Err(())}
        if self.boundary.as_ref().is_some_and(|boundary|boundary.recheck().is_err()){self.report_refusal(&format!("step={capture_step} capture boundary_recheck_failed"));return Err(())}
        if Instant::now() >= self.deadline {self.report_refusal(&format!("step={capture_step} capture deadline_expired"));return Err(())}
        if self.next >= self.command_limit {self.report_refusal(&format!("step={capture_step} capture command_limit"));return Err(())}
        if !binary.is_absolute() {self.report_refusal(&format!("step={capture_step} capture binary_not_absolute"));return Err(())}
        let metadata = match fs::symlink_metadata(binary){Ok(m)=>m,Err(e)=>{self.report_refusal(&format!("step={capture_step} capture binary_metadata errno={:?}",e.raw_os_error()));return Err(())}};
        if !metadata.is_file() || metadata.nlink() != 1 || metadata.mode() & 0o022 != 0 {
            self.report_refusal(&format!("step={capture_step} capture unsafe_binary_metadata"));
            return Err(());
        }
        self.next += 1;
        let path = self.work.join(format!("command-{:03}.output", self.next));
        let output = match OpenOptions::new().write(true).read(true).create_new(true).mode(0o600)
            .open(path) {Ok(f)=>f,Err(e)=>{self.report_refusal(&format!("step={capture_step} capture output_create errno={:?}",e.raw_os_error()));return Err(())}};
        let error = output.try_clone().map_err(|_| ())?;
        let mut command = Command::new(binary);
        command.args(args).env_clear().env("LC_ALL", "C").env("LD_LIBRARY_PATH", "/work/tools/lib")
            .stdin(Stdio::null())
            .stdout(Stdio::from(output.try_clone().map_err(|_| ())?)).stderr(Stdio::from(error));
        // A dedicated process group lets a deadline signal this fixture's tool
        // and its descendants, but a task stuck in uninterruptible kernel I/O
        // may survive: that is unknown and requires manual inspection.
        unsafe { command.pre_exec(|| {
            if setpgid(0, 0) != 0 { return Err(std::io::Error::last_os_error()); }
            let r = Rlimit { current: LIMIT, maximum: LIMIT };
            if setrlimit(1, &r) != 0 { return Err(std::io::Error::last_os_error()); }
            Ok(())
        }); }
        let mut child = command.spawn().map_err(|_| ())?;
        let group = i32::try_from(child.id()).map_err(|_| ())?;
        let status = loop {
            match child.try_wait() {
                Ok(Some(status)) => break status,
                Ok(None) if Instant::now() < self.deadline => std::thread::sleep(Duration::from_millis(10)),
                _ => {
                    unsafe { kill(-group, 9); }
                    let cleanup_deadline = Instant::now() + Duration::from_secs(2);
                    while Instant::now() < cleanup_deadline {
                        if matches!(child.try_wait(), Ok(Some(_))) { break; }
                        std::thread::sleep(Duration::from_millis(10));
                    }
                    return Err(());
                }
            }
        };
        // A successful direct child does not prove its descendants exited.
        // Once reaped, the numeric process-group identity can be reused; do
        // not signal it. Return unknown and require separate cgroup recovery.
        if !group_absent(group) {
            return Err(());
        }
        if !status.success() { return Err(()); }
        let metadata = output.metadata().map_err(|_| ())?;
        if metadata.len() > LIMIT { return Err(()); }
        let mut bytes = Vec::new();
        let mut read = output; use std::io::{Seek, SeekFrom};
        read.seek(SeekFrom::Start(0)).map_err(|_| ())?;
        read.take(LIMIT + 1).read_to_end(&mut bytes).map_err(|_| ())?;
        if bytes.len() > LIMIT as usize { return Err(()); }
        String::from_utf8(bytes).map_err(|_| ())
    }
    fn loop_info(&mut self) -> Result<String, ()> {
        let tool = self.losetup.clone();
        let node = self.loop_node.to_str().ok_or(())?.to_owned();
        let output = self.capture(&tool, &vec!["--list".into(), "--raw".into(), "--noheadings".into(),
            "--output".into(), "BACK-INO,BACK-MAJ:MIN,MAJ:MIN,OFFSET,SIZELIMIT,RO,REF".into(), node])?;
        let fields: Vec<_> = output.split_ascii_whitespace().collect();
        if fields.len() != 7 { return Err(()); }
        Ok(fields.join("|"))
    }
    fn dm(&mut self, args: &[String]) -> Result<String, ()> { let tool = self.dmsetup.clone(); self.capture(&tool, args) }
    fn fixed_name(&self, e: &Expected) -> Result<(), ()> {
        if &self.expected != e { return Err(()); }
        if self.loop_node != PathBuf::from(format!("/dev/loop{}", e.loop_minor)) { return Err(()); }
        if self.mount != PathBuf::from("/work/mount") { return Err(()); }
        Ok(())
    }
    fn table(&mut self, inactive: bool) -> Result<Option<String>, ()> {
        let mut args = vec![];
        if inactive { args.push("--inactive".into()); }
        args.extend(["table".into(), self.expected.dm_name.clone()]);
        let output = self.dm(&args)?;
        let lines: Vec<_> = output.lines().filter(|x| !x.trim().is_empty()).collect();
        match lines.as_slice() { [] if inactive => Ok(None), [line] => Ok(Some((*line).into())), _ => Err(()) }
    }
    fn mapper_absence_from_sysfs(&self, e: &Expected) -> Result<bool, ()> {
        let class = self.sysroot.join("class/block");
        let dev = self.sysroot.join(format!("dev/block/{}:{}", e.dm_major, e.dm_minor));
        let mut count = 0usize;
        for entry in fs::read_dir(class).map_err(|_| ())? {
            count += 1; if count > 40_000 { return Err(()); }
            let path = entry.map_err(|_| ())?.path().join("dm");
            match fs::metadata(&path) {
                Ok(meta) if meta.is_dir() => (),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                _ => return Err(()),
            }
            let name = read_small(&path.join("name"))?;
            let uuid = read_small(&path.join("uuid"))?;
            if name == e.dm_name || uuid == e.dm_uuid { return Ok(false); }
        }
        match fs::metadata(dev) {
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(true),
            _ => Err(()),
        }
    }
    // Best effort only: failure or a missing receipt is always unknown. This
    // independent one-shot receipt is outside the normal command budget.
    fn refusal_with_sync(&self,text:&str,sync:impl FnOnce(&File,&File)->std::io::Result<()>)->std::io::Result<(u64,u64)> {
        let directory=OpenOptions::new().read(true).custom_flags(0x30000).open(&self.work)?;let d=directory.metadata()?;
        let named=fs::symlink_metadata(&self.work)?;
        if !d.is_dir() || d.uid()!=unsafe{geteuid()} || d.mode()&0o7777!=0o700 || (d.dev(),d.ino())!=(named.dev(),named.ino()){return Err(std::io::ErrorKind::PermissionDenied.into())}
        let raw=unsafe{openat(directory.as_raw_fd(),c"refusal.receipt".as_ptr(),0x40|0x80|1|0x20000|0x80000,0o600)};
        if raw<0{return Err(std::io::Error::last_os_error())}let mut f=unsafe{File::from_raw_fd(raw)};
        writeln!(f,"v1 ref={} sequence={} stage={}:{} branch={text}",self.expected.loop_ref,self.next,d.dev(),d.ino())?;
        sync(&f,&directory)?;Ok((d.dev(),d.ino()))
    }
    fn sync_refusal(file:impl FnOnce()->std::io::Result<()>,dir:impl FnOnce()->std::io::Result<()>)->std::io::Result<()> {file()?;dir()}
    fn report_refusal(&self,text:&str) {
        self.report_refusal_with(text,|f,d|Self::sync_refusal(||f.sync_all(),||d.sync_all()))
    }
    fn report_refusal_with(&self,text:&str,sync:impl FnOnce(&File,&File)->std::io::Result<()>) {
        match self.refusal_with_sync(text,sync) {Ok((dev,ino))=>eprintln!("REFUSAL_SYNCED ref={} sequence={} stage={dev}:{ino} branch={text}",self.expected.loop_ref,self.next),Err(e)=>eprintln!("REFUSAL_UNKNOWN errno={:?}",e.raw_os_error())}
    }
    fn effect_guard(&self,step:super::provisioning::Step,guardian_failed:bool,boundary_failed:bool)->Result<(),()> {
        if guardian_failed {self.report_refusal(&format!("step={step:?} effect guardian_not_live"));return Err(())}
        if boundary_failed {self.report_refusal(&format!("step={step:?} effect boundary_recheck_failed"));return Err(())}Ok(())
    }
    fn ledger(&mut self, text: &str) -> Result<(), ()> {
        if self.next >= self.command_limit || Instant::now() >= self.deadline || text.len() > 1024 {
            return Err(());
        }
        self.next += 1;
        let path = self.work.join(format!("journal-{:03}", self.next));
        let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(path).map_err(|_| ())?;
        writeln!(file, "{text} expected={:?}", self.expected).map_err(|_| ())?;
        file.sync_all().map_err(|_| ())?;
        File::open(&self.work).map_err(|_| ())?.sync_all().map_err(|_| ())
    }
    fn record_fixture_fsid(&mut self,e:&Expected)->Result<(),()> {
        if self.fixture_fsid.is_some(){return Err(())}
        let mount=File::open(&self.mount).map_err(|_| ())?;let info=super::btrfs_identity::inspect(&mount,&self.sysroot).map_err(|_| ())?;
        let major=u32::try_from(e.dm_major).map_err(|_| ())?;let minor=u32::try_from(e.dm_minor).map_err(|_| ())?;
        if info.underlying!=(major,minor){return Err(())}
        let fsid=info.fsid.iter().map(|b|format!("{b:02x}")).collect::<String>();
        self.ledger(&format!("fixture_fsid={fsid} mount_id={} namespace_inode={}",info.mount_id,self.fixture_ns_inode))?;
        self.fixture_fsid=Some(info.fsid);self.fixture_mount_id=Some(info.mount_id);
        if self.fixture_mount(e)!=Ok(true){return Err(())}Ok(())
    }
    fn image_path(&self) -> Result<PathBuf, ()> {
        if self.work != PathBuf::from("/work/fixture") { return Err(()); }
        Ok(self.work.join("backing.img"))
    }
    fn block_device_matches(path: &Path, major: u64, minor: u64) -> Result<bool, ()> {
        use std::os::unix::fs::FileTypeExt;
        let meta = fs::metadata(path).map_err(|_| ())?;
        if !meta.file_type().is_block_device() { return Err(()); }
        Ok(device_numbers(meta.rdev()) == (major, minor))
    }
    fn format_node_check(&self,path:&Path,major:u64,minor:u64)->Result<(),()> {
        use std::os::unix::fs::FileTypeExt;
        let meta=match fs::metadata(path){Ok(m)=>m,Err(e)=>{self.report_refusal(&format!("step=Format format node_metadata errno={:?}",e.raw_os_error()));return Err(())}};
        if !meta.file_type().is_block_device(){self.report_refusal("step=Format format node_not_block");return Err(())}
        self.format_node_numbers(device_numbers(meta.rdev()),(major,minor))
    }
    fn format_node_numbers(&self,observed:(u64,u64),expected:(u64,u64))->Result<(),()> {if observed!=expected {self.report_refusal(&format!("step=Format format node_wrong_device observed={observed:?}"));return Err(())}Ok(())}
}

fn group_absent(group: i32) -> bool {
    let result=unsafe { kill(-group,0) };
    result<0 && std::io::Error::last_os_error().raw_os_error()==Some(3) // ESRCH
}

fn device_numbers(value: u64) -> (u64,u64) {
    (((value >> 8) & 0xfff) | ((value >> 32) & 0xffff_f000),
     (value & 0xff) | ((value >> 12) & 0xffff_ff00))
}

fn read_small(path: &Path) -> Result<String, ()> {
    let file = File::open(path).map_err(|_| ())?;
    let mut bytes = Vec::new(); file.take(257).read_to_end(&mut bytes).map_err(|_| ())?;
    if bytes.is_empty() || bytes.len() > 256 { return Err(()); }
    let value = String::from_utf8(bytes).map_err(|_| ())?;
    let value = value.trim_end_matches('\n');
    if value.is_empty() || value.contains('\n') || value.contains('\r') { return Err(()); }
    Ok(value.into())
}

fn assigned_loop_absent(output: &str, expected: (u64,u64)) -> Result<bool, ()> {
    let mut count = 0usize;
    for row in output.lines().filter(|x| !x.trim().is_empty()) {
        count += 1; if count > 40_000 { return Err(()); }
        let mut parts = row.trim().split(':');
        let major = parts.next().ok_or(())?.parse::<u64>().map_err(|_| ())?;
        let minor = parts.next().ok_or(())?.parse::<u64>().map_err(|_| ())?;
        if parts.next().is_some() { return Err(()); }
        if (major,minor) == expected { return Ok(false); }
    }
    Ok(true)
}

impl Backend for RealBackend {
    fn journal(&mut self, state: State, action: Option<Action>) -> Result<(), ()> {
        // Commands and ledger use one bounded monotonic sequence. Existing file
        // is a hard refusal; no journal is reused or guessed after a crash.
        self.ledger(&format!("state={state:?} action={action:?}"))
    }
    fn observe(&mut self) -> Result<Observation, ()> {
        self.fixed_name(&self.expected)?;
        let loop_row = self.loop_info()?;
        let name = self.expected.dm_name.clone();
        let info = self.dm(&["--columns".into(), "--noheadings".into(), "--separator".into(), "|".into(),
            "-o".into(), "name,uuid,major,minor,open".into(), "info".into(), name])?;
        let mut lines = info.lines().filter(|x| !x.trim().is_empty());
        let mapper_row = lines.next().ok_or(())?.to_owned();
        if lines.next().is_some() { return Err(()); }
        let active = self.table(false)?.ok_or(())?;
        let inactive = self.table(true)?;
        Ok(Observation { loop_row, mapper_row, active, inactive })
    }
    fn observe_loop(&mut self) -> Result<String, ()> { self.loop_info() }
    fn effect(&mut self, action: Action, e: &Expected) -> Result<(), ()> {
        if self.loop_owner.as_ref().is_some_and(|owner|!owner.guardian_live()){return Err(())}
        if self.boundary.as_ref().is_some_and(|boundary|boundary.recheck().is_err()){return Err(())}
        self.fixed_name(e)?;
        let name = e.dm_name.clone();
        match action {
            Action::Suspend => { self.dm(&["--noflush".into(), "--nolockfs".into(), "suspend".into(), name])?; }
            Action::LoadError => { self.dm(&["reload".into(), name, "--table".into(), format!("0 {} error", e.sectors)])?; }
            Action::LoadLinear => { self.dm(&["reload".into(), name, "--table".into(), format!("0 {} linear {}:{} 0", e.sectors,e.loop_major,e.loop_minor)])?; }
            Action::Resume => { self.dm(&["resume".into(), name])?; }
            Action::Unmount => { return Err(()); } // Path-based umount cannot prove held mount identity.
            Action::RemoveMapper => { self.dm(&["remove".into(), name])?; }
            Action::DetachLoop => { self.loop_owner.as_mut().ok_or(())?.rundown_close().map_err(|_| ())?; }
        }; Ok(())
    }
    fn fixture_mount(&mut self, e: &Expected) -> Result<bool, ()> {
        self.fixed_name(e)?;
        let expected_mount=match self.original_bind.as_ref().ok_or(())?.observe().map_err(|_| ())? {None=>return Ok(false),Some(id)=>id};
        let named=fs::symlink_metadata(&self.mount).map_err(|_| ())?;
        let held=File::open(&self.mount).map_err(|_| ())?;
        let meta=held.metadata().map_err(|_| ())?;
        if !meta.is_dir() || (named.dev(),named.ino())!=(meta.dev(),meta.ino()) {return Err(())}
        let info=super::btrfs_identity::inspect(&held,&self.sysroot).map_err(|_| ())?;
        let major=u32::try_from(e.dm_major).map_err(|_| ())?;let minor=u32::try_from(e.dm_minor).map_err(|_| ())?;
        if fs::metadata("/proc/self/ns/mnt").map_err(|_| ())?.ino()!=self.fixture_ns_inode || self.fixture_fsid!=Some(info.fsid) || self.fixture_mount_id!=Some(info.mount_id) || info.mount_id!=expected_mount || info.underlying!=(major,minor) {return Err(())}
        let after=fs::symlink_metadata(&self.mount).map_err(|_| ())?;
        if (after.dev(),after.ino())!=(meta.dev(),meta.ino()) {return Err(())}
        Ok(true)
    }
    fn mapper_absent(&mut self, e: &Expected) -> Result<bool, ()> {
        self.fixed_name(e)?;
        self.mapper_absence_from_sysfs(e)
    }
    fn loop_absent(&mut self, e: &Expected) -> Result<bool, ()> {
        self.fixed_name(e)?;
        // An unbound status or missing losetup row does not establish final
        // file-description release. The diagnostic must remain unknown.
        Err(())
    }
    fn loop_has_no_holders(&mut self, e: &Expected) -> Result<bool, ()> {
        self.fixed_name(e)?;
        let path = self.sysroot.join(format!("dev/block/{}:{}/holders",e.loop_major,e.loop_minor));
        let mut entries = fs::read_dir(path).map_err(|_| ())?;
        match entries.next() { None => Ok(true), Some(Ok(_)) => Ok(false), Some(Err(_)) => Err(()) }
    }
}

impl super::provisioning::Backend for RealBackend {
    fn arm_owner(&mut self,e:&Expected)->Result<(),()> {
        self.expected=e.clone();
        if self.loop_owner.is_some(){return Err(())}
        let inputs=self.arm_inputs.take().ok_or(())?;
        match self.start_guarded_owner(&inputs.boundary,inputs.ledger,inputs.owner_stderr,inputs.guardian_stderr) {Ok(())=>Ok(()),Err(failure)=>{self.guarded_failure=Some(failure);Err(())}}
    }
    fn pending(&mut self, step: super::provisioning::Step) -> Result<(), ()> {
        use super::provisioning::Step;use super::diagnostic_receipt::{Effect,Record};
        self.ledger(&format!("provision_pending={step:?}"))?;
        let effect=match step {Step::Backing=>return Ok(()),Step::Loop=>Effect::ConfigureLoop,Step::Mapper=>Effect::CreateMapper,Step::Format=>Effect::MakeFilesystem,Step::Mount=>Effect::Mount};
        self.diagnostic.as_mut().ok_or(())?.record(Record::Pending(effect)).map_err(|_| ())
    }
    fn confirmed(&mut self, state: super::provisioning::Status) -> Result<(), ()> {
        use super::provisioning::Status;use super::diagnostic_receipt::{Effect,Observation,Record};
        let effect=match state {Status::BackingReady=>return self.ledger(&format!("provision_confirmed={state:?}")),Status::LoopReady=>Effect::ConfigureLoop,Status::MapperReady=>{let o=Observation::Mapper{major:u32::try_from(self.expected.dm_major).map_err(|_| ())?,minor:u32::try_from(self.expected.dm_minor).map_err(|_| ())?,uuid:self.expected.dm_uuid.clone()};self.diagnostic.as_mut().ok_or(())?.observe(o).map_err(|_| ())?;Effect::CreateMapper},Status::Formatted=>{
          let dev=format!("/dev/mapper/{}",self.expected.dm_name);if Self::block_device_matches(Path::new(&dev),self.expected.dm_major,self.expected.dm_minor)!=Ok(true){return Err(())}
          let tool=self.blkid.clone();let uuid=self.capture(&tool,&["-p".into(),"-s".into(),"UUID".into(),"-o".into(),"value".into(),dev.clone()])?.trim().to_owned();
          if Self::block_device_matches(Path::new(&dev),self.expected.dm_major,self.expected.dm_minor)!=Ok(true){return Err(())}
          self.diagnostic.as_mut().ok_or(())?.observe(Observation::Filesystem{uuid:uuid.clone()}).map_err(|_| ())?;self.observed_fsuuid=Some(uuid);Effect::MakeFilesystem},Status::Mounted=>{
          let b=self.fixture_fsid.ok_or(())?;let uuid=format!("{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]);
          if self.observed_fsuuid.as_ref()!=Some(&uuid){return Err(())}let o=Observation::Mount{namespace_inode:self.fixture_ns_inode,mount_id:self.fixture_mount_id.ok_or(())?};self.diagnostic.as_mut().ok_or(())?.observe(o).map_err(|_| ())?;Effect::Mount},_=>return Err(())};
        self.diagnostic.as_mut().ok_or(())?.record(Record::Confirmed(effect)).map_err(|_| ())?;self.ledger(&format!("provision_confirmed={state:?}"))
    }
    fn effect(&mut self, step: super::provisioning::Step, e: &Expected) -> Result<(), ()> {
        self.effect_guard(step,self.loop_owner.as_ref().is_some_and(|owner|!owner.guardian_live()),false)?;
        self.effect_guard(step,false,self.boundary.as_ref().is_some_and(|boundary|boundary.recheck().is_err()))?;
        use super::provisioning::Step;
        if self.fixed_name(e).is_err(){self.report_refusal(&format!("step={step:?} effect fixed_name_failed"));return Err(())}
        let image_path = match self.image_path(){Ok(p)=>p,Err(())=>{self.report_refusal(&format!("step={step:?} effect image_path_failed"));return Err(())}};
        let device = format!("/dev/mapper/{}",e.dm_name);
        match step {
            Step::Backing => {
                if self.image.is_some() { return Err(()); }
                let file = OpenOptions::new().read(true).write(true).create_new(true).mode(0o600)
                    .open(image_path).map_err(|_| ())?;
                file.set_len(536_870_912).map_err(|_| ())?;
                file.sync_all().map_err(|_| ())?;
                File::open(&self.work).map_err(|_| ())?.sync_all().map_err(|_| ())?;
                self.image = Some(file);
            }
            Step::Loop => {
                if !Self::block_device_matches(&self.loop_node,e.loop_major,e.loop_minor)? { return Err(()); }
                // The held-FD owner performs LOOP_CONFIGURE atomically. A pipe
                // alone does not authenticate its identity; the unimplemented
                // guardian must install this client after attestation.
                self.loop_owner.as_mut().ok_or(())?.configure().map_err(|_| ())?;
            }
            Step::Mapper => {
                self.dm(&["create".into(),e.dm_name.clone(),"--uuid".into(),e.dm_uuid.clone(),
                    "--major".into(),e.dm_major.to_string(),"--minor".into(),e.dm_minor.to_string(),
                    "--addnodeoncreate".into(),"--table".into(),format!("0 {} linear {}:{} 0",e.sectors,e.loop_major,e.loop_minor)])?;
            }
            Step::Format => {
                self.format_node_check(Path::new(&device),e.dm_major,e.dm_minor)?;
                let tool=self.mkfs.clone();
                self.capture(&tool, &["--metadata".into(),"single".into(),"--data".into(),"single".into(),device])?;
            }
            Step::Mount => {
                if !Self::block_device_matches(Path::new(&device),e.dm_major,e.dm_minor)? { return Err(()); }
                let tool=self.mount_tool.clone();
                self.capture(&tool, &["-t".into(),"btrfs".into(),"-o".into(),"noatime".into(),device,
                    self.mount.to_str().ok_or(())?.into()])?;
                self.record_fixture_fsid(e)?;
            }
        }
        Ok(())
    }
    fn created_backing_identity(&mut self) -> Result<(u64,u64,u64), ()> {
        let file = self.image.as_ref().ok_or(())?;
        let metadata = file.metadata().map_err(|_| ())?;
        if !metadata.is_file() || metadata.nlink()!=1 || metadata.len()!=536_870_912 || metadata.mode()&0o777!=0o600 { return Err(()); }
        let (major,minor)=device_numbers(metadata.dev());
        self.expected.backing_major=major; self.expected.backing_minor=minor;
        self.expected.backing_inode=metadata.ino();
        Ok((major,minor,metadata.ino()))
    }
    fn backing_matches(&mut self, e: &Expected) -> Result<bool, ()> {
        self.fixed_name(e)?;
        let file=self.image.as_ref().ok_or(())?; let held=file.metadata().map_err(|_| ())?;
        let named=fs::symlink_metadata(self.image_path()?).map_err(|_| ())?;
        Ok(held.is_file() && named.is_file() && held.nlink()==1 && named.nlink()==1 &&
           held.dev()==named.dev() && held.ino()==named.ino() && held.len()==536_870_912 &&
           held.ino()==e.backing_inode && device_numbers(held.dev())==(e.backing_major,e.backing_minor))
    }
    fn loop_unassigned(&mut self, e: &Expected) -> Result<bool, ()> {
        // Selection hint only. The held owner still requires same-FD ENXIO
        // and atomic LOOP_CONFIGURE; this never proves final release.
        self.fixed_name(e)?;let tool=self.losetup.clone();let output=self.capture(&tool,&["--list".into(),"--raw".into(),"--noheadings".into(),"--output".into(),"MAJ:MIN".into()])?;assigned_loop_absent(&output,(e.loop_major,e.loop_minor))
    }
    fn mapper_unassigned(&mut self, e: &Expected) -> Result<bool, ()> {
        super::Backend::mapper_absent(self,e)
    }
    fn loop_row(&mut self) -> Result<String, ()> { self.loop_info() }
    fn observation(&mut self) -> Result<Observation, ()> { super::Backend::observe(self) }
    fn no_holders(&mut self, e: &Expected) -> Result<bool, ()> {
        self.fixed_name(e)?;
        let path=self.sysroot.join(format!("dev/block/{}:{}/holders",e.dm_major,e.dm_minor));
        let mut entries=fs::read_dir(path).map_err(|_| ())?;
        match entries.next() { None=>Ok(true), Some(Ok(_))=>Ok(false), Some(Err(_))=>Err(()) }
    }
    fn loop_held_only_by_mapper(&mut self, e: &Expected) -> Result<bool, ()> {
        self.fixed_name(e)?;
        let path=self.sysroot.join(format!("dev/block/{}:{}/holders",e.loop_major,e.loop_minor));
        let mut observed=0;
        for entry in fs::read_dir(path).map_err(|_| ())? {
            observed+=1; if observed>1 { return Ok(false); }
            let dev=read_small(&entry.map_err(|_| ())?.path().join("dev"))?;
            if dev!=format!("{}:{}",e.dm_major,e.dm_minor) { return Ok(false); }
        }
        Ok(observed==1)
    }
    fn mounted(&mut self, e: &Expected) -> Result<bool, ()> { super::Backend::fixture_mount(self,e) }
}

#[cfg(test)] mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(0);
    fn backend() -> (RealBackend, PathBuf) {
        let path = std::env::temp_dir().join(format!("ipse-fault-controller-test-{}-{}",std::process::id(),NEXT.fetch_add(1,Ordering::Relaxed)));
        fs::create_dir(&path).unwrap(); fs::set_permissions(&path,fs::Permissions::from_mode(0o700)).unwrap();
        let nonce = "0123456789abcdef0123456789abcdef";
        let expected = Expected { loop_major:7,loop_minor:42,backing_major:0,backing_minor:37,backing_inode:221,
            loop_ref:format!("ipse-q-{nonce}"),dm_name:format!("ipse-q-{nonce}"),dm_uuid:format!("IPSE-Q-{nonce}"),dm_major:253,dm_minor:11,sectors:1_048_576 };
        (RealBackend {work:path.clone(),mount:"/work/mount".into(),loop_node:"/dev/loop42".into(),
            losetup:"/usr/bin/losetup".into(),dmsetup:"/usr/bin/dmsetup".into(),umount:"/usr/bin/umount".into(),
            mount_tool:"/usr/bin/mount".into(),mkfs:"/usr/bin/mkfs.btrfs".into(),blkid:"/usr/bin/blkid".into(),observed_fsuuid:None,original_bind:None,sysroot:"/sys".into(),
            expected,deadline:Instant::now()+Duration::from_secs(3),next:0,image:None,loop_owner:None,boundary:None,arm_inputs:None,guarded_failure:None,diagnostic:None,
            command_limit:WORK_COMMANDS,cleanup_reserved:false,fixture_fsid:None,fixture_mount_id:None,fixture_ns_inode:fs::metadata("/proc/self/ns/mnt").unwrap().ino()},path)
    }
    #[test] fn guardian_deadline_follows_backend_with_reserved_grace() {assert!(guardian_budget(Duration::ZERO).is_err());assert_eq!(guardian_budget(Duration::from_millis(1)).unwrap(),35_001);assert_eq!(guardian_budget(Duration::from_secs(120)).unwrap(),155_000);assert!(guardian_budget(Duration::from_millis(120_001)).is_err());}
    #[test] fn format_node_diagnostic_records_missing_and_wrong_file_kind() {
        let (b,p)=backend();
        let missing=p.join("missing-node");
        assert!(b.format_node_check(&missing,252,4094).is_err());
        assert!(fs::read_to_string(p.join("refusal.receipt")).unwrap().ends_with("branch=step=Format format node_metadata errno=Some(2)\n"));
        fs::remove_file(p.join("refusal.receipt")).unwrap();
        let ordinary=p.join("ordinary-node");
        fs::write(&ordinary,b"fixture").unwrap();
        assert!(b.format_node_check(&ordinary,252,4094).is_err());
        assert!(fs::read_to_string(p.join("refusal.receipt")).unwrap().ends_with("branch=step=Format format node_not_block\n"));
        assert!(RealBackend::block_device_matches(&missing,252,4094).is_err());
        assert!(RealBackend::block_device_matches(&ordinary,252,4094).is_err());
        drop(b);fs::remove_file(ordinary).unwrap();fs::remove_file(p.join("refusal.receipt")).unwrap();fs::remove_dir(p).unwrap();
    }
    #[test] fn captured_output_and_exclusive_journal_are_bounded() {
        let (mut b,path)=backend();
        let result=b.capture(Path::new("/usr/bin/printf"), &["fixture".into()]).unwrap();
        assert_eq!(result,"fixture");
        assert!(b.journal(State::FaultPending,Some(Action::Suspend)).is_ok());
        assert!(path.join("command-001.output").is_file());
        assert!(path.join("journal-002").is_file());
        fs::remove_dir_all(path).unwrap();
    }
    #[test] fn deadline_kills_only_owned_test_process_group() {
        let (mut b,path)=backend(); b.deadline=Instant::now()+Duration::from_millis(150);
        let started=Instant::now();
        assert!(b.capture(Path::new("/usr/bin/sleep"), &["5".into()]).is_err());
        assert!(started.elapsed()<Duration::from_secs(3));
        fs::remove_dir_all(path).unwrap();
    }
    #[test] fn output_file_collision_refuses_before_start() {
        let (mut b,path)=backend(); fs::write(path.join("command-001.output"),"keep").unwrap();
        assert!(b.capture(Path::new("/usr/bin/printf"), &["overwrite".into()]).is_err());
        assert_eq!(fs::read_to_string(path.join("command-001.output")).unwrap(),"keep");
        assert!(fs::read_to_string(path.join("refusal.receipt")).unwrap().ends_with("branch=step=Other capture output_create errno=Some(17)\n"));
        fs::remove_dir_all(path).unwrap();
    }
    #[test] fn refusal_is_one_shot_and_missing_receipt_is_not_success() {
        let (mut b,path)=backend();fs::write(path.join("refusal.receipt"),"existing").unwrap();
        assert!(b.capture(Path::new("/no-such-fault-tool"), &[]).is_err());
        assert_eq!(fs::read_to_string(path.join("refusal.receipt")).unwrap(),"existing");
        fs::remove_file(path.join("refusal.receipt")).unwrap();
        assert!(b.capture(Path::new("/no-such-fault-tool"), &[]).is_err());
        assert!(fs::read_to_string(path.join("refusal.receipt")).unwrap().ends_with("branch=step=Other capture binary_metadata errno=Some(2)\n"));
        fs::remove_dir_all(path).unwrap();
    }
    #[test] fn refusal_reports_exact_guard_and_wrong_device_and_sync_failures() {
        let (b,p)=backend();
        assert!(b.effect_guard(super::super::provisioning::Step::Format,true,false).is_err());
        let r=fs::read_to_string(p.join("refusal.receipt")).unwrap();assert!(r.contains("ref=ipse-q-0123456789abcdef0123456789abcdef sequence=0 stage="));assert!(r.ends_with("branch=step=Format effect guardian_not_live\n"));
        fs::remove_file(p.join("refusal.receipt")).unwrap();
        assert!(b.effect_guard(super::super::provisioning::Step::Format,false,true).is_err());
        assert!(fs::read_to_string(p.join("refusal.receipt")).unwrap().ends_with("branch=step=Format effect boundary_recheck_failed\n"));
        fs::remove_file(p.join("refusal.receipt")).unwrap();
        assert!(b.format_node_numbers((252,4093),(252,4094)).is_err());
        assert!(fs::read_to_string(p.join("refusal.receipt")).unwrap().ends_with("branch=step=Format format node_wrong_device observed=(252, 4093)\n"));
        assert!(RealBackend::sync_refusal(||Err(std::io::Error::other("file sync")),||Ok(())).is_err());
        assert!(RealBackend::sync_refusal(||Ok(()),||Err(std::io::Error::other("dir sync"))).is_err());
        fs::remove_file(p.join("refusal.receipt")).unwrap();
        assert!(b.refusal_with_sync("step=Format test",|_,_|Err(std::io::Error::other("sync failed"))).is_err());
        assert!(p.join("refusal.receipt").exists()); // Visible does not mean synced.
        drop(b);fs::remove_file(p.join("refusal.receipt")).unwrap();fs::remove_dir(p).unwrap();
    }
    #[test] fn refusal_marker_child() {
        if std::env::var_os("IPSE_TEST_REFUSAL_CHILD").is_none(){return}
        let (b,p)=backend();b.report_refusal_with("step=Format injected_sync_failure",|_,_|Err(std::io::Error::other("injected")));
        drop(b);fs::remove_file(p.join("refusal.receipt")).unwrap();fs::remove_dir(p).unwrap();
    }
    #[test] fn sync_failure_never_emits_a_synced_marker() {
        let out=std::process::Command::new(std::env::current_exe().unwrap()).args(["--exact","real_backend::tests::refusal_marker_child","--nocapture"]).env("IPSE_TEST_REFUSAL_CHILD","1").output().unwrap();
        assert!(out.status.success());let err=String::from_utf8(out.stderr).unwrap();assert!(err.contains("REFUSAL_UNKNOWN"));assert!(!err.contains("REFUSAL_SYNCED"));
    }
    #[test] fn direct_child_success_with_live_descendant_is_not_success() {
        let (mut b,path)=backend(); let script=path.join("forking-tool");
        fs::write(&script,"#!/bin/sh\n(/usr/bin/sleep 0.2) &\nexit 0\n").unwrap();
        fs::set_permissions(&script,fs::Permissions::from_mode(0o700)).unwrap();
        let started=Instant::now();
        assert!(b.capture(&script,&[]).is_err());
        assert!(started.elapsed()<Duration::from_secs(3));
        std::thread::sleep(Duration::from_millis(300));
        fs::remove_dir_all(path).unwrap();
    }
    #[test] fn oversize_output_stops_without_unbounded_fixture_growth() {
        let (mut b,path)=backend();
        assert!(b.capture(Path::new("/usr/bin/head"), &["-c".into(),"100000".into(),"/dev/zero".into()]).is_err());
        assert!(fs::metadata(path.join("command-001.output")).unwrap().len()<=LIMIT);
        fs::remove_dir_all(path).unwrap();
    }
    #[test] fn mapper_absence_requires_complete_enumeration_and_absent_device_identity() {
        let (mut b,path)=backend(); b.sysroot=path.join("fake-sys");
        fs::create_dir_all(b.sysroot.join("class/block")).unwrap();
        fs::create_dir_all(b.sysroot.join("dev/block")).unwrap();
        let e=b.expected.clone();
        assert_eq!(b.mapper_absence_from_sysfs(&e),Ok(true));
        let dm=b.sysroot.join("class/block/dm-2/dm"); fs::create_dir_all(&dm).unwrap();
        fs::write(dm.join("name"),format!("{}\n",e.dm_name)).unwrap();
        fs::write(dm.join("uuid"),format!("{}\n",e.dm_uuid)).unwrap();
        assert_eq!(b.mapper_absence_from_sysfs(&e),Ok(false));
        fs::write(dm.join("name"),"other\n").unwrap(); fs::write(dm.join("uuid"),"other\n").unwrap();
        assert_eq!(b.mapper_absence_from_sysfs(&e),Ok(true));
        fs::create_dir_all(b.sysroot.join("dev/block/253:11")).unwrap();
        assert_eq!(b.mapper_absence_from_sysfs(&e),Err(()));
        fs::remove_file(dm.join("uuid")).unwrap();
        assert_eq!(b.mapper_absence_from_sysfs(&e),Err(()));
        fs::remove_dir_all(path).unwrap();
    }
    #[test] fn loop_holders_are_exactly_the_fixture_mapper_before_format() {
        let (mut b,path)=backend(); b.sysroot=path.join("fake-sys");
        let holders=b.sysroot.join("dev/block/7:42/holders"); fs::create_dir_all(&holders).unwrap();
        let e=b.expected.clone();
        assert_eq!(super::super::provisioning::Backend::loop_held_only_by_mapper(&mut b,&e),Ok(false));
        fs::create_dir(holders.join("dm-11")).unwrap();
        fs::write(holders.join("dm-11/dev"),"253:11\n").unwrap();
        assert_eq!(super::super::provisioning::Backend::loop_held_only_by_mapper(&mut b,&e),Ok(true));
        fs::create_dir(holders.join("dm-12")).unwrap();
        fs::write(holders.join("dm-12/dev"),"253:12\n").unwrap();
        assert_eq!(super::super::provisioning::Backend::loop_held_only_by_mapper(&mut b,&e),Ok(false));
        fs::remove_dir_all(path).unwrap();
    }
    #[test] fn loop_absence_requires_a_valid_complete_list() {
        assert_eq!(assigned_loop_absent("7:1\n7:2\n",(7,42)),Ok(true));
        assert_eq!(assigned_loop_absent("7:1\n7:42\n",(7,42)),Ok(false));
        assert_eq!(assigned_loop_absent("7:1 extra\n",(7,42)),Err(()));
        assert_eq!(assigned_loop_absent("7:1:2\n",(7,42)),Err(()));
    }
    #[test] fn cleanup_window_cannot_be_reserved_after_uncertainty_or_twice() {
        let (mut b,path)=backend();
        assert!(b.reserve_cleanup(State::Unknown).is_err());
        b.next=WORK_COMMANDS;
        assert!(b.reserve_cleanup(State::LinearActive).is_ok());
        assert_eq!(b.command_limit,MAX_COMMANDS);
        assert!(b.reserve_cleanup(State::LinearActive).is_err());
        fs::remove_dir_all(path).unwrap();
    }
    #[test] fn constructor_refuses_malformed_nonce_and_host_mount_namespace() {
        assert!(RealBackend::new("bad",42,253,11,1,30).is_err());
        let inode=fs::metadata("/proc/self/ns/mnt").unwrap().ino();
        assert!(RealBackend::new("0123456789abcdef0123456789abcdef",42,253,11,inode,30).is_err());
        assert!(RealBackend::new("0123456789abcdef0123456789abcdef",4096,253,11,1,30).is_err());
        assert!(RealBackend::new("0123456789abcdef0123456789abcdef",42,7,11,1,30).is_err());
    }
    #[test] fn real_observation_parser_runs_against_nonmutating_fake_tools() {
        let (mut b,path)=backend();
        let name="0123456789abcdef0123456789abcdef";
        let losetup=path.join("fake-losetup");
        let dmsetup=path.join("fake-dmsetup");
        fs::write(&losetup,format!("#!/bin/sh\nprintf '%s\\n' '221 0:37 7:42 0 536870912 0 ipse-q-{name}'\n")).unwrap();
        fs::write(&dmsetup,format!("#!/bin/sh\ncase \" $* \" in\n  *' info '*) printf '%s\\n' 'ipse-q-{name}|IPSE-Q-{name}|253|11|0' ;;\n  *' --inactive '*) exit 0 ;;\n  *' table '*) printf '%s\\n' '0 1048576 linear 7:42 0' ;;\n  *) exit 2 ;;\nesac\n")).unwrap();
        fs::set_permissions(&losetup,fs::Permissions::from_mode(0o700)).unwrap();
        fs::set_permissions(&dmsetup,fs::Permissions::from_mode(0o700)).unwrap();
        b.losetup=losetup;b.dmsetup=dmsetup;
        let observation=super::Backend::observe(&mut b).unwrap();
        assert_eq!(observation.loop_row,format!("221|0:37|7:42|0|536870912|0|ipse-q-{name}"));
        assert_eq!(observation.active,"0 1048576 linear 7:42 0");
        assert_eq!(observation.inactive,None);
        fs::remove_dir_all(path).unwrap();
    }
}

// Recovery must remain fail-closed until a retained cgroup boundary, complete
// mount/holder evidence and independent owner/guardian are implemented.
impl super::RecoveryBackend for RealBackend {
    fn verify_owned_quiescence(&mut self,_:&super::Expected)->Result<(),()> {Err(())}
    fn reserve_recovery_budget(&mut self)->Result<(),()> {Err(())}
}

// LOOP_CTL_REMOVE is implemented, but no live path can reach it until the
// unique loop index's durable creation record is verified against held state.
impl super::IndexRemovalBackend for RealBackend {
    fn created_index_identity(&mut self,_:&super::Expected)->Result<bool,()> {Err(())}
    fn remove_created_index(&mut self,e:&super::Expected)->Result<(),()> {
        self.fixed_name(e)?;super::loop_device::remove(e.loop_minor).map_err(|_|())
    }
    fn index_absent(&mut self,e:&super::Expected)->Result<bool,()> {
        self.fixed_name(e)?;
        let block=self.sysroot.join(format!("block/loop{}",e.loop_minor));
        let device=self.sysroot.join(format!("dev/block/{}:{}",e.loop_major,e.loop_minor));
        match (fs::symlink_metadata(block),fs::symlink_metadata(device)) {
            (Err(a),Err(b)) if a.kind()==std::io::ErrorKind::NotFound && b.kind()==std::io::ErrorKind::NotFound => Ok(true),
            (Ok(_),_)|(_,Ok(_))=>Ok(false),_=>Err(())
        }
    }
}
impl super::diagnostic_fault::RecordedBackend for RealBackend {
 fn diagnostic_record(&mut self,r:super::diagnostic_receipt::Record)->Result<(),()> {if self.loop_owner.as_ref().is_none_or(|owner|!owner.guardian_live()){return Err(())}if self.boundary.as_ref().is_none_or(|b|b.recheck().is_err()){return Err(())}self.diagnostic.as_mut().ok_or(())?.record(r).map_err(|_| ())}
 fn fault_budget(&self,minimum_ms:u64)->Result<(),()> {if self.deadline.saturating_duration_since(Instant::now())<Duration::from_millis(minimum_ms){Err(())}else{Ok(())}}
}
