use ratatui::{
    Frame,
    layout::Rect,
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
};

use crate::app::DashboardState;
use crate::theme::Theme;

pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, state: &DashboardState) {
    let block = Block::default()
        .title(Span::styled(" dashboard ", Style::default().fg(theme.fg)))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.border));

    let inner = block.inner(area);
    frame.render_widget(block, area);

    // Counts-only summary. The Rails dashboard collapsed to a small JSON
    // payload (counts only) when chart-tied data sources were retired in May
    // 2026; the TUI mirrors that with a key/value list.
    let rows = [
        ("videos", state.data.video_count),
        ("channels", state.data.channel_count),
        ("projects", state.data.project_count),
        ("footage", state.data.footage_count),
        ("notes", state.data.note_count),
    ];

    // Two-column layout: left-aligned label, right-justified count, padded so
    // every count column lines up regardless of label length.
    let label_width = rows.iter().map(|(l, _)| l.len()).max().unwrap_or(0);

    let mut lines: Vec<Line> = Vec::with_capacity(rows.len() + 4);
    lines.push(Line::from(""));
    for (label, value) in rows.iter() {
        lines.push(Line::from(vec![
            Span::raw("  "),
            Span::styled(
                format!("{:<width$}", label, width = label_width),
                Style::default().fg(theme.muted),
            ),
            Span::raw("  "),
            Span::styled(value.to_string(), Style::default().fg(theme.fg)),
        ]));
    }

    // Placeholder copy mirrors the Rails dashboard's caption verbatim — the
    // chart toolbar retired in May 2026 and Rails left a single-line note in
    // its place ("[ dashboard reset — charts return with intentional metrics
    // in a later phase. ]"). The CLI shows the same line so the two surfaces
    // read identically while waiting for the next chart phase.
    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::raw("  "),
        Span::styled(
            "[ dashboard reset — charts return with intentional metrics in a later phase. ]",
            Style::default().fg(theme.muted),
        ),
    ]));

    if let Some(ref msg) = state.flash {
        lines.push(Line::from(""));
        lines.push(Line::from(vec![
            Span::raw("  "),
            Span::styled(format!("! {}", msg), Style::default().fg(theme.danger)),
        ]));
    }

    let paragraph = Paragraph::new(lines).style(Style::default().bg(theme.bg).fg(theme.fg));
    frame.render_widget(paragraph, inner);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::models::DashboardData;
    use crate::theme::{Theme, ThemeMode};
    use ratatui::{Terminal, backend::TestBackend, style::Color};

    fn sample_dashboard_state() -> DashboardState {
        DashboardState {
            data: DashboardData {
                video_count: 12,
                channel_count: 3,
                project_count: 2,
                footage_count: 87,
                note_count: 14,
            },
            flash: None,
        }
    }

    /// Render the counts-summary dashboard and confirm every cell carries the
    /// theme's background color. Charts are gone but the regression for the
    /// "respect theme.bg" rule still applies — the dashboard frame must paint
    /// its background even where the inner Paragraph content is empty.
    fn assert_dashboard_bg_matches_theme(mode: ThemeMode) {
        let theme = Theme::from_mode(mode);
        let width: u16 = 60;
        let height: u16 = 20;
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).expect("test backend");
        let state = sample_dashboard_state();
        terminal
            .draw(|frame| {
                // Mirror the real frame paint in ui/mod.rs so the dashboard
                // is rendered over a theme-coloured backdrop.
                frame.render_widget(
                    Block::default().style(Style::default().bg(theme.bg)),
                    frame.area(),
                );
                render(frame, frame.area(), &theme, &state);
            })
            .expect("draw");

        let buf = terminal.backend().buffer().clone();
        let mut mismatched = Vec::new();
        for y in 0..height {
            for x in 0..width {
                let cell = &buf[(x, y)];
                let bg = cell.style().bg.unwrap_or(Color::Reset);
                if bg != theme.bg {
                    mismatched.push((x, y, bg));
                }
            }
        }
        assert!(
            mismatched.is_empty(),
            "{:?} theme: {} cells did not carry theme.bg ({:?}). First few: {:?}",
            mode,
            mismatched.len(),
            theme.bg,
            &mismatched[..mismatched.len().min(5)],
        );
    }

    #[test]
    fn dashboard_backgrounds_honor_dark_theme() {
        assert_dashboard_bg_matches_theme(ThemeMode::Dark);
    }

    #[test]
    fn dashboard_backgrounds_honor_light_theme() {
        assert_dashboard_bg_matches_theme(ThemeMode::Light);
    }

    #[test]
    fn dashboard_renders_placeholder_copy_verbatim() {
        // The Rails dashboard's `[ dashboard reset — ... ]` caption must
        // appear on the CLI dashboard verbatim so the two surfaces read
        // identically while charts are absent.
        let theme = Theme::from_mode(ThemeMode::Dark);
        let backend = TestBackend::new(120, 20);
        let mut terminal = Terminal::new(backend).expect("test backend");
        let state = sample_dashboard_state();
        terminal
            .draw(|frame| {
                render(frame, frame.area(), &theme, &state);
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

        assert!(
            rendered.contains(
                "[ dashboard reset — charts return with intentional metrics in a later phase. ]"
            ),
            "expected the Rails dashboard placeholder copy verbatim, got:\n{}",
            rendered
        );
    }

    #[test]
    fn dashboard_renders_all_five_counts() {
        // Smoke check: every count label should appear in the rendered buffer.
        let theme = Theme::from_mode(ThemeMode::Dark);
        let backend = TestBackend::new(60, 20);
        let mut terminal = Terminal::new(backend).expect("test backend");
        let state = sample_dashboard_state();
        terminal
            .draw(|frame| {
                render(frame, frame.area(), &theme, &state);
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

        for label in ["videos", "channels", "projects", "footage", "notes"] {
            assert!(
                rendered.contains(label),
                "expected {} in rendered dashboard, got:\n{}",
                label,
                rendered
            );
        }
        // Every count value should be present.
        for value in ["12", "3", "2", "87", "14"] {
            assert!(
                rendered.contains(value),
                "expected count {} in rendered dashboard",
                value
            );
        }
    }
}
