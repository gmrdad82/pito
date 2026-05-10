use clap::{Parser, Subcommand};

use crate::confirm::YesNo;

#[derive(Parser)]
#[command(
    name = "pito",
    about = "pito CLI",
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
    /// Configure local authentication state
    Auth(AuthArgs),
    /// Import footage from local files
    Footage(FootageArgs),
    /// Print help
    Help,
    /// Search videos and channels
    Search(SearchArgs),
    /// List saved views
    Views(ViewsArgs),
    /// Print version
    Version,
}

// --- auth -------------------------------------------------------------------

#[derive(clap::Args)]
pub struct AuthArgs {
    #[command(subcommand)]
    pub command: AuthCommand,
}

/// Subcommands of `pito auth`. Per the Phase 18 CLI parity spec
/// (work unit 2): `login`, `logout`, `whoami`.
#[derive(Subcommand)]
pub enum AuthCommand {
    /// Save server URL and token to ~/.config/pito/auth.toml
    Login(AuthLoginArgs),
    /// Delete ~/.config/pito/auth.toml
    Logout(AuthLogoutArgs),
    /// Show the resolved server URL and a token preview
    Whoami(AuthWhoamiArgs),
}

#[derive(clap::Args)]
pub struct AuthLoginArgs {
    /// Server URL (e.g. https://app.pitomd.com). If omitted, prompted interactively.
    #[arg(long, value_name = "URL")]
    pub url: Option<String>,

    /// API token. If omitted, prompted interactively.
    #[arg(long, value_name = "TOKEN")]
    pub token: Option<String>,

    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct AuthLogoutArgs {
    /// Confirmation gate. Pass `--confirm yes` to actually delete the
    /// auth file. Without this flag, prints the preview and exits 0.
    #[arg(long, value_name = "YES_OR_NO", value_enum)]
    pub confirm: Option<YesNo>,

    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct AuthWhoamiArgs {
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

// --- footage ----------------------------------------------------------------

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

// --- search -----------------------------------------------------------------

#[derive(clap::Args)]
pub struct SearchArgs {
    /// Search query string. Hits `GET /search.json?q=<query>`.
    #[arg(value_name = "QUERY")]
    pub query: String,

    /// Cap the result count (per Phase 18 spec, default 50).
    #[arg(long, value_name = "N", default_value_t = 50)]
    pub limit: u32,

    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

// --- views ------------------------------------------------------------------

#[derive(clap::Args)]
pub struct ViewsArgs {
    #[command(subcommand)]
    pub command: ViewsCommand,
}

#[derive(Subcommand)]
pub enum ViewsCommand {
    /// List saved views (GET /saved_views.json)
    List(ViewsListArgs),
}

#[derive(clap::Args)]
pub struct ViewsListArgs {
    /// Cap the result count (per Phase 18 spec, default 50).
    #[arg(long, value_name = "N", default_value_t = 50)]
    pub limit: u32,

    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}
