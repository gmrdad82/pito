use chrono::{DateTime, Utc};
use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
};

use crate::theme::Theme;
use crate::ui::videos::SortDirection;

// --- Filter chips ---

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChannelFilter {
    None,
    Starred,
    Connected,
}

// --- Data types ---

pub struct ChannelsState {
    pub channels: Vec<ChannelRow>,
    pub selected: usize,
    pub selected_ids: Vec<u64>,
    /// Sorting feature stub — kept for the upcoming column-header sort flow.
    #[allow(dead_code)]
    pub sort_column: usize,
    /// Sorting feature stub — kept for the upcoming column-header sort flow.
    #[allow(dead_code)]
    pub sort_direction: SortDirection,
    pub scroll_offset: usize,
    pub filter: ChannelFilter,
    /// Brief flash message displayed in the toolbar (e.g. "URL is locked").
    pub flash: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ChannelRow {
    pub id: u64,
    pub channel_url: String,
    pub star: bool,
    pub connected: bool,
    pub last_synced_at: Option<String>,
}

// --- Helpers ---

/// Format a UTC ISO-8601 timestamp as a compact relative duration vs. now.
///
/// Compact format buckets:
/// - `None` or unparseable → `"never"`
/// - `< 60s` → `"~60s ago"`
/// - `< 60m` → `"~Xm ago"`
/// - `< 24h` → `"~Xh ago"`
/// - `< 30d` → `"~Xd ago"`
/// - `< 365d` → `"~Xmo ago"` (X = floor(days / 30))
/// - otherwise → `"~Xyr ago"` (X = floor(days / 365))
pub fn format_relative_time(ts: Option<&str>) -> String {
    format_relative_time_at(ts, Utc::now())
}

/// Testable variant of [`format_relative_time`] that accepts an explicit "now"
/// reference instead of reading the wall clock.
pub fn format_relative_time_at(ts: Option<&str>, now: DateTime<Utc>) -> String {
    let Some(ts) = ts else {
        return "never".to_string();
    };
    if ts.is_empty() {
        return "never".to_string();
    }
    let Ok(then) = DateTime::parse_from_rfc3339(ts) else {
        return "never".to_string();
    };
    let then_utc = then.with_timezone(&Utc);
    let secs = (now - then_utc).num_seconds().max(0);

    if secs < 60 {
        return "~60s ago".to_string();
    }
    let mins = secs / 60;
    if mins < 60 {
        return format!("~{}m ago", mins);
    }
    let hours = secs / 3600;
    if hours < 24 {
        return format!("~{}h ago", hours);
    }
    let days = secs / 86_400;
    if days < 30 {
        return format!("~{}d ago", days);
    }
    if days < 365 {
        return format!("~{}mo ago", days / 30);
    }
    format!("~{}yr ago", days / 365)
}

/// Render the star marker for a channel.
pub fn star_indicator(star: bool) -> &'static str {
    if star { "yes" } else { "no" }
}

/// Render the connected marker.
pub fn connected_indicator(connected: bool) -> &'static str {
    if connected { "o" } else { "-" }
}

/// Last-sync cell text. Rails no longer emits a server-side `syncing`
/// boolean (Path A2 retract), so this is just the relative time when known
/// and an em-dash otherwise.
pub fn last_sync_cell(last_synced_at: Option<&str>) -> String {
    if last_synced_at.is_some() {
        format_relative_time(last_synced_at)
    } else {
        "\u{2014}".to_string()
    }
}

/// Same as [`last_sync_cell`] but, when `animate` is true, replaces the cell
/// content with `syncing` plus one to three trailing dots based on `tick` to
/// give the user a subtle pulse while pito polls the API after a sync
/// confirm. The decoration is purely cosmetic — the text stays under the
/// column width.
pub fn last_sync_cell_animated(last_synced_at: Option<&str>, animate: bool, tick: u8) -> String {
    if animate {
        let dots = match tick % 4 {
            0 => "",
            1 => ".",
            2 => "..",
            _ => "...",
        };
        format!("syncing{}", dots)
    } else {
        last_sync_cell(last_synced_at)
    }
}

// --- Render ---

/// Subset of app state the channels view needs to render the live "syncing"
/// indicator while pito polls the API after a sync confirm.
#[derive(Debug, Clone, Copy, Default)]
pub struct SyncAnim<'a> {
    pub ids: &'a [u64],
    pub tick: u8,
}

