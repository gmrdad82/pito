use std::io::Write;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use crate::api::client::PitoClient;
use crate::api::models::{AppSettings, BulkOperationStatus, Channel, DashboardData, StatusData};
use crate::api::thumbnails::{Cache as ThumbnailCache, Tier};
use crate::theme::{Theme, ThemeMode};
use crate::ui::footage_detail::{
    FootageDetailState, PreviewProtocol, ScrubRects, TerminalCapability,
};
use ratatui_image::picker::Picker;

// ── Helpers ──────────────────────────────────────────────────────

pub fn default_app_settings() -> AppSettings {
    AppSettings {
        max_panes: 3,
        pane_title_length: 24,
        theme: "dark".to_string(),
    }
}

pub fn empty_dashboard_data() -> DashboardData {
    DashboardData {
        video_count: 0,
        channel_count: 0,
        project_count: 0,
        footage_count: 0,
        note_count: 0,
    }
}

pub fn log_error(scope: &str, err: &dyn std::fmt::Display) {
    let dir = error_log_dir();
    if std::fs::create_dir_all(&dir).is_err() { return; }
    let path = dir.join("error.log");
    let line = format!("[{}] {}: {}\n", current_timestamp(), scope, err);
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&path) {
        let _ = f.write_all(line.as_bytes());
    }
}

fn error_log_dir() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_CACHE_HOME") { if !xdg.is_empty() { return PathBuf::from(xdg).join("pito"); } }
    if let Ok(home) = std::env::var("HOME") { if !home.is_empty() { return PathBuf::from(home).join(".cache").join("pito"); } }
    PathBuf::from("/tmp").join("pito")
}

fn current_timestamp() -> String {
    chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string()
}

// ── Polling ──────────────────────────────────────────────────────

pub const SYNC_POLL_INTERVAL: Duration = Duration::from_millis(500);
pub const SYNC_POLL_DEADLINE: Duration = Duration::from_secs(10);
pub const OPERATION_POLL_INTERVAL: Duration = Duration::from_millis(500);
pub const OPERATION_POLL_DEADLINE: Duration = Duration::from_secs(30);
pub const STATUS_POLL_INTERVAL: Duration = Duration::from_secs(5);

#[derive(Debug, Clone)]
pub struct SyncPolling {
    pub affected_ids: Vec<u64>,
    pub next_poll_at: Instant,
    pub deadline: Instant,
    pub tick: u8,
}

impl SyncPolling {
    pub fn new(affected_ids: Vec<u64>) -> Self {
        let now = Instant::now();
        Self { affected_ids, next_poll_at: now, deadline: now + SYNC_POLL_DEADLINE, tick: 0 }
    }
}

#[derive(Debug, Clone)]
pub struct OperationProgress {
    pub operation_id: u64,
    pub kind: String,
    pub last_status: Option<BulkOperationStatus>,
    pub next_poll_at: Instant,
    pub deadline: Instant,
    pub dismissed: bool,
    pub last_error: Option<String>,
    pub tick: u8,
}

impl OperationProgress {
    pub fn new(operation_id: u64, kind: impl Into<String>) -> Self {
        let now = Instant::now();
        Self { operation_id, kind: kind.into(), last_status: None, next_poll_at: now, deadline: now + OPERATION_POLL_DEADLINE, dismissed: false, last_error: None, tick: 0 }
    }
}

// ── App ──────────────────────────────────────────────────────────

pub struct App<C: PitoClient> {
    pub running: bool,
    pub theme_mode: ThemeMode,
    pub sidebar_open: bool,
    pub authenticated: bool,

    // Data
    pub channels: Vec<Channel>,
    pub selected_channel_ids: Vec<u64>,
    pub conversation_lines: Vec<String>,

    // Input
    pub input_buffer: String,
    pub cursor_pos: usize,

    // Client
    pub client: C,

    // Bulk operations
    pub sync_polling: Option<SyncPolling>,
    pub operation_progress: Option<OperationProgress>,

    // Status polling
    pub status_data: StatusData,
    pub last_status_poll: Instant,

    // Datetime tick (1 Hz)
    pub last_time_update: Instant,
    pub cached_time_string: String,
    pub display_time_string: String,
    pub scramble_tick: u8,
    pub scramble_total: u8,

