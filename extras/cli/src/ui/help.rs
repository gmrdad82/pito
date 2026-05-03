use ratatui::{
    Frame,
    layout::{Constraint, Flex, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph},
};

use crate::theme::Theme;

/// Minimum width (in columns) for the help dialog. At narrower terminal sizes
/// we still clamp here so the longest description line stays visible.
/// 64 cols accommodates `2 (margin) + 22 (key column) + 36 (longest
/// description) + 2 (borders) + a couple of cells of breathing room`.
const MIN_WIDTH: u16 = 64;
/// Target width as a percentage of the terminal width. Generous enough that
/// the longest description ("D — delete selection (or current row)") fits
/// without truncation across typical terminal widths.
const TARGET_WIDTH_PCT: u16 = 75;
/// Hard ceiling so very wide terminals don't stretch the dialog into useless
/// whitespace. `100` is wide enough for every description line we render.
const MAX_WIDTH: u16 = 100;

pub fn render(frame: &mut Frame, area: Rect, theme: &Theme) {
    let popup = sized_rect(area);

    frame.render_widget(Clear, popup);

    let lines = vec![
        Line::from(Span::styled(
            " keyboard shortcuts",
            Style::default().fg(theme.accent),
        )),
        Line::from(""),
        shortcut_line("?", "toggle this help", theme),
        shortcut_line("q", "back / close", theme),
        shortcut_line(":q", "quit", theme),
        shortcut_line("Ctrl+C", "quit", theme),
        Line::from(""),
        Line::from(Span::styled(
            " navigation",
            Style::default().fg(theme.accent),
        )),
        Line::from(""),
        shortcut_line("g d", "go to dashboard", theme),
        shortcut_line("g c", "go to channels", theme),
        shortcut_line("g v", "go to videos", theme),
        shortcut_line("g s", "go to saved views", theme),
        shortcut_line("g e", "go to settings", theme),
        Line::from(""),
        Line::from(Span::styled(" general", Style::default().fg(theme.accent))),
        Line::from(""),
        shortcut_line("n", "toggle dark/light theme", theme),
        shortcut_line("/", "open search", theme),
        shortcut_line("j/k", "down/up", theme),
        shortcut_line("space", "toggle bulk select on row (bulk mode only)", theme),
        shortcut_line("b", "toggle bulk mode", theme),
        Line::from(""),
        Line::from(Span::styled(
            " channels list",
            Style::default().fg(theme.accent),
        )),
        Line::from(""),
        shortcut_line("s", "toggle star on highlighted row", theme),
        shortcut_line("D", "delete selection (or current row)", theme),
        shortcut_line("Y", "sync selection (or current row)", theme),
        shortcut_line("f s", "filter: starred (toggle)", theme),
        shortcut_line("f c", "filter: connected (toggle)", theme),
        shortcut_line("f y", "filter: syncing (toggle)", theme),
        Line::from(""),
        Line::from(vec![
            Span::raw("  "),
            Span::styled(
                "connected reflects OAuth state — only the web UI can toggle it",
                Style::default().fg(theme.muted),
            ),
        ]),
        Line::from(""),
        Line::from(Span::styled(
            " channel detail",
            Style::default().fg(theme.accent),
        )),
        Line::from(""),
        shortcut_line("v", "view URL in browser", theme),
        shortcut_line("s", "toggle star", theme),
        shortcut_line("Y", "sync this channel", theme),
        shortcut_line("D", "delete this channel", theme),
        Line::from(""),
        Line::from(vec![
            Span::raw("  "),
            Span::styled(
                "connected reflects OAuth state — only the web UI can toggle it",
                Style::default().fg(theme.muted),
            ),
        ]),
        Line::from(""),
        Line::from(Span::styled(
            " confirmation prompts",
            Style::default().fg(theme.accent),
        )),
        Line::from(""),
        shortcut_line("y", "confirm", theme),
        shortcut_line("Esc / any other key", "cancel", theme),
    ];

    let block = Block::default()
        .title(" [help] ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.accent))
        .style(Style::default().bg(theme.bg));

    let paragraph = Paragraph::new(lines).block(block);
    frame.render_widget(paragraph, popup);
}

fn shortcut_line<'a>(key: &'a str, desc: &'a str, theme: &Theme) -> Line<'a> {
    Line::from(vec![
        Span::raw("  "),
        Span::styled(format!("{:<22}", key), Style::default().fg(theme.cyan)),
        Span::styled(desc, Style::default().fg(theme.fg)),
    ])
}

/// Compute the help dialog rect.
///
/// Width: clamp(MIN_WIDTH, area * TARGET_WIDTH_PCT / 100, MAX_WIDTH) so the
/// dialog comfortably fits the longest description line on typical terminals
/// without becoming unreadably wide on ultrawide displays.
/// Height: 80% of the terminal so all sections are visible without scrolling
/// (mirrors the previous behaviour).
fn sized_rect(area: Rect) -> Rect {
    let target_width = area.width.saturating_mul(TARGET_WIDTH_PCT) / 100;
    let width = target_width.clamp(MIN_WIDTH, MAX_WIDTH).min(area.width);

    let vertical = Layout::vertical([Constraint::Percentage(80)])
        .flex(Flex::Center)
        .split(area);
    let horizontal = Layout::horizontal([Constraint::Length(width)])
        .flex(Flex::Center)
        .split(vertical[0]);
    horizontal[0]
}
