mod api;
mod app;
mod cli;
mod commands;
mod footage;
mod keys;
mod theme;
mod ui;
mod widgets;

use anyhow::Result;
use clap::Parser;

fn main() -> Result<()> {
    let parsed = cli::Cli::parse();
    match parsed.command {
        None => commands::tui::run(),
        Some(cli::Commands::Footage(args)) => commands::footage::run(args),
        Some(cli::Commands::Help) => commands::help::run(),
        Some(cli::Commands::Version) => commands::version::run(),
    }
}
