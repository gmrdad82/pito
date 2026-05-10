use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
};

use crate::theme::Theme;

// --- Data types ---

pub struct VideosState {
    pub videos: Vec<VideoRow>,
    pub selected: usize,
    pub selected_ids: Vec<u64>,
    /// Sorting feature stub — kept for the upcoming column-header sort flow.
    #[allow(dead_code)]
    pub sort_column: usize,
    /// Sorting feature stub — kept for the upcoming column-header sort flow.
    #[allow(dead_code)]
    pub sort_direction: SortDirection,
    pub scroll_offset: usize,
}

/// Path A2 retract: VideoRow lost the title / privacy / published / duration
/// columns when those fields left the wire. The row now identifies the video
/// by `youtube_video_id`, with a star marker and the surviving counts.
pub struct VideoRow {
    pub id: u64,
    pub youtube_video_id: String,
    /// The channel id this video belongs to (matches saved-views convention).
    pub channel_id: u64,
    pub star: bool,
    pub views: u64,
    pub trend: String,
    pub likes: u64,
    pub comments: u64,
    pub watch_time_minutes: f64,
}

#[derive(Clone, Copy)]
#[allow(dead_code)]
pub enum SortDirection {
    Asc,
    Desc,
}

// --- Formatting helpers ---

pub fn format_number(n: u64) -> String {
    if n == 0 {
        return "0".to_string();
    }
    let s = n.to_string();
    let mut result = String::with_capacity(s.len() + s.len() / 3);
    for (i, ch) in s.chars().rev().enumerate() {
        if i > 0 && i % 3 == 0 {
            result.push(',');
        }
        result.push(ch);
    }
    result.chars().rev().collect()
}

pub fn format_watch_time(minutes: f64) -> String {
    let total_minutes = minutes.round() as u64;
    let hours = total_minutes / 60;
    let mins = total_minutes % 60;
    format!("{}h{:02}m", hours, mins)
}

fn trend_indicator(trend: &str) -> &str {
    match trend {
        "up" => "▲",
        "down" => "▼",
        _ => "—",
    }
}

// --- Column widths ---

struct Columns {
    youtube_id: u16,
    channel: u16,
    star: u16,
    views: u16,
    trend: u16,
    likes: u16,
    comments: u16,
    watch: u16,
}

impl Columns {
    fn compute(width: u16) -> Self {
        // Checkboxes are always rendered, so the prefix column is always 4
        // cols wide ("[ ] " / "[x] ").
        let prefix = 4;
        let star = 3;
        let views = 8;
        let trend = 3;
        let likes = 8;
        let comments = 8;
        let watch = 6;
        let fixed = star + views + trend + likes + comments + watch;
        let remaining = width.saturating_sub(prefix + fixed + 2); // 2 for border padding
        let channel = remaining.clamp(8, 16);
        let youtube_id = remaining.saturating_sub(channel);

        Self {
            youtube_id,
            channel,
            star,
            views,
            trend,
            likes,
            comments,
            watch,
        }
    }
}

// --- Render ---

pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, state: &VideosState) {
    let block = Block::default()
        .title(Span::styled(" videos ", Style::default().fg(theme.fg)))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.border));

    let inner = block.inner(area);
    frame.render_widget(block, area);

    if inner.height < 3 || inner.width < 20 {
        return;
    }

    let layout = Layout::vertical([
        Constraint::Length(1), // toolbar
        Constraint::Length(1), // spacer
        Constraint::Length(1), // header
        Constraint::Length(1), // separator
        Constraint::Min(0),    // rows
    ])
    .split(inner);

    render_toolbar(frame, layout[0], theme, state);
    render_table_header(frame, layout[2], theme, state, inner.width);
    render_separator(frame, layout[3], theme, inner.width);
    render_rows(frame, layout[4], theme, state, inner.width);
}

fn render_toolbar(frame: &mut Frame, area: Rect, theme: &Theme, state: &VideosState) {
    let count = format!("{} videos total", state.videos.len());
    let right_len = count.len() as u16;
    let left_width = area.width.saturating_sub(right_len + 1);

    let line = Line::from(vec![
        Span::styled("[add]", Style::default().fg(theme.accent)),
        Span::raw(" "),
        Span::styled("[bulk]", Style::default().fg(theme.accent)),
        Span::raw(" "),
        Span::styled("[saved views]", Style::default().fg(theme.accent)),
        Span::raw(" ".repeat((left_width.saturating_sub(28)) as usize)),
        Span::styled(count, Style::default().fg(theme.muted)),
    ]);

    frame.render_widget(Paragraph::new(line), area);
}

