//! Fixed Linux filesystem, syscall, and resource policy. No external crates.
use std::ffi::CStr;
use std::ffi::CString;
use std::fs::{self, DirBuilder, File, OpenOptions};
use std::io::{self, Read};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::os::unix::io::{AsRawFd, FromRawFd};
use std::path::{Path, PathBuf};
use std::time::Duration;

pub const PROFILE: &str = "linux-workspace-v1";
extern "C" {
    fn syscall(number: i64, ...) -> i64;
    fn geteuid() -> u32;
    fn getuid() -> u32;
    fn getgid() -> u32;
    fn getpwuid(uid: u32) -> *const Passwd;
    fn getrlimit(resource: i32, limits: *mut Limit) -> i32;
    fn setrlimit(resource: i32, limits: *const Limit) -> i32;
    fn prctl(option: i32, ...) -> i32;
}
#[repr(C)]
struct Passwd {
    name: *const i8,
    password: *const i8,
    uid: u32,
    gid: u32,
    gecos: *const i8,
    dir: *const i8,
    shell: *const i8,
}
#[repr(C)]
struct Limit {
    current: u64,
    maximum: u64,
}
#[repr(C)]
struct Ruleset {
    fs: u64,
    net: u64,
    scoped: u64,
}
#[repr(C)]
struct MountAttr {
    set: u64,
    clear: u64,
    propagation: u64,
    userns_fd: u64,
}
struct Mount {
    _source_file: File,
    source: CString,
    identity: [u64; 3],
    target: CString,
    readonly: bool,
    directory: bool,
    devices: bool,
}
#[repr(C, packed)]
struct PathRule {
    access: u64,
    fd: i32,
}
#[repr(C)]
#[derive(Clone, Copy)]
struct Filter {
    code: u16,
    jt: u8,
    jf: u8,
    k: u32,
}
#[repr(C)]
struct Program {
    len: u16,
    filters: *const Filter,
}
pub struct Sandbox {
    rules: File,
    temp: PathBuf,
    filters: Vec<Filter>,
    cpu: u64,
    nproc: u64,
    base: PathBuf,
    root: CString,
    cwd: CString,
    mounts: Vec<Mount>,
    uid_map: Vec<u8>,
    gid_map: Vec<u8>,
}
impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.base);
    }
}
fn error(label: &str) -> String {
    format!("{label}: {}", io::Error::last_os_error())
}
fn instruction(code: u16, jt: u8, jf: u8, k: u32) -> Filter {
    Filter { code, jt, jf, k }
}
fn cpath(path: &Path) -> Result<CString, String> {
    CString::new(path.as_os_str().as_bytes()).map_err(|_| "NUL in sandbox path".into())
}
#[cfg(target_arch = "x86_64")]
const SYS: [i64; 8] = [272, 165, 161, 80, 257, 1, 3, 126];
#[cfg(not(target_arch = "x86_64"))]
const SYS: [i64; 8] = [97, 40, 51, 49, 56, 64, 57, 91];
fn checked(value: i64) -> io::Result<()> {
    if value < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}
