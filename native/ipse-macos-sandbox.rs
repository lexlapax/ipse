//! Fixed App Sandbox worker policy. The supervisor stays outside the sandbox.
use std::fs::{self, DirBuilder};
use std::io::{self, Read};
use std::os::unix::fs::DirBuilderExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

pub const PROFILE: &str = "macos-workspace-v1";
#[repr(C)]
struct Limit { soft: u64, hard: u64 }
extern "C" {
    fn getrlimit(resource: i32, limit: *mut Limit) -> i32;
    fn setrlimit(resource: i32, limit: *const Limit) -> i32;
    fn geteuid() -> u32;
    fn setpgid(pid: i32, pgid: i32) -> i32;
    fn kill(pid: i32, signal: i32) -> i32;
}

fn xml(value: &str) -> String {
    value.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
        .replace('"', "&quot;").replace('\'', "&apos;")
}

pub fn entitlements(workspace: &str, data: &str) -> Result<String, String> {
    for root in [workspace, data] {
        if !Path::new(root).is_absolute() || root.len() > 16_384 || root.contains('\0') {
            return Err("invalid macOS entitlement root".into());
        }
    }
    let directory = |root: &str| xml(&format!("{}/", root.trim_end_matches('/')));
    Ok(format!("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n\
<plist version=\"1.0\"><dict>\n\
<key>com.apple.security.app-sandbox</key><true/>\n\
<key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>\n\
<array><string>{}</string><string>{}</string></array>\n\
<key>com.apple.security.temporary-exception.files.absolute-path.read-only</key>\n\
<array><string>/opt/homebrew/</string><string>/usr/local/</string></array>\n\
</dict></plist>\n", directory(workspace), directory(data)))
}

// Accept only the fixed plist vocabulary; never resolve XML declarations/entities.
#[derive(PartialEq, Eq)]
enum PlistValue { True, Strings(Vec<String>) }
fn plist(xml: &str) -> Result<std::collections::BTreeMap<String, PlistValue>, String> {
    fn take<'a>(input: &mut &'a str, token: &str) -> Result<(), String> {
        *input = input.trim_start();
        *input = input.strip_prefix(token).ok_or("unexpected signed plist token")?;
        Ok(())
    }
    fn string(input: &mut &str, tag: &str) -> Result<String, String> {
        take(input, &format!("<{tag}>"))?;
        let end = input.find(&format!("</{tag}>" )).ok_or("unterminated signed plist value")?;
        let encoded = &input[..end];
        if encoded.contains('<') { return Err("unexpected signed plist markup".into()); }
        let mut result = String::new();
        let mut rest = encoded;
        while let Some(index) = rest.find('&') {
            result.push_str(&rest[..index]);
            rest = &rest[index+1..];
            let end = rest.find(';').ok_or("invalid signed plist entity")?;
            result.push(match &rest[..end] {
                "amp" => '&', "lt" => '<', "gt" => '>', "quot" => '"', "apos" => '\'',
                _ => return Err("unexpected signed plist entity".into()),
            });
            rest = &rest[end+1..];
        }
        result.push_str(rest);
        *input = &input[end + tag.len() + 3..];
        Ok(result)
    }
    if xml.len() > 65_536 { return Err("signed plist exceeds limit".into()); }
    let mut input = xml.trim_start();
    take(&mut input, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")?;
    input = input.trim_start();
    if input.starts_with("<!DOCTYPE") {
        let http = "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">";
        let https = http.replace("http://", "https://");
        if input.starts_with(http) { take(&mut input, http)?; }
        else { take(&mut input, &https)?; }
    }
    take(&mut input, "<plist version=\"1.0\">")?;
    take(&mut input, "<dict>")?;
    let mut values = std::collections::BTreeMap::new();
    while !input.trim_start().starts_with("</dict>") {
        if values.len() >= 3 { return Err("unexpected signed entitlement key".into()); }
        let key = string(&mut input, "key")?;
        let value = if input.trim_start().starts_with("<true/>") {
            take(&mut input, "<true/>")?;
            PlistValue::True
        } else {
            let mut value = Vec::new();
            take(&mut input, "<array>")?;
            while !input.trim_start().starts_with("</array>") {
                if value.len() >= 4 { return Err("too many signed entitlement roots".into()); }
                value.push(string(&mut input, "string")?);
            }
            take(&mut input, "</array>")?;
            PlistValue::Strings(value)
        };
        if values.insert(key, value).is_some() { return Err("duplicate signed entitlement".into()); }
    }
    take(&mut input, "</dict>")?;
    take(&mut input, "</plist>")?;
    if !input.trim().is_empty() { return Err("trailing signed plist data".into()); }
    Ok(values)
}