fn render_table_header(
    frame: &mut Frame,
    area: Rect,
    theme: &Theme,
    _state: &VideosState,
    width: u16,
) {
    let cols = Columns::compute(width);
    let style = Style::default().fg(theme.muted);

    // Checkboxes are always rendered, so the prefix column is always 4 cols
    // wide ("[ ] " / "[x] ").
    let spans: Vec<Span> = vec![
        Span::styled("    ", style),
        Span::styled(pad_right("YouTube id", cols.youtube_id), style),
        Span::styled(pad_right("channel", cols.channel), style),
        Span::styled(pad_center("★", cols.star), style),
        Span::styled(pad_left("views", cols.views), style),
        Span::styled(pad_center("trend", cols.trend), style),
        Span::styled(pad_left("likes", cols.likes), style),
        Span::styled(pad_left("chats", cols.comments), style),
        Span::styled(pad_left("watch", cols.watch), style),
    ];

    frame.render_widget(Paragraph::new(Line::from(spans)), area);
}

fn render_separator(frame: &mut Frame, area: Rect, theme: &Theme, width: u16) {
    let line = Line::from(Span::styled(
        "─".repeat(width as usize),
        Style::default().fg(theme.border),
    ));
    frame.render_widget(Paragraph::new(line), area);
}

fn render_rows(frame: &mut Frame, area: Rect, theme: &Theme, state: &VideosState, width: u16) {
    let cols = Columns::compute(width);
    let visible_count = area.height as usize;

    for i in 0..visible_count {
        let idx = state.scroll_offset + i;
        if idx >= state.videos.len() {
            break;
        }

        let video = &state.videos[idx];
        let is_selected = idx == state.selected;
        let is_checked = state.selected_ids.contains(&video.id);

        let row_style = if is_selected {
            Style::default().fg(theme.fg).bg(theme.border)
        } else {
            Style::default().fg(theme.fg)
        };

        let mut spans: Vec<Span> = Vec::new();

        // Prefix: always-on checkbox. Cursor position is conveyed by the row
        // highlight (background color); selection state by the `[ ]` / `[x]`
        // marker. Mirrors the web side's always-on checkbox UX.
        let check = if is_checked { "[x] " } else { "[ ] " };
        spans.push(Span::styled(check, row_style));

        // Youtube id (truncated)
        let yt = truncate(&video.youtube_video_id, cols.youtube_id as usize);
        spans.push(Span::styled(pad_right(&yt, cols.youtube_id), row_style));

        // Channel id (matches saved-view convention; full URL lives on channel detail)
        let channel = format!("#{}", video.channel_id);
        spans.push(Span::styled(
            pad_right(&truncate(&channel, cols.channel as usize), cols.channel),
            row_style,
        ));

        // Star marker
        let star_marker = if video.star { "★" } else { " " };
        let star_style = if video.star {
            Style::default()
                .fg(theme.orange)
                .bg(if is_selected { theme.border } else { theme.bg })
        } else {
            row_style
        };
        spans.push(Span::styled(pad_center(star_marker, cols.star), star_style));

        // Views (right-aligned)
        spans.push(Span::styled(
            pad_left(&format_number(video.views), cols.views),
            row_style,
        ));

        // Trend indicator
        let trend_str = trend_indicator(&video.trend);
        let trend_style = match video.trend.as_str() {
            "up" => Style::default().fg(theme.success).bg(if is_selected {
                theme.border
            } else {
                theme.bg
            }),
            _ => Style::default().fg(theme.muted).bg(if is_selected {
                theme.border
            } else {
                theme.bg
            }),
        };
        spans.push(Span::styled(pad_center(trend_str, cols.trend), trend_style));

        // Likes
        spans.push(Span::styled(
            pad_left(&format_number(video.likes), cols.likes),
            row_style,
        ));

        // Comments
        spans.push(Span::styled(
            pad_left(&format_number(video.comments), cols.comments),
            row_style,
        ));

        // Watch time
        spans.push(Span::styled(
            pad_left(&format_watch_time(video.watch_time_minutes), cols.watch),
            row_style,
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

// --- String padding helpers ---

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
