use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph},
};

use crate::theme::Theme;

pub struct SearchState {
    pub query: String,
    pub cursor_pos: usize,
    pub results: Option<SearchResultsData>,
    /// Section selector for the search overlay. Currently only `Videos`; kept
    /// for the upcoming multi-section search (channels + saved views).
    #[allow(dead_code)]
    pub selected_section: SearchSection,
    pub selected_row: usize,
}

pub struct SearchResultsData {
    pub videos: Vec<SearchVideoHit>,
    pub video_total: u64,
    pub took_ms: f64,
}

pub struct SearchVideoHit {
    /// Reserved for upcoming row-click navigation (Enter opens the video).
    #[allow(dead_code)]
    pub id: u64,
    pub title: String,
    pub channel_id: u64,
    pub channel_url: Option<String>,
    pub privacy_status: String,
    pub duration_seconds: u32,
}

/// Section selector. The Channels branch was dropped (see channel-revamp spec)
/// but the enum is preserved as a single-variant `Videos` to keep wiring trivial.
#[derive(Clone, Copy, PartialEq)]
pub enum SearchSection {
    Videos,
}

pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, state: &SearchState) {
    let popup = centered_rect(80, 70, area);

    frame.render_widget(Clear, popup);

    let block = Block::default()
        .title(" search ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.accent))
        .style(Style::default().bg(theme.bg));

    let inner = block.inner(popup);
    frame.render_widget(block, popup);

    let layout = Layout::vertical([
        Constraint::Length(1), // input line
        Constraint::Length(1), // spacer
        Constraint::Length(1), // results summary
        Constraint::Length(1), // spacer
        Constraint::Min(0),    // results body
    ])
    .split(inner);

    render_input(frame, layout[0], theme, state);

    if let Some(ref results) = state.results {
        let summary = Line::from(vec![
            Span::styled("  results for ", Style::default().fg(theme.muted)),
            Span::styled(format!("\"{}\"", state.query), Style::default().fg(theme.fg)),
            Span::styled(
                format!(
                    " — {} video{} ({:.0}ms)",
                    results.video_total,
                    if results.video_total == 1 { "" } else { "s" },
                    results.took_ms,
                ),
                Style::default().fg(theme.muted),
            ),
        ]);
        frame.render_widget(Paragraph::new(summary), layout[2]);
    }

    if let Some(ref results) = state.results {
        render_results(frame, layout[4], theme, state, results);
    }
}

fn render_input(frame: &mut Frame, area: Rect, theme: &Theme, state: &SearchState) {
    let char_pos = state.cursor_pos.min(state.query.chars().count());
    let before_cursor: String = state.query.chars().take(char_pos).collect();
    let after_cursor: String = state.query.chars().skip(char_pos).collect();

    let cursor_char: String = if char_pos < state.query.chars().count() {
        after_cursor.chars().take(1).collect()
    } else {
        "_".to_string()
    };

    let after_cursor_rest: String = if char_pos < state.query.chars().count() {
        after_cursor.chars().skip(1).collect()
    } else {
        String::new()
    };

    let line = Line::from(vec![
        Span::styled("  / ", Style::default().fg(theme.accent)),
        Span::styled(before_cursor, Style::default().fg(theme.fg)),
        Span::styled(cursor_char, Style::default().fg(theme.bg).bg(theme.fg)),
        Span::styled(after_cursor_rest, Style::default().fg(theme.fg)),
    ]);
    frame.render_widget(Paragraph::new(line), area);
}

fn render_results(
    frame: &mut Frame,
    area: Rect,
    theme: &Theme,
    state: &SearchState,
    results: &SearchResultsData,
) {
    let mut lines: Vec<Line> = Vec::new();

    lines.push(Line::from(Span::styled(
        "  videos",
        Style::default().fg(theme.accent),
    )));

    lines.push(Line::from(vec![
        Span::styled("  ", Style::default().fg(theme.muted)),
        Span::styled(
            format!(
                "{:<24} {:<20} {:<6} {:>6}",
                "title", "channel", "state", "length"
            ),
            Style::default().fg(theme.muted),
        ),
    ]));

    lines.push(Line::from(Span::styled(
        format!("  {}", "─".repeat(60)),
        Style::default().fg(theme.border),
    )));

    for (i, video) in results.videos.iter().enumerate() {
        let is_selected = i == state.selected_row;
        let title_truncated = truncate_str(&video.title, 24);
        let channel_label = video
            .channel_url
            .as_deref()
            .map(crate::ui::channel_detail::short_url)
            .unwrap_or_else(|| format!("#{}", video.channel_id));
        let channel_truncated = truncate_str(&channel_label, 20);
        let privacy = abbreviate_privacy(&video.privacy_status);
        let duration = format_duration(video.duration_seconds);

        let row_text = format!(
            "{:<24} {:<20} {:<6} {:>6}",
            title_truncated, channel_truncated, privacy, duration,
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

fn centered_rect(percent_x: u16, percent_y: u16, area: Rect) -> Rect {
    let popup_layout = Layout::vertical([
        Constraint::Percentage((100 - percent_y) / 2),
        Constraint::Percentage(percent_y),
        Constraint::Percentage((100 - percent_y) / 2),
    ])
    .split(area);

    Layout::horizontal([
        Constraint::Percentage((100 - percent_x) / 2),
        Constraint::Percentage(percent_x),
        Constraint::Percentage((100 - percent_x) / 2),
    ])
    .split(popup_layout[1])[1]
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
