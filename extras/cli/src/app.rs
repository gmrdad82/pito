use std::io::Write;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use crate::api::client::PitoClient;
use crate::api::models::{AppSettings, BulkOperationStatus, DashboardData, ResponseMode};
use crate::api::thumbnails::{Cache as ThumbnailCache, Tier};
use crate::keybindings::Action as KeybindingAction;
use crate::theme::{Theme, ThemeMode};
use crate::ui::channel_detail::{ChannelDetailState, ChannelInfo, ChannelVideoRow};
use crate::ui::channels::{ChannelFilter, ChannelRow, ChannelsState};
use crate::ui::confirmation::{
    ConfirmationItem, ConfirmationKind, ConfirmationOutcome, ConfirmationState,
};
use crate::ui::footage_detail::{
    FootageDetailState, PreviewProtocol, ScrubRects, TerminalCapability,
};
use crate::ui::leader_menu::LeaderMenuState;
use crate::ui::saved_views::{SavedViewRow, SavedViewsState};
use crate::ui::search::{SearchSection, SearchState};
use crate::ui::settings::SettingsState;
use crate::ui::video_detail::VideoDetailState;
use crate::ui::videos::{SortDirection, VideoRow, VideosState};
use ratatui_image::picker::Picker;

/// Default settings used when `/settings.json` fails. We never want a missing
/// settings endpoint to block the rest of the TUI from rendering, so the
/// fallback is hard-coded with conservative values that match the production
/// defaults.
pub fn default_app_settings() -> AppSettings {
    AppSettings {
        max_panes: 3,
        pane_title_length: 24,
        theme: "dark".to_string(),
    }
}

/// Empty dashboard payload used when `/dashboard.json` fails. Renders as an
/// empty dashboard with zero counts so the rest of the navigation still works.
pub fn empty_dashboard_data() -> DashboardData {
    DashboardData {
        video_count: 0,
        channel_count: 0,
        project_count: 0,
        footage_count: 0,
        note_count: 0,
    }
}

/// Append a single error line to the pito debug log file. The path is
/// `$XDG_CACHE_HOME/pito/error.log`, falling back to `$HOME/.cache/pito/`
/// and finally `/tmp/pito/`. We swallow every IO error: logging is
/// best-effort and must never panic the TUI nor surface to the user.
///
/// Using `print!`/`eprintln!` would corrupt the alternate-screen TUI rendering;
/// the only signals the user gets in-app are flash messages on the relevant
/// screen.
pub fn log_error(scope: &str, err: &dyn std::fmt::Display) {
    let dir = error_log_dir();
    if std::fs::create_dir_all(&dir).is_err() {
        return;
    }
    let path = dir.join("error.log");
    let line = format!("[{}] {}: {}\n", current_timestamp(), scope, err);
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
    {
        let _ = f.write_all(line.as_bytes());
    }
}

fn error_log_dir() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_CACHE_HOME")
        && !xdg.is_empty()
    {
        return PathBuf::from(xdg).join("pito");
    }
    if let Ok(home) = std::env::var("HOME")
        && !home.is_empty()
    {
        return PathBuf::from(home).join(".cache").join("pito");
    }
    PathBuf::from("/tmp").join("pito")
}

fn current_timestamp() -> String {
    chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string()
}

/// Cadence of post-sync channel re-fetches.
pub const SYNC_POLL_INTERVAL: Duration = Duration::from_millis(500);

/// Hard cap on how long pito keeps polling after a sync confirm.
pub const SYNC_POLL_DEADLINE: Duration = Duration::from_secs(10);

/// Cadence of bulk-operation progress polling.
pub const OPERATION_POLL_INTERVAL: Duration = Duration::from_millis(500);

/// Hard cap on how long the in-TUI progress overlay polls a bulk operation.
/// After this elapses we dismiss the overlay (server-side work continues).
pub const OPERATION_POLL_DEADLINE: Duration = Duration::from_secs(30);

/// Tracks an in-flight post-sync polling window so the channels view can
/// re-fetch the affected rows without blocking the UI thread.
#[derive(Debug, Clone)]
pub struct SyncPolling {
    /// Channel ids that were sent in the bulk_sync_channels(confirm=true) call.
    pub affected_ids: Vec<u64>,
    /// Earliest time at which the next refetch should happen.
    pub next_poll_at: Instant,
    /// After this instant, polling stops regardless of channel state.
    pub deadline: Instant,
    /// Increment-on-tick counter used to animate the `syncing.`, `syncing..`,
    /// `syncing...` indicator on affected rows.
    pub tick: u8,
}

impl SyncPolling {
    pub fn new(affected_ids: Vec<u64>) -> Self {
        let now = Instant::now();
        Self {
            affected_ids,
            next_poll_at: now,
            deadline: now + SYNC_POLL_DEADLINE,
            tick: 0,
        }
    }
}

/// Server-side bulk operation tracked by the in-TUI progress overlay.
///
/// Created the moment a bulk delete/sync confirm returns an `operation_id`.
/// `last_status` is updated each time the polling loop fetches the status
/// endpoint. The overlay reads `last_status` to render its progress bar; the
/// `App::tick` loop owns the polling cadence and dismissal logic.
#[derive(Debug, Clone)]
pub struct OperationProgress {
    pub operation_id: u64,
    /// "bulk_delete" | "bulk_sync" — used to title the overlay.
    pub kind: String,
    /// Most recent status snapshot. `None` until the first poll succeeds.
    pub last_status: Option<BulkOperationStatus>,
    /// Earliest time at which the next status fetch should happen.
    pub next_poll_at: Instant,
    /// After this instant, polling stops and the overlay dismisses.
    pub deadline: Instant,
    /// Set when the user pressed Esc to dismiss early — server work continues.
    pub dismissed: bool,
    /// Most recent error message from a failed status fetch, surfaced in flash.
    pub last_error: Option<String>,
    /// Increment-on-tick counter used to advance the per-row dot-loader
    /// animation (`=---` / `-=--` / `--=-` / `---=`) for items that are still
    /// pending. Mirrors Rails' bounce-loader CSS animation.
    pub tick: u8,
}

impl OperationProgress {
    pub fn new(operation_id: u64, kind: impl Into<String>) -> Self {
        let now = Instant::now();
        Self {
            operation_id,
            kind: kind.into(),
            last_status: None,
            next_poll_at: now,
            deadline: now + OPERATION_POLL_DEADLINE,
            dismissed: false,
            last_error: None,
            tick: 0,
        }
    }
}

