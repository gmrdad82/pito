mod api;
mod app;
mod auth;
mod cli;
mod commands;
mod confirm;
mod footage;
mod keys;
mod output;
mod theme;
mod ui;
mod widgets;

use anyhow::Result;
use clap::Parser;

fn main() -> Result<()> {
    let parsed = cli::Cli::parse();
    match parsed.command {
        None => commands::tui::run(),
        Some(cli::Commands::Auth(args)) => commands::auth::run(args),
        Some(cli::Commands::Calendar(args)) => commands::calendar::run(args),
        Some(cli::Commands::Footage(args)) => commands::footage::run(args),
        Some(cli::Commands::Games(args)) => commands::games::run(args),
        Some(cli::Commands::Help) => commands::help::run(),
        Some(cli::Commands::Notifications(args)) => commands::notifications::run(args),
        Some(cli::Commands::Search(args)) => commands::search::run(args),
        Some(cli::Commands::Views(args)) => commands::views::run(args),
        Some(cli::Commands::Version) => commands::version::run(),
    }
}