    // Footage detail (salvaged)
    pub footage_detail_state: Option<FootageDetailState>,
    pub footage_detail_rects: Option<ScrubRects>,
    pub terminal_capability: TerminalCapability,
    pub thumbnails_picker: Option<Picker>,
    pub thumbnails_cache: ThumbnailCache,
    pub thumbnails_base_url: String,
    pub footage_detail_preview: Option<PreviewProtocol>,
}

impl<C: PitoClient> App<C> {
    pub fn new(client: C, thumbnails_base_url: impl Into<String>) -> Self {
        let thumbnails_cache = ThumbnailCache::default();
        let thumbnails_base_url: String = thumbnails_base_url.into();

        Self {
            running: true,
            theme_mode: ThemeMode::Dark,
            sidebar_open: true,
            authenticated: false,
            channels: Vec::new(),
            selected_channel_ids: Vec::new(),
            conversation_lines: Vec::new(),
            input_buffer: String::new(),
            cursor_pos: 0,
            client,
            sync_polling: None,
            operation_progress: None,
status_data: StatusData {
            connected: true,
                sidekiq_busy: 0,
                sidekiq_enqueued: 0,
                sidekiq_retry: 0,
                sidekiq_dead: 0,
            },
            last_status_poll: Instant::now(),
            last_time_update: Instant::now(),
            cached_time_string: String::new(),
            display_time_string: String::new(),
            scramble_tick: 0,
            scramble_total: 6,
            footage_detail_state: None,
            footage_detail_rects: None,
            terminal_capability: TerminalCapability::TextOnly,
            thumbnails_picker: None,
            thumbnails_cache,
            thumbnails_base_url,
            footage_detail_preview: None,
        }
    }

    pub fn theme(&self) -> Theme { Theme::from_mode(self.theme_mode) }
    pub fn toggle_theme(&mut self) { self.theme_mode = self.theme_mode.toggle(); }
    pub fn quit(&mut self) { self.running = false; }
    pub fn toggle_sidebar(&mut self) { self.sidebar_open = !self.sidebar_open; }

    pub fn push_line(&mut self, s: impl Into<String>) {
        self.conversation_lines.push(s.into());
    }

    pub fn set_terminal_capability(&mut self, capability: TerminalCapability) {
        self.terminal_capability = capability;
        self.thumbnails_picker = match capability {
            TerminalCapability::TextOnly => None,
            _ => Some(crate::ui::footage_detail::capability::halfblocks_picker()),
        };
    }

    pub fn set_terminal_capability_with_picker(&mut self, capability: TerminalCapability, picker: Picker) {
        self.terminal_capability = capability;
        self.thumbnails_picker = match capability {
            TerminalCapability::TextOnly => None,
            _ => Some(picker),
        };
    }

    pub fn syncing_animated_ids(&self) -> Vec<u64> {
        self.sync_polling.as_ref().map(|sp| sp.affected_ids.clone()).unwrap_or_default()
    }

    pub fn sync_anim_tick(&self) -> u8 {
        self.sync_polling.as_ref().map(|sp| sp.tick).unwrap_or(0)
    }

    /// Return true if at least 1 second has elapsed since the last time
    /// update, and reset the timer. Also starts a scramble animation.
    /// Callers use this to gate datetime recomputation so the status bar
    /// only refreshes at 1 Hz.
    pub fn update_time_stale(&mut self) -> bool {
        if self.last_time_update.elapsed() >= Duration::from_secs(1) {
            self.last_time_update = Instant::now();
            self.scramble_tick = self.scramble_total;
            true
        } else {
            false
        }
    }

    /// Compute the displayed time string, scrambling during transitions.
    /// Returns the string that should be rendered for the current frame.
    pub fn scrambled_time(&mut self) -> String {
        if self.cached_time_string.is_empty() {
            self.cached_time_string = chrono::Local::now().format("%a, %b %e · %H:%M:%S").to_string();
            self.display_time_string = self.cached_time_string.clone();
            return self.display_time_string.clone();
        }

        if self.scramble_tick > 0 {
            self.scramble_tick -= 1;
            let progress = (self.scramble_total - self.scramble_tick) as f64 / self.scramble_total as f64;
            let scrambled: String = self.cached_time_string.chars()
                .enumerate()
                .map(|(i, c)| {
                    if i >= self.display_time_string.len() { return c; }
                    let old = self.display_time_string.chars().nth(i).unwrap_or(c);
                    if c == old { return c; }
                    if fastrand::f64() < progress * 0.7 + 0.3 { return c; }
                    let set = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
                    let idx = fastrand::usize(..set.len());
                    set.chars().nth(idx).unwrap_or(c)
                })
                .collect();
            self.display_time_string = scrambled;
            self.display_time_string.clone()
        } else {
            self.display_time_string = self.cached_time_string.clone();
            self.display_time_string.clone()
        }
    }