pub fn render(
    frame: &mut Frame,
    area: Rect,
    theme: &Theme,
    state: &ChannelsState,
    sync_anim: SyncAnim<'_>,
) {
    let block = Block::default()
        .title(Span::styled(" channels ", Style::default().fg(theme.fg)))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.border));

    let inner = block.inner(area);
    frame.render_widget(block, area);

    if inner.height < 3 || inner.width < 20 {
        return;
    }

    let layout = Layout::vertical([
        Constraint::Length(1), // toolbar
        Constraint::Length(1), // filter chips
        Constraint::Length(1), // header
        Constraint::Length(1), // separator
        Constraint::Min(0),    // rows
    ])
    .split(inner);

    render_toolbar(frame, layout[0], theme, state);
    render_filter_row(frame, layout[1], theme, state);
    render_table_header(frame, layout[2], theme, state);
    render_separator(frame, layout[3], theme, inner.width);
    render_rows(frame, layout[4], theme, state, sync_anim);
}

fn render_toolbar(frame: &mut Frame, area: Rect, theme: &Theme, state: &ChannelsState) {
    let count = format!("{} channels total", visible_channels(state).len());
    let selected_count = state.selected_ids.len();
    let right = if selected_count > 0 {
        format!("{} selected · {}", selected_count, count)
    } else {
        count
    };
    let right_w = right.len() as u16;
    let left_max = area.width.saturating_sub(right_w + 1) as usize;

    let mut left_spans: Vec<Span> = vec![
        Span::styled("[add]", Style::default().fg(theme.accent)),
        Span::raw(" "),
        Span::styled("[bulk]", Style::default().fg(theme.accent)),
    ];
    if let Some(ref flash) = state.flash {
        left_spans.push(Span::raw("  "));
        left_spans.push(Span::styled(
            flash.clone(),
            Style::default().fg(theme.danger),
        ));
    }

    let used: usize = left_spans.iter().map(|s| s.content.chars().count()).sum();
    if used < left_max {
        left_spans.push(Span::raw(" ".repeat(left_max - used)));
    }
    left_spans.push(Span::styled(right, Style::default().fg(theme.muted)));
    frame.render_widget(Paragraph::new(Line::from(left_spans)), area);
}

fn render_filter_row(frame: &mut Frame, area: Rect, theme: &Theme, state: &ChannelsState) {
    let chip = |label: &'static str, is_active: bool| -> Span {
        let style = if is_active {
            Style::default().fg(theme.bg).bg(theme.accent)
        } else {
            Style::default().fg(theme.muted)
        };
        Span::styled(format!(" {} ", label), style)
    };

    let line = Line::from(vec![
        Span::styled("  filter: ", Style::default().fg(theme.muted)),
        chip("starred (f s)", state.filter == ChannelFilter::Starred),
        Span::raw(" "),
        chip("connected (f c)", state.filter == ChannelFilter::Connected),
    ]);
    frame.render_widget(Paragraph::new(line), area);
}

fn render_table_header(frame: &mut Frame, area: Rect, theme: &Theme, _state: &ChannelsState) {
    let style = Style::default().fg(theme.muted);
    // Checkboxes are always rendered, so the prefix column is always 4 cols
    // wide ("[ ] " / "[x] ").
    let spans: Vec<Span> = vec![
        Span::styled("    ", style),
        Span::styled(pad_right("url", 40), style),
        Span::styled(pad_center("starred", 7), style),
        Span::styled(pad_center("conn", 5), style),
        Span::styled(pad_left("last sync", 12), style),
    ];
    frame.render_widget(Paragraph::new(Line::from(spans)), area);
}

fn render_separator(frame: &mut Frame, area: Rect, theme: &Theme, width: u16) {
    let line = Line::from(Span::styled(
        "\u{2500}".repeat(width as usize),
        Style::default().fg(theme.border),
    ));
    frame.render_widget(Paragraph::new(line), area);
}

/// Compute the filtered view of the channels list.
pub fn visible_channels(state: &ChannelsState) -> Vec<&ChannelRow> {
    state
        .channels
        .iter()
        .filter(|c| match state.filter {
            ChannelFilter::None => true,
            ChannelFilter::Starred => c.star,
            ChannelFilter::Connected => c.connected,
        })
        .collect()
}

