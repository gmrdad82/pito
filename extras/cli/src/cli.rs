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
    /// Import footage from local files
    Footage(FootageArgs),
    /// Print help
    Help,
    /// Print version
    Version,
}

#[derive(clap::Args)]
pub struct FootageArgs {
    #[command(subcommand)]
    pub command: FootageCommand,
}

#[derive(Subcommand)]
pub enum FootageCommand {
    /// Import footage files from a local directory into a project
    Import(FootageImportArgs),
}

#[derive(clap::Args)]
pub struct FootageImportArgs {
    /// Project id to import footage into
    #[arg(long, value_name = "ID")]
    pub project: u64,

    /// Path to the local directory containing footage files
    #[arg(long, value_name = "DIR")]
    pub path: std::path::PathBuf,

    /// Optional Game id to associate with each imported footage row
    #[arg(long, value_name = "ID")]
    pub game: Option<u64>,

    /// Platform name (required when --game is set, must match the game's platforms)
    #[arg(long, value_name = "NAME")]
    pub platform: Option<String>,

    /// Footage kind: a_roll or b_roll
    #[arg(long, value_name = "KIND", default_value = "a_roll")]
    pub kind: FootageKindArg,

    /// Recording source: obs or camera
    #[arg(long, value_name = "SOURCE", default_value = "obs")]
    pub source: FootageSourceArg,

    /// Optional markdown description applied to every newly-added row
    #[arg(long, value_name = "TEXT")]
    pub description: Option<String>,

    /// Optional NAS path applied to every newly-added row
    #[arg(long = "nas-path", value_name = "PATH")]
    pub nas_path: Option<String>,

    /// Print classifications and exit without prompting or sending traffic
    #[arg(long)]
    pub dry_run: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum FootageKindArg {
    #[value(name = "a_roll")]
    ARoll,
    #[value(name = "b_roll")]
    BRoll,
}

impl FootageKindArg {
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::ARoll => "a_roll",
            Self::BRoll => "b_roll",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum FootageSourceArg {
    Obs,
    Camera,
}

impl FootageSourceArg {
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Obs => "obs",
            Self::Camera => "camera",
        }
    }
}
