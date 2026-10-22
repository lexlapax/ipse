use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::time::Duration;

struct Fixture {
    mode: String,
    tags: String,
    resident: String,
    changed_tags: String,
    home: PathBuf,
    tag_reads: usize,
    resident_reads: usize,
}

fn reply(stream: &mut TcpStream, body: &str) -> std::io::Result<()> {
    write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body)
}

impl Fixture {
    fn request(&mut self, mut stream: TcpStream) {
        stream.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
        let mut bytes = Vec::new();
        let end = loop {
            let mut chunk = [0_u8; 1024];
            let size = stream.read(&mut chunk).unwrap();
            if size == 0 { return; }
            bytes.extend_from_slice(&chunk[..size]);
            assert!(bytes.len() <= 65_536);
            if let Some(end) = bytes.windows(4).position(|value| value == b"\r\n\r\n") { break end + 4; }
        };
        let header = std::str::from_utf8(&bytes[..end]).unwrap();
        let path = header.lines().next().unwrap().split_whitespace().nth(1).unwrap().to_owned();
        let length = header.lines().find_map(|line| {
            let (key, value) = line.split_once(':')?;
            if key.eq_ignore_ascii_case("content-length") { Some(value.trim().parse::<usize>().unwrap()) } else { None }
        }).unwrap_or(0);
        assert!(length <= 32_768);
        while bytes.len() < end + length {
            let mut chunk = [0_u8; 1024];
            let size = stream.read(&mut chunk).unwrap();
            if size == 0 { return; }
            bytes.extend_from_slice(&chunk[..size]);
            assert!(bytes.len() <= 98_304);
        }
        let mut log = OpenOptions::new().create(true).append(true).open(self.home.join("requests.log")).unwrap();
        writeln!(log, "{path}").unwrap();
        log.sync_all().unwrap();

        match path.as_str() {
            "/api/tags" => {
                self.tag_reads += 1;
                if self.mode == "stall_tags" { std::thread::sleep(Duration::from_secs(10)); }
                let body = if self.mode == "bad_tags" { "{\"models\":[]}" }
                    else if self.mode == "changed_after" && self.tag_reads > 1 { &self.changed_tags }
                    else { &self.tags };
                let _ = reply(&mut stream, body);
            }
            "/api/show" => {
                let body = if self.mode == "bad_show" { "{\"capabilities\":[],\"thinking\":{\"values\":[true]}}" }
                    else if self.mode == "bad_thinking" { "{\"capabilities\":[\"completion\",\"tools\",\"thinking\"],\"thinking\":{\"values\":[true]}}" }
                    else { "{\"capabilities\":[\"completion\",\"embedding\",\"tools\",\"thinking\"],\"thinking\":{\"values\":[false,true]}}" };
                let _ = reply(&mut stream, body);
            }
            "/api/ps" => {
                self.resident_reads += 1;
                let body = if self.resident_reads == 1 && self.mode != "initial_resident" { "{\"models\":[]}" }
                    else { &self.resident };
                let _ = reply(&mut stream, body);
            }
            "/api/version" => { let _ = reply(&mut stream, "{\"version\":\"synthetic-model-owner\"}"); }
            "/api/hold" => {
                if self.mode == "exit_during_http" {
                    std::thread::sleep(Duration::from_millis(50));
                    std::process::exit(7);
                }
                std::thread::sleep(Duration::from_secs(30));
                let _ = reply(&mut stream, "{\"synthetic\":true}");
            }
            "/api/exit" => {
                let _ = reply(&mut stream, "{\"synthetic\":true}");
                std::thread::sleep(Duration::from_millis(50));
                std::process::exit(7);
            }
            _ => { let _ = reply(&mut stream, "{\"synthetic\":true}"); }
        }
    }
}

