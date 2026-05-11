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
        shortcut_line("space", "open leader menu", theme),
        Line::from(""),
        Line::from(Span::styled(
            " channels list",
            Style::default().fg(theme.accent),
        )),
        Line::from(""),
        shortcut_line("x", "toggle row selection", theme),
        shortcut_line("s", "toggle star on highlighted row", theme),
        shortcut_line("D", "delete selection (or current row)", theme),
        shortcut_line("Y", "sync selection (or current row)", theme),
        shortcut_line("f s", "filter: starred (toggle)", theme),
        shortcut_line("f c", "filter: connected (toggle)", theme),
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
            " videos list",
            Style::default().fg(theme.accent),
        )),
        Line::from(""),
        shortcut_line("x", "toggle row selection", theme),
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::ThemeMode;
    use ratatui::{Terminal, backend::TestBackend};

    fn render_to_string() -> String {
        let theme = Theme::from_mode(ThemeMode::Dark);
        let backend = TestBackend::new(120, 60);
        let mut terminal = Terminal::new(backend).expect("test backend");
        terminal
            .draw(|frame| {
                render(frame, frame.area(), &theme);
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
    fn help_does_not_advertise_retired_filter_y_shortcut() {
        // Path A2 retract: Rails dropped the server-side `syncing` boolean,
        // and `keys.rs::handle_filter_prefix` no longer accepts `f y`. The
        // help overlay must not advertise a shortcut that does nothing —
        // surfaced during the Phase 7.5 parity sweep.
        let rendered = render_to_string();
        assert!(
            !rendered.contains("filter: syncing"),
            "help overlay must not list the retired `f y` filter shortcut, got:\n{}",
            rendered
        );
    }

    #[test]
    fn help_still_lists_starred_and_connected_filters() {
        let rendered = render_to_string();
        assert!(
            rendered.contains("filter: starred"),
            "help should list `f s` filter: starred"
        );
        assert!(
            rendered.contains("filter: connected"),
            "help should list `f c` filter: connected"
        );
    }
}
