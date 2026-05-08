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
    pub last_synced_at: Option<String>,
}

/// Per-video row on the channel detail screen. Path A2 retract: Video has no
/// title / privacy / duration / published metadata anymore, so the row shows
/// the youtube id, the star marker, and the surviving counts.
pub struct ChannelVideoRow {
    /// Reserved for upcoming row-click navigation (Enter opens video detail).
    #[allow(dead_code)]
    pub id: u64,
    pub youtube_video_id: String,
    pub star: bool,
    pub views: u64,
    pub likes: u64,
    pub comments: u64,
    pub last_synced_at: Option<String>,
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

    // Actions row. Mirrors the Rails breadcrumb-actions row at the top of
    // `channels/show.html.erb` — only the bracketed action links live up here.
    // `(s) star` is intentionally NOT in the keystroke hint legend: the
    // star/unstar action is exposed inline next to the `Starred` KV row
    // below, so duplicating it at the top is noise. `connected` is also
    // omitted because it's OAuth-managed and only the web UI can toggle it.
    let actions = Line::from(vec![
        Span::raw("  "),
        Span::styled("[view]", Style::default().fg(theme.accent)),
        Span::raw(" "),
        Span::styled("[sync]", Style::default().fg(theme.accent)),
        Span::raw(" "),
        Span::styled("[delete]", Style::default().fg(theme.danger)),
        Span::raw("    "),
        Span::styled(
            "(v) view  (Y) sync  (D) delete",
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

    // Path A2 retract: there's no in-flight `syncing` flag from the wire any
    // more, so the cell is just the relative time.
    let last_sync = last_sync_cell(state.channel.last_synced_at.as_deref());

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
                "{:<14} {:<3} {:>8} {:>7} {:>7} {:<11}",
                "youtube id", "★", "views", "likes", "chats", "last sync"
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

        let yt_truncated = truncate_str(&video.youtube_video_id, 14);
        let star_marker = if video.star { "★" } else { " " };
        let last_sync = last_sync_cell(video.last_synced_at.as_deref());

        let row_text = format!(
            "{:<14} {:<3} {:>8} {:>7} {:>7} {:<11}",
            yt_truncated,
            star_marker,
            format_number(video.views),
            format_number(video.likes),
            format_number(video.comments),
            last_sync,
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
        Span::styled(
            format!("[{}]", keystroke),
            Style::default().fg(theme.accent),
        ),
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
    use crate::theme::{Theme, ThemeMode};
    use ratatui::{Terminal, backend::TestBackend};

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

    fn sample_state() -> ChannelDetailState {
        ChannelDetailState {
            channel: ChannelInfo {
                id: 7,
                tenant_id: 1,
                channel_url: "https://youtube.com/@sample".to_string(),
                star: false,
                connected: false,
                last_synced_at: None,
            },
            videos: vec![],
            video_selected: 0,
            video_scroll: 0,
            flash: None,
        }
    }

    /// Render the channel detail screen and capture the rendered text. Used by
    /// the layout-parity tests below to assert presence/absence of specific
    /// substrings in the action legend.
    fn render_to_string(state: &ChannelDetailState) -> String {
        let theme = Theme::from_mode(ThemeMode::Dark);
        let backend = TestBackend::new(120, 20);
        let mut terminal = Terminal::new(backend).expect("test backend");
        terminal
            .draw(|frame| {
                render(frame, frame.area(), &theme, state);
            })
            .expect("draw");
        let buf = terminal.backend().buffer().clone();
        let mut rendered = String::new();
        for y in 0..buf.area.height {
            for x in 0..buf.area.width {
                rendered.push_str(buf[(x, y)].symbol());
            }
            rendered.push('\n');
        }
        rendered
    }

    #[test]
    fn action_legend_omits_star_keystroke_hint() {
        // Layout-parity sweep (Phase 7.5): the top action legend mirrors the
        // Rails breadcrumb-actions row, which only renders bracketed action
        // links. The `(s) star` hint at the top was redundant — star/unstar
        // is exposed inline next to the `Starred` KV row below — so it was
        // removed during the parity sweep.
        let rendered = render_to_string(&sample_state());
        assert!(
            !rendered.contains("(s) star"),
            "(s) star keystroke hint must not appear at the top of channel detail; got:\n{}",
            rendered
        );
        // The remaining keystroke hints stay so users can still discover the
        // top-level actions.
        assert!(
            rendered.contains("(v) view"),
            "(v) view hint should remain, got:\n{}",
            rendered
        );
        assert!(
            rendered.contains("(Y) sync"),
            "(Y) sync hint should remain, got:\n{}",
            rendered
        );
        assert!(
            rendered.contains("(D) delete"),
            "(D) delete hint should remain, got:\n{}",
            rendered
        );
    }

    #[test]
    fn action_legend_keeps_bracketed_action_labels() {
        // The bracketed `[view] [sync] [delete]` labels remain — they are the
        // CLI's analog to the Rails breadcrumb's `[e] [sync] [-]` action row.
        let rendered = render_to_string(&sample_state());
        for label in ["[view]", "[sync]", "[delete]"] {
            assert!(
                rendered.contains(label),
                "expected bracketed action label {} to remain in legend, got:\n{}",
                label,
                rendered
            );
        }
    }
}
