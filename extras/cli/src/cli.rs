use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(
    name = "pito",
    about = "Pito CLI",
    version,
    disable_help_subcommand = true,
    disable_version_flag = false,
    arg_required_else_help = false
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Commands>,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Import footage from local files (Phase 4)
    Footage(FootageArgs),
    /// Print help
    Help,
    /// Print version
    Version,
}

#[derive(clap::Args)]
pub struct FootageArgs {
    // Phase 4 fills these in.
    #[arg(long, hide = true)]
    pub _placeholder: Option<String>,
}