fn identity(fd: i32) -> io::Result<[u64; 3]> {
    let mut stat = [0u64; 32];
    checked(unsafe {
        syscall(
            if cfg!(target_arch = "x86_64") {
                332
            } else {
                291
            },
            fd,
            b"\0".as_ptr(),
            0x1000u32,
            0x100u32,
            stat.as_mut_ptr(),
        )
    })?;
    if stat[0] as u32 & 0x100 == 0 {
        return Err(io::Error::from_raw_os_error(95));
    }
    Ok([stat[4], stat[17] & 0xffffffff, stat[17] >> 32])
}
fn map_write(path: &[u8], bytes: &[u8]) -> io::Result<()> {
    let fd = unsafe { syscall(SYS[4], -100i32, path.as_ptr(), 1u32 | 0x80000, 0u32) };
    checked(fd)?;
    let result = unsafe { syscall(SYS[5], fd, bytes.as_ptr(), bytes.len()) };
    let error = if result < 0 {
        Some(io::Error::last_os_error())
    } else {
        None
    };
    unsafe {
        syscall(SYS[6], fd);
    }
    if let Some(error) = error {
        return Err(error);
    }
    if result as usize != bytes.len() {
        return Err(io::Error::from_raw_os_error(5));
    }
    Ok(())
}
fn attributes(path: *const i8, readonly: bool, directory: bool, devices: bool) -> io::Result<()> {
    let attr = MountAttr {
        set: u64::from(readonly) | 2 | if devices { 0 } else { 4 },
        clear: 0,
        propagation: 0,
        userns_fd: 0,
    };
    checked(unsafe {
        syscall(
            442,
            -100i32,
            path,
            if directory { 0x8000u32 } else { 0 },
            &attr as *const MountAttr,
            32usize,
        )
    })
}

fn process_headroom() -> Result<u64, String> {
    let uid = unsafe { getuid() };
    let mut scanned = 0usize;
    let mut count = 0u64;
    let mut charge = || -> Result<(), String> {
        scanned += 1;
        if scanned > 1_000_000 {
            return Err("process scan exceeds one million entries".into());
        }
        Ok(())
    };
    for entry in fs::read_dir("/proc").map_err(|e| format!("cannot count UID threads: {e}"))? {
        charge()?;
        let entry = entry.map_err(|e| e.to_string())?;
        if !entry
            .file_name()
            .as_encoded_bytes()
            .iter()
            .all(u8::is_ascii_digit)
        {
            continue;
        }
        let mut status = String::new();
        let result = File::open(entry.path().join("status"))
            .and_then(|f| f.take(65537).read_to_string(&mut status));
        match result {
            Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
            Err(e) => return Err(format!("cannot inspect UID thread ownership: {e}")),
            Ok(_) => (),
        }
        if status.len() > 65536 {
            return Err("process status exceeds limit".into());
        }
        let real = status
            .lines()
            .find_map(|s| s.strip_prefix("Uid:"))
            .and_then(|s| s.split_whitespace().next())
            .ok_or("missing process real UID")?
            .parse::<u32>()
            .map_err(|_| "invalid process real UID")?;
        if real != uid {
            continue;
        }
        let tasks = match fs::read_dir(entry.path().join("task")) {
            Ok(tasks) => tasks,
            Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
            Err(e) => return Err(format!("cannot count real-UID tasks: {e}")),
        };
        for task in tasks {
            charge()?;
            match task {
                Ok(task) => {
                    if task
                        .file_name()
                        .as_encoded_bytes()
                        .iter()
                        .all(u8::is_ascii_digit)
                    {
                        count += 1;
                    }
                }
                Err(e) if e.kind() == io::ErrorKind::NotFound => (),
                Err(e) => return Err(format!("cannot enumerate real-UID tasks: {e}")),
            }
        }
    }
    let mut limit = Limit {
        current: 0,
        maximum: 0,
    };
    if unsafe { getrlimit(6, &mut limit) } < 0 {
        return Err(error("read NPROC hard limit"));
    }
    let ceiling = count.saturating_add(1024).min(limit.maximum);
    if ceiling <= count {
        return Err("existing real-UID thread count exhausts NPROC hard limit".into());
    }
    Ok(ceiling)
}
fn protected_path(path: &Path) -> Result<PathBuf, String> {
    let absolute = if path.is_absolute() {
        path.to_owned()
    } else {
        std::env::current_dir()
            .map_err(|e| e.to_string())?
            .join(path)
    };
    let mut ancestor = absolute.as_path();
    let mut suffix = Vec::new();
    loop {
        match fs::canonicalize(ancestor) {
            Ok(mut base) => {
                for item in suffix.iter().rev() {
                    base.push(item);
                }
                return Ok(base);
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                suffix.push(
                    ancestor
                        .file_name()
                        .ok_or("invalid protected path")?
                        .to_owned(),
                );
                ancestor = ancestor.parent().ok_or("invalid protected path")?;
            }
            Err(e) => return Err(format!("cannot resolve protected workspace boundary: {e}")),
        }
    }
}
fn validate_workspace(workspace: &Path) -> Result<(), String> {
    if workspace == Path::new("/") || workspace == Path::new("/tmp") {
        return Err("sandbox workspace is too broad".into());
    }
    for root in [
        "/usr", "/bin", "/lib", "/lib64", "/etc", "/dev", "/proc", "/sys", "/run",
    ] {
        let root = protected_path(Path::new(root))?;
        if root.starts_with(workspace) || workspace.starts_with(&root) {
            return Err("sandbox workspace overlaps a protected system path".into());
        }
    }
    let record = unsafe { getpwuid(getuid()) };
    if record.is_null() || unsafe { (*record).dir.is_null() } {
        return Err("cannot resolve real-UID home directory".into());
    }
    let home = protected_path(Path::new(std::ffi::OsStr::from_bytes(unsafe {
        CStr::from_ptr((*record).dir).to_bytes()
    })))?;
    if home.starts_with(workspace) {
        return Err("sandbox workspace includes the real home directory".into());
    }
    let mut protected = vec![
        home.join(".ipse"),
        home.join(".ssh"),
        home.join(".aws"),
        home.join(".codex"),
    ];
    if let Some(path) = std::env::var_os("IPSE_HOME") {
        if !path.is_empty() {
            protected.push(PathBuf::from(path));
        }
    }
    for path in protected {
        let path = protected_path(&path)?;
        if path.starts_with(workspace) || workspace.starts_with(&path) {
            return Err("sandbox workspace overlaps a protected credential directory".into());
        }
    }
    Ok(())
}

