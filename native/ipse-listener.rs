use std::process::{Child, ExitStatus};

pub fn port(text: &str) -> Result<u16, String> {
    if text.is_empty() || !text.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err("listener port must be a decimal integer from 1 to 65535".into());
    }
    text.parse::<u16>().ok().filter(|port| *port != 0)
        .ok_or_else(|| "listener port must be a decimal integer from 1 to 65535".into())
}

#[cfg(target_os = "linux")]
mod linux {
    use super::*;
    use std::fs::{self, File};
    use std::io::Read;
    use std::sync::mpsc::{self, Receiver, TryRecvError};
    use std::time::{Duration, Instant};

    const MAX_TCP: usize = 1_048_576;
    const MAX_FDS: usize = 4096;
    const MAX_STATUS: usize = 65_536;

    fn matching_pid_namespace(bytes: &[u8], pid: u32) -> Result<(), String> {
        if bytes.len() > MAX_STATUS { return Err("owned listener status exceeds bound".into()); }
        let text = std::str::from_utf8(bytes).map_err(|_| "owned listener status malformed")?;
        let mut identities = text.lines().filter_map(|line| line.strip_prefix("NStgid:"));
        let identity = identities.next().ok_or("owned listener PID namespace unavailable")?;
        let mut values = identity.split_whitespace();
        let value = values.next().ok_or("owned listener PID namespace unavailable")?;
        if identities.next().is_some() || values.next().is_some()
            || !value.bytes().all(|byte| byte.is_ascii_digit())
            || pid == 0 || value.parse::<u32>().ok() != Some(pid) {
            return Err("owned listener requires matching procfs and PID namespaces".into());
        }
        Ok(())
    }

    fn require_matching_pid_namespace() -> Result<(), String> {
        let file = File::open("/proc/self/status")
            .map_err(|_| "owned listener PID namespace unavailable")?;
        let mut bytes = Vec::new();
        file.take((MAX_STATUS + 1) as u64).read_to_end(&mut bytes)
            .map_err(|_| "owned listener PID namespace unavailable")?;
        matching_pid_namespace(&bytes, std::process::id())
    }

    fn hexadecimal(text: &str, width: usize) -> Result<u64, String> {
        if text.len() != width || !text.bytes().all(|c| c.is_ascii_hexdigit()) {
            return Err("malformed listener TCP table".into());
        }
        u64::from_str_radix(text, 16).map_err(|_| "malformed listener TCP table".into())
    }

    fn address(text: &str) -> Result<(u64, u64), String> {
        let (host, port) = text.split_once(':').ok_or("malformed listener TCP address")?;
        Ok((hexadecimal(host, 8)?, hexadecimal(port, 4)?))
    }

    fn listening_inode(text: &str, port: u16) -> Result<Option<u64>, String> {
        let mut lines = text.lines();
        if lines.next().map(|line| line.split_whitespace().take(4).collect::<Vec<_>>())
            != Some(vec!["sl", "local_address", "rem_address", "st"]) {
            return Err("malformed listener TCP header".into());
        }
        let mut found = None;
        for line in lines {
            let fields = line.split_whitespace().collect::<Vec<_>>();
            if fields.len() < 10 { return Err("malformed listener TCP row".into()); }
            fields[0].strip_suffix(':').ok_or("malformed listener TCP row")?
                .parse::<u32>().map_err(|_| "malformed listener TCP row")?;
            let (host, local_port) = address(fields[1])?;
            address(fields[2])?;
            let state = hexadecimal(fields[3], 2)?;
            let inode = fields[9].parse::<u64>().map_err(|_| "malformed listener socket inode")?;
            if state == 10 && local_port == u64::from(port) {
                if host != u64::from(u32::from_ne_bytes([127, 0, 0, 1])) || inode == 0 || found.is_some() {
                    return Err("listener tuple is foreign or ambiguous".into());
                }
                found = Some(inode);
            }
        }
        Ok(found)
    }

    fn table(port: u16) -> Result<Option<u64>, String> {
        let file = File::open("/proc/self/net/tcp")
            .map_err(|_| "owned listener TCP table unavailable")?;
        let mut bytes = Vec::new();
        file.take((MAX_TCP + 1) as u64).read_to_end(&mut bytes)
            .map_err(|_| "owned listener TCP table unavailable")?;
        table_bytes(&bytes, port)
    }