fn codesign_command() -> Command {
    let mut command = Command::new("/usr/bin/codesign");
    // Keep loader injection, proxies, and provider credentials out of signing.
    command.env_clear().env("PATH", "/usr/bin:/bin").env("LANG", "C");
    command
}

pub fn codesign_exec(args: &[String]) -> io::Error {
    codesign_command().args(args).exec()
}

fn codesign(args: &[&str], cancelled: &AtomicBool) -> Result<Vec<u8>, String> {
    let mut command = codesign_command();
    command.args(args).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
    unsafe { command.pre_exec(|| {
        if setpgid(0, 0) == -1 { return Err(io::Error::last_os_error()); }
        Ok(())
    }); }
    let mut child = command.spawn().map_err(|e| format!("cannot start codesign: {e}"))?;
    struct Guard(i32);
    impl Drop for Guard { fn drop(&mut self) { unsafe { kill(-self.0, 9); } } }
    let _guard = Guard(child.id() as i32);
    let (tx, rx) = mpsc::sync_channel(16);
    fn read(mut stream: impl Read + Send + 'static, stdout: bool,
            tx: mpsc::SyncSender<(bool, Vec<u8>)>) {
        thread::spawn(move || {
            let mut buffer = [0u8; 4096];
            while let Ok(size) = stream.read(&mut buffer) {
                if size == 0 || tx.send((stdout, buffer[..size].to_vec())).is_err() { break; }
            }
        });
    }
    read(child.stdout.take().unwrap(), true, tx.clone());
    read(child.stderr.take().unwrap(), false, tx.clone());
    drop(tx);
    let deadline = Instant::now() + Duration::from_secs(10);
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let result = loop {
        if cancelled.load(Ordering::SeqCst) { break Err("macOS sandbox setup cancelled".into()); }
        if Instant::now() >= deadline { break Err("macOS signature verification timed out".into()); }
        match rx.recv_timeout(Duration::from_millis(10)) {
            Ok((out, bytes)) => {
                if stdout.len() + stderr.len() + bytes.len() > 65_536 {
                    break Err("macOS signature response exceeds limit".into());
                }
                if out { stdout.extend(bytes); } else { stderr.extend(bytes); }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                match child.try_wait() {
                    Ok(Some(status)) if status.success() => break Ok(stdout),
                    Ok(Some(_)) => break Err(format!("macOS signature verification failed: {}",
                        String::from_utf8_lossy(&stderr))),
                    Ok(None) => thread::sleep(Duration::from_millis(5)),
                    Err(e) => break Err(format!("cannot wait for codesign: {e}")),
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => (),
        }
    };
    if result.is_err() { let _ = child.kill(); let _ = child.wait(); }
    result
}

pub struct Invocation { pub command: Command, temp: PathBuf }
impl Drop for Invocation { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.temp); } }

