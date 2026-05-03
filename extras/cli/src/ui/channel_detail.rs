use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
};

use crate::theme::Theme;
use crate::ui::channels::last_sync_cell;

pub struct ChannelDetailState {
    pub channel: ChannelInfo,
    pub videos: Vec<ChannelVideoRow>,
    pub video_selected: usize,
    pub video_scroll: usize,
    /// Brief flash message (e.g. "URL is locked") shown above the actions row.
    pub flash: Option<String>,
}

pub struct ChannelInfo {
    pub id: u64,
    pub tenant_id: u64,
    pub channel_url: String,
    pub star: bool,
    pub connected: bool,
    pub syncing: bool,
    pub last_synced_at: Option<String>,
}

pub struct ChannelVideoRow {
    /// Reserved for upcoming row-click navigation (Enter opens video detail).
    #[allow(dead_code)]
    pub id: u64,
    pub title: String,
    pub views: u64,
    pub likes: u64,
    pub privacy_status: String,
    pub published_at: String,
    pub duration_seconds: u32,
}

pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, state: &ChannelDetailState) {
    let title = format!(" channels › {} ", short_url(&state.channel.channel_url));
    let block = Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.border));

    let inner = block.inner(area);
    frame.render_widget(block, area);

    let layout = Layout::vertical([
        Constraint::Length(1), // actions
        Constraint::Length(1), // flash
        Constraint::Length(7), // KV pairs (6 fields)
        Constraint::Length(1), // spacer
        Constraint::Min(0),    // video table
    ])
    .split(inner);

    // Actions row. `connected` is intentionally not in the legend — it's
    // OAuth-managed and only the web UI can toggle it.
    let actions = Line::from(vec![
        Span::raw("  "),
        Span::styled("[view]", Style::default().fg(theme.accent)),
        Span::raw(" "),
        Span::styled("[sync]", Style::default().fg(theme.accent)),
        Span::raw(" "),
        Span::styled("[delete]", Style::default().fg(theme.danger)),
        Span::raw("    "),
        Span::styled(
            "(v) view  (Y) sync  (D) delete  (s) star",
            Style::default().fg(theme.muted),
        ),
    ]);
    frame.render_widget(Paragraph::new(actions), layout[0]);

    // Flash message
    if let Some(ref flash) = state.flash {
        let line = Line::from(vec![
            Span::raw("  "),
            Span::styled(flash.clone(), Style::default().fg(theme.danger)),
        ]);
        frame.render_widget(Paragraph::new(line), layout[1]);
    }

    render_kv_pairs(frame, layout[2], theme, state);
    render_video_table(frame, layout[4], theme, state);
}

fn render_kv_pairs(frame: &mut Frame, area: Rect, theme: &Theme, state: &ChannelDetailState) {
    let star_span = bool_span("yes", "no", state.channel.star, theme);
    let connected_span = bool_span("yes", "no", state.channel.connected, theme);

    let last_sync = last_sync_cell(
        state.channel.syncing,
        state.channel.last_synced_at.as_deref(),
    );

    // Action label describes the OPPOSITE of the current state — the action
    // pressing the key will perform. Only `Starred` carries an inline action;
    // `Connected` is OAuth-managed and read-only here.
    let star_action_label = if state.channel.star { "unstar" } else { "star" };

    let id_str = state.channel.id.to_string();
    let tenant_str = state.channel.tenant_id.to_string();
    let lines = vec![
        kv_line("ID", &id_str, theme),
        kv_line("Tenant", &tenant_str, theme),
        kv_line("URL", &state.channel.channel_url, theme),
        kv_line_span_action("Starred", star_span, "s", star_action_label, theme),
        kv_line_span("Connected", connected_span, theme),
        kv_line("Last sync", &last_sync, theme),
    ];
    frame.render_widget(Paragraph::new(lines), area);
}

