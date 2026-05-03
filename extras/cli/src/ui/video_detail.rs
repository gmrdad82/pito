use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

use crate::theme::Theme;

// --- Data types ---

pub struct VideoDetailState {
    pub video: VideoInfo,
    pub stats: Vec<StatRow>,
    pub stats_selected: usize,
    pub stats_scroll: usize,
}

pub struct VideoInfo {
    /// Reserved for upcoming row-click navigation (e.g. delete from detail).
    #[allow(dead_code)]
    pub id: u64,
    pub youtube_video_id: String,
    pub title: String,
    pub channel_id: u64,
    pub channel_url: Option<String>,
    pub privacy_status: String,
    pub published_at: String,
    pub duration_seconds: u32,
    pub description: Option<String>,
}

pub struct StatRow {
    pub date: String,
    pub views: u64,
    pub likes: u64,
    pub comments: u64,
    pub watch_time_minutes: f64,
}

// --- Formatting helpers (re-exported from videos module or duplicated for independence) ---

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
    format!("{}h{:02}", hours, mins)
}

pub fn format_duration(seconds: u32) -> String {
    let mins = seconds / 60;
    let secs = seconds % 60;
    format!("{}:{:02}", mins, secs)
}

// --- Render ---

pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, state: &VideoDetailState) {
    let title = format!(" videos › {} ", state.video.title);
    let block = Block::default()
        .title(Span::styled(title, Style::default().fg(theme.fg)))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.border));

    let inner = block.inner(area);
    frame.render_widget(block, area);

    if inner.height < 5 || inner.width < 20 {
        return;
    }

    let layout = Layout::vertical([
        Constraint::Length(1), // toolbar
        Constraint::Length(1), // spacer
        Constraint::Length(7), // metadata key/value pairs
        Constraint::Length(1), // spacer
        Constraint::Length(1), // stats header label
        Constraint::Length(1), // stats table header
        Constraint::Length(1), // separator
        Constraint::Min(0),   // stats rows
    ])
    .split(inner);

    render_toolbar(frame, layout[0], theme);
    render_metadata(frame, layout[2], theme, state);
    render_stats_label(frame, layout[4], theme);
    render_stats_header(frame, layout[5], theme);
    render_stats_separator(frame, layout[6], theme, inner.width);
    render_stats_rows(frame, layout[7], theme, state);
}

fn render_toolbar(frame: &mut Frame, area: Rect, theme: &Theme) {
    let line = Line::from(vec![
        Span::styled("[edit]", Style::default().fg(theme.accent)),
        Span::raw(" "),
        Span::styled("[delete]", Style::default().fg(theme.danger)),
    ]);
    frame.render_widget(Paragraph::new(line), area);
}

fn render_metadata(frame: &mut Frame, area: Rect, theme: &Theme, state: &VideoDetailState) {
    let video = &state.video;
    let key_style = Style::default().fg(theme.muted);
    let val_style = Style::default().fg(theme.fg);

    let key_width = 14;

    let description = video
        .description
        .as_deref()
        .unwrap_or("—");
    let desc_truncated = if description.chars().count() > (area.width as usize).saturating_sub(key_width + 2) {
        let max = (area.width as usize).saturating_sub(key_width + 5);
        format!("{}...", description.chars().take(max).collect::<String>())
    } else {
        description.to_string()
    };

    let duration_str = format_duration(video.duration_seconds);
    let channel_label = video
        .channel_url
        .as_deref()
        .map(crate::ui::channel_detail::short_url)
        .unwrap_or_else(|| format!("#{}", video.channel_id));
    let rows: Vec<Line> = vec![
        make_kv_line("youtube id", &video.youtube_video_id, key_width, key_style, val_style),
        make_kv_line("channel", &channel_label, key_width, key_style, val_style),
        make_kv_line("privacy", &video.privacy_status, key_width, key_style, val_style),
        make_kv_line("published", &video.published_at, key_width, key_style, val_style),
        make_kv_line("duration", &duration_str, key_width, key_style, val_style),
        make_kv_line("description", &desc_truncated, key_width, key_style, val_style),
    ];

    let paragraph = Paragraph::new(rows);
    frame.render_widget(paragraph, area);
}

fn make_kv_line<'a>(
    key: &'a str,
    value: &'a str,
    key_width: usize,
    key_style: Style,
    val_style: Style,
) -> Line<'a> {
    Line::from(vec![
        Span::styled(format!("{:<width$}", key, width = key_width), key_style),
        Span::styled(value.to_string(), val_style),
    ])
}

fn render_stats_label(frame: &mut Frame, area: Rect, theme: &Theme) {
    let line = Line::from(Span::styled(
        "recent stats (30 days)",
        Style::default().fg(theme.fg),
    ));
    frame.render_widget(Paragraph::new(line), area);
}

fn render_stats_header(frame: &mut Frame, area: Rect, theme: &Theme) {
    let style = Style::default().fg(theme.muted);
    let line = Line::from(vec![
        Span::styled(format!("{:<12}", "date"), style),
        Span::styled(format!("{:>8}", "views"), style),
        Span::styled(format!("{:>8}", "likes"), style),
        Span::styled(format!("{:>8}", "chats"), style),
        Span::styled(format!("{:>8}", "watch"), style),
    ]);
    frame.render_widget(Paragraph::new(line), area);
}

fn render_stats_separator(frame: &mut Frame, area: Rect, theme: &Theme, width: u16) {
    let sep_width = 44.min(width as usize);
    let line = Line::from(Span::styled(
        "─".repeat(sep_width),
        Style::default().fg(theme.border),
    ));
    frame.render_widget(Paragraph::new(line), area);
}

fn render_stats_rows(frame: &mut Frame, area: Rect, theme: &Theme, state: &VideoDetailState) {
    let visible_count = area.height as usize;

    for i in 0..visible_count {
        let idx = state.stats_scroll + i;
        if idx >= state.stats.len() {
            break;
        }

        let stat = &state.stats[idx];
        let is_selected = idx == state.stats_selected;

        let row_style = if is_selected {
            Style::default().fg(theme.fg).bg(theme.border)
        } else {
            Style::default().fg(theme.fg)
        };

        let line = Line::from(vec![
            Span::styled(format!("{:<12}", stat.date), row_style),
            Span::styled(format!("{:>8}", format_number(stat.views)), row_style),
            Span::styled(format!("{:>8}", format_number(stat.likes)), row_style),
            Span::styled(format!("{:>8}", format_number(stat.comments)), row_style),
            Span::styled(format!("{:>8}", format_watch_time(stat.watch_time_minutes)), row_style),
        ]);

        let row_area = Rect {
            x: area.x,
            y: area.y + i as u16,
            width: area.width,
            height: 1,
        };
        frame.render_widget(Paragraph::new(line), row_area);
    }
}
