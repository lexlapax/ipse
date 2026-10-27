//! Read-only host workspace diagnostic, not device or mount qualification.
#[path="btrfs_identity.rs"] mod btrfs_identity;
fn main()->std::io::Result<()>{let f=std::fs::File::open("/home/lexlapax/projects/lexlapax/ipse")?;let result=btrfs_identity::inspect(&f,std::path::Path::new("/sys"))?;if result.underlying!=(259,12){return Err(std::io::ErrorKind::InvalidData.into())}println!("workspace Btrfs ioctl and sysfs underlying-device identification agrees");Ok(())}
