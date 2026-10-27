path = "/tmp/ipse-serenity-qualification-plan/fixture/real_backend.rs"
s = File.read!(path)
[first, rest] = String.split(s, "    fn fixture_mount(&mut self, e: &Expected) -> Result<bool, ()> {", parts: 2)
[_old, last] = String.split(rest, "    fn mapper_absent(&mut self, e: &Expected) -> Result<bool, ()> {", parts: 2)
replacement = ~S"""
    fn fixture_mount(&mut self, e: &Expected) -> Result<bool, ()> {
        self.fixed_name(e)?;
        let contents = fs::read_to_string("/proc/self/mountinfo").map_err(|_| ())?;
        if contents.len() > 1_048_576 { return Err(()); }
        let target = self.mount.to_str().ok_or(())?;
        let mut id = None;
        for line in contents.lines() {
            let (left,right) = line.split_once(" - ").ok_or(())?;
            let l: Vec<_> = left.split_ascii_whitespace().collect();
            let r: Vec<_> = right.split_ascii_whitespace().collect();
            if l.len() < 6 || r.len() < 3 { return Err(()); }
            if l[4] == target {
                if id.is_some() || r[0] != "btrfs" { return Err(()); }
                id=Some(l[0].parse::<u64>().map_err(|_| ())?);
            }
        }
        let Some(expected_mount)=id else{return Ok(false)};
        let named=fs::symlink_metadata(&self.mount).map_err(|_| ())?;
        let held=File::open(&self.mount).map_err(|_| ())?;
        let meta=held.metadata().map_err(|_| ())?;
        if !meta.is_dir() || (named.dev(),named.ino())!=(meta.dev(),meta.ino()) {return Err(())}
        let info=super::btrfs_identity::inspect(&held,&self.sysroot).map_err(|_| ())?;
        if info.mount_id!=expected_mount || info.underlying!=(e.dm_major as u32,e.dm_minor as u32) {return Err(())}
        let after=fs::symlink_metadata(&self.mount).map_err(|_| ())?;
        if (after.dev(),after.ino())!=(meta.dev(),meta.ino()) {return Err(())}
        Ok(true)
    }
"""
File.write!(path, first <> replacement <> "    fn mapper_absent(&mut self, e: &Expected) -> Result<bool, ()> {" <> last)