fn render_video_table(frame: &mut Frame, area: Rect, theme: &Theme, state: &ChannelDetailState) {
    if area.height < 2 {
        return;
    }

    let mut lines: Vec<Line> = Vec::new();

    lines.push(Line::from(Span::styled(
        format!("  videos ({})", state.videos.len()),
        Style::default().fg(theme.fg),
    )));

    lines.push(Line::from(vec![
        Span::styled("  ", Style::default().fg(theme.muted)),
        Span::styled(
            format!(
                "{:<22} {:>7} {:>6} {:<5} {:<11} {:>6}",
                "title", "views", "likes", "state", "date", "length"
            ),
            Style::default().fg(theme.muted),
        ),
    ]));

    lines.push(Line::from(Span::styled(
        format!("  {}", "─".repeat(60)),
        Style::default().fg(theme.border),
    )));

    let visible_rows = (area.height as usize).saturating_sub(3);
    let end = (state.video_scroll + visible_rows).min(state.videos.len());
    for (i, video) in state.videos[state.video_scroll..end].iter().enumerate() {
        let idx = state.video_scroll + i;
        let is_selected = idx == state.video_selected;

        let title_truncated = truncate_str(&video.title, 22);
        let duration = format_duration(video.duration_seconds);
        let privacy = abbreviate_privacy(&video.privacy_status);

        let row_text = format!(
            "{:<22} {:>7} {:>6} {:<5} {:<11} {:>6}",
            title_truncated,
            format_number(video.views),
            format_number(video.likes),
            privacy,
            &video.published_at,
            duration,
        );

        let style = if is_selected {
            Style::default().fg(theme.accent)
        } else {
            Style::default().fg(theme.fg)
        };

        let prefix = if is_selected { "> " } else { "  " };
        lines.push(Line::from(Span::styled(
            format!("{}{}", prefix, row_text),
            style,
        )));
    }

    frame.render_widget(Paragraph::new(lines), area);
}

fn kv_line<'a>(key: &'a str, value: &'a str, theme: &Theme) -> Line<'a> {
    Line::from(vec![
        Span::styled(format!("  {:<14} ", key), Style::default().fg(theme.muted)),
        Span::styled(value, Style::default().fg(theme.fg)),
    ])
}

/// KV row that takes a pre-styled value span and renders no inline action
/// hint. Used for read-only fields (e.g. `Connected`, which is OAuth-managed
/// and cannot be toggled from pito).
fn kv_line_span<'a>(key: &'a str, value: Span<'a>, theme: &Theme) -> Line<'a> {
    Line::from(vec![
        Span::styled(format!("  {:<14} ", key), Style::default().fg(theme.muted)),
        value,
    ])
}

/// KV row that appends an inline action hint after the value, e.g.
/// `Starred    no    [s] star`. The hint shows the OPPOSITE of the current
/// state — what pressing the key will do.
fn kv_line_span_action<'a>(
    key: &'a str,
    value: Span<'a>,
    keystroke: &'a str,
    action_label: &'a str,
    theme: &Theme,
) -> Line<'a> {
    Line::from(vec![
        Span::styled(format!("  {:<14} ", key), Style::default().fg(theme.muted)),
        value,
        Span::raw("    "),
        Span::styled(format!("[{}]", keystroke), Style::default().fg(theme.accent)),
        Span::raw(" "),
        Span::styled(action_label, Style::default().fg(theme.muted)),
    ])
}

fn bool_span<'a>(yes: &'a str, no: &'a str, val: bool, theme: &Theme) -> Span<'a> {
    if val {
        Span::styled(yes, Style::default().fg(theme.success))
    } else {
        Span::styled(no, Style::default().fg(theme.muted))
    }
}

fn format_number(n: u64) -> String {
    if n == 0 {
        return "0".to_string();
    }
    let s = n.to_string();
    let mut result = String::new();
    for (i, ch) in s.chars().rev().enumerate() {
        if i > 0 && i % 3 == 0 {
            result.push(',');
        }
        result.push(ch);
    }
    result.chars().rev().collect()
}

fn format_duration(seconds: u32) -> String {
    let m = seconds / 60;
    let s = seconds % 60;
    format!("{:02}:{:02}", m, s)
}

fn truncate_str(s: &str, max: usize) -> String {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() <= max {
        s.to_string()
    } else if max <= 3 {
        chars.iter().take(max).collect()
    } else {
        let prefix: String = chars.iter().take(max - 3).collect();
        format!("{}...", prefix)
    }
}

fn abbreviate_privacy(status: &str) -> &str {
    match status {
        "public" => "pub",
        "private" => "priv",
        "unlisted" => "unl",
        _ => status,
    }
}

/// Strip the `https://youtube.com/` prefix when present, otherwise return the URL as-is.
pub fn short_url(url: &str) -> String {
    let prefixes = [
        "https://www.youtube.com/",
        "https://youtube.com/",
        "http://www.youtube.com/",
        "http://youtube.com/",
    ];
    for p in prefixes {
        if let Some(rest) = url.strip_prefix(p) {
            return rest.to_string();
        }
    }
    url.to_string()
}

/// Open a URL in the platform-default browser. Returns Err on failure.
pub fn open_in_browser(url: &str) -> std::io::Result<()> {
    open::that(url)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn short_url_strips_known_prefixes() {
        assert_eq!(
            short_url("https://youtube.com/@example"),
            "@example".to_string()
        );
        assert_eq!(
            short_url("https://www.youtube.com/@example"),
            "@example".to_string()
        );
        assert_eq!(
            short_url("ftp://example.com/x"),
            "ftp://example.com/x".to_string()
        );
    }
}
