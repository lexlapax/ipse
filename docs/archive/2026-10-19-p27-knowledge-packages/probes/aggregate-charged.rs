use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom, Write};
use std::process::{Child, Command, Stdio};

const ALLOCATION: usize = 64 * 1024 * 1024;

fn child() {
    let mut bytes = vec![0_u8; ALLOCATION];
    for offset in (0..bytes.len()).step_by(4096) {
        unsafe { bytes.as_mut_ptr().add(offset).write_volatile(1) };
    }
    println!("ready");
    std::io::stdout().flush().unwrap();
    let mut release = [0_u8; 1];
    std::io::stdin().read_exact(&mut release).unwrap();
    std::hint::black_box(&bytes);
}

fn allocate() -> Child {
    let mut child = Command::new(std::env::current_exe().unwrap())
        .arg("allocate").stdin(Stdio::piped()).stdout(Stdio::piped())
        .spawn().unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap()).read_line(&mut line).unwrap();
    assert_eq!(line, "ready\n");
    child
}

fn finish(mut child: Child) {
    child.stdin.take().unwrap().write_all(b"x").unwrap();
    assert!(child.wait().unwrap().success());
}

fn value(counter: &mut File) -> u64 {
    counter.seek(SeekFrom::Start(0)).unwrap();
    let mut text = String::new();
    counter.read_to_string(&mut text).unwrap();
    text.trim().parse().unwrap()
}

fn reset(counter: &mut File) {
    counter.seek(SeekFrom::Start(0)).unwrap();
    counter.write_all(b"1").unwrap();
}

fn main() {
    if std::env::args().nth(1).as_deref() == Some("allocate") {
        child();
        return;
    }
    let membership = fs::read_to_string("/proc/self/cgroup").unwrap();
    let relative = membership.lines().find_map(|s| s.strip_prefix("0::")).unwrap();
    assert!(relative.contains("ipse-p27-aggregate-probe-"));
    let path = format!("/sys/fs/cgroup{relative}/memory.peak");
    let mut lifetime = File::open(&path).unwrap();
    let mut interval = OpenOptions::new().read(true).write(true).open(&path).unwrap();
    reset(&mut interval);
    let empty = value(&mut interval);
    for _ in 0..2 { finish(allocate()); }
    let serial = value(&mut interval);
    reset(&mut interval);
    let first = allocate();
    let second = allocate();
    finish(first);
    finish(second);
    let overlap = value(&mut interval);
    reset(&mut interval);
    finish(allocate());
    let after_reset = value(&mut interval);
    let lifetime_peak = value(&mut lifetime);
    assert!(serial > empty + 48 * 1024 * 1024);
    assert!(overlap > serial + 48 * 1024 * 1024);
    assert!(after_reset + 48 * 1024 * 1024 < overlap);
    assert!(lifetime_peak >= overlap);
    println!("{{\"metric\":\"linux_memcg_charged_peak_bytes\",\"allocation_bytes_each\":{ALLOCATION},\"empty\":{empty},\"serial\":{serial},\"overlap\":{overlap},\"after_fd_reset\":{after_reset},\"lifetime\":{lifetime_peak},\"samples_used\":false,\"children_reaped\":true,\"inference_requests\":0}}");
}
