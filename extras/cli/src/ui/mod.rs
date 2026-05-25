use ratatui::{
    Frame,
    layout::Rect,
    style::Style,
    text::{Line, Span},
    widgets::{Block, Paragraph},
};

pub mod footage_detail;

use crate::app::App;
use crate::api::client::PitoClient;

const SIDEBAR_WIDTH: u16 = 36;

pub fn render<C: PitoClient>(frame: &mut Frame, app: &mut App<C>) {
    let theme = app.theme();

    // Full-screen background
    frame.render_widget(
        Block::default().style(Style::default().bg(theme.bg)),
        frame.area(),
    );

    let area = frame.area();
    let cols = area.width;
    let rows = area.height;

    // ── Layout zones ───────────────────────────────────────────
    // header (1) | main+sidebar | input (1) | status (1)
    let header_area = Rect::new(area.x, area.y, cols, 1);
    let body_start = area.y + 1;
    let body_height = rows.saturating_sub(3);
    let input_y = body_start + body_height;
    let status_y = input_y + 1;

    let main_width = if app.sidebar_open {
        cols.saturating_sub(SIDEBAR_WIDTH + 1)
    } else {
        cols
    };
    let sidebar_x = area.x + main_width + 1;

    // ── Header ─────────────────────────────────────────────────
    let header_bg = Style::default().bg(theme.bg).fg(theme.fg);
    let mut spans: Vec<Span> = Vec::new();
    if app.channels.is_empty() {
        spans.push(Span::styled("no channels connected", Style::default().fg(theme.muted)));
    } else {
        for ch in &app.channels {
            spans.push(Span::styled(format!("@{} ", ch.channel_url), Style::default().fg(theme.accent)));
        }
    }
    let right = Span::styled("pito", Style::default().fg(theme.muted));
    let left_width: u16 = spans.iter().map(|s| s.width() as u16).sum();
    let right_width: u16 = right.width() as u16;
    let pad = cols.saturating_sub(left_width + right_width);
    spans.push(Span::raw(" ".repeat(pad as usize)));
    spans.push(right);
    frame.render_widget(Paragraph::new(Line::from(spans)).style(header_bg), header_area);

    // ── Main area ──────────────────────────────────────────────
    let main_area = Rect::new(area.x, body_start, main_width, body_height);
    let visible_lines: Vec<&str> = app.conversation_lines.iter()
        .rev()
        .take(body_height as usize)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .map(|s| s.as_str())
        .collect();

    let mut main_spans: Vec<Line> = Vec::new();
    for line in &visible_lines {
        main_spans.push(Line::from(Span::styled(*line, Style::default().fg(theme.fg))));
    }
    while main_spans.len() < body_height as usize {
        main_spans.push(Line::from(""));
    }
    frame.render_widget(
        Paragraph::new(main_spans).style(Style::default().bg(theme.bg).fg(theme.fg)),
        main_area,
    );

    // ── Sidebar divider ────────────────────────────────────────
    if app.sidebar_open && cols > SIDEBAR_WIDTH {
        let divider_x = sidebar_x.saturating_sub(1);
        let divider_area = Rect::new(divider_x, body_start, 1, body_height);
        frame.render_widget(
            Block::default().style(Style::default().bg(theme.border)),
            divider_area,
        );
    }

    // ── Sidebar ────────────────────────────────────────────────
    if app.sidebar_open && cols > SIDEBAR_WIDTH {
        let sidebar_area = Rect::new(sidebar_x, body_start, SIDEBAR_WIDTH.min(cols - sidebar_x), body_height);
        let mut sb_lines: Vec<Line> = Vec::new();
        let a = Style::default().fg(theme.accent);
        let m = Style::default().fg(theme.muted);

        sb_lines.push(Line::from(Span::styled("channels", a)));
        if app.channels.is_empty() {
            sb_lines.push(Line::from(Span::styled("  (none)", m)));
        } else {
            for ch in app.channels.iter().take(6) {
                sb_lines.push(Line::from(Span::styled(format!("  @{}", ch.channel_url), m)));
            }
        }
        sb_lines.push(Line::from(""));
        sb_lines.push(Line::from(Span::styled("videos", a)));
        sb_lines.push(Line::from(Span::styled("  (use /videos)", m)));
        sb_lines.push(Line::from(""));
        sb_lines.push(Line::from(Span::styled("games", a)));
        sb_lines.push(Line::from(Span::styled("  (use /games)", m)));

        while sb_lines.len() < body_height as usize {
            sb_lines.push(Line::from(""));
        }
        frame.render_widget(
            Paragraph::new(sb_lines).style(Style::default().bg(theme.bg).fg(theme.fg)),
            sidebar_area,
        );
    }

    // ── Input line ─────────────────────────────────────────────
    let input_area = Rect::new(area.x, input_y, cols, 1);
    let prompt = Span::styled("> ", Style::default().fg(theme.accent));
    let input_text = Span::styled(&app.input_buffer, Style::default().fg(theme.fg));
    frame.render_widget(
        Paragraph::new(Line::from(vec![prompt, input_text]))
            .style(Style::default().bg(theme.bg).fg(theme.fg)),
        input_area,
    );

    // ── Status bar ─────────────────────────────────────────────
    let status_area = Rect::new(area.x, status_y, cols, 1);

    // Time tick + scramble before immutable borrow
    let now_str = app.scrambled_time();

    let sd = &app.status_data;
    let conn_fg = if sd.connected { theme.success } else { theme.danger };
    let mut st = vec![Span::styled("connected", Style::default().fg(conn_fg))];
    let mut right: Vec<Span> = Vec::new();
    right.push(Span::styled("Sidekiq", Style::default().fg(theme.muted)));
    right.push(Span::raw(" "));
    right.push(Span::styled(format!("b{}", sd.sidekiq_busy), Style::default().fg(if sd.sidekiq_busy > 0 { theme.success } else { theme.muted })));
    right.push(Span::raw(" "));
    right.push(Span::styled(format!("e{}", sd.sidekiq_enqueued), Style::default().fg(if sd.sidekiq_enqueued > 0 { theme.orange } else { theme.muted })));
    right.push(Span::raw(" "));
    right.push(Span::styled(format!("r{}", sd.sidekiq_retry), Style::default().fg(if sd.sidekiq_retry > 0 { theme.danger } else { theme.muted })));
    right.push(Span::raw(" "));
    right.push(Span::styled(format!("d{}", sd.sidekiq_dead), Style::default().fg(if sd.sidekiq_dead > 0 { theme.purple } else { theme.muted })));
    right.push(Span::styled(" · ", Style::default().fg(theme.muted)));
    right.push(Span::styled(now_str, Style::default().fg(theme.cyan)));

    // Right-align: push enough padding to push content to the right edge
    let right_w: u16 = right.iter().map(|s| s.width() as u16).sum();
    let left_w: u16 = st.iter().map(|s| s.width() as u16).sum();
    let pad = cols.saturating_sub(left_w + right_w);
    st.push(Span::raw(" ".repeat(pad as usize)));
    st.extend(right);

    frame.render_widget(
        Paragraph::new(Line::from(st))
            .style(Style::default().bg(theme.bg).fg(theme.fg)),
        status_area,
    );
}