pub struct DashboardState {
    pub data: DashboardData,
    /// Brief flash message shown on the dashboard toolbar (e.g. used to
    /// surface a fetch failure when the underlying endpoint returns 406/500).
    pub flash: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Screen {
    Dashboard,
    Channels,
    ChannelDetail,
    Videos,
    VideoDetail,
    SavedViews,
    Settings,
    /// Footage detail — DaVinci-style scrub UI for an imported footage.
    /// Phase 7.5 step 06 (CLI half).
    FootageDetail,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Overlay {
    Help,
    Search,
    Confirmation,
    /// Unified leader-key menu — root popup triggered by SPACE. Driven by
    /// `config/keybindings.yml` (shared with the Rails web app). State lives
    /// in `App::leader_menu`.
    LeaderMenu,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyState {
    Normal,
    GPrefix,
    ColonPrefix,
    FilterPrefix,
}

pub struct App {
    pub running: bool,
    pub screen: Screen,
    pub overlay: Option<Overlay>,
    pub theme_mode: ThemeMode,
    pub key_state: KeyState,
    pub dashboard_state: DashboardState,
    pub channels_state: ChannelsState,
    pub channel_detail_state: Option<ChannelDetailState>,
    pub videos_state: VideosState,
    pub video_detail_state: Option<VideoDetailState>,
    /// State for the footage detail scrub screen. Allocated lazily when the
    /// user navigates into the footage detail surface; cleared on back-out
    /// so the manifest doesn't outlive the navigation.
    pub footage_detail_state: Option<FootageDetailState>,
    /// Most-recently-rendered scrub rects (preview + strip). Captured by
    /// `ui::render` so the mouse-event router knows which rects the cursor
    /// lives in. `None` until the first frame renders the footage detail
    /// screen.
    pub footage_detail_rects: Option<ScrubRects>,
    /// Terminal graphics capability detected once at boot. Used by the
    /// footage detail screen to pick a render path; never re-detected per
    /// frame (the user's terminal doesn't change underneath us).
    pub terminal_capability: TerminalCapability,
    /// Picker built once at boot from the detected capability. Used by the
    /// footage detail screen to convert decoded `DynamicImage` bytes into a
    /// `StatefulProtocol` ready for `ratatui-image::StatefulImage`. `None`
    /// only on `TextOnly` terminals (where image rendering is skipped).
    pub thumbnails_picker: Option<Picker>,
    /// On-disk LRU cache for fetched master / thumb JPEGs.
    pub thumbnails_cache: ThumbnailCache,
    /// Base URL used to fetch the manifest + frames. Defaults to
    /// `PITO_API_URL` (or `https://app.pitomd.com`); tests inject a wiremock
    /// origin via `with_client_and_thumbnails_config`.
    pub thumbnails_base_url: String,
    /// Currently-loaded image protocol for the active scrub timestamp.
    /// Rebuilt whenever `(footage_id, active_timestamp)` changes. `None`
    /// before the first successful fetch and on text-only terminals.
    pub footage_detail_preview: Option<PreviewProtocol>,
    pub search_state: SearchState,
    pub saved_views_state: SavedViewsState,
    pub settings_state: SettingsState,
    pub confirmation_state: Option<ConfirmationState>,
    /// Tracks which screen launched the confirmation so we can route the
    /// confirm callback to the right state mutator.
    pub confirmation_origin: Option<Screen>,
    /// In-flight post-sync polling window. `None` when no sync is being
    /// observed.
    pub sync_polling: Option<SyncPolling>,
    /// In-flight bulk-operation progress, drives the overlay rendering.
    pub operation_progress: Option<OperationProgress>,
    /// Leader-menu overlay state. `Some` while the popup is open; `None`
    /// otherwise. Populated when the user presses the leader key (SPACE),
    /// cleared when the popup is dismissed (Esc / leader / completed action).
    pub leader_menu: Option<LeaderMenuState>,
    /// Status-line message produced by leader-menu actions that don't yet
    /// have a concrete TUI implementation (web-only navigates, contextual
    /// actions, etc.). Rendered in the footer; cleared on the next leader
    /// interaction.
    pub leader_status: Option<String>,
    /// The single client used for all backend calls during this session.
    /// Holding one instance is required so mutations made by bulk delete /
    /// sync (which live in the mock's internal state) are visible to the
    /// follow-up `refresh_channels` call. Spawning a fresh `MockClient::new()`
    /// per call would re-seed and silently undo the change.
    client: Box<dyn PitoClient>,
}

/// Default thumbnails base URL when no explicit override is provided. Mirrors
/// `HttpClient::DEFAULT_BASE_URL` — duplicated here to avoid pulling the
/// `http_client` module into every test that constructs `App`.
pub const DEFAULT_THUMBNAILS_BASE_URL: &str = "https://app.pitomd.com";

impl App {
    pub fn with_client(client: Box<dyn PitoClient>) -> Self {
        let base_url = std::env::var("PITO_API_URL")
            .unwrap_or_else(|_| DEFAULT_THUMBNAILS_BASE_URL.to_string());
        let cache = ThumbnailCache::new();
        Self::with_client_and_thumbnails_config(client, base_url, cache)
    }

    /// Build the app with explicit thumbnails plumbing. Tests use this to
    /// point the manifest / frame fetches at a wiremock origin and to redirect
    /// the on-disk cache at a `tempfile::tempdir`. The `client` argument
    /// behaves identically to `with_client`.
    pub fn with_client_and_thumbnails_config(
        client: Box<dyn PitoClient>,
        thumbnails_base_url: impl Into<String>,
        thumbnails_cache: ThumbnailCache,
    ) -> Self {
        // Each per-endpoint fetch is wrapped in its own match block so a 406/500
        // on one endpoint cannot blank the state of another. Every error is
        // routed to the relevant screen's flash slot (if it has user-visible
        // surface) and to the on-disk debug log so the user can `tail` it.
        // Using `?` here would cascade — that's the bug class we explicitly
        // avoid.
        let mut dashboard_flash: Option<String> = None;
        let dashboard_data = match client.get_dashboard() {
            Ok(data) => data,
            Err(e) => {
                log_error("startup get_dashboard", &e);
                dashboard_flash = Some(format!("dashboard fetch failed: {}", e));
                empty_dashboard_data()
            }
        };
        let dashboard_state = DashboardState {
            data: dashboard_data,
            flash: dashboard_flash,
        };

        let mut channels_flash: Option<String> = None;
        let channels = match client.get_channels() {
            Ok(c) => c,
            Err(e) => {
                log_error("startup get_channels", &e);
                channels_flash = Some(format!("channels fetch failed: {}", e));
                Vec::new()
            }
        };
        let channels_state = ChannelsState {
            channels: channels
                .iter()
                .map(|c| ChannelRow {
                    id: c.id,
                    channel_url: c.channel_url.clone(),
                    star: c.star,
                    connected: c.connected,
                    last_synced_at: c.last_synced_at.clone(),
                })
                .collect(),
            selected: 0,
            selected_ids: Vec::new(),
            sort_column: 0,
            sort_direction: SortDirection::Asc,
            scroll_offset: 0,
            filter: ChannelFilter::None,
            flash: channels_flash,
        };

        let videos = match client.get_videos() {
            Ok(v) => v,
            Err(e) => {
                log_error("startup get_videos", &e);
                Vec::new()
            }
        };
        let videos_state = VideosState {
            videos: videos
                .iter()
                .map(|v| VideoRow {
                    id: v.id,
                    youtube_video_id: v.youtube_video_id.clone(),
                    channel_id: v.channel_id,
                    star: v.star,
                    views: v.views,
                    trend: v.trend.clone().unwrap_or_else(|| "flat".to_string()),
                    likes: v.likes,
                    comments: v.comments,
                    watch_time_minutes: v.watch_time_minutes,
                })
                .collect(),
            selected: 0,
            selected_ids: Vec::new(),
            sort_column: 0,
            sort_direction: SortDirection::Asc,
            scroll_offset: 0,
        };

        let saved_views = match client.get_saved_views() {
            Ok(s) => s,
            Err(e) => {
                log_error("startup get_saved_views", &e);
                Vec::new()
            }
        };
        let saved_views_state = SavedViewsState {
            views: saved_views
                .iter()
                .map(|sv| SavedViewRow {
                    id: sv.id,
                    name: sv.name.clone(),
                    kind: sv.kind.clone(),
                    url: sv.url.clone(),
                })
                .collect(),
            selected: 0,
        };

        // Settings is a meta endpoint — when it fails we silently fall back to
        // defaults rather than surfacing a flash, since the user doesn't
        // actively look at settings on startup. The debug log still records
        // the failure so it's diagnosable.
        let settings = match client.get_settings() {
            Ok(s) => s,
            Err(e) => {
                log_error("startup get_settings", &e);
                default_app_settings()
            }
        };
        let settings_state = SettingsState {
            max_panes: settings.max_panes,
            pane_title_length: settings.pane_title_length,
            theme: settings.theme,
            search_engine: "Meilisearch".to_string(),
            search_connected: true,
        };

        let search_state = SearchState {
            query: String::new(),
            cursor_pos: 0,
            results: None,
            selected_section: SearchSection::Videos,
            selected_row: 0,
        };

        Self {
            running: true,
            screen: Screen::Dashboard,
            overlay: None,
            theme_mode: ThemeMode::Dark,
            key_state: KeyState::Normal,
            dashboard_state,
            channels_state,
            channel_detail_state: None,
            videos_state,
            video_detail_state: None,
            footage_detail_state: None,
            footage_detail_rects: None,
            // Tests construct App via this constructor; default to TextOnly
            // so test runs never block on real stdio probing. The real CLI
            // entry point (`commands::tui::run`) overrides this immediately
            // after construction with the result of `capability::detect`.
            terminal_capability: TerminalCapability::TextOnly,
            thumbnails_picker: None,
            thumbnails_cache,
            thumbnails_base_url: thumbnails_base_url.into(),
            footage_detail_preview: None,
            search_state,
            saved_views_state,
            settings_state,
            confirmation_state: None,
            confirmation_origin: None,
            sync_polling: None,
            operation_progress: None,
            leader_menu: None,
            leader_status: None,
            client,
        }
    }

    /// Override the terminal capability after boot. Called from
    /// `commands::tui::run` once detection has completed (which must happen
    /// after `enable_raw_mode` + `EnterAlternateScreen` per the
    /// ratatui-image contract).
    ///
    /// Also rebuilds `thumbnails_picker` to match — every capability except
    /// `TextOnly` produces a usable Picker (the live render path falls back
    /// gracefully to text when `thumbnails_picker` is `None`).
    pub fn set_terminal_capability(&mut self, capability: TerminalCapability) {
        self.terminal_capability = capability;
        self.thumbnails_picker = match capability {
            TerminalCapability::TextOnly => None,
            // For graphics-capable terminals the real CLI replaces the picker
            // via `set_terminal_capability_with_picker` below, which preserves
            // the upstream Picker built from the live `from_query_stdio`
            // probe (the latter carries the right font_size, is_tmux flag,
            // etc.). Calling this method without a Picker means the App was
            // constructed in tests / via a manual override; fall back to the
            // halfblocks Picker so rendering still works in those paths.
            _ => Some(crate::ui::footage_detail::capability::halfblocks_picker()),
        };
    }

    /// Variant of `set_terminal_capability` that takes the upstream Picker
    /// built by `Picker::from_query_stdio` so the live CLI keeps the correct
    /// font_size / is_tmux flags. Tests call the simpler
    /// `set_terminal_capability` and rely on the halfblocks fallback.
    pub fn set_terminal_capability_with_picker(
        &mut self,
        capability: TerminalCapability,
        picker: Picker,
    ) {
        self.terminal_capability = capability;
        self.thumbnails_picker = match capability {
            TerminalCapability::TextOnly => None,
            _ => Some(picker),
        };
    }

    /// Open the footage detail screen for the given id + label.
    /// The label is what shows in the preview header (typically the
    /// footage's filename or YouTube id).
    ///
    /// Synchronously fetches the manifest from
    /// `GET /footages/:id/frames.json` and, on success, the active master
    /// frame. Failures (network, 404, decode) surface in the screen's flash
    /// slot and never panic — the screen still renders with the text
    /// fallback so the user can navigate back out.
    ///
    /// The CLI doesn't yet ship a footage list / picker screen, so this
    /// method is unreachable from the binary's runtime keymap today —
    /// the screen is exercised by tests. Once a footage browser screen
    /// lands the `Enter`-on-a-footage-row arm will call this.
    #[allow(dead_code)]
    pub fn open_footage_detail(&mut self, footage_id: u64, label: impl Into<String>) {
        let mut state = FootageDetailState::new(footage_id, label);
        // Manifest fetch happens inline. The synchronous tick loop blocks
        // briefly here, which is acceptable per the dispatch's "synchronous
        // fetch — prefetch can land later" decision.
        match crate::api::thumbnails::fetch_manifest(&self.thumbnails_base_url, footage_id) {
            Ok(manifest) => {
                state.set_manifest(manifest);
            }
            Err(e) => {
                log_error("open_footage_detail fetch_manifest", &e);
                state.flash = Some(format!("frames manifest fetch failed: {}", e));
            }
        }
        self.footage_detail_state = Some(state);
        self.footage_detail_rects = None;
        self.footage_detail_preview = None;
        self.screen = Screen::FootageDetail;
        // Once the manifest is set, kick off the active master fetch so the
        // first frame the user sees is a real image (when graphics work) or
        // the text fallback (when they don't).
        self.refresh_active_preview_protocol();
    }

    /// Apply a manifest fetched from
    /// `GET /footages/:id/frames.json` to the footage detail state. No-op
    /// when the screen has been closed in the meantime.
    ///
    /// Used directly by tests; the runtime path goes through
    /// `open_footage_detail` (which calls `fetch_manifest` itself).
    #[allow(dead_code)]
    pub fn apply_footage_manifest(&mut self, manifest: crate::api::thumbnails::Manifest) {
        if let Some(ref mut s) = self.footage_detail_state {
            s.set_manifest(manifest);
        }
        self.refresh_active_preview_protocol();
    }

    /// Fetch the master JPEG for the active scrub timestamp (cache-aware) and
    /// rebuild the `StatefulProtocol` that backs the preview rendering. No-op
    /// when:
    ///
    /// - The screen has been closed (`footage_detail_state` is `None`).
    /// - The manifest is empty (no frames extracted server-side yet).
    /// - The terminal capability is `TextOnly` (no protocol to build).
    /// - The cached `(footage_id, timestamp)` matches the current preview
    ///   already (avoids re-decoding on every keystroke).
    ///
    /// Errors are recorded to the on-disk debug log and surfaced in the
    /// screen's flash slot. The fallback path keeps rendering text so the
    /// user can still scrub.
    pub fn refresh_active_preview_protocol(&mut self) {
        let Some(state) = self.footage_detail_state.as_ref() else {
            return;
        };
        let Some(ref manifest) = state.manifest else {
            return;
        };
        if manifest.timestamps.is_empty() {
            // Nothing to render — keep `footage_detail_preview` as `None` so
            // the renderer falls back to the "no frames" placeholder.
            self.footage_detail_preview = None;
            return;
        }
        let footage_id = state.footage_id;
        let timestamp = state.active_timestamp_seconds;

        // Quick reuse path: the active timestamp didn't change since the
        // last build. Saves a cache lookup AND a re-decode on every step().
        if let Some(ref preview) = self.footage_detail_preview
            && preview.matches(footage_id, timestamp)
        {
            return;
        }

        // No picker means TextOnly (or pre-detection); skip image work.
        let Some(picker) = self.thumbnails_picker.clone() else {
            return;
        };

        let base_url = self.thumbnails_base_url.clone();
        let cache = self.thumbnails_cache.clone();
        let bytes_result = cache.fetch_or_get(footage_id, Tier::Master, timestamp, || {
            crate::api::thumbnails::fetch_frame_bytes(
                &base_url,
                footage_id,
                Tier::Master,
                timestamp,
            )
        });
        let bytes = match bytes_result {
            Ok(b) => b,
            Err(e) => {
                log_error("refresh_active_preview_protocol fetch_frame_bytes", &e);
                if let Some(ref mut s) = self.footage_detail_state {
                    s.flash = Some(format!("frame fetch failed: {}", e));
                }
                self.footage_detail_preview = None;
                return;
            }
        };
        match image::load_from_memory(&bytes) {
            Ok(dyn_img) => {
                let protocol = picker.new_resize_protocol(dyn_img);
                self.footage_detail_preview =
                    Some(PreviewProtocol::new(footage_id, timestamp, protocol));
            }
            Err(e) => {
                log_error("refresh_active_preview_protocol decode", &e);
                if let Some(ref mut s) = self.footage_detail_state {
                    s.flash = Some(format!("frame decode failed: {}", e));
                }
                self.footage_detail_preview = None;
            }
        }
    }

    /// Stash the rects rendered for the active footage detail frame so the
    /// mouse handler can route events to the scrub state.
    ///
    /// `ui::render` writes to the field directly, so this convenience helper
    /// is currently used only by tests that want to seed rects without
    /// going through a full render cycle.
    #[allow(dead_code)]
    pub fn record_footage_detail_rects(&mut self, rects: ScrubRects) {
        self.footage_detail_rects = Some(rects);
    }

    pub fn theme(&self) -> Theme {
        Theme::from_mode(self.theme_mode)
    }

    pub fn toggle_theme(&mut self) {
        self.theme_mode = self.theme_mode.toggle();
    }

    pub fn quit(&mut self) {
        self.running = false;
    }

    /// Open the leader-menu overlay pointed at the root menu. Clears any
    /// stale leader-status message from the previous interaction so the
    /// user sees a clean slate on the next popup.
    pub fn open_leader_menu(&mut self) {
        self.leader_menu = Some(LeaderMenuState::new());
        self.leader_status = None;
        self.overlay = Some(Overlay::LeaderMenu);
    }

    /// Close the leader-menu overlay. Idempotent.
    pub fn close_leader_menu(&mut self) {
        self.leader_menu = None;
        if self.overlay == Some(Overlay::LeaderMenu) {
            self.overlay = None;
        }
    }

    /// Quit + logout: best-effort delete of the on-disk auth file, then quit
    /// the TUI. Any IO error during delete is surfaced as a status message
    /// rather than killing the session — the user can still exit cleanly
    /// even if the file lives in an unwritable directory.
    pub fn quit_and_logout(&mut self) {
        match crate::auth::auth_file_path() {
            Ok(path) => {
                if let Err(e) = crate::auth::delete_file(&path) {
                    log_error("quit_and_logout delete_file", &e);
                    self.leader_status = Some(format!("logout failed: {}", e));
                }
            }
            Err(e) => {
                log_error("quit_and_logout auth_file_path", &e);
                self.leader_status = Some(format!("logout failed: {}", e));
            }
        }
        self.quit();
    }

    /// Run an action's side effect WITHOUT closing the leader-menu overlay.
    /// Used by the combined action + submenu shape (root-menu resource keys
    /// `c`, `C`, `V`, `P`, `G`, `N` carry both a Navigate / Open action AND a
    /// submenu reference: the action fires for status-line feedback, the menu
    /// then drills into the submenu without closing).
    ///
    /// `Quit` / `QuitAndLogout` intentionally do NOT respect the "keep open"
    /// contract — they always terminate the TUI. The schema doesn't combine
    /// either with a submenu, but the explicit early-exit guards against a
    /// future schema bug where someone wires a submenu to a Quit-shaped item.
    pub fn run_leader_action_keep_open(&mut self, action: &KeybindingAction) {
        match action {
            KeybindingAction::Quit => self.quit(),
            KeybindingAction::QuitAndLogout => self.quit_and_logout(),
            KeybindingAction::Navigate { path } => {
                self.leader_status = Some(format!("Web action: navigate {}", path));
            }
            KeybindingAction::Today => {
                self.leader_status = Some("Action: today (calendar view pending)".to_string());
            }
            KeybindingAction::Open { target } => {
                self.leader_status = Some(format!("Action: open {}", target));
            }
            KeybindingAction::BulkDelete => {
                self.leader_status = Some("Action: bulk_delete".to_string());
            }
            KeybindingAction::BulkSync => {
                self.leader_status = Some("Action: bulk_sync".to_string());
            }
            KeybindingAction::BulkResync => {
                self.leader_status = Some("Action: bulk_resync".to_string());
            }
            KeybindingAction::FilterUnread => {
                self.leader_status = Some("Action: filter_unread".to_string());
            }
            KeybindingAction::MarkAllRead => {
                self.leader_status = Some("Action: mark_all_read".to_string());
            }
            KeybindingAction::ContextualAdd => {
                self.leader_status = Some("Action: contextual_add".to_string());
            }
        }
    }

    /// Dispatch a leader-menu action. Returns `true` when the action consumed
    /// the menu (closes the overlay); `false` when the menu should stay open
    /// (e.g. submenu navigation handled at the call site, not here).
    ///
    /// Concrete actions:
    /// - `Quit` — flips `running` to false and closes the menu.
    /// - `QuitAndLogout` — clears the auth file, then quits.
    /// - `Today` — surfaces a placeholder status (calendar view is not yet
    ///   implemented in the TUI; the action stays no-op-but-acknowledged so
    ///   the keybinding doesn't feel broken).
    /// - `Navigate { path }` — TUI doesn't speak web routes; logs a status
    ///   message so the binding still gives feedback.
    /// - Everything else — placeholder status message.
    pub fn run_leader_action(&mut self, action: &KeybindingAction) -> bool {
        match action {
            KeybindingAction::Quit => {
                self.close_leader_menu();
                self.quit();
            }
            KeybindingAction::QuitAndLogout => {
                self.close_leader_menu();
                self.quit_and_logout();
            }
            KeybindingAction::Navigate { path } => {
                self.leader_status = Some(format!("Web action: navigate {}", path));
                self.close_leader_menu();
            }
            KeybindingAction::Today => {
                // Calendar view isn't implemented in the TUI yet; record the
                // intent so the binding remains discoverable.
                self.leader_status = Some("Action: today (calendar view pending)".to_string());
                self.close_leader_menu();
            }
            KeybindingAction::Open { target } => {
                self.leader_status = Some(format!("Action: open {}", target));
                self.close_leader_menu();
            }
            KeybindingAction::BulkDelete => {
                self.leader_status = Some("Action: bulk_delete".to_string());
                self.close_leader_menu();
            }
            KeybindingAction::BulkSync => {
                self.leader_status = Some("Action: bulk_sync".to_string());
                self.close_leader_menu();
            }
            KeybindingAction::BulkResync => {
                self.leader_status = Some("Action: bulk_resync".to_string());
                self.close_leader_menu();
            }
            KeybindingAction::FilterUnread => {
                self.leader_status = Some("Action: filter_unread".to_string());
                self.close_leader_menu();
            }
            KeybindingAction::MarkAllRead => {
                self.leader_status = Some("Action: mark_all_read".to_string());
                self.close_leader_menu();
            }
            KeybindingAction::ContextualAdd => {
                self.leader_status = Some("Action: contextual_add".to_string());
                self.close_leader_menu();
            }
        }
        true
    }

    /// Re-fetch the dashboard counts. Currently has no runtime trigger — the
    /// chart range selector that called this on every key press was retired
    /// when the dashboard collapsed to counts-only in May 2026. Kept because
    /// it's exercised by tests and will be the obvious entry point if a manual
    /// refresh keybinding is wired up later.
    #[allow(dead_code)]
    pub fn reload_dashboard(&mut self) {
        match self.client.get_dashboard() {
            Ok(data) => {
                self.dashboard_state.data = data;
                self.dashboard_state.flash = None;
            }
            Err(e) => {
                log_error("reload_dashboard", &e);
                self.dashboard_state.flash = Some(format!("dashboard fetch failed: {}", e));
                // Keep the previous counts so the summary doesn't blank.
            }
        }
    }

    pub fn refresh_channels(&mut self) {
        match self.client.get_channels() {
            Ok(channels) => {
                self.channels_state.channels = channels
                    .iter()
                    .map(|c| ChannelRow {
                        id: c.id,
                        channel_url: c.channel_url.clone(),
                        star: c.star,
                        connected: c.connected,
                        last_synced_at: c.last_synced_at.clone(),
                    })
                    .collect();
                // Clamp the cursor to the new length (post-delete, etc.)
                let len = self.channels_state.channels.len();
                if self.channels_state.selected >= len.saturating_sub(1) {
                    self.channels_state.selected = len.saturating_sub(1);
                }
            }
            Err(e) => {
                // Don't blank the existing channels list — leave the previous
                // snapshot in place and surface the failure on the flash slot.
                log_error("refresh_channels", &e);
                self.channels_state.flash = Some(format!("channels fetch failed: {}", e));
            }
        }
    }

    pub fn open_channel_detail(&mut self, channel_id: u64) {
        if let Ok(channel) = self.client.get_channel(channel_id) {
            let videos = self
                .client
                .get_channel_videos(channel_id)
                .unwrap_or_default();
            self.channel_detail_state = Some(ChannelDetailState {
                channel: ChannelInfo {
                    id: channel.id,
                    tenant_id: channel.tenant_id,
                    channel_url: channel.channel_url,
                    star: channel.star,
                    connected: channel.connected,
                    last_synced_at: channel.last_synced_at,
                },
                videos: videos
                    .iter()
                    .map(|v| ChannelVideoRow {
                        id: v.id,
                        youtube_video_id: v.youtube_video_id.clone(),
                        star: v.star,
                        views: v.views,
                        likes: v.likes,
                        comments: v.comments,
                        last_synced_at: v.last_synced_at.clone(),
                    })
                    .collect(),
                video_selected: 0,
                video_scroll: 0,
                flash: None,
            });
            self.screen = Screen::ChannelDetail;
        }
    }

    pub fn refresh_channel_detail(&mut self, channel_id: u64) {
        if let Ok(channel) = self.client.get_channel(channel_id)
            && let Some(ref mut state) = self.channel_detail_state
        {
            state.channel = ChannelInfo {
                id: channel.id,
                tenant_id: channel.tenant_id,
                channel_url: channel.channel_url,
                star: channel.star,
                connected: channel.connected,
                last_synced_at: channel.last_synced_at,
            };
        }
    }

    pub fn open_video_detail(&mut self, video_id: u64) {
        if let Ok(video) = self.client.get_video(video_id) {
            let stats = self.client.get_video_stats(video_id).unwrap_or_default();
            use crate::ui::video_detail::{StatRow, VideoInfo};
            self.video_detail_state = Some(VideoDetailState {
                video: VideoInfo {
                    id: video.id,
                    youtube_video_id: video.youtube_video_id,
                    channel_id: video.channel_id,
                    channel_url: video.channel_url,
                    star: video.star,
                    views: video.views,
                    likes: video.likes,
                    comments: video.comments,
                    watch_time_minutes: video.watch_time_minutes,
                    last_synced_at: video.last_synced_at,
                },
                stats: stats
                    .iter()
                    .map(|s| StatRow {
                        date: s.date.clone(),
                        views: s.views,
                        likes: s.likes,
                        comments: s.comments,
                        watch_time_minutes: s.watch_time_minutes,
                    })
                    .collect(),
                stats_selected: 0,
                stats_scroll: 0,
            });
            self.screen = Screen::VideoDetail;
        }
    }

    pub fn perform_search(&mut self) {
        if self.search_state.query.is_empty() {
            self.search_state.results = None;
            return;
        }
        if let Ok(results) = self.client.search(&self.search_state.query) {
            use crate::ui::search::{SearchResultsData, SearchVideoHit};
            self.search_state.results = Some(SearchResultsData {
                videos: results
                    .videos
                    .iter()
                    .map(|hit| SearchVideoHit {
                        id: hit.record.id,
                        youtube_video_id: hit.record.youtube_video_id.clone(),
                        channel_id: hit.record.channel_id,
                        channel_url: hit.record.channel_url.clone(),
                        star: hit.record.star,
                        views: hit.record.views,
                    })
                    .collect(),
                video_total: results.video_total,
                took_ms: results.took_ms,
            });
        }
    }

    // --- Channel mutations (toggle star) ---
    //
    // `connected` is OAuth-managed; only the web UI may toggle it. pito and
    // the MCP surface treat connected as read-only.

    pub fn toggle_star_for_selected_channel(&mut self) {
        let visible = crate::ui::channels::visible_channels(&self.channels_state);
        let Some(row) = visible.get(self.channels_state.selected).cloned() else {
            return;
        };
        let id = row.id;
        let new_star = !row.star;
        match self.client.update_channel(id, Some(new_star)) {
            Ok(updated) => {
                // Refresh the local row from the server-returned Channel so
                // anything else the backend changed (e.g. updated_at) lands in
                // the UI immediately.
                if let Some(c) = self.channels_state.channels.iter_mut().find(|c| c.id == id) {
                    c.star = updated.star;
                }
            }
            Err(e) => {
                log_error("toggle_star_for_selected_channel", &e);
                self.channels_state.flash = Some(format!("star update failed: {}", e));
            }
        }
    }

    pub fn toggle_star_on_detail(&mut self) {
        let Some(ref state) = self.channel_detail_state else {
            return;
        };
        let id = state.channel.id;
        let new_star = !state.channel.star;
        match self.client.update_channel(id, Some(new_star)) {
            Ok(updated) => {
                if let Some(ref mut s) = self.channel_detail_state {
                    s.channel.star = updated.star;
                }
                if let Some(c) = self.channels_state.channels.iter_mut().find(|c| c.id == id) {
                    c.star = updated.star;
                }
            }
            Err(e) => {
                log_error("toggle_star_on_detail", &e);
                if let Some(ref mut s) = self.channel_detail_state {
                    s.flash = Some(format!("star update failed: {}", e));
                }
            }
        }
    }

    // --- Bulk action launchers ---

    /// Compute the set of channel ids targeted by a bulk action from the current
    /// channels list — selected ids if any, otherwise the highlighted row.
    pub fn channels_target_ids(&self) -> Vec<u64> {
        if !self.channels_state.selected_ids.is_empty() {
            return self.channels_state.selected_ids.clone();
        }
        let visible = crate::ui::channels::visible_channels(&self.channels_state);
        if let Some(row) = visible.get(self.channels_state.selected) {
            vec![row.id]
        } else {
            vec![]
        }
    }

    pub fn open_delete_confirmation(&mut self, ids: Vec<u64>) {
        if ids.is_empty() {
            return;
        }
        let Ok(_preview) = self.client.bulk_delete_channels(&ids, false) else {
            return;
        };
        let items: Vec<ConfirmationItem> = ids
            .iter()
            .map(|id| {
                let label = self
                    .channels_state
                    .channels
                    .iter()
                    .find(|c| c.id == *id)
                    .map(|c| c.channel_url.clone())
                    .or_else(|| {
                        self.channel_detail_state
                            .as_ref()
                            .filter(|s| s.channel.id == *id)
                            .map(|s| s.channel.channel_url.clone())
                    })
                    .unwrap_or_else(|| format!("#{}", id));
                ConfirmationItem {
                    id: *id,
                    label,
                    will_be_skipped: false,
                }
            })
            .collect();
        self.confirmation_state = Some(ConfirmationState {
            kind: ConfirmationKind::Delete,
            items,
            message: format!("{} channel(s) will be deleted", ids.len()),
        });
        self.confirmation_origin = Some(self.screen);
        self.overlay = Some(Overlay::Confirmation);
    }

    pub fn open_sync_confirmation(&mut self, ids: Vec<u64>) {
        if ids.is_empty() {
            return;
        }
        let Ok(preview) = self.client.bulk_sync_channels(&ids, false) else {
            return;
        };
        let skipped_set: std::collections::HashSet<u64> =
            preview.skipped.iter().map(|s| s.id).collect();
        let items: Vec<ConfirmationItem> = ids
            .iter()
            .map(|id| {
                let label = self
                    .channels_state
                    .channels
                    .iter()
                    .find(|c| c.id == *id)
                    .map(|c| c.channel_url.clone())
                    .or_else(|| {
                        self.channel_detail_state
                            .as_ref()
                            .filter(|s| s.channel.id == *id)
                            .map(|s| s.channel.channel_url.clone())
                    })
                    .unwrap_or_else(|| format!("#{}", id));
                ConfirmationItem {
                    id: *id,
                    label,
                    will_be_skipped: skipped_set.contains(id),
                }
            })
            .collect();
        self.confirmation_state = Some(ConfirmationState {
            kind: ConfirmationKind::Sync,
            items,
            message: preview.message,
        });
        self.confirmation_origin = Some(self.screen);
        self.overlay = Some(Overlay::Confirmation);
    }

    /// Apply the result of a confirmation. `outcome == Cancel` simply dismisses.
    /// `outcome == Proceed` sends the confirm=true call to the API.
    pub fn resolve_confirmation(&mut self, outcome: ConfirmationOutcome) {
        let Some(state) = self.confirmation_state.take() else {
            self.overlay = None;
            self.confirmation_origin = None;
            return;
        };
        let origin = self.confirmation_origin.take();
        self.overlay = None;

        if outcome == ConfirmationOutcome::Cancel {
            return;
        }

        let sync_target_ids = if state.kind == ConfirmationKind::Sync {
            Some(state.syncable_ids())
        } else {
            None
        };
        let response = match state.kind {
            ConfirmationKind::Delete => {
                let ids = state.all_ids();
                self.client.bulk_delete_channels(&ids, true)
            }
            ConfirmationKind::Sync => {
                let ids = state.syncable_ids();
                self.client.bulk_sync_channels(&ids, true)
            }
        };
        let resp = match response {
            Ok(r) => r,
            Err(e) => {
                self.channels_state.flash = Some(format!("Action failed: {}", e));
                return;
            }
        };

        // After successful enqueue, refresh local state.
        if resp.mode == ResponseMode::Enqueued {
            self.refresh_channels();
            // Clear selection (always-on; the rows just toggled-off).
            self.channels_state.selected_ids.clear();

            // If we came from the detail screen and the channel was deleted,
            // bounce back to the channels list.
            if let Some(Screen::ChannelDetail) = origin {
                if state.kind == ConfirmationKind::Delete {
                    self.channel_detail_state = None;
                    self.screen = Screen::Channels;
                } else if let Some(s) = self.channel_detail_state.as_ref() {
                    let id = s.channel.id;
                    self.refresh_channel_detail(id);
                }
            }

            // Kick off post-sync polling so the rows transition from
            // `syncing` → idle automatically without a manual refresh.
            if let Some(ids) = sync_target_ids
                && !ids.is_empty()
            {
                self.sync_polling = Some(SyncPolling::new(ids));
            }

            // Arm bulk-operation progress overlay if the backend returned an
            // operation_id. The overlay renders over the active screen and
            // dismisses on completion / Esc / deadline.
            if let Some(op_id) = resp.operation_id {
                let kind = match state.kind {
                    ConfirmationKind::Delete => "bulk_delete",
                    ConfirmationKind::Sync => "bulk_sync",
                };
                self.operation_progress = Some(OperationProgress::new(op_id, kind));
            }
        }
    }

    /// Driven from `tick`: poll the operation status endpoint when due, store
    /// the latest snapshot on the progress struct, and clear it once the
    /// operation reaches a terminal state. Returning `true` means the loop
    /// should request a short sleep so the progress bar refreshes promptly.
    fn drive_operation_progress(&mut self) -> bool {
        let Some(progress) = self.operation_progress.as_mut() else {
            return false;
        };
        if progress.dismissed {
            // User pressed Esc — drop the overlay; server keeps working.
            self.operation_progress = None;
            return false;
        }

        // Advance the dot-loader animation counter on every tick so pending
        // rows visually pulse while polling is active. Wrap on overflow — the
        // frame index is `tick % 4`.
        progress.tick = progress.tick.wrapping_add(1);

        let now = Instant::now();
        if now >= progress.deadline {
            // Hard timeout. Surface a hint so the user knows we stopped
            // watching — the operation may still complete server-side.
            self.channels_state.flash =
                Some("Bulk operation still running — closed progress view".to_string());
            self.operation_progress = None;
            return false;
        }

        if now >= progress.next_poll_at {
            progress.next_poll_at = now + OPERATION_POLL_INTERVAL;
            let op_id = progress.operation_id;
            match self.client.get_bulk_operation_status(op_id) {
                Ok(status) => {
                    let terminal = matches!(status.status.as_str(), "completed" | "failed");
                    let failed = status.status == "failed";
                    if let Some(p) = self.operation_progress.as_mut() {
                        p.last_status = Some(status);
                    }
                    if terminal {
                        // On completion, drop the overlay and refresh the
                        // visible state so the user sees the result.
                        if failed {
                            self.channels_state.flash =
                                Some("Bulk operation failed — see logs".to_string());
                        }
                        self.refresh_channels();
                        self.operation_progress = None;
                    }
                }
                Err(e) => {
                    // Don't tear down the overlay on a transient error — let
                    // the deadline handle the worst case. Record the error so
                    // the overlay can show a hint.
                    if let Some(p) = self.operation_progress.as_mut() {
                        p.last_error = Some(format!("{}", e));
                    }
                }
            }
        }
        true
    }

    /// Mark the active operation overlay as dismissed. The next tick removes
    /// it. Server-side work continues.
    pub fn dismiss_operation_progress(&mut self) {
        if let Some(p) = self.operation_progress.as_mut() {
            p.dismissed = true;
        }
    }

    /// Driven from the main loop on every iteration. Performs any periodic
    /// work (post-sync polling, bulk operation progress polling) and returns
    /// the maximum amount of time the loop should block waiting for the next
    /// key event.
    pub fn tick(&mut self) -> Duration {
        // Bulk operation progress is independent of sync polling — drive it
        // first so the overlay updates regardless of what else is in flight.
        let op_active = self.drive_operation_progress();

        let Some(ref mut polling) = self.sync_polling else {
            if op_active {
                // Tick at ~125ms so the per-row dot-loader animation feels
                // alive (4 frames over ~500ms). The status-fetch cadence is
                // independently throttled by `OPERATION_POLL_INTERVAL` inside
                // `drive_operation_progress`.
                return Duration::from_millis(125);
            }
            // No background work: wait the standard "responsive" interval —
            // crossterm wakes us as soon as a key arrives.
            return Duration::from_millis(250);
        };

        let now = Instant::now();

        // Advance the dot-animation counter every tick so the indicator
        // visually pulses while polling is active.
        polling.tick = polling.tick.wrapping_add(1);

        if now >= polling.next_poll_at {
            polling.next_poll_at = now + SYNC_POLL_INTERVAL;

            // Re-fetch the channels list and the detail screen so the affected
            // rows reflect current server state.
            let affected = polling.affected_ids.clone();
            self.refresh_channels();
            if let Some(s) = self.channel_detail_state.as_ref() {
                let id = s.channel.id;
                if affected.contains(&id) {
                    self.refresh_channel_detail(id);
                }
            }

            // Stop polling once the first refresh lands. Path A2 retract:
            // Rails JSON no longer carries a server-side `syncing` boolean,
            // so we can't watch it flip back. The bulk-operation progress
            // overlay (`OperationProgress`) is the durable terminal-state
            // signal; the sync_polling window's only remaining job is to
            // animate the row indicator on the affected rows during the
            // first refetch after confirm. Single-tick clear matches the
            // near-instant completion of `ChannelSync` in production.
            let now = Instant::now();
            if now >= self.sync_polling.as_ref().unwrap().deadline {
                self.sync_polling = None;
                return Duration::from_millis(250);
            }
            self.sync_polling = None;
            return Duration::from_millis(250);
        }

        // While polling, prefer a short sleep so the dot animation feels
        // alive and the next refetch fires on time.
        SYNC_POLL_INTERVAL / 4
    }

    /// Set of ids that should render with the animated `syncing.../..` cell
    /// because we are actively polling them.
    pub fn syncing_animated_ids(&self) -> &[u64] {
        match &self.sync_polling {
            Some(p) => &p.affected_ids,
            None => &[],
        }
    }

    /// Tick counter for the `syncing` dot animation. 0 when no polling is in
    /// flight.
    pub fn sync_anim_tick(&self) -> u8 {
        self.sync_polling.as_ref().map(|p| p.tick).unwrap_or(0)
    }

    /// Clear any flash messages on the channels screen and detail screen.
    pub fn clear_flash(&mut self) {
        self.channels_state.flash = None;
        self.dashboard_state.flash = None;
        if let Some(ref mut s) = self.channel_detail_state {
            s.flash = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn proceed_sync(app: &mut App, ids: Vec<u64>) {
        app.open_sync_confirmation(ids);
        app.resolve_confirmation(ConfirmationOutcome::Proceed);
    }

    #[test]
    fn sync_confirm_arms_polling_for_syncable_ids() {
        let mut app = App::with_client(Box::new(MockClient::new()));
        // Channel 1 is idle in the seed, so it is "syncable" — this should
        // arm post-sync polling for that id.
        proceed_sync(&mut app, vec![1]);

        let polling = app
            .sync_polling
            .as_ref()
            .expect("polling should be armed after a sync confirm");
        assert_eq!(polling.affected_ids, vec![1]);
        assert!(polling.deadline > Instant::now());
        assert_eq!(app.syncing_animated_ids(), &[1]);
    }

    #[test]
    fn sync_confirm_does_not_arm_polling_when_target_already_syncing() {
        let mut app = App::with_client(Box::new(MockClient::new()));
        // Channel 2 is seeded as syncing — preview marks it skipped, so
        // resolve_confirmation has no syncable_ids and polling stays off.
        proceed_sync(&mut app, vec![2]);
        assert!(app.sync_polling.is_none());
        assert!(app.syncing_animated_ids().is_empty());
    }

    #[test]
    fn tick_clears_polling_when_no_target_is_syncing() {
        let mut app = App::with_client(Box::new(MockClient::new()));
        proceed_sync(&mut app, vec![1]);
        assert!(app.sync_polling.is_some());

        // Mock flips the channel's syncing flag back to false on confirm,
        // mirroring near-instant Rails job completion. The first tick
        // refetches and stops polling.
        let _ = app.tick();
        assert!(
            app.sync_polling.is_none(),
            "polling should clear once nothing remains syncing"
        );
    }

    #[test]
    fn tick_returns_long_idle_timeout_when_no_polling() {
        let mut app = App::with_client(Box::new(MockClient::new()));
        let timeout = app.tick();
        assert!(timeout >= Duration::from_millis(100));
    }

    #[test]
    fn delete_confirm_does_not_arm_sync_polling() {
        let mut app = App::with_client(Box::new(MockClient::new()));
        app.open_delete_confirmation(vec![1]);
        app.resolve_confirmation(ConfirmationOutcome::Proceed);
        assert!(app.sync_polling.is_none());
    }

    #[test]
    fn delete_confirm_removes_channel_from_visible_list() {
        // Regression: confirming a delete must drop the channel from the
        // displayed list. Previously the app spun up a fresh MockClient on
        // every call, so the post-confirm refresh re-seeded the deleted row.
        let mut app = App::with_client(Box::new(MockClient::new()));
        let before_len = app.channels_state.channels.len();
        assert!(app.channels_state.channels.iter().any(|c| c.id == 1));

        app.open_delete_confirmation(vec![1]);
        app.resolve_confirmation(ConfirmationOutcome::Proceed);

        assert_eq!(app.channels_state.channels.len(), before_len - 1);
        assert!(
            !app.channels_state.channels.iter().any(|c| c.id == 1),
            "deleted channel must not be in the refreshed list"
        );
    }

    #[test]
    fn delete_confirm_clears_bulk_selection() {
        let mut app = App::with_client(Box::new(MockClient::new()));
        app.channels_state.selected_ids = vec![1, 3];

        app.open_delete_confirmation(vec![1, 3]);
        app.resolve_confirmation(ConfirmationOutcome::Proceed);

        assert!(app.channels_state.selected_ids.is_empty());
        for id in [1u64, 3] {
            assert!(
                !app.channels_state.channels.iter().any(|c| c.id == id),
                "channel {} should be gone after bulk delete",
                id
            );
        }
    }

    #[test]
    fn delete_confirm_from_detail_returns_to_channels_list() {
        let mut app = App::with_client(Box::new(MockClient::new()));
        app.open_channel_detail(1);
        assert_eq!(app.screen, Screen::ChannelDetail);

        // Single-row delete from the detail screen, same path as the channels
        // list delete.
        app.open_delete_confirmation(vec![1]);
        app.resolve_confirmation(ConfirmationOutcome::Proceed);

        assert_eq!(app.screen, Screen::Channels);
        assert!(app.channel_detail_state.is_none());
        assert!(!app.channels_state.channels.iter().any(|c| c.id == 1));
    }

    #[test]
    fn bulk_delete_confirm_arms_operation_progress_then_clears_on_completed() {
        // Confirming a bulk delete should attach an OperationProgress so the
        // overlay can render. Repeated tick() calls walk the mock state
        // machine pending → running → completed; after completion the
        // progress is cleared and the affected channel is gone.
        let mut app = App::with_client(Box::new(MockClient::new()));
        assert!(app.channels_state.channels.iter().any(|c| c.id == 1));

        app.open_delete_confirmation(vec![1]);
        app.resolve_confirmation(ConfirmationOutcome::Proceed);

        // Progress overlay should be armed with bulk_delete kind.
        let progress = app
            .operation_progress
            .as_ref()
            .expect("operation_progress should be armed after confirm");
        assert_eq!(progress.kind, "bulk_delete");
        assert!(progress.last_status.is_none(), "no poll yet before tick");

        // Tick a few times to drive the mock state machine.
        // The mock requires force-firing past the next_poll_at timestamp; the
        // first tick lands on `pending`, the second on `running`, the third on
        // `completed` — but mock pollings happen back-to-back inside each tick
        // since next_poll_at is initialized to "now". We loosen the check by
        // just hammering tick a few times until progress clears.
        for _ in 0..6 {
            // Force-advance: clear the per-poll throttle so each tick actually
            // hits the mock.
            if let Some(p) = app.operation_progress.as_mut() {
                p.next_poll_at = std::time::Instant::now();
            }
            let _ = app.tick();
            if app.operation_progress.is_none() {
                break;
            }
        }

        assert!(
            app.operation_progress.is_none(),
            "operation_progress should clear once status hits completed"
        );
        assert!(
            !app.channels_state.channels.iter().any(|c| c.id == 1),
            "deleted channel must not be in the refreshed list"
        );
    }

    #[test]
    fn dismiss_operation_progress_marks_dismissed() {
        let mut app = App::with_client(Box::new(MockClient::new()));
        app.open_delete_confirmation(vec![1]);
        app.resolve_confirmation(ConfirmationOutcome::Proceed);
        assert!(app.operation_progress.is_some());

        app.dismiss_operation_progress();
        // Next tick should drop the overlay even though the operation hasn't
        // completed server-side yet.
        let _ = app.tick();
        assert!(app.operation_progress.is_none());
    }

    #[test]
    fn delete_cancel_keeps_channel_in_list() {
        let mut app = App::with_client(Box::new(MockClient::new()));
        let before_len = app.channels_state.channels.len();

        app.open_delete_confirmation(vec![1]);
        app.resolve_confirmation(ConfirmationOutcome::Cancel);

        assert_eq!(app.channels_state.channels.len(), before_len);
        assert!(app.channels_state.channels.iter().any(|c| c.id == 1));
    }

    // --- Star toggle: local state must reflect the server-returned channel ---

    #[test]
    fn toggle_star_for_selected_channel_flips_local_state_on_success() {
        // Reproduces the bug surface: pressing `s` should flip the row's star
        // immediately. The local row mirrors the Channel returned by the
        // backend, so the column rendering on the next frame is correct.
        let mut app = App::with_client(Box::new(MockClient::new()));
        app.screen = Screen::Channels;
        app.channels_state.selected = 0;

        let visible = crate::ui::channels::visible_channels(&app.channels_state);
        let row = (*visible.first().expect("at least one channel")).clone();
        let id = row.id;
        let before_star = row.star;

        app.toggle_star_for_selected_channel();

        let after = app
            .channels_state
            .channels
            .iter()
            .find(|c| c.id == id)
            .expect("channel must still exist after toggle");
        assert_eq!(
            after.star, !before_star,
            "local row's star must flip after a successful update"
        );
        assert!(
            app.channels_state.flash.is_none(),
            "no flash on success path"
        );
    }

    #[test]
    fn toggle_star_on_detail_propagates_to_list_and_detail() {
        // The detail screen and the channels list share state; toggling on
        // detail must update both so backing out to the list shows the new
        // value without a refetch.
        let mut app = App::with_client(Box::new(MockClient::new()));
        app.open_channel_detail(1);
        let before = app
            .channel_detail_state
            .as_ref()
            .expect("detail open")
            .channel
            .star;

        app.toggle_star_on_detail();

        let after_detail = app
            .channel_detail_state
            .as_ref()
            .expect("detail still open")
            .channel
            .star;
        let after_list = app
            .channels_state
            .channels
            .iter()
            .find(|c| c.id == 1)
            .expect("channel 1 in list")
            .star;
        assert_eq!(after_detail, !before);
        assert_eq!(after_list, !before);
    }

    #[test]
    fn toggle_star_on_failure_sets_flash_and_keeps_local_state() {
        // When the backend rejects the PATCH (production bug: silent no-op
        // because `.is_ok()` swallowed the error), the user must see a flash
        // and the local row must NOT flip — otherwise the UI lies.
        struct UpdateFailingClient {
            inner: MockClient,
        }
        impl PitoClient for UpdateFailingClient {
            fn get_dashboard(&self) -> Result<DashboardData> {
                self.inner.get_dashboard()
            }
            fn get_channels(&self) -> Result<Vec<Channel>> {
                self.inner.get_channels()
            }
            fn get_channel(&self, id: u64) -> Result<Channel> {
                self.inner.get_channel(id)
            }
            fn get_channel_videos(&self, id: u64) -> Result<Vec<Video>> {
                self.inner.get_channel_videos(id)
            }
            fn get_videos(&self) -> Result<Vec<Video>> {
                self.inner.get_videos()
            }
            fn get_video(&self, id: u64) -> Result<Video> {
                self.inner.get_video(id)
            }
            fn get_video_stats(&self, id: u64) -> Result<Vec<VideoStat>> {
                self.inner.get_video_stats(id)
            }
            fn search(&self, q: &str) -> Result<SearchResults> {
                self.inner.search(q)
            }
            fn get_saved_views(&self) -> Result<Vec<SavedView>> {
                self.inner.get_saved_views()
            }
            fn get_settings(&self) -> Result<AppSettings> {
                self.inner.get_settings()
            }
            fn bulk_delete_channels(
                &self,
                ids: &[u64],
                confirm: bool,
            ) -> Result<BulkOperationResponse> {
                self.inner.bulk_delete_channels(ids, confirm)
            }
            fn bulk_sync_channels(
                &self,
                ids: &[u64],
                confirm: bool,
            ) -> Result<BulkOperationResponse> {
                self.inner.bulk_sync_channels(ids, confirm)
            }
            fn create_channel(&self, url: &str) -> Result<Channel> {
                self.inner.create_channel(url)
            }
            fn update_channel(&self, _id: u64, _star: Option<bool>) -> Result<Channel> {
                Err(anyhow!("simulated 422 from Rails"))
            }
            fn get_bulk_operation_status(&self, id: u64) -> Result<BulkOperationStatus> {
                self.inner.get_bulk_operation_status(id)
            }
        }

        let mut app = App::with_client(Box::new(UpdateFailingClient {
            inner: MockClient::new(),
        }));
        app.screen = Screen::Channels;
        app.channels_state.selected = 0;
        let visible = crate::ui::channels::visible_channels(&app.channels_state);
        let row = (*visible.first().expect("at least one channel")).clone();
        let id = row.id;
        let before_star = row.star;

        app.toggle_star_for_selected_channel();

        let after = app
            .channels_state
            .channels
            .iter()
            .find(|c| c.id == id)
            .expect("channel still in list");
        assert_eq!(
            after.star, before_star,
            "local row must NOT flip when the server rejects the update"
        );
        let flash = app
            .channels_state
            .flash
            .as_deref()
            .expect("flash must be set on update failure");
        assert!(flash.contains("star update failed"));
    }

    // --- Connected toggle dropped: pressing `c` must be a silent no-op ---

    #[test]
    fn c_is_noop_on_channels_list() {
        // Per Fix 2 (May 2026): connected is OAuth-managed; only the web UI
        // can toggle it. Pressing `c` on the list must do nothing — the
        // connected column stays as it was.
        use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
        let mut app = App::with_client(Box::new(MockClient::new()));
        app.screen = Screen::Channels;
        app.channels_state.selected = 0;
        let visible = crate::ui::channels::visible_channels(&app.channels_state);
        let row = (*visible.first().expect("at least one channel")).clone();
        let id = row.id;
        let before_connected = row.connected;

        crate::keys::handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE),
        );

        let after = app
            .channels_state
            .channels
            .iter()
            .find(|c| c.id == id)
            .expect("channel still in list");
        assert_eq!(
            after.connected, before_connected,
            "`c` on channels list must not toggle connected"
        );
    }

    #[test]
    fn c_is_noop_on_channel_detail() {
        use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
        let mut app = App::with_client(Box::new(MockClient::new()));
        app.open_channel_detail(1);
        let before_connected = app
            .channel_detail_state
            .as_ref()
            .expect("detail open")
            .channel
            .connected;

        crate::keys::handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE),
        );

        let after_detail = app
            .channel_detail_state
            .as_ref()
            .expect("detail still open")
            .channel
            .connected;
        assert_eq!(
            after_detail, before_connected,
            "`c` on channel detail must not toggle connected"
        );
    }

    // --- Resilience: per-endpoint failures must not blank other state ---

    use crate::api::client::MockClient;
    use crate::api::models::{
        AppSettings, BulkOperationResponse, BulkOperationStatus, Channel, DashboardData, SavedView,
        SearchResults, Video, VideoStat,
    };
    use anyhow::{Result, anyhow};
    use std::cell::Cell;

    /// What endpoint a `FailingClient` should fail. The remaining endpoints
    /// proxy through to a regular `MockClient`.
    #[derive(Debug, Clone, Copy)]
    enum FailEndpoint {
        Settings,
        Channels,
        Dashboard,
    }

    /// Mock client that delegates to `MockClient` but returns an error on a
    /// single configured endpoint. Used to verify that pito surfaces the
    /// failure on the right flash slot without wiping unrelated state.
    struct FailingClient {
        inner: MockClient,
        fail: FailEndpoint,
    }

    impl FailingClient {
        fn new(fail: FailEndpoint) -> Self {
            Self {
                inner: MockClient::new(),
                fail,
            }
        }
    }

    impl PitoClient for FailingClient {
        fn get_dashboard(&self) -> Result<DashboardData> {
            if matches!(self.fail, FailEndpoint::Dashboard) {
                return Err(anyhow!("simulated 500 on dashboard"));
            }
            self.inner.get_dashboard()
        }
        fn get_channels(&self) -> Result<Vec<Channel>> {
            if matches!(self.fail, FailEndpoint::Channels) {
                return Err(anyhow!("simulated 500 on channels"));
            }
            self.inner.get_channels()
        }
        fn get_channel(&self, id: u64) -> Result<Channel> {
            self.inner.get_channel(id)
        }
        fn get_channel_videos(&self, id: u64) -> Result<Vec<Video>> {
            self.inner.get_channel_videos(id)
        }
        fn get_videos(&self) -> Result<Vec<Video>> {
            self.inner.get_videos()
        }
        fn get_video(&self, id: u64) -> Result<Video> {
            self.inner.get_video(id)
        }
        fn get_video_stats(&self, id: u64) -> Result<Vec<VideoStat>> {
            self.inner.get_video_stats(id)
        }
        fn search(&self, q: &str) -> Result<SearchResults> {
            self.inner.search(q)
        }
        fn get_saved_views(&self) -> Result<Vec<SavedView>> {
            self.inner.get_saved_views()
        }
        fn get_settings(&self) -> Result<AppSettings> {
            if matches!(self.fail, FailEndpoint::Settings) {
                return Err(anyhow!("simulated 406 on settings"));
            }
            self.inner.get_settings()
        }
        fn bulk_delete_channels(
            &self,
            ids: &[u64],
            confirm: bool,
        ) -> Result<BulkOperationResponse> {
            self.inner.bulk_delete_channels(ids, confirm)
        }
        fn bulk_sync_channels(&self, ids: &[u64], confirm: bool) -> Result<BulkOperationResponse> {
            self.inner.bulk_sync_channels(ids, confirm)
        }
        fn create_channel(&self, url: &str) -> Result<Channel> {
            self.inner.create_channel(url)
        }
        fn update_channel(&self, id: u64, star: Option<bool>) -> Result<Channel> {
            self.inner.update_channel(id, star)
        }
        fn get_bulk_operation_status(&self, id: u64) -> Result<BulkOperationStatus> {
            self.inner.get_bulk_operation_status(id)
        }
    }

    #[test]
    fn settings_failure_does_not_blank_channels_or_dashboard() {
        // Reproduces the production bug: /settings.json returns 406 because the
        // Rails controller has no JSON variant. Channels (live) must still
        // populate, dashboard data must still populate, settings falls back to
        // the hard-coded defaults.
        let app = App::with_client(Box::new(FailingClient::new(FailEndpoint::Settings)));

        // Channels still populated from the mock seed.
        assert!(
            !app.channels_state.channels.is_empty(),
            "channels must populate even when settings fails"
        );
        // No flash on channels — settings failure is meta and shouldn't bleed
        // into the channels screen.
        assert!(
            app.channels_state.flash.is_none(),
            "settings failure must not add a flash to channels"
        );
        // Dashboard data still populated.
        assert!(
            app.dashboard_state.data.video_count > 0,
            "dashboard must populate even when settings fails"
        );
        assert!(app.dashboard_state.flash.is_none());

        // Settings fell back to the hard-coded defaults.
        let defaults = default_app_settings();
        assert_eq!(app.settings_state.max_panes, defaults.max_panes);
        assert_eq!(
            app.settings_state.pane_title_length,
            defaults.pane_title_length
        );
        assert_eq!(app.settings_state.theme, defaults.theme);
    }

    #[test]
    fn channels_failure_surfaces_flash_and_keeps_other_state() {
        // When channels fetch fails the user must see a flash on the channels
        // screen but the dashboard, videos, and settings should still load.
        let app = App::with_client(Box::new(FailingClient::new(FailEndpoint::Channels)));

        assert!(
            app.channels_state.channels.is_empty(),
            "no channels to show when fetch failed"
        );
        let flash = app
            .channels_state
            .flash
            .as_deref()
            .expect("flash must be set when channels fetch fails");
        assert!(
            flash.contains("channels fetch failed"),
            "flash should describe the failure, got: {}",
            flash
        );
        // Other state still loads from the underlying mock.
        assert!(app.dashboard_state.data.video_count > 0);
        assert_eq!(app.settings_state.max_panes, 4);
    }

    #[test]
    fn dashboard_failure_surfaces_flash_and_keeps_other_state() {
        let app = App::with_client(Box::new(FailingClient::new(FailEndpoint::Dashboard)));

        assert_eq!(app.dashboard_state.data.video_count, 0);
        assert_eq!(app.dashboard_state.data.channel_count, 0);
        let flash = app
            .dashboard_state
            .flash
            .as_deref()
            .expect("dashboard flash must be set on failure");
        assert!(flash.contains("dashboard fetch failed"));
        // Channels and settings still load.
        assert!(!app.channels_state.channels.is_empty());
        assert!(app.channels_state.flash.is_none());
    }

    /// Mock that fails the second call to `get_channels`. Lets us verify
    /// `refresh_channels` keeps the previously-loaded list rather than blanking
    /// it on a transient failure.
    struct FailOnSecondChannelsClient {
        inner: MockClient,
        calls: Cell<u32>,
    }

    impl FailOnSecondChannelsClient {
        fn new() -> Self {
            Self {
                inner: MockClient::new(),
                calls: Cell::new(0),
            }
        }
    }

    impl PitoClient for FailOnSecondChannelsClient {
        fn get_dashboard(&self) -> Result<DashboardData> {
            self.inner.get_dashboard()
        }
        fn get_channels(&self) -> Result<Vec<Channel>> {
            let n = self.calls.get() + 1;
            self.calls.set(n);
            if n == 2 {
                return Err(anyhow!("simulated transient 500 on channels"));
            }
            self.inner.get_channels()
        }
        fn get_channel(&self, id: u64) -> Result<Channel> {
            self.inner.get_channel(id)
        }
        fn get_channel_videos(&self, id: u64) -> Result<Vec<Video>> {
            self.inner.get_channel_videos(id)
        }
        fn get_videos(&self) -> Result<Vec<Video>> {
            self.inner.get_videos()
        }
        fn get_video(&self, id: u64) -> Result<Video> {
            self.inner.get_video(id)
        }
        fn get_video_stats(&self, id: u64) -> Result<Vec<VideoStat>> {
            self.inner.get_video_stats(id)
        }
        fn search(&self, q: &str) -> Result<SearchResults> {
            self.inner.search(q)
        }
        fn get_saved_views(&self) -> Result<Vec<SavedView>> {
            self.inner.get_saved_views()
        }
        fn get_settings(&self) -> Result<AppSettings> {
            self.inner.get_settings()
        }
        fn bulk_delete_channels(
            &self,
            ids: &[u64],
            confirm: bool,
        ) -> Result<BulkOperationResponse> {
            self.inner.bulk_delete_channels(ids, confirm)
        }
        fn bulk_sync_channels(&self, ids: &[u64], confirm: bool) -> Result<BulkOperationResponse> {
            self.inner.bulk_sync_channels(ids, confirm)
        }
        fn create_channel(&self, url: &str) -> Result<Channel> {
            self.inner.create_channel(url)
        }
        fn update_channel(&self, id: u64, star: Option<bool>) -> Result<Channel> {
            self.inner.update_channel(id, star)
        }
        fn get_bulk_operation_status(&self, id: u64) -> Result<BulkOperationStatus> {
            self.inner.get_bulk_operation_status(id)
        }
    }

    #[test]
    fn refresh_channels_failure_keeps_previous_snapshot() {
        // Startup loads channels (call 1, succeeds). The subsequent
        // refresh_channels (call 2) fails — the previously-loaded list must
        // remain visible and a flash must be set.
        let mut app = App::with_client(Box::new(FailOnSecondChannelsClient::new()));
        let before = app.channels_state.channels.clone();
        assert!(!before.is_empty());

        app.refresh_channels();

        assert_eq!(
            app.channels_state.channels.len(),
            before.len(),
            "refresh failure must not blank the existing list"
        );
        let flash = app
            .channels_state
            .flash
            .as_deref()
            .expect("flash must be set on refresh failure");
        assert!(flash.contains("channels fetch failed"));
    }

    #[test]
    fn reload_dashboard_failure_keeps_previous_data() {
        // Same shape as refresh_channels but for the dashboard.
        struct FailDashboardOnReload {
            inner: MockClient,
            calls: Cell<u32>,
        }
        impl PitoClient for FailDashboardOnReload {
            fn get_dashboard(&self) -> Result<DashboardData> {
                let n = self.calls.get() + 1;
                self.calls.set(n);
                if n == 2 {
                    return Err(anyhow!("simulated 500 on dashboard reload"));
                }
                self.inner.get_dashboard()
            }
            fn get_channels(&self) -> Result<Vec<Channel>> {
                self.inner.get_channels()
            }
            fn get_channel(&self, id: u64) -> Result<Channel> {
                self.inner.get_channel(id)
            }
            fn get_channel_videos(&self, id: u64) -> Result<Vec<Video>> {
                self.inner.get_channel_videos(id)
            }
            fn get_videos(&self) -> Result<Vec<Video>> {
                self.inner.get_videos()
            }
            fn get_video(&self, id: u64) -> Result<Video> {
                self.inner.get_video(id)
            }
            fn get_video_stats(&self, id: u64) -> Result<Vec<VideoStat>> {
                self.inner.get_video_stats(id)
            }
            fn search(&self, q: &str) -> Result<SearchResults> {
                self.inner.search(q)
            }
            fn get_saved_views(&self) -> Result<Vec<SavedView>> {
                self.inner.get_saved_views()
            }
            fn get_settings(&self) -> Result<AppSettings> {
                self.inner.get_settings()
            }
            fn bulk_delete_channels(
                &self,
                ids: &[u64],
                confirm: bool,
            ) -> Result<BulkOperationResponse> {
                self.inner.bulk_delete_channels(ids, confirm)
            }
            fn bulk_sync_channels(
                &self,
                ids: &[u64],
                confirm: bool,
            ) -> Result<BulkOperationResponse> {
                self.inner.bulk_sync_channels(ids, confirm)
            }
            fn create_channel(&self, url: &str) -> Result<Channel> {
                self.inner.create_channel(url)
            }
            fn update_channel(&self, id: u64, star: Option<bool>) -> Result<Channel> {
                self.inner.update_channel(id, star)
            }
            fn get_bulk_operation_status(&self, id: u64) -> Result<BulkOperationStatus> {
                self.inner.get_bulk_operation_status(id)
            }
        }

        let mut app = App::with_client(Box::new(FailDashboardOnReload {
            inner: MockClient::new(),
            calls: Cell::new(0),
        }));
        let before = app.dashboard_state.data.video_count;
        assert!(before > 0);

        app.reload_dashboard();

        assert_eq!(
            app.dashboard_state.data.video_count, before,
            "reload failure must not zero out the previous dashboard data"
        );
        assert!(app.dashboard_state.flash.is_some());
    }

    #[test]
    fn clear_flash_clears_dashboard_flash_too() {
        let mut app = App::with_client(Box::new(FailingClient::new(FailEndpoint::Dashboard)));
        assert!(app.dashboard_state.flash.is_some());

        app.clear_flash();

        assert!(app.channels_state.flash.is_none());
        assert!(app.dashboard_state.flash.is_none());
    }

    #[test]
    fn log_error_writes_line_to_disk() {
        // Point the logger at a temp dir and verify the expected line shape
        // ends up in error.log. Using a process-scoped XDG_CACHE_HOME write is
        // safe in test threads because the dir is unique per test run.
        let tmp = std::env::temp_dir().join(format!(
            "pito-test-{}-{}",
            std::process::id(),
            chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        // Safety: env vars are process-global. We restore the previous value
        // after the call to avoid leaking into other tests that read XDG_*.
        let prev = std::env::var("XDG_CACHE_HOME").ok();
        // SAFETY: setting XDG_CACHE_HOME from a single-threaded test is safe;
        // cargo test parallelism could race, so the test pins a per-pid dir
        // and restores the previous value before returning.
        unsafe {
            std::env::set_var("XDG_CACHE_HOME", &tmp);
        }

        log_error("test scope", &"boom");

        let log_path = tmp.join("pito").join("error.log");
        let contents = std::fs::read_to_string(&log_path).expect("error.log should exist");
        assert!(
            contents.contains("test scope"),
            "log line should include the scope, got: {}",
            contents
        );
        assert!(
            contents.contains("boom"),
            "log line should include the error, got: {}",
            contents
        );

        // Cleanup: restore the env and remove the temp dir.
        unsafe {
            match prev {
                Some(v) => std::env::set_var("XDG_CACHE_HOME", v),
                None => std::env::remove_var("XDG_CACHE_HOME"),
            }
        }
        let _ = std::fs::remove_dir_all(&tmp);
    }

    // --- Footage detail screen wiring --------------------------------------

    /// Build an `App` with the thumbnails fetcher pinned to an
    /// almost-certainly-closed localhost port. Lets unit tests assert the
    /// "manifest fetch fails gracefully" path without hitting the network or
    /// having to spin up a wiremock server (which lives in the integration
    /// tests). The exact port is arbitrary; any TCP connection refused
    /// surfaces as `Err` from `fetch_manifest`.
    fn app_with_unreachable_thumbnails() -> App {
        let dir = std::env::temp_dir().join(format!(
            "pito-thumbs-{}-{}",
            std::process::id(),
            chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        let cache = crate::api::thumbnails::Cache::with_root(dir, 1_000_000);
        App::with_client_and_thumbnails_config(
            Box::new(MockClient::new()),
            "http://127.0.0.1:1",
            cache,
        )
    }

    #[test]
    fn open_footage_detail_seeds_state_and_navigates() {
        let mut app = app_with_unreachable_thumbnails();
        assert!(app.footage_detail_state.is_none());
        app.open_footage_detail(42, "fixture.mp4");
        assert_eq!(app.screen, Screen::FootageDetail);
        let s = app.footage_detail_state.as_ref().expect("state seeded");
        assert_eq!(s.footage_id, 42);
        assert_eq!(s.label, "fixture.mp4");
        // Manifest fetch fails (unreachable URL) → manifest stays None and
        // the screen's flash slot records the failure for the user.
        assert!(s.manifest.is_none());
        let flash = s.flash.as_deref().expect("flash records fetch failure");
        assert!(
            flash.contains("manifest"),
            "flash should mention the manifest, got: {}",
            flash
        );
        // Rects are stamped by the renderer; not present until the first
        // draw lands.
        assert!(app.footage_detail_rects.is_none());
        // No image protocol either — there are no bytes to decode.
        assert!(app.footage_detail_preview.is_none());
    }

    #[test]
    fn apply_footage_manifest_snaps_active_to_median() {
        use crate::api::thumbnails::Manifest;
        let mut app = app_with_unreachable_thumbnails();
        app.open_footage_detail(42, "fixture.mp4");
        app.apply_footage_manifest(Manifest {
            duration_seconds: 240.0,
            timestamps: vec![0, 60, 120, 180, 240],
        });
        let s = app.footage_detail_state.as_ref().unwrap();
        // Median index = 5/2 = 2 → ts=120.
        assert_eq!(s.active_timestamp_seconds, 120);
        assert_eq!(s.manifest.as_ref().unwrap().timestamps.len(), 5);
    }

    #[test]
    fn apply_footage_manifest_no_op_when_screen_closed() {
        use crate::api::thumbnails::Manifest;
        let mut app = app_with_unreachable_thumbnails();
        // Never opened; apply must not panic.
        app.apply_footage_manifest(Manifest {
            duration_seconds: 240.0,
            timestamps: vec![0, 60, 120],
        });
        assert!(app.footage_detail_state.is_none());
    }

    #[test]
    fn set_terminal_capability_persists_for_render_path() {
        let mut app = App::with_client(Box::new(MockClient::new()));
        // Default after construction is TextOnly (so tests don't probe stdio).
        assert_eq!(app.terminal_capability, TerminalCapability::TextOnly);
        // TextOnly default produces no picker — image rendering is skipped.
        assert!(app.thumbnails_picker.is_none());
        app.set_terminal_capability(TerminalCapability::Halfblocks);
        assert_eq!(app.terminal_capability, TerminalCapability::Halfblocks);
        // Any non-TextOnly capability arms a picker so the live image render
        // path has something to call `new_resize_protocol` on.
        assert!(app.thumbnails_picker.is_some());
    }

    #[test]
    fn set_terminal_capability_text_only_drops_picker() {
        let mut app = App::with_client(Box::new(MockClient::new()));
        app.set_terminal_capability(TerminalCapability::Kitty);
        assert!(app.thumbnails_picker.is_some());
        // Switching back to TextOnly must drop the picker — the live render
        // path early-outs whenever the picker is `None`.
        app.set_terminal_capability(TerminalCapability::TextOnly);
        assert!(app.thumbnails_picker.is_none());
    }

    #[test]
    fn footage_detail_q_returns_to_dashboard_and_clears_state() {
        // The `q` keybinding on the FootageDetail screen must hand the user
        // back to the dashboard AND drop the footage_detail_state so a
        // subsequent navigation starts clean.
        use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
        let mut app = app_with_unreachable_thumbnails();
        app.open_footage_detail(42, "fixture.mp4");
        assert_eq!(app.screen, Screen::FootageDetail);

        crate::keys::handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('q'), KeyModifiers::NONE),
        );

        assert_eq!(app.screen, Screen::Dashboard);
        assert!(app.footage_detail_state.is_none());
        assert!(app.footage_detail_rects.is_none());
        assert!(app.footage_detail_preview.is_none());
    }

    #[test]
    fn footage_detail_keyboard_step_walks_active_timestamp() {
        use crate::api::thumbnails::Manifest;
        use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
        let mut app = app_with_unreachable_thumbnails();
        app.open_footage_detail(42, "fixture.mp4");
        app.apply_footage_manifest(Manifest {
            duration_seconds: 240.0,
            timestamps: vec![0, 60, 120, 180, 240],
        });
        // Median = 120.
        fn active(app: &App) -> u64 {
            app.footage_detail_state
                .as_ref()
                .unwrap()
                .active_timestamp_seconds
        }
        assert_eq!(active(&app), 120);

        // `l` steps forward.
        crate::keys::handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('l'), KeyModifiers::NONE),
        );
        assert_eq!(active(&app), 180);
        // `→` steps forward too.
        crate::keys::handle_key(&mut app, KeyEvent::new(KeyCode::Right, KeyModifiers::NONE));
        assert_eq!(active(&app), 240);
        // `h` steps backward.
        crate::keys::handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('h'), KeyModifiers::NONE),
        );
        assert_eq!(active(&app), 180);
        // `g` jumps to start.
        crate::keys::handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('g'), KeyModifiers::NONE),
        );
        assert_eq!(active(&app), 0);
        // `G` jumps to end.
        crate::keys::handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('G'), KeyModifiers::NONE),
        );
        assert_eq!(active(&app), 240);
        // `H` jumps 10 cells back (saturates at 0 here — only 5 cells).
        crate::keys::handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('H'), KeyModifiers::NONE),
        );
        assert_eq!(active(&app), 0);
    }

    // --- refresh_active_preview_protocol edge cases ------------------------

    #[test]
    fn refresh_active_preview_protocol_no_op_when_screen_closed() {
        let mut app = app_with_unreachable_thumbnails();
        // No footage detail state → must not panic and must not allocate a
        // preview protocol.
        app.refresh_active_preview_protocol();
        assert!(app.footage_detail_preview.is_none());
    }

    #[test]
    fn refresh_active_preview_protocol_no_op_with_empty_manifest() {
        use crate::api::thumbnails::Manifest;
        let mut app = app_with_unreachable_thumbnails();
        app.set_terminal_capability(TerminalCapability::Halfblocks);
        app.open_footage_detail(42, "fixture.mp4");
        // Server returns no extracted frames yet — empty manifest.
        app.apply_footage_manifest(Manifest {
            duration_seconds: 0.0,
            timestamps: vec![],
        });
        // Even with a graphics-capable picker armed, the empty manifest
        // means there are no frames to fetch — preview stays None.
        assert!(app.footage_detail_preview.is_none());
    }

    #[test]
    fn refresh_active_preview_protocol_no_op_when_text_only() {
        use crate::api::thumbnails::Manifest;
        let mut app = app_with_unreachable_thumbnails();
        // TextOnly capability: no Picker, no image work.
        app.set_terminal_capability(TerminalCapability::TextOnly);
        app.open_footage_detail(42, "fixture.mp4");
        app.apply_footage_manifest(Manifest {
            duration_seconds: 240.0,
            timestamps: vec![0, 60, 120, 180, 240],
        });
        // No protocol allocated even though the manifest has timestamps.
        assert!(app.footage_detail_preview.is_none());
    }

    #[test]
    fn refresh_active_preview_protocol_records_flash_on_fetch_failure() {
        use crate::api::thumbnails::Manifest;
        let mut app = app_with_unreachable_thumbnails();
        app.set_terminal_capability(TerminalCapability::Halfblocks);
        app.open_footage_detail(42, "fixture.mp4");
        // Apply a manifest synthetically so the fetch path fires (the
        // initial `open_footage_detail` already failed and recorded a flash).
        app.apply_footage_manifest(Manifest {
            duration_seconds: 240.0,
            timestamps: vec![0, 60, 120],
        });
        let s = app.footage_detail_state.as_ref().unwrap();
        // The frame fetch hit the unreachable URL too — flash records the
        // failure, and the preview slot stays empty so the renderer falls
        // back to text.
        let flash = s.flash.as_deref().unwrap_or("");
        assert!(
            flash.contains("frame") || flash.contains("manifest"),
            "expected fetch-failure flash, got: {:?}",
            flash
        );
        assert!(app.footage_detail_preview.is_none());
    }

    #[test]
    fn refresh_active_preview_protocol_uses_cached_bytes() {
        // Pre-seed the on-disk cache with a real JPEG so the fetch path
        // doesn't need to hit the network. The result: a `PreviewProtocol`
        // built for the active timestamp, with `matches` returning true.
        use crate::api::thumbnails::{Cache, Manifest, Tier};
        let dir = std::env::temp_dir().join(format!(
            "pito-preview-{}-{}",
            std::process::id(),
            chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        let cache = Cache::with_root(&dir, 1_000_000);
        // Encode a tiny JPEG via the `image` crate so the decoder accepts
        // it. 4×4 RGB pixels are enough for ratatui-image to construct a
        // halfblocks protocol.
        let img = image::DynamicImage::new_rgb8(4, 4);
        let mut buf: Vec<u8> = Vec::new();
        let mut cursor = std::io::Cursor::new(&mut buf);
        img.write_to(&mut cursor, image::ImageFormat::Jpeg)
            .expect("encode JPEG");
        cache.write(42, Tier::Master, 120, &buf).unwrap();

        let mut app = App::with_client_and_thumbnails_config(
            Box::new(MockClient::new()),
            "http://127.0.0.1:1",
            cache,
        );
        app.set_terminal_capability(TerminalCapability::Halfblocks);
        app.open_footage_detail(42, "fixture.mp4");
        // open_footage_detail's manifest fetch failed; supply one
        // synthetically and re-trigger refresh_active_preview_protocol via
        // apply_footage_manifest.
        app.apply_footage_manifest(Manifest {
            duration_seconds: 240.0,
            timestamps: vec![0, 60, 120, 180, 240],
        });
        // Median = 120s → the cached frame at ts=120 is hit; the preview
        // protocol must be allocated and tagged with (42, 120).
        let preview = app
            .footage_detail_preview
            .as_ref()
            .expect("preview protocol allocated from cache hit");
        assert!(preview.matches(42, 120));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn refresh_active_preview_protocol_skips_rebuild_when_active_unchanged() {
        // Calling refresh twice in a row when the state didn't change must
        // be cheap (no fetch, no decode). We can't observe the fetcher
        // skipping directly, but we can verify the preview's identity is
        // stable across the second call.
        use crate::api::thumbnails::{Cache, Manifest, Tier};
        let dir = std::env::temp_dir().join(format!(
            "pito-stable-{}-{}",
            std::process::id(),
            chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        let cache = Cache::with_root(&dir, 1_000_000);
        let img = image::DynamicImage::new_rgb8(4, 4);
        let mut buf: Vec<u8> = Vec::new();
        let mut cursor = std::io::Cursor::new(&mut buf);
        img.write_to(&mut cursor, image::ImageFormat::Jpeg).unwrap();
        cache.write(42, Tier::Master, 120, &buf).unwrap();

        let mut app = App::with_client_and_thumbnails_config(
            Box::new(MockClient::new()),
            "http://127.0.0.1:1",
            cache,
        );
        app.set_terminal_capability(TerminalCapability::Halfblocks);
        app.open_footage_detail(42, "fixture.mp4");
        app.apply_footage_manifest(Manifest {
            duration_seconds: 240.0,
            timestamps: vec![0, 60, 120, 180, 240],
        });
        let first_id = app
            .footage_detail_preview
            .as_ref()
            .map(|p| (p.footage_id(), p.timestamp_seconds()))
            .unwrap();
        // Second call without changing state: identity stays the same.
        app.refresh_active_preview_protocol();
        let second_id = app
            .footage_detail_preview
            .as_ref()
            .map(|p| (p.footage_id(), p.timestamp_seconds()))
            .unwrap();
        assert_eq!(first_id, second_id);

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Spin up a wiremock `MockServer` on a fresh runtime, run the async
    /// setup closure to register stubs, and return the server URI. The
    /// runtime lives in a parked background thread so the synchronous
    /// `reqwest::blocking` path can run without colliding with the tokio
    /// reactor that hosts wiremock.
    fn start_wiremock_server<F, Fut>(setup: F) -> (String, std::thread::JoinHandle<()>)
    where
        F: FnOnce(wiremock::MockServer) -> Fut + Send + 'static,
        Fut: std::future::Future<Output = wiremock::MockServer> + Send,
    {
        use std::sync::mpsc;
        let (tx, rx) = mpsc::channel::<String>();
        let handle = std::thread::spawn(move || {
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("runtime");
            rt.block_on(async move {
                let server = wiremock::MockServer::start().await;
                let server = setup(server).await;
                tx.send(server.uri()).expect("send uri");
                // Park the runtime alive — drop happens when the test
                // thread joins us via JoinHandle, by which point the test
                // is done with the server.
                let () = std::future::pending().await;
                drop(server);
            });
        });
        let uri = rx.recv().expect("recv uri");
        (uri, handle)
    }

    #[test]
    fn open_footage_detail_drives_real_manifest_fetch_via_wiremock() {
        // Integration-flavored unit test: stand up a wiremock server that
        // returns the canonical manifest shape, point `App::with_client_and_
        // thumbnails_config` at it, and confirm `open_footage_detail`
        // populates the manifest synchronously. This exercises the full
        // wire path (HTTP, JSON decode, state transition) without leaving
        // the binary's test harness.
        use crate::api::thumbnails::Cache;
        use serde_json::json;
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, ResponseTemplate};

        let (base_url, _server_thread) = start_wiremock_server(|server| async move {
            Mock::given(method("GET"))
                .and(path("/footages/77/frames.json"))
                .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                    "duration_seconds": 240.0,
                    "timestamps": [60, 120, 180]
                })))
                .mount(&server)
                .await;
            server
        });

        let dir = std::env::temp_dir().join(format!(
            "pito-wiremock-{}-{}",
            std::process::id(),
            chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        let cache = Cache::with_root(&dir, 1_000_000);
        let mut app =
            App::with_client_and_thumbnails_config(Box::new(MockClient::new()), base_url, cache);
        // TextOnly skips the frame fetch; manifest fetch still runs.
        app.set_terminal_capability(TerminalCapability::TextOnly);
        app.open_footage_detail(77, "fixture.mp4");

        let s = app
            .footage_detail_state
            .as_ref()
            .expect("state seeded after fetch");
        let manifest = s
            .manifest
            .as_ref()
            .expect("manifest populated by live fetch");
        assert!((manifest.duration_seconds - 240.0).abs() < f64::EPSILON);
        assert_eq!(manifest.timestamps, vec![60, 120, 180]);
        // Median snap from `set_manifest`: 3 entries → index 1 → 120s.
        assert_eq!(s.active_timestamp_seconds, 120);
        // No flash on the success path.
        assert!(s.flash.is_none(), "no flash expected, got: {:?}", s.flash);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn open_footage_detail_records_flash_on_404_manifest() {
        // Mirror of the success test, but the server replies 404. The
        // screen still opens (so the user can navigate back out), the
        // manifest stays None, and the flash records the failure.
        use crate::api::thumbnails::Cache;
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, ResponseTemplate};

        let (base_url, _server_thread) = start_wiremock_server(|server| async move {
            Mock::given(method("GET"))
                .and(path("/footages/999/frames.json"))
                .respond_with(ResponseTemplate::new(404))
                .mount(&server)
                .await;
            server
        });

        let dir = std::env::temp_dir().join(format!(
            "pito-wm404-{}-{}",
            std::process::id(),
            chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        let cache = Cache::with_root(&dir, 1_000_000);
        let mut app =
            App::with_client_and_thumbnails_config(Box::new(MockClient::new()), base_url, cache);
        app.set_terminal_capability(TerminalCapability::TextOnly);
        app.open_footage_detail(999, "missing.mp4");

        let s = app.footage_detail_state.as_ref().unwrap();
        assert!(s.manifest.is_none());
        let flash = s.flash.as_deref().unwrap_or("");
        assert!(
            flash.contains("manifest"),
            "expected manifest fetch flash, got: {:?}",
            flash
        );
        // Screen is still open so the user can press `q` to back out.
        assert_eq!(app.screen, Screen::FootageDetail);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn open_footage_detail_handles_empty_manifest() {
        // Importer hasn't extracted frames yet — server returns an empty
        // timestamps array. open_footage_detail should accept the manifest
        // (no flash) and the renderer's "no frames" placeholder takes over.
        use crate::api::thumbnails::Cache;
        use serde_json::json;
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, ResponseTemplate};

        let (base_url, _server_thread) = start_wiremock_server(|server| async move {
            Mock::given(method("GET"))
                .and(path("/footages/7/frames.json"))
                .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                    "duration_seconds": 0.0,
                    "timestamps": []
                })))
                .mount(&server)
                .await;
            server
        });

        let dir = std::env::temp_dir().join(format!(
            "pito-empty-{}-{}",
            std::process::id(),
            chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        let cache = Cache::with_root(&dir, 1_000_000);
        let mut app =
            App::with_client_and_thumbnails_config(Box::new(MockClient::new()), base_url, cache);
        app.set_terminal_capability(TerminalCapability::Halfblocks);
        app.open_footage_detail(7, "freshly-imported.mp4");

        let s = app.footage_detail_state.as_ref().unwrap();
        let manifest = s.manifest.as_ref().expect("empty manifest still applies");
        assert!(manifest.timestamps.is_empty());
        assert_eq!(s.active_timestamp_seconds, 0);
        // No flash on success — empty timestamps is a valid response,
        // not an error.
        assert!(s.flash.is_none(), "no flash expected, got: {:?}", s.flash);
        // No preview either — there's nothing to fetch.
        assert!(app.footage_detail_preview.is_none());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn refresh_active_preview_protocol_records_flash_on_decode_failure() {
        // Pre-seed the cache with bytes that AREN'T a valid JPEG. The
        // fetcher returns successfully (cache hit), but `image::load_from_
        // memory` rejects the body. The screen surfaces the failure on the
        // flash slot and clears the preview.
        use crate::api::thumbnails::{Cache, Manifest, Tier};
        let dir = std::env::temp_dir().join(format!(
            "pito-decode-{}-{}",
            std::process::id(),
            chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        let cache = Cache::with_root(&dir, 1_000_000);
        cache.write(42, Tier::Master, 120, b"not a jpeg").unwrap();
        let mut app = App::with_client_and_thumbnails_config(
            Box::new(MockClient::new()),
            "http://127.0.0.1:1",
            cache,
        );
        app.set_terminal_capability(TerminalCapability::Halfblocks);
        app.open_footage_detail(42, "fixture.mp4");
        app.apply_footage_manifest(Manifest {
            duration_seconds: 240.0,
            timestamps: vec![0, 60, 120, 180, 240],
        });
        assert!(app.footage_detail_preview.is_none());
        let s = app.footage_detail_state.as_ref().unwrap();
        let flash = s.flash.as_deref().unwrap_or("");
        assert!(
            flash.contains("decode") || flash.contains("frame"),
            "expected decode-failure flash, got: {:?}",
            flash
        );

        let _ = std::fs::remove_dir_all(&dir);
    }
}