fn render_rows(
    frame: &mut Frame,
    area: Rect,
    theme: &Theme,
    state: &ChannelsState,
    sync_anim: SyncAnim<'_>,
) {
    let rows = visible_channels(state);
    let visible_count = area.height as usize;

    for i in 0..visible_count {
        let idx = state.scroll_offset + i;
        if idx >= rows.len() {
            break;
        }
        let channel = rows[idx];
        let is_cursor = idx == state.selected;
        let is_checked = state.selected_ids.contains(&channel.id);

        let row_style = if is_cursor {
            Style::default().fg(theme.fg).bg(theme.border)
        } else {
            Style::default().fg(theme.fg)
        };

        let mut spans: Vec<Span> = Vec::new();
        // Always-on checkboxes (no bulk-mode gate). Mirrors the web side's
        // always-on checkbox UX. The row highlight (background color) carries
        // the cursor position; the `[ ]` / `[x]` marker carries selection.
        let check = if is_checked { "[x] " } else { "[ ] " };
        spans.push(Span::styled(check, row_style));

        let url = truncate(&channel.channel_url, 40);
        spans.push(Span::styled(pad_right(&url, 40), row_style));

        let star_style = if channel.star {
            Style::default()
                .fg(theme.orange)
                .bg(if is_cursor { theme.border } else { theme.bg })
        } else {
            row_style
        };
        spans.push(Span::styled(
            pad_center(star_indicator(channel.star), 7),
            star_style,
        ));

        let conn_style = if channel.connected {
            Style::default()
                .fg(theme.success)
                .bg(if is_cursor { theme.border } else { theme.bg })
        } else {
            Style::default()
                .fg(theme.muted)
                .bg(if is_cursor { theme.border } else { theme.bg })
        };
        spans.push(Span::styled(
            pad_center(connected_indicator(channel.connected), 5),
            conn_style,
        ));

        let is_polled = sync_anim.ids.contains(&channel.id);
        let last_sync_style = if is_polled {
            Style::default()
                .fg(theme.accent)
                .bg(if is_cursor { theme.border } else { theme.bg })
        } else {
            row_style
        };
        spans.push(Span::styled(
            pad_left(
                &last_sync_cell_animated(
                    channel.last_synced_at.as_deref(),
                    is_polled,
                    sync_anim.tick,
                ),
                12,
            ),
            last_sync_style,
        ));

        let row_area = Rect {
            x: area.x,
            y: area.y + i as u16,
            width: area.width,
            height: 1,
        };
        frame.render_widget(Paragraph::new(Line::from(spans)), row_area);
    }
}

// --- String helpers ---

fn pad_right(s: &str, width: u16) -> String {
    let w = width as usize;
    let char_count = s.chars().count();
    if char_count >= w {
        s.chars().take(w).collect()
    } else {
        let mut result = s.to_string();
        for _ in 0..(w - char_count) {
            result.push(' ');
        }
        result
    }
}

fn pad_left(s: &str, width: u16) -> String {
    let w = width as usize;
    let char_count = s.chars().count();
    if char_count >= w {
        s.chars().take(w).collect()
    } else {
        let mut result = " ".repeat(w - char_count);
        result.push_str(s);
        result
    }
}

fn pad_center(s: &str, width: u16) -> String {
    let w = width as usize;
    let char_count = s.chars().count();
    if char_count >= w {
        return s.chars().take(w).collect();
    }
    let pad = (w - char_count) / 2;
    let mut result = " ".repeat(pad);
    result.push_str(s);
    while result.chars().count() < w {
        result.push(' ');
    }
    result
}