    fn table_bytes(bytes: &[u8], port: u16) -> Result<Option<u64>, String> {
        if bytes.len() > MAX_TCP { return Err("owned listener TCP table exceeds bound".into()); }
        let text = std::str::from_utf8(bytes).map_err(|_| "malformed listener TCP table")?;
        listening_inode(text, port)
    }

    fn socket_inode(link: &str) -> Result<Option<u64>, String> {
        if !link.starts_with("socket:") { return Ok(None); }
        let value = link.strip_prefix("socket:[").and_then(|s| s.strip_suffix(']'))
            .ok_or("malformed owned socket link")?;
        if value.is_empty() || !value.bytes().all(|c| c.is_ascii_digit()) { return Err("malformed owned socket inode".into()); }
        let value = value.parse::<u64>().ok().filter(|n| *n > 0)
            .ok_or("malformed owned socket inode")?;
        Ok(Some(value))
    }

    fn inspect(pid: u32, port: u16) -> Result<Option<u64>, String> {
        let Some(inode) = table(port)? else { return Ok(None); };
        let entries = fs::read_dir(format!("/proc/{pid}/fd"))
            .map_err(|_| "owned listener descriptors unavailable")?;
        let mut owned = false;
        for (index, entry) in entries.enumerate() {
            if index >= MAX_FDS { return Err("owned listener descriptors exceed bound".into()); }
            let entry = entry.map_err(|_| "owned listener descriptor unavailable")?;
            let name = entry.file_name();
            if !name.to_str().is_some_and(|s| !s.is_empty() && s.bytes().all(|c| c.is_ascii_digit())) {
                return Err("malformed owned listener descriptor".into());
            }
            let link = match fs::read_link(entry.path()) {
                Ok(link) => link,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                Err(_) => return Err("owned listener descriptor unavailable".into()),
            };
            if let Some(link) = link.to_str() { owned |= socket_inode(link)? == Some(inode); }
        }
        if !owned { return Err("listener is not owned by the direct child".into()); }
        if table(port)? != Some(inode) { return Err("owned listener changed during admission".into()); }
        Ok(Some(inode))
    }

    fn payload(pid: u32, port: u16, inode: u64) -> [u8; 15] {
        let mut bytes = [0_u8; 15]; bytes[0] = 1;
        bytes[1..5].copy_from_slice(&pid.to_be_bytes());
        bytes[5..7].copy_from_slice(&port.to_be_bytes());
        bytes[7..15].copy_from_slice(&inode.to_be_bytes()); bytes
    }

    pub struct Listener {
        port: u16, admitted: bool, next: Instant,
        pending: Option<Receiver<Result<Option<u64>, String>>>,
    }

    impl Listener {
        pub fn new(port: u16) -> Result<Self, String> {
            require_matching_pid_namespace()?;
            Ok(Self { port, admitted: false, next: Instant::now(), pending: None })
        }

        pub fn inspection_pending(&self) -> bool { self.pending.is_some() }