    /// Poll GET /status.json every [`STATUS_POLL_INTERVAL`]. Errors are
    /// silently discarded — the status bar shows the last successful data.
    pub fn poll_status(&mut self) {
        if self.last_status_poll.elapsed() < STATUS_POLL_INTERVAL {
            return;
        }
        self.last_status_poll = Instant::now();
        if let Ok(data) = self.client.get_status() {
            self.status_data = data;
        }
    }

    // ── Footage detail (salvaged) ────────────────────────────────

    pub fn open_footage_detail(&mut self, footage_id: u64, label: impl Into<String>) {
        let mut state = FootageDetailState::new(footage_id, label);
        match crate::api::thumbnails::fetch_manifest(&self.thumbnails_base_url, footage_id) {
            Ok(manifest) => state.set_manifest(manifest),
            Err(e) => {
                log_error("open_footage_detail fetch_manifest", &e);
                state.flash = Some(format!("frames manifest fetch failed: {}", e));
            }
        }
        self.footage_detail_state = Some(state);
        self.footage_detail_rects = None;
        self.footage_detail_preview = None;
        self.refresh_active_preview_protocol();
    }

    pub fn apply_footage_manifest(&mut self, manifest: crate::api::thumbnails::Manifest) {
        if let Some(ref mut s) = self.footage_detail_state { s.set_manifest(manifest); }
        self.refresh_active_preview_protocol();
    }

    pub fn record_footage_detail_rects(&mut self, rects: ScrubRects) {
        self.footage_detail_rects = Some(rects);
    }

    pub fn refresh_active_preview_protocol(&mut self) {
        let Some(state) = self.footage_detail_state.as_ref() else { return; };
        let Some(ref manifest) = state.manifest else { return; };
        if manifest.timestamps.is_empty() { self.footage_detail_preview = None; return; }
        let footage_id = state.footage_id;
        let timestamp = state.active_timestamp_seconds;
        if let Some(ref preview) = self.footage_detail_preview {
            if preview.matches(footage_id, timestamp) { return; }
        }
        let Some(picker) = self.thumbnails_picker.clone() else { return; };
        let base_url = self.thumbnails_base_url.clone();
        let cache = self.thumbnails_cache.clone();
        let bytes_result = cache.fetch_or_get(footage_id, Tier::Master, timestamp, || {
            crate::api::thumbnails::fetch_frame_bytes(&base_url, footage_id, Tier::Master, timestamp)
        });
        let bytes = match bytes_result {
            Ok(b) => b,
            Err(e) => {
                log_error("refresh_active_preview_protocol", &e);
                if let Some(ref mut s) = self.footage_detail_state { s.flash = Some(format!("frame fetch failed: {}", e)); }
                self.footage_detail_preview = None;
                return;
            }
        };
        match image::load_from_memory(&bytes) {
            Ok(dyn_img) => {
                let protocol = picker.new_resize_protocol(dyn_img);
                self.footage_detail_preview = Some(PreviewProtocol::new(footage_id, timestamp, protocol));
            }
            Err(e) => {
                log_error("refresh_active_preview_protocol decode", &e);
                if let Some(ref mut s) = self.footage_detail_state { s.flash = Some(format!("frame decode failed: {}", e)); }
                self.footage_detail_preview = None;
            }
        }
    }

    // ── Commands ─────────────────────────────────────────────────

