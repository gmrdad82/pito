use anyhow::Result;
use clap::CommandFactory;

use crate::cli::Cli;

pub fn run() -> Result<()> {
    Cli::command().print_help()?;
    println!();
    Ok(())
}
