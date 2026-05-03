use anyhow::Result;

pub fn run() -> Result<()> {
    println!("pito {}", env!("CARGO_PKG_VERSION"));
    Ok(())
}