pub fn prepare(worker: &str, workspace: &str, data: &str, timeout: u64,
               shell: &str, cancelled: &AtomicBool) -> Result<Invocation, String> {
    if unsafe { geteuid() } == 0 { return Err("macOS native sandbox refuses root".into()); }
    for path in [worker, workspace, data] {
        if fs::canonicalize(path).map_err(|e| e.to_string())? != Path::new(path) {
            return Err("macOS sandbox paths must be canonical".into());
        }
    }
    let executable = Path::new(worker);
    if !worker.ends_with("/Contents/MacOS/ipse-runner") {
        return Err("invalid macOS sandbox worker path".into());
    }
    let app = executable.parent().unwrap().parent().unwrap().parent().unwrap();
    let app = app.to_str().ok_or("invalid macOS bundle path")?;
    codesign(&["--verify", "--strict", app], cancelled)?;
    let actual = codesign(&["--display", "--entitlements", ":-", app], cancelled)?;
    let actual = String::from_utf8(actual).map_err(|_| "invalid signed entitlements")?;
    if plist(&actual)? != plist(&entitlements(workspace, data)?)? {
        return Err("macOS worker signed entitlements do not match the fixed policy".into());
    }
    let mut random = [0u8; 16];
    fs::File::open("/dev/urandom").and_then(|mut f| f.read_exact(&mut random))
        .map_err(|e| format!("cannot allocate macOS sandbox temp name: {e}"))?;
    let name: String = random.iter().map(|n| format!("{n:02x}")).collect();
    let temp = Path::new(data).join(format!("run-{name}"));
    DirBuilder::new().mode(0o700).create(&temp)
        .map_err(|e| format!("cannot create macOS command temp: {e}"))?;
    let mut command = Command::new(worker);
    command.args(["--macos-worker", workspace, temp.to_str().unwrap(), &timeout.to_string(), shell]);
    command.env_clear().env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin")
        .env("LANG", "C").env("HOME", &temp).env("TMPDIR", &temp);
    Ok(Invocation { command, temp })
}

fn limit(resource: i32, requested: u64) -> io::Result<()> {
    let mut previous = Limit { soft: 0, hard: 0 };
    if unsafe { getrlimit(resource, &mut previous) } == -1 { return Err(io::Error::last_os_error()); }
    let value = requested.min(previous.soft).min(previous.hard);
    let next = Limit { soft: value, hard: value };
    if unsafe { setrlimit(resource, &next) } == -1 { return Err(io::Error::last_os_error()); }
    Ok(())
}

pub fn worker(args: &[String]) -> Result<(), String> {
    if args.len() != 6 { return Err("invalid macOS sandbox worker arguments".into()); }
    let timeout: u64 = args[4].parse().map_err(|_| "invalid worker timeout")?;
    // Darwin resource numbers come from the public sys/resource.h contract.
    for (resource, ceiling) in [(4, 0), (8, 256), (1, 64 * 1024 * 1024),
        (0, timeout.saturating_add(999) / 1000 + 1)] {
        limit(resource, ceiling).map_err(|e| format!("cannot apply macOS resource limit: {e}"))?;
    }
    let error = Command::new("/bin/sh").args(["-c", &args[5]])
        .current_dir(&args[2]).env_clear()
        .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin")
        .env("LANG", "C").env("HOME", &args[3]).env("TMPDIR", &args[3]).exec();
    Err(format!("cannot execute sandboxed shell: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn signed_policy_requires_boolean_and_exact_roots() {
        let expected = entitlements("/workspace", "/data").unwrap();
        let normalized = expected.replace("http://", "https://");
        assert!(plist(&expected).unwrap() == plist(&normalized).unwrap());
        let changed_type = expected.replace("<true/>", "<array><string>true</string></array>");
        assert!(plist(&expected).unwrap() != plist(&changed_type).unwrap());
        let changed_root = expected.replace("/workspace/", "/broader/");
        assert!(plist(&expected).unwrap() != plist(&changed_root).unwrap());
        let duplicate = expected.replace("</dict>", "<key>com.apple.security.app-sandbox</key><true/></dict>");
        assert!(plist(&duplicate).is_err());
        assert!(plist(&(expected + "trailing")).is_err());
    }
}