pub fn prepare(cwd: &Path, timeout: Duration) -> Result<Sandbox, String> {
    if !cfg!(all(
        target_os = "linux",
        target_endian = "little",
        any(target_arch = "x86_64", target_arch = "aarch64")
    )) {
        return Err("sandbox requires native Linux x86_64 or aarch64".into());
    }
    if unsafe { geteuid() } == 0 {
        return Err("sandbox refuses effective root".into());
    }
    let mut status = String::new();
    File::open("/proc/self/status")
        .map_err(|e| e.to_string())?
        .take(65537)
        .read_to_string(&mut status)
        .map_err(|e| e.to_string())?;
    if status.len() > 65536 {
        return Err("process status exceeds limit".into());
    }
    for key in ["CapPrm:", "CapEff:", "CapAmb:"] {
        let value = status
            .lines()
            .find_map(|line| line.strip_prefix(key))
            .ok_or_else(|| format!("missing {key}"))?
            .trim();
        if u64::from_str_radix(value, 16).map_err(|_| "invalid capability status")? != 0 {
            return Err("sandbox refuses privileged capabilities".into());
        }
    }
    let abi = unsafe { syscall(444, 0usize, 0usize, 1u32) };
    if abi < 6 {
        return Err("sandbox requires enabled Landlock ABI >= 6 (signal isolation)".into());
    }
    // ABI 3 adds TRUNCATE; ABI 5 adds IOCTL_DEV. Unknown future rights are
    // deliberately not claimed, so profile updates must track kernel additions.
    let rights = (1u64 << 16) - 1;
    // ABI 6 isolates signal recipients and abstract UNIX sockets to this
    // Landlock domain and its descendants, including across exec and fork.
    let attr = Ruleset {
        fs: rights,
        net: 0,
        scoped: 3,
    };
    let fd = unsafe { syscall(444, &attr as *const Ruleset, 24usize, 0u32) };
    if fd < 0 {
        return Err(error("create Landlock ruleset"));
    }
    let rules = unsafe { File::from_raw_fd(fd as i32) };
    let nproc = process_headroom()?;
    let workspace = fs::canonicalize(cwd).map_err(|e| e.to_string())?;
    if !workspace.is_dir() {
        return Err("workspace must be a directory".into());
    }
    validate_workspace(&workspace)?;
    let mut temp = None;
    for _ in 0..32 {
        let mut random = [0u8; 16];
        File::open("/dev/urandom")
            .and_then(|mut f| f.read_exact(&mut random))
            .map_err(|e| e.to_string())?;
        let suffix: String = random.iter().map(|b| format!("{b:02x}")).collect();
        let path = PathBuf::from(format!("/tmp/ipse-sandbox-{suffix}"));
        match DirBuilder::new().mode(0o700).create(&path) {
            Ok(()) => {
                temp = Some(path);
                break;
            }
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e.to_string()),
        }
    }
    let base = temp.ok_or("cannot create private temporary directory")?;
    let data = base.join("data");
    let root_path = base.join("root");
    let created = DirBuilder::new()
        .mode(0o700)
        .create(&data)
        .and_then(|_| DirBuilder::new().mode(0o700).create(&root_path));
    if let Err(error) = created {
        let _ = fs::remove_dir_all(&base);
        return Err(error.to_string());
    }
    let mut sandbox = Sandbox {
        rules,
        temp: data,
        root: cpath(&root_path)?,
        cwd: cpath(&workspace)?,
        base,
        mounts: Vec::new(),
        uid_map: format!("{} {} 1\n", unsafe { getuid() }, unsafe { getuid() }).into_bytes(),
        gid_map: format!("{} {} 1\n", unsafe { getgid() }, unsafe { getgid() }).into_bytes(),
        filters: Vec::new(),
        nproc,
        cpu: timeout
            .as_secs()
            .saturating_add(u64::from(timeout.subsec_nanos() != 0))
            .saturating_add(1),
    };
    sandbox.allow(&workspace, rights)?;
    sandbox.allow(&sandbox.temp, rights)?;
    for p in ["/usr", "/bin", "/lib", "/lib64"] {
        match fs::canonicalize(p) {
            Ok(path) => {
                sandbox.allow(&path, 1 | 4 | 8)?;
                sandbox.mount_plan(&path, Path::new(p), true, true, false)?;
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => (),
            Err(e) => return Err(e.to_string()),
        }
    }
    for (p, access) in [
        ("/etc/ld.so.cache", 4),
        ("/etc/localtime", 4),
        ("/dev/null", 6),
        ("/dev/zero", 4),
        ("/dev/urandom", 4),
        ("/dev/random", 4),
    ] {
        match fs::canonicalize(p) {
            Ok(path) => {
                sandbox.allow(&path, access)?;
                sandbox.mount_plan(
                    &path,
                    Path::new(p),
                    p != "/dev/null",
                    false,
                    p.starts_with("/dev/"),
                )?;
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound && p.starts_with("/etc/") => (),
            Err(e) => return Err(e.to_string()),
        }
    }
    // /tmp and the absolute HOME/TMPDIR path resolve to the same private data.
    // Mount workspace after /tmp so temporary test workspaces remain visible.
    let data = sandbox.temp.clone();
    sandbox.mount_plan(&data, Path::new("/tmp"), false, true, false)?;
    sandbox.mount_plan(&workspace, &workspace, false, true, false)?;
    sandbox.mount_plan(&data, &data, false, true, false)?;
    sandbox.filters = filter();
    Ok(sandbox)
}
impl Sandbox {
    /// Policy strings and mountpoint directories are prepared before fork.
    fn namespace_root(&self) -> io::Result<()> {
        checked(unsafe { syscall(SYS[0], 0x10000000u32) })?;
        map_write(b"/proc/self/setgroups\0", b"deny\n")?;
        map_write(b"/proc/self/uid_map\0", &self.uid_map)?;
        map_write(b"/proc/self/gid_map\0", &self.gid_map)?;
        checked(unsafe { syscall(SYS[0], 0x00020000u32 | 0x40000000u32) })?;
        checked(unsafe {
            syscall(
                SYS[1],
                0usize,
                b"/\0".as_ptr(),
                0usize,
                0x40000usize | 0x4000usize,
                0usize,
            )
        })?;
        checked(unsafe {
            syscall(
                SYS[1],
                self.root.as_ptr(),
                self.root.as_ptr(),
                0usize,
                4096usize,
                0usize,
            )
        })?;
        attributes(self.root.as_ptr(), true, true, false)?;
        for mount in &self.mounts {
            let source = unsafe {
                syscall(
                    SYS[4],
                    -100i32,
                    mount.source.as_ptr(),
                    0x200000u32 | 0x80000,
                    0u32,
                )
            };
            checked(source)?;
            let actual = identity(source as i32);
            if actual
                .as_ref()
                .map(|value| *value != mount.identity)
                .unwrap_or(true)
            {
                unsafe {
                    syscall(SYS[6], source);
                }
                return Err(actual
                    .err()
                    .unwrap_or_else(|| io::Error::from_raw_os_error(116)));
            }
            let tree = unsafe {
                syscall(
                    428,
                    source,
                    b"\0".as_ptr(),
                    1u32 | 0x80000 | 0x1000 | if mount.directory { 0x8000 } else { 0 },
                )
            };
            let tree_error = if tree < 0 {
                Some(io::Error::last_os_error())
            } else {
                None
            };
            unsafe {
                syscall(SYS[6], source);
            }
            if let Some(error) = tree_error {
                return Err(error);
            }
            let result = unsafe {
                syscall(
                    429,
                    tree,
                    b"\0".as_ptr(),
                    -100i32,
                    mount.target.as_ptr(),
                    4u32,
                )
            };
            let error = if result < 0 {
                Some(io::Error::last_os_error())
            } else {
                None
            };
            unsafe {
                syscall(SYS[6], tree);
            }
            if let Some(error) = error {
                return Err(error);
            }
            attributes(
                mount.target.as_ptr(),
                mount.readonly,
                mount.directory,
                mount.devices,
            )?;
        }
        checked(unsafe { syscall(SYS[2], self.root.as_ptr()) })?;
        checked(unsafe { syscall(SYS[3], self.cwd.as_ptr()) })?;
        for cap in 0..64i32 {
            let result = unsafe { prctl(24, cap as usize, 0usize, 0usize, 0usize) };
            if result < 0 && io::Error::last_os_error().raw_os_error() != Some(22) {
                return Err(io::Error::last_os_error());
            }
        }
        let header = [0x20080522u32, 0];
        let data = [0u32; 6];
        checked(unsafe { syscall(SYS[7], header.as_ptr(), data.as_ptr()) })?;
        Ok(())
    }
    fn mount_plan(
        &mut self,
        source: &Path,
        target: &Path,
        readonly: bool,
        directory: bool,
        devices: bool,
    ) -> Result<(), String> {
        let relative = target
            .strip_prefix("/")
            .map_err(|_| "mount path must be absolute")?;
        let destination = self.base.join("root").join(relative);
        let create = |path: &Path| -> io::Result<()> {
            if directory {
                fs::create_dir_all(path)
            } else {
                fs::create_dir_all(path.parent().unwrap())?;
                OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .mode(0o600)
                    .open(path)
                    .map(|_| ())
            }
        };
        create(&destination).map_err(|e| e.to_string())?;
        if let Ok(relative) = target.strip_prefix("/tmp") {
            create(&self.temp.join(relative)).map_err(|e| e.to_string())?;
        }
        // Pin the validated source inode until spawn; never re-resolve an
        // attacker-replaceable workspace pathname in the child mount sequence.
        let source_file = OpenOptions::new()
            .read(true)
            .custom_flags(0x200000 | 0x80000)
            .open(source)
            .map_err(|e| e.to_string())?;
        let fd_path = PathBuf::from(format!("/proc/self/fd/{}", source_file.as_raw_fd()));
        if fs::canonicalize(&fd_path).map_err(|e| e.to_string())? != source {
            return Err("sandbox mount source changed during preparation".into());
        }
        self.mounts.push(Mount {
            source: cpath(source)?,
            identity: identity(source_file.as_raw_fd()).map_err(|e| e.to_string())?,
            _source_file: source_file,
            target: cpath(&destination)?,
            readonly,
            directory,
            devices,
        });
        Ok(())
    }
    pub fn temp_dir(&self) -> &Path {
        &self.temp
    }
    fn allow(&self, path: &Path, access: u64) -> Result<(), String> {
        let file = OpenOptions::new()
            .read(true)
            .custom_flags(0x200000 | 0x80000)
            .open(path)
            .map_err(|e| e.to_string())?;
        let rule = PathRule {
            access,
            fd: file.as_raw_fd(),
        };
        if unsafe {
            syscall(
                445,
                self.rules.as_raw_fd(),
                1u32,
                &rule as *const PathRule,
                0u32,
            )
        } < 0
        {
            return Err(error("add Landlock path rule"));
        }
        Ok(())
    }
    /// Invoke only in the child's pre_exec. All policy allocation happens in prepare.
    /// NPROC provides 1024 slots above the observed real-UID thread count,
    /// clamped to the existing hard limit. It is not a private aggregate quota.
    pub fn apply(&self) -> io::Result<()> {
        self.namespace_root()?;
        for (resource, maximum) in [
            (4, 0),
            (0, self.cpu),
            (9, 16 * 1024 * 1024 * 1024),
            (7, 256),
            (1, 64 * 1024 * 1024),
            (6, self.nproc),
        ] {
            let limit = Limit {
                current: maximum,
                maximum,
            };
            if unsafe { setrlimit(resource, &limit) } < 0 {
                return Err(io::Error::last_os_error());
            }
        }
        // Preserve Rust's spawn-error pipe until exec while closing inherited
        // nonstandard descriptors at successful exec, including the ruleset.
        if unsafe { syscall(436, 3u32, u32::MAX, 4u32) } < 0 {
            return Err(io::Error::last_os_error());
        }
        if unsafe { prctl(38, 1usize, 0usize, 0usize, 0usize) } < 0 {
            return Err(io::Error::last_os_error());
        }
        if unsafe { syscall(446, self.rules.as_raw_fd(), 0u32) } < 0 {
            return Err(io::Error::last_os_error());
        }
        let program = Program {
            len: self.filters.len() as u16,
            filters: self.filters.as_ptr(),
        };
        if unsafe { prctl(22, 2usize, &program as *const Program, 0usize, 0usize) } < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }
}
fn filter() -> Vec<Filter> {
    let mut f = Vec::new();
    let arch = if cfg!(target_arch = "x86_64") {
        0xc000003e
    } else {
        0xc00000b7
    };
    f.push(instruction(0x20, 0, 0, 4)); // seccomp_data.arch
    f.push(instruction(0x15, 1, 0, arch));
    f.push(instruction(0x06, 0, 0, 0x80000000)); // KILL_PROCESS
    f.push(instruction(0x20, 0, 0, 0)); // seccomp_data.nr
                                        // Reject x32 and any high-bit syscall encoding on both native ABIs.
    f.push(instruction(0x45, 0, 1, 0x40000000));
    f.push(instruction(0x06, 0, 0, 0x80000000));
    f.push(instruction(0x15, 0, 1, 435)); // clone3 must permit libc fallback
    f.push(instruction(0x06, 0, 0, 0x50000 | 38));
    let clone = if cfg!(target_arch = "x86_64") {
        56
    } else {
        220
    };
    f.push(instruction(0x15, 0, 3, clone));
    f.push(instruction(0x20, 0, 0, 16)); // low word of args[0], native little endian
    f.push(instruction(0x45, 0, 1, 0x7e020000)); // all legacy CLONE_NEW* flags
    f.push(instruction(0x06, 0, 0, 0x50000 | 1));
    f.push(instruction(0x20, 0, 0, 0));
    // prlimit64 can change another same-UID process even without signal or
    // ptrace access. libc's current-process resource queries use pid zero.
    let prlimit = if cfg!(target_arch = "x86_64") {
        302
    } else {
        261
    };
    f.push(instruction(0x15, 0, 4, prlimit));
    f.push(instruction(0x20, 0, 0, 16));
    f.push(instruction(0x15, 1, 0, 0));
    f.push(instruction(0x06, 0, 0, 0x50000 | 1));
    f.push(instruction(0x06, 0, 0, 0x7fff0000));
    let socketpair = if cfg!(target_arch = "x86_64") {
        53
    } else {
        199
    };
    f.push(instruction(0x15, 0, 9, socketpair));
    f.push(instruction(0x20, 0, 0, 16));
    f.push(instruction(0x15, 1, 0, 1));
    f.push(instruction(0x06, 0, 0, 0x50000 | 1));
    f.push(instruction(0x20, 0, 0, 24));
    f.push(instruction(0x54, 0, 0, 0xf));
    // Connected private pairs support BEAM and Rust's fork/exec error channel.
    // Datagram pairs remain denied because they can address external peers.
    f.push(instruction(0x15, 2, 0, 1));
    f.push(instruction(0x15, 1, 0, 5));
    f.push(instruction(0x06, 0, 0, 0x50000 | 1));
    f.push(instruction(0x06, 0, 0, 0x7fff0000));
    let deny: &[u32] = if cfg!(target_arch = "x86_64") {
        &[
            109, 112, 41, 42, 43, 49, 50, 288, 101, 310, 311, 438, 165, 166, 155, 161, 272, 308,
            321, 298, 248, 249, 250, 133, 259, 304, 105, 106, 113, 114, 116, 117, 119, 122, 123,
            126, 170, 171, 172, 173, 169, 175, 176, 313, 246, 320, 167, 168, 163, 179, 425, 426,
            427, 428, 429, 430, 431, 432, 433, 442, 443,
        ]
    } else {
        &[
            154, 157, 198, 200, 201, 202, 203, 242, 117, 270, 271, 438, 40, 39, 41, 51, 97, 268,
            280, 241, 217, 218, 219, 33, 265, 143, 144, 145, 146, 147, 149, 151, 152, 159, 161,
            162, 91, 142, 105, 106, 273, 104, 294, 224, 225, 89, 60, 425, 426, 427, 428, 429, 430,
            431, 432, 433, 442, 443,
        ]
    };
    for nr in deny {
        f.push(instruction(0x15, 0, 1, *nr));
        f.push(instruction(0x06, 0, 0, 0x50000 | 1));
    }
    let ipc: &[u32] = if cfg!(target_arch = "x86_64") {
        &[
            29, 30, 31, 64, 65, 66, 67, 68, 69, 70, 71, 220, 312, 424, 434, 438,
        ]
    } else {
        &[
            186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 272, 424, 434, 438,
        ]
    };
    for nr in ipc {
        f.push(instruction(0x15, 0, 1, *nr));
        f.push(instruction(0x06, 0, 0, 0x50000 | 1));
    }
    // Scheduling and page-migration APIs have target PID/group/user arguments;
    // reject them rather than grant ambient mutation of host processes.
    let process_mutation: &[u32] = if cfg!(target_arch = "x86_64") {
        &[141, 142, 144, 203, 251, 314, 256, 279, 440, 448]
    } else {
        &[140, 118, 119, 122, 30, 274, 238, 239, 440, 448]
    };
    for nr in process_mutation {
        f.push(instruction(0x15, 0, 1, *nr));
        f.push(instruction(0x06, 0, 0, 0x50000 | 1));
    }
    f.push(instruction(0x06, 0, 0, 0x7fff0000));
    f
}
