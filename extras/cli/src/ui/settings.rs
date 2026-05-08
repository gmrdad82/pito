use ratatui::{
    Frame,
    layout::Rect,
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
};

use crate::theme::Theme;

pub struct SettingsState {
    pub max_panes: u32,
    pub pane_title_length: u32,
    pub theme: String,
    pub search_engine: String,
    pub search_connected: bool,
}

pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, state: &SettingsState) {
    let block = Block::default()
        .title(" settings ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.border));

    let inner = block.inner(area);
    frame.render_widget(block, area);

    let search_status = if state.search_connected {
        Span::styled("▲ connected", Style::default().fg(theme.success))
    } else {
        Span::styled("▼ disconnected", Style::default().fg(theme.danger))
    };

    let max_panes_str = state.max_panes.to_string();
    let pane_title_str = state.pane_title_length.to_string();
    let lines = vec![
        Line::from(""),
        section_header("workspaces", theme),
        kv_line("max panes", &max_panes_str, theme),
        kv_line("pane title length", &pane_title_str, theme),
        Line::from(""),
        section_header("appearance", theme),
        kv_line("theme", &state.theme, theme),
        Line::from(""),
        section_header("search", theme),
        kv_line("engine", &state.search_engine, theme),
        kv_line_span("status", search_status, theme),
    ];

    frame.render_widget(Paragraph::new(lines), inner);
}

fn section_header<'a>(title: &'a str, theme: &Theme) -> Line<'a> {
    Line::from(Span::styled(
        format!("  {}", title),
        Style::default().fg(theme.fg),
    ))
}

fn kv_line<'a>(key: &'a str, value: &'a str, theme: &Theme) -> Line<'a> {
    Line::from(vec![
        Span::styled(
            format!("    {:<20} ", key),
            Style::default().fg(theme.muted),
        ),
        Span::styled(value, Style::default().fg(theme.fg)),
    ])
}

fn kv_line_span<'a>(key: &'a str, value: Span<'a>, theme: &Theme) -> Line<'a> {
    Line::from(vec![
        Span::styled(
            format!("    {:<20} ", key),
            Style::default().fg(theme.muted),
        ),
        value,
    ])
}