    pub fn execute_command(&mut self, cmd: &str) {
        self.push_line(format!("> {}", cmd));
        let parts: Vec<&str> = cmd.split_whitespace().collect();
        if parts.is_empty() { return; }

        match parts[0] {
            "/help" => {
                self.push_line("  /status /channels /videos /games /reindex /config");
                self.push_line("  /sidebar — toggle sidebar");
                self.push_line("  Tab toggles sidebar");
            }
            "/status" => {
                match self.client.get_dashboard() {
                    Ok(d) => {
                        self.push_line(format!("  channels  {}", d.channel_count));
                        self.push_line(format!("  videos    {}", d.video_count));
                        self.push_line(format!("  footage   {}", d.footage_count));
                    }
                    Err(e) => { self.push_line(format!("  error: {:#}", e)); }
                }
            }
            "/channels" => {
                match self.client.get_channels() {
                    Ok(chans) => {
                        let count = chans.len();
                        self.push_line(format!("channels ({}):", count));
                        for ch in &chans {
                            let star = if ch.star { "★" } else { " " };
                            self.push_line(format!("  {} {}", star, ch.channel_url));
                        }
                        self.channels = chans;
                    }
                    Err(e) => { self.push_line(format!("  error: {:#}", e)); }
                }
            }
            "/videos" => {
                match self.client.get_videos() {
                    Ok(videos) => {
                        self.push_line(format!("videos ({}):", videos.len()));
                        for v in videos.iter().take(30) {
                            self.push_line(format!("  {}  {} views", v.youtube_video_id, v.views));
                        }
                    }
                    Err(e) => { self.push_line(format!("  error: {:#}", e)); }
                }
            }
            "/games" => {
                // /games fetches videos and filters locally for a "games"
                // category based on the youtube_video_id or channel_url matching
                // gaming-related keywords.  In a future iteration the server may
                // expose a dedicated endpoint; for now we reuse get_videos().
                match self.client.get_videos() {
                    Ok(videos) => {
                        let game_keywords = [
                            "game", "gaming", "play", "twitch", "minecraft",
                            "fortnite", "valorant", "league", "dota", "csgo",
                            "elden", "zelda", "mario", "pokemon", "gta",
                        ];
                        let games: Vec<_> = videos
                            .iter()
                            .filter(|v| {
                                let haystack = format!(
                                    "{} {}",
                                    v.youtube_video_id.to_lowercase(),
                                    v.channel_url
                                        .as_deref()
                                        .unwrap_or("")
                                        .to_lowercase()
                                );
                                game_keywords
                                    .iter()
                                    .any(|kw| haystack.contains(kw))
                            })
                            .collect();
                        self.push_line(format!("games ({}):", games.len()));
                        for g in games.iter().take(30) {
                            self.push_line(format!(
                                "  {}  {} views",
                                g.youtube_video_id, g.views
                            ));
                        }
                        if games.is_empty() {
                            self.push_line("  (no gaming-related videos found)");
                        }
                    }
                    Err(e) => { self.push_line(format!("  error: {:#}", e)); }
                }
            }
            "/reindex" => {
                // /reindex meilisearch|voyage  →  POST /commands/execute
                let target = if parts.len() >= 2 { parts[1] } else { "" };
                match target {
                    "meilisearch" | "voyage" => {
                        let command = format!("reindex {}", target);
                        match self.client.execute_command(&command) {
                            Ok(resp) => {
                                self.push_line(format!("  reindex {} → {}", target, resp));
                            }
                            Err(e) => {
                                self.push_line(format!("  error: {:#}", e));
                            }
                        }
                    }
                    _ => {
                        self.push_line("  usage: /reindex meilisearch|voyage");
                    }
                }
            }
            "/config" => {
                match self.client.execute_command("config show") {
                    Ok(resp) => {
                        self.push_line(format!("  config: {}", resp));
                    }
                    Err(e) => {
                        self.push_line(format!("  error: {:#}", e));
                    }
                }
            }
            "/auth" => {
                if parts.len() < 2 || parts[1].len() != 6 {
                    self.push_line("  usage: /auth <6-digit-code>");
                } else {
                    self.push_line("  authenticating...");
                    match self.client.authenticate(parts[1]) {
                        Ok(true) => {
                            self.authenticated = true;
                            self.push_line("  authenticated");
                            if let Ok(chans) = self.client.get_channels() {
                                self.push_line(format!("  {} channels loaded", chans.len()));
                                self.channels = chans;
                            }
                        }
                        Ok(false) => { self.push_line("  login failed"); }
                        Err(e) => { self.push_line(format!("  error: {:#}", e)); }
                    }
                }
            }
            "/sidebar" => { self.toggle_sidebar(); }
            "help" => {
                self.push_line("  commands: /help /status /channels /videos /games /reindex /config /sidebar");
            }
            "clear" => { self.conversation_lines.clear(); }
            _ => {
                self.push_line(format!("  unknown: {} — try /help", parts[0]));
            }
        }
    }
}
