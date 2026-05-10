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
    /// Read calendar entries / schedule / month grid (Phase 21)
    Calendar(CalendarArgs),
    /// Import footage from local files
    Footage(FootageArgs),
    /// Browse / inspect games (Phase 21)
    Games(GamesArgs),
    /// Print help
    Help,
    /// Read or modify notifications (Phase 21)
    Notifications(NotificationsArgs),
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

// --- games (Phase 21) -------------------------------------------------------

#[derive(clap::Args)]
pub struct GamesArgs {
    #[command(subcommand)]
    pub command: GamesCommand,
}

#[derive(Subcommand)]
pub enum GamesCommand {
    /// List games (GET /games.json)
    List(GamesListArgs),
    /// Show a single game by slug or id (GET /games/:id.json)
    Show(GamesShowArgs),
    /// IGDB type-ahead search (GET /games/search.json?q=)
    Search(GamesSearchArgs),
    /// Enqueue an IGDB resync (POST /games/:id/resync.json)
    Resync(GamesResyncArgs),
}

#[derive(clap::Args)]
pub struct GamesListArgs {
    /// Sort column passed to the server (e.g. release_year, title).
    #[arg(long, value_name = "COL")]
    pub sort: Option<String>,
    /// Sort direction. Server understands `asc` / `desc`.
    #[arg(long, value_name = "DIR")]
    pub dir: Option<String>,
    /// 1-indexed page number.
    #[arg(long, value_name = "N")]
    pub page: Option<u32>,
    /// Filter by genre (server interprets the value).
    #[arg(long, value_name = "VALUE")]
    pub genre: Option<String>,
    /// Filter by platform_owned id.
    #[arg(long = "platform-owned", value_name = "VALUE")]
    pub platform_owned: Option<String>,
    /// Cap the result count in the rendered output (server-side pagination is unchanged).
    #[arg(long, value_name = "N", default_value_t = 50)]
    pub limit: u32,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct GamesShowArgs {
    /// Slug (e.g. `the-witness`) or integer id (e.g. `42`). The server
    /// 301s integer ids to the canonical slug; reqwest follows.
    #[arg(value_name = "SLUG_OR_ID")]
    pub slug_or_id: String,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct GamesSearchArgs {
    /// Query string. Empty queries are accepted by the server.
    #[arg(value_name = "QUERY")]
    pub query: String,
    /// Cap the rendered result count (server-side cap stays the same).
    #[arg(long, value_name = "N", default_value_t = 50)]
    pub limit: u32,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct GamesResyncArgs {
    /// Slug or integer id of the game to resync.
    #[arg(value_name = "SLUG_OR_ID")]
    pub slug_or_id: String,
    /// Confirmation gate. Pass `--confirm yes` to actually enqueue.
    /// Without this flag, prints the preview and exits 0.
    #[arg(long, value_name = "YES_OR_NO", value_enum)]
    pub confirm: Option<YesNo>,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

// --- calendar (Phase 21) ----------------------------------------------------

#[derive(clap::Args)]
pub struct CalendarArgs {
    #[command(subcommand)]
    pub command: CalendarCommand,
}

#[derive(Subcommand)]
pub enum CalendarCommand {
    /// Paginated schedule (GET /calendar/schedule.json)
    Schedule(CalendarScheduleArgs),
    /// Month grid (GET /calendar/month/:year/:month.json)
    Month(CalendarMonthArgs),
    /// Show one entry (GET /calendar/entries/:id.json)
    Show(CalendarShowArgs),
    /// Create a manual entry (POST /calendar/entries.json)
    Create(CalendarCreateArgs),
    /// Update a manual entry (PATCH /calendar/entries/:id.json)
    Update(CalendarUpdateArgs),
    /// Set the user-override note (PATCH /calendar/entries/:id/note.json)
    Note(CalendarNoteArgs),
    /// Soft-cancel one or N entries (DELETE /deletions/calendar_entry/:ids.json)
    Cancel(CalendarCancelArgs),
}

#[derive(clap::Args)]
pub struct CalendarScheduleArgs {
    /// Comma-separated entry-type filter (e.g. `video,game`).
    #[arg(long, value_name = "CSV")]
    pub types: Option<String>,
    /// Filter by source (e.g. `derived`, `manual`).
    #[arg(long, value_name = "VALUE")]
    pub source: Option<String>,
    /// Filter by state (e.g. `scheduled`).
    #[arg(long, value_name = "VALUE")]
    pub state: Option<String>,
    /// 1-indexed page number.
    #[arg(long, value_name = "N")]
    pub page: Option<u32>,
    /// Cap the rendered row count.
    #[arg(long, value_name = "N", default_value_t = 50)]
    pub limit: u32,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct CalendarMonthArgs {
    /// Year (e.g. 2026).
    #[arg(value_name = "YEAR")]
    pub year: i32,
    /// Month (1-12).
    #[arg(value_name = "MONTH")]
    pub month: u32,
    /// Comma-separated entry-type filter.
    #[arg(long, value_name = "CSV")]
    pub types: Option<String>,
    /// Filter by state.
    #[arg(long, value_name = "VALUE")]
    pub state: Option<String>,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct CalendarShowArgs {
    /// Entry id.
    #[arg(value_name = "ID")]
    pub id: u64,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct CalendarCreateArgs {
    /// Entry type. Must be one of MANUAL_ENTRY_TYPES on the server.
    #[arg(long, value_name = "VALUE")]
    pub entry_type: String,
    /// Title.
    #[arg(long, value_name = "TEXT")]
    pub title: String,
    /// ISO-8601 start timestamp (e.g. `2026-06-01T10:00:00Z`).
    #[arg(long, value_name = "ISO8601")]
    pub starts_at: String,
    /// Optional ISO-8601 end timestamp.
    #[arg(long, value_name = "ISO8601")]
    pub ends_at: Option<String>,
    /// IANA timezone (e.g. `Europe/Bucharest`).
    #[arg(long, value_name = "TZ")]
    pub timezone: Option<String>,
    /// All-day flag. Wire format is `"yes"` / `"no"`.
    #[arg(long, value_name = "YES_OR_NO", value_enum)]
    pub all_day: Option<YesNo>,
    /// Optional description.
    #[arg(long, value_name = "TEXT")]
    pub description: Option<String>,
    /// Optional parent entry id (linkable manual entries).
    #[arg(long, value_name = "ID")]
    pub parent_entry_id: Option<u64>,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct CalendarUpdateArgs {
    /// Entry id.
    #[arg(value_name = "ID")]
    pub id: u64,
    /// New title.
    #[arg(long, value_name = "TEXT")]
    pub title: Option<String>,
    /// New ISO-8601 starts_at.
    #[arg(long, value_name = "ISO8601")]
    pub starts_at: Option<String>,
    /// New ISO-8601 ends_at.
    #[arg(long, value_name = "ISO8601")]
    pub ends_at: Option<String>,
    /// New timezone.
    #[arg(long, value_name = "TZ")]
    pub timezone: Option<String>,
    /// New all-day flag.
    #[arg(long, value_name = "YES_OR_NO", value_enum)]
    pub all_day: Option<YesNo>,
    /// New description.
    #[arg(long, value_name = "TEXT")]
    pub description: Option<String>,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct CalendarNoteArgs {
    /// Entry id.
    #[arg(value_name = "ID")]
    pub id: u64,
    /// Note text. Empty string clears the note.
    #[arg(long, value_name = "TEXT")]
    pub note: String,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct CalendarCancelArgs {
    /// One or more entry ids. Pass `--ids 12` or `--ids 12,55` for bulk.
    #[arg(long, value_name = "CSV")]
    pub ids: String,
    /// Confirmation gate. Pass `--confirm yes` to actually soft-cancel.
    /// Without this flag, prints the preview and exits 0.
    #[arg(long, value_name = "YES_OR_NO", value_enum)]
    pub confirm: Option<YesNo>,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

// --- notifications (Phase 21) -----------------------------------------------

#[derive(clap::Args)]
pub struct NotificationsArgs {
    #[command(subcommand)]
    pub command: NotificationsCommand,
}

#[derive(Subcommand)]
pub enum NotificationsCommand {
    /// Paginated list (GET /notifications.json)
    List(NotificationsListArgs),
    /// Show one notification (GET /notifications/:id.json)
    Show(NotificationsShowArgs),
    /// Unread badge (GET /notifications/badge.json)
    Badge(NotificationsBadgeArgs),
    /// Mark a notification read (PATCH /notifications/:id/read.json)
    Read(NotificationsReadArgs),
    /// Mark a notification unread (PATCH /notifications/:id/unread.json)
    Unread(NotificationsUnreadArgs),
    /// Bulk mark-read (PATCH /notifications/mark_read.json?ids=)
    MarkRead(NotificationsMarkReadArgs),
    /// Mark every notification read (PATCH /notifications/mark_all_read.json)
    MarkAllRead(NotificationsMarkAllReadArgs),
}

#[derive(clap::Args)]
pub struct NotificationsListArgs {
    /// `unread` or `all`. Server default is `unread`.
    #[arg(long, value_name = "VALUE")]
    pub filter: Option<String>,
    /// Filter by kind (e.g. `video_published`).
    #[arg(long, value_name = "VALUE")]
    pub kind: Option<String>,
    /// Filter by severity (e.g. `success`, `warning`, `failure`).
    #[arg(long, value_name = "VALUE")]
    pub severity: Option<String>,
    /// 1-indexed page number.
    #[arg(long, value_name = "N")]
    pub page: Option<u32>,
    /// Cap the rendered row count.
    #[arg(long, value_name = "N", default_value_t = 50)]
    pub limit: u32,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct NotificationsShowArgs {
    /// Notification id.
    #[arg(value_name = "ID")]
    pub id: u64,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct NotificationsBadgeArgs {
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct NotificationsReadArgs {
    /// Notification id.
    #[arg(value_name = "ID")]
    pub id: u64,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct NotificationsUnreadArgs {
    /// Notification id.
    #[arg(value_name = "ID")]
    pub id: u64,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct NotificationsMarkReadArgs {
    /// One or more notification ids. Pass `--ids 12,13`.
    #[arg(long, value_name = "CSV")]
    pub ids: String,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args)]
pub struct NotificationsMarkAllReadArgs {
    /// Confirmation gate. Pass `--confirm yes` to actually mark all read.
    /// Without this flag, prints the preview (unread count) and exits 0.
    #[arg(long, value_name = "YES_OR_NO", value_enum)]
    pub confirm: Option<YesNo>,
    /// Emit JSON output instead of plaintext.
    #[arg(long)]
    pub json: bool,
}