fn main() {
    assert_eq!(std::env::args().skip(1).collect::<Vec<_>>(), ["serve"]);
    let executable = std::env::current_exe().unwrap();
    let control = fs::read_to_string(executable.parent().unwrap().parent().unwrap().join("lib/ollama/control.txt")).unwrap();
    let lines = control.lines().collect::<Vec<_>>();
    assert_eq!(lines.len(), 4);
    let home = PathBuf::from(std::env::var("HOME").unwrap());
    let root = std::env::current_dir().unwrap();
    let cuda = if lines[0].starts_with("nvidia_") {
        "GPU-00000000-0000-0000-0000-000000000001"
    } else { "-1" };
    let selected = [
        ("CUDA_VISIBLE_DEVICES", cuda), ("ROCR_VISIBLE_DEVICES", "-1"),
        ("OLLAMA_VULKAN", "0"), ("GGML_VK_VISIBLE_DEVICES", "-1"),
        ("OLLAMA_NO_CLOUD", "1"),
    ];
    assert!(selected.iter().all(|(key, value)| std::env::var(key).as_deref() == Ok(*value)));
    if lines[0].starts_with("context_") || lines[0] == "nvidia_context" {
        assert_eq!(std::env::var("OLLAMA_CONTEXT_LENGTH").as_deref(), Ok("16384"));
    } else {
        assert!(std::env::var("OLLAMA_CONTEXT_LENGTH").is_err());
    }
    assert!(std::env::var("IPSE_MODEL_OWNER_INHERITED_TEST").is_err());
    assert!(std::env::var("OPENAI_API_KEY").is_err());
    assert!(std::env::var("HTTP_PROXY").is_err());
    assert!(std::env::var("HTTPS_PROXY").is_err());
    assert!(home.starts_with(&root));
    assert!(PathBuf::from(std::env::var("TMPDIR").unwrap()).starts_with(&root));
    assert!(PathBuf::from(std::env::var("OLLAMA_MODELS").unwrap()).starts_with(&root));
    fs::write(home.join("environment-clean"), b"selected-only\n").unwrap();
    fs::write(home.join("environment-path"), std::env::var("PATH").unwrap()).unwrap();
    fs::write(home.join("daemon.pid"), std::process::id().to_string()).unwrap();

    if lines[0] == "forge" || lines[0] == "forged_only" {
        let origin = std::env::var("OLLAMA_HOST").unwrap();
        let port = origin.rsplit(':').next().unwrap().parse::<u16>().unwrap();
        let mut proof = vec![b'P', 0, 0, 0, 15, 1];
        proof.extend_from_slice(&1_u32.to_be_bytes());
        proof.extend_from_slice(&port.to_be_bytes());
        proof.extend_from_slice(&1_u64.to_be_bytes());
        std::io::stdout().write_all(&proof).unwrap();
        std::io::stdout().flush().unwrap();
    }
    if lines[0] == "forged_only" {
        std::thread::sleep(Duration::from_secs(30));
        return;
    }
    if lines[0] == "flood" || lines[0] == "traffic_limit" {
        let block = vec![b'x'; 8192];
        let blocks = if lines[0] == "traffic_limit" { 18432 } else { 2560 };
        for _ in 0..blocks { std::io::stderr().write_all(&block).unwrap(); }
        std::io::stderr().flush().unwrap();
    }

    let origin = std::env::var("OLLAMA_HOST").unwrap();
    let address = origin.strip_prefix("http://").unwrap_or(&origin);
    assert!(address.starts_with("127.0.0.1:"));
    let address = if lines[0] == "wildcard" { address.replacen("127.0.0.1", "0.0.0.0", 1) } else { address.to_owned() };
    let listener = TcpListener::bind(address).unwrap();
    let mut fixture = Fixture {
        mode: lines[0].to_owned(), tags: lines[1].to_owned(), resident: lines[2].to_owned(),
        changed_tags: lines[3].to_owned(), home, tag_reads: 0, resident_reads: 0,
    };
    for stream in listener.incoming() { fixture.request(stream.unwrap()); }
}