fn truncate(s: &str, max: usize) -> String {
    let char_count = s.chars().count();
    if char_count <= max {
        s.to_string()
    } else if max <= 3 {
        s.chars().take(max).collect()
    } else {
        format!("{}...", s.chars().take(max - 3).collect::<String>())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    /// Fixed reference instant for tests so relative-time math is deterministic.
    fn ref_now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 4, 30, 10, 0, 0).unwrap()
    }

    fn row(id: u64, url: &str, star: bool, connected: bool, last_sync: Option<&str>) -> ChannelRow {
        ChannelRow {
            id,
            channel_url: url.to_string(),
            star,
            connected,
            last_synced_at: last_sync.map(|s| s.to_string()),
        }
    }

    fn state(rows: Vec<ChannelRow>, filter: ChannelFilter) -> ChannelsState {
        ChannelsState {
            channels: rows,
            selected: 0,
            selected_ids: vec![],
            sort_column: 0,
            sort_direction: SortDirection::Asc,
            scroll_offset: 0,
            filter,
            flash: None,
        }
    }

    #[test]
    fn star_and_connected_indicators() {
        assert_eq!(star_indicator(true), "yes");
        assert_eq!(star_indicator(false), "no");
        assert_eq!(connected_indicator(true), "o");
        assert_eq!(connected_indicator(false), "-");
    }

    #[test]
    fn last_sync_cell_when_known() {
        // Path A2: there's no in-flight `syncing` flag from the wire any more.
        // The cell renders the relative time when known (anything other than
        // "never" / em-dash) and the em-dash placeholder when not.
        let cell = last_sync_cell(Some("2026-04-30T09:55:00Z"));
        assert!(
            cell.starts_with("~") && cell.ends_with(" ago"),
            "expected a relative-time string, got {:?}",
            cell
        );
    }

    #[test]
    fn last_sync_cell_when_never_synced() {
        assert_eq!(last_sync_cell(None), "\u{2014}");
    }

    #[test]
    fn last_sync_cell_animated_pulses_through_dots_while_polling() {
        // Tick 0 → no dots, 1 → ".", 2 → "..", 3 → "...", then wraps. The
        // animation kicks in based on `animate` (CLI-local polling state),
        // not on a wire field.
        assert_eq!(last_sync_cell_animated(None, true, 0), "syncing");
        assert_eq!(last_sync_cell_animated(None, true, 1), "syncing.");
        assert_eq!(last_sync_cell_animated(None, true, 2), "syncing..");
        assert_eq!(last_sync_cell_animated(None, true, 3), "syncing...");
        assert_eq!(last_sync_cell_animated(None, true, 4), "syncing");
    }

    #[test]
    fn last_sync_cell_animated_falls_back_when_not_polling() {
        // animate=false: same as the static cell. We assert on the structural
        // shape rather than a specific bucket so the test isn't time-sensitive.
        let cell = last_sync_cell_animated(Some("2026-04-30T09:55:00Z"), false, 7);
        assert!(
            cell.starts_with("~") && cell.ends_with(" ago"),
            "expected a relative-time string, got {:?}",
            cell
        );
        assert_eq!(last_sync_cell_animated(None, false, 2), "\u{2014}");
    }

    #[test]
    fn relative_time_handles_none() {
        assert_eq!(format_relative_time_at(None, ref_now()), "never");
    }

    #[test]
    fn relative_time_handles_empty_string() {
        assert_eq!(format_relative_time_at(Some(""), ref_now()), "never");
    }

    #[test]
    fn relative_time_under_a_minute() {
        // 30 seconds ago bucketed into the "<60s" bucket → "~60s ago".
        let ts = "2026-04-30T09:59:30Z";
        assert_eq!(format_relative_time_at(Some(ts), ref_now()), "~60s ago");
    }

    #[test]
    fn relative_time_minutes() {
        // 5 minutes ago.
        let ts = "2026-04-30T09:55:00Z";
        assert_eq!(format_relative_time_at(Some(ts), ref_now()), "~5m ago");
    }

    #[test]
    fn relative_time_hours() {
        // 4 hours ago.
        let ts = "2026-04-30T06:00:00Z";
        assert_eq!(format_relative_time_at(Some(ts), ref_now()), "~4h ago");
    }

    #[test]
    fn relative_time_days() {
        // 3 days ago.
        let ts = "2026-04-27T10:00:00Z";
        assert_eq!(format_relative_time_at(Some(ts), ref_now()), "~3d ago");
    }

    #[test]
    fn relative_time_months() {
        // 6 months ago: 180 days back from the reference. 180 / 30 = 6.
        let now = ref_now();
        let then = now - chrono::Duration::days(180);
        let ts = then.to_rfc3339();
        assert_eq!(format_relative_time_at(Some(&ts), now), "~6mo ago");
    }

    #[test]
    fn relative_time_years() {
        // 2 years ago: 730 days back. 730 / 365 = 2.
        let now = ref_now();
        let then = now - chrono::Duration::days(730);
        let ts = then.to_rfc3339();
        assert_eq!(format_relative_time_at(Some(&ts), now), "~2yr ago");
    }

    #[test]
    fn filter_starred_subset() {
        let s = state(
            vec![
                row(1, "a", true, false, None),
                row(2, "b", false, true, None),
                row(3, "c", true, true, None),
            ],
            ChannelFilter::Starred,
        );
        let visible = visible_channels(&s);
        assert_eq!(visible.len(), 2);
        assert!(visible.iter().all(|c| c.star));
    }

    #[test]
    fn filter_connected_subset() {
        let s = state(
            vec![
                row(1, "a", false, false, None),
                row(2, "b", false, true, None),
            ],
            ChannelFilter::Connected,
        );
        assert_eq!(visible_channels(&s).len(), 1);
    }

    #[test]
    fn truncate_long_url_to_40_chars_with_ellipsis() {
        let url = "https://www.youtube.com/@a-very-long-channel-handle-that-goes-on";
        let result = truncate(url, 40);
        assert_eq!(result.chars().count(), 40);
        assert!(result.ends_with("..."));
        assert!(url.starts_with(result.trim_end_matches("...")));
    }

    #[test]
    fn truncate_short_url_returns_unchanged() {
        let url = "https://youtube.com/@x";
        assert_eq!(truncate(url, 40), url);
    }

    #[test]
    fn pad_center_centers_one_char_in_three() {
        assert_eq!(pad_center("*", 3), " * ");
        assert_eq!(pad_center(" ", 3), "   ");
    }

    #[test]
    fn filter_none_returns_all() {
        let s = state(
            vec![
                row(1, "a", false, false, None),
                row(2, "b", false, false, None),
            ],
            ChannelFilter::None,
        );
        assert_eq!(visible_channels(&s).len(), 2);
    }
}