        pub fn poll_child(&mut self, child: &mut Child) -> Result<(Option<ExitStatus>, Option<[u8; 15]>), String> {
            let observed = if let Some(receiver) = &self.pending {
                match receiver.try_recv() {
                    Ok(result) => { self.pending = None; Some(result) }
                    Err(TryRecvError::Empty) => return Ok((None, None)),
                    Err(TryRecvError::Disconnected) => return Err("owned listener inspection failed".into()),
                }
            } else { None };
            // The main stdio loop is the only reaper. While inspection is pending,
            // retain the unreaped Child so its PID cannot identify another process.
            let status = child.try_wait().map_err(|_| "cannot wait for stdio server")?;
            if status.is_some() { return Ok((status, None)); }
            if let Some(result) = observed {
                self.next = Instant::now() + Duration::from_millis(25);
                if let Some(inode) = result? {
                    self.admitted = true;
                    return Ok((None, Some(payload(child.id(), self.port, inode))));
                }
            }
            if !self.admitted && Instant::now() >= self.next {
                let (send, receive) = mpsc::channel(); let pid = child.id(); let port = self.port;
                std::thread::Builder::new().name("ipse-listener".into())
                    .spawn(move || { let result = inspect(pid, port); let _ = send.send(result); })
                    .map_err(|_| "owned listener inspection could not start")?;
                self.pending = Some(receive);
            }
            Ok((None, None))
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        const HEADER: &str = "  sl local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode\n";
        fn row(host: &str, port: u16, state: &str, inode: &str) -> String {
            format!("0: {host}:{port:04X} 00000000:0000 {state} 00000000:00000000 00:00000000 00000000 1000 0 {inode} 1\n")
        }
        #[test]
        fn accepts_only_exact_loopback_listen_inode() {
            let own = HEADER.to_string() + &row("0100007F", 21434, "0A", "991");
            assert_eq!(listening_inode(&own, 21434).unwrap(), Some(991));
            assert_eq!(listening_inode(&own, 21435).unwrap(), None);
            assert_eq!(listening_inode(&(HEADER.to_string() + &row("0100007F", 21434, "01", "991")), 21434).unwrap(), None);
            for host in ["00000000", "0200007F", "0100000A"] {
                assert!(listening_inode(&(HEADER.to_string() + &row(host, 21434, "0A", "991")), 21434).is_err());
            }
        }
        #[test]
        fn rejects_ambiguous_and_malformed_required_records() {
            let own = row("0100007F", 21434, "0A", "991");
            assert!(listening_inode(&(HEADER.to_string() + &own + &own), 21434).is_err());
            for text in ["", "wrong header\n", "sl local_address rem_address st\nbroken\n"] {
                assert!(listening_inode(text, 21434).is_err());
            }
            for inode in ["0", "no", "18446744073709551616"] {
                assert!(listening_inode(&(HEADER.to_string() + &row("0100007F", 21434, "0A", inode)), 21434).is_err());
            }
            for host in ["010007F", "ZZ00007F"] {
                assert!(listening_inode(&(HEADER.to_string() + &row(host, 21434, "0A", "991")), 21434).is_err());
            }
        }
        #[test]
        fn table_bytes_have_finite_and_utf8_bounds() {
            assert!(table_bytes(&vec![b'x'; MAX_TCP + 1], 21434).is_err());
            assert!(table_bytes(&[255], 21434).is_err());
            assert_eq!(table_bytes(HEADER.as_bytes(), 21434).unwrap(), None);
        }
        #[test]
        fn procfs_pid_namespace_must_name_only_the_current_process() {
            assert!(matching_pid_namespace(b"Name:\tipse-runner\nNStgid:\t7\n", 7).is_ok());
            for text in ["", "NStgid:\n", "NStgid: 7\nNStgid: 7\n", "NStgid: 7 8\n",
                "NStgid: 7 7\n", "NStgid: 8\n", "NStgid: 0\n", "NStgid: +7\n",
                "NStgid: -7\n", "NStgid: 7x\n", "NStgid: 4294967296\n"] {
                assert!(matching_pid_namespace(text.as_bytes(), 7).is_err(), "{text:?}");
            }
            assert!(matching_pid_namespace(b"NStgid: 0\n", 0).is_err());
            assert!(matching_pid_namespace(&[255], 7).is_err());
            assert!(matching_pid_namespace(&vec![b'x'; MAX_STATUS + 1], 7).is_err());
        }
        #[test]
        fn socket_links_are_exact_and_payload_is_native_fact() {
            assert_eq!(socket_inode("socket:[991]").unwrap(), Some(991));
            assert_eq!(socket_inode("/tmp/socket:[991]").unwrap(), None);
            for link in ["socket:[0]", "socket:[991]extra", "socket:991", "socket:[x]", "socket:[+991]"] { assert!(socket_inode(link).is_err()); }
            let bytes = payload(123, 21434, 991);
            assert_eq!(bytes.len(), 15); assert_eq!(bytes[0], 1);
            assert_eq!(u32::from_be_bytes(bytes[1..5].try_into().unwrap()), 123);
            assert_eq!(u16::from_be_bytes(bytes[5..7].try_into().unwrap()), 21434);
            assert_eq!(u64::from_be_bytes(bytes[7..].try_into().unwrap()), 991);
        }
    }
}

#[cfg(target_os = "linux")]
pub use linux::Listener;
#[cfg(not(target_os = "linux"))]
pub struct Listener;
#[cfg(not(target_os = "linux"))]
impl Listener {
    pub fn new(_port: u16) -> Result<Self, String> { Err("owned listener admission requires Linux".into()) }
    pub fn inspection_pending(&self) -> bool { false }
    pub fn poll_child(&mut self, _child: &mut Child) -> Result<(Option<ExitStatus>, Option<[u8; 15]>), String> {
        Err("owned listener admission requires Linux".into())
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn port_requires_literal_nonzero_u16() {
        assert_eq!(super::port("1").unwrap(), 1); assert_eq!(super::port("65535").unwrap(), 65535);
        for value in ["", "0", "65536", "+12", " 12", "12x", "-1", "localhost:12"] { assert!(super::port(value).is_err()); }
    }
}
