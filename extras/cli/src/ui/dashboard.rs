use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::{Modifier, Style},
    symbols::Marker,
    text::{Line, Span},
    widgets::{Axis, Bar, BarChart, BarGroup, Block, Borders, Chart, Dataset},
    Frame,
};

use crate::app::{DashboardState, RANGES};
use crate::theme::Theme;

pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, state: &DashboardState) {
    let rows = Layout::vertical([
        Constraint::Length(1), // toolbar
        Constraint::Min(0),   // charts
    ])
    .split(area);

    render_toolbar(frame, rows[0], theme, state);

    let chart_rows =
        Layout::vertical([Constraint::Percentage(50), Constraint::Percentage(50)]).split(rows[1]);
    let top =
        Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)]).split(chart_rows[0]);
    let bottom =
        Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)]).split(chart_rows[1]);

    render_daily_views(frame, top[0], theme, state);
    render_top_videos(frame, top[1], theme, state);
    render_views_by_channel(frame, bottom[0], theme, state);
    render_daily_engagement(frame, bottom[1], theme, state);
}

fn render_toolbar(frame: &mut Frame, area: Rect, theme: &Theme, state: &DashboardState) {
    let mut spans: Vec<Span> = vec![Span::styled(" dashboard  ", Style::default().fg(theme.fg))];

    for (i, &r) in RANGES.iter().enumerate() {
        let style = if i == state.range_index {
            Style::default().fg(theme.accent).add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(theme.muted)
        };
        spans.push(Span::styled(format!(" [{}] ", r), style));
    }

    spans.push(Span::styled(
        format!(
            "   {} videos, {} ch",
            state.data.video_count, state.data.channel_count
        ),
        Style::default().fg(theme.muted),
    ));

    // Surface fetch failures inline on the toolbar — the dashboard has no
    // separate flash row, so painting in red here keeps the user informed
    // without breaking the alternate-screen TUI by writing to stdout.
    if let Some(ref msg) = state.flash {
        spans.push(Span::raw("  "));
        spans.push(Span::styled(
            format!("! {}", msg),
            Style::default().fg(theme.danger),
        ));
    }

    frame.render_widget(Line::from(spans), area);
}

fn format_number(n: u64) -> String {
    if n >= 10_000 {
        format!("{}k", n / 1000)
    } else if n >= 1_000 {
        let k = n as f64 / 1000.0;
        if n.is_multiple_of(1000) {
            format!("{}k", n / 1000)
        } else {
            format!("{:.1}k", k)
        }
    } else {
        n.to_string()
    }
}

fn render_daily_views(frame: &mut Frame, area: Rect, theme: &Theme, state: &DashboardState) {
    let data: Vec<(f64, f64)> = state
        .data
        .daily_views
        .iter()
        .enumerate()
        .map(|(i, (_, v))| (i as f64, *v as f64))
        .collect();

    if data.is_empty() {
        return;
    }

    let y_max = data.iter().map(|(_, y)| *y).fold(0.0_f64, f64::max);
    let x_max = (data.len() as f64 - 1.0).max(1.0);

    let first_date = short_date(&state.data.daily_views.first().unwrap().0);
    let last_date = short_date(&state.data.daily_views.last().unwrap().0);

    let dataset = Dataset::default()
        .name("views")
        .marker(Marker::Braille)
        .style(Style::default().fg(theme.accent))
        .data(&data);

    let chart = Chart::new(vec![dataset])
        .style(Style::default().bg(theme.bg))
        .block(
            Block::default()
                .title(Span::styled(
                    " daily views ",
                    Style::default().fg(theme.fg),
                ))
                .borders(Borders::ALL)
                .border_style(Style::default().fg(theme.border)),
        )
        .x_axis(
            Axis::default()
                .bounds([0.0, x_max])
                .labels(vec![
                    Span::styled(first_date, Style::default().fg(theme.muted)),
                    Span::styled(last_date, Style::default().fg(theme.muted)),
                ])
                .style(Style::default().fg(theme.muted)),
        )
        .y_axis(
            Axis::default()
                .bounds([0.0, y_max * 1.1])
                .labels(vec![
                    Span::styled("0", Style::default().fg(theme.muted)),
                    Span::styled(format_number(y_max as u64), Style::default().fg(theme.muted)),
                ])
                .style(Style::default().fg(theme.muted)),
        );

    frame.render_widget(chart, area);
}

fn render_views_by_channel(frame: &mut Frame, area: Rect, theme: &Theme, state: &DashboardState) {
    let colors = [theme.accent, theme.success, theme.pink];

    let mut all_data: Vec<Vec<(f64, f64)>> = Vec::new();
    let mut y_max: f64 = 0.0;
    let mut x_max: f64 = 1.0;

    for (_name, series) in &state.data.views_by_channel {
        let points: Vec<(f64, f64)> = series
            .iter()
            .enumerate()
            .map(|(i, (_, v))| (i as f64, *v as f64))
            .collect();
        if !points.is_empty() {
            x_max = (points.len() as f64 - 1.0).max(x_max);
            let local_max = points.iter().map(|(_, y)| *y).fold(0.0_f64, f64::max);
            if local_max > y_max {
                y_max = local_max;
            }
        }
        all_data.push(points);
    }

    if all_data.is_empty() {
        return;
    }

    let datasets: Vec<Dataset> = state
        .data
        .views_by_channel
        .iter()
        .enumerate()
        .map(|(i, (name, _))| {
            Dataset::default()
                .name(format!("[{}]", name))
                .marker(Marker::Braille)
                .style(Style::default().fg(colors[i % colors.len()]))
                .data(&all_data[i])
        })
        .collect();

    let first_date = state
        .data
        .views_by_channel
        .first()
        .and_then(|(_, s)| s.first().map(|(d, _)| short_date(d)))
        .unwrap_or_default();
    let last_date = state
        .data
        .views_by_channel
        .first()
        .and_then(|(_, s)| s.last().map(|(d, _)| short_date(d)))
        .unwrap_or_default();

    let chart = Chart::new(datasets)
        .style(Style::default().bg(theme.bg))
        .block(
            Block::default()
                .title(Span::styled(
                    " views by channel ",
                    Style::default().fg(theme.fg),
                ))
                .borders(Borders::ALL)
                .border_style(Style::default().fg(theme.border)),
        )
        .x_axis(
            Axis::default()
                .bounds([0.0, x_max])
                .labels(vec![
                    Span::styled(first_date, Style::default().fg(theme.muted)),
                    Span::styled(last_date, Style::default().fg(theme.muted)),
                ])
                .style(Style::default().fg(theme.muted)),
        )
        .y_axis(
            Axis::default()
                .bounds([0.0, y_max * 1.1])
                .labels(vec![
                    Span::styled("0", Style::default().fg(theme.muted)),
                    Span::styled(format_number(y_max as u64), Style::default().fg(theme.muted)),
                ])
                .style(Style::default().fg(theme.muted)),
        );

    frame.render_widget(chart, area);
}

fn render_top_videos(frame: &mut Frame, area: Rect, theme: &Theme, state: &DashboardState) {
    let max_views = state
        .data
        .top_videos
        .iter()
        .map(|v| v.views)
        .max()
        .unwrap_or(1);

    let bars: Vec<Bar> = state
        .data
        .top_videos
        .iter()
        .map(|v| {
            let label = truncate_chars(&v.title, 20);
            Bar::default()
                .value(v.views)
                .label(Line::from(label))
                .style(Style::default().fg(theme.accent))
                .value_style(Style::default().fg(theme.fg))
        })
        .collect();

    let group = BarGroup::default().bars(&bars);

    let barchart = BarChart::default()
        .style(Style::default().bg(theme.bg))
        .block(
            Block::default()
                .title(Span::styled(
                    " top videos by views ",
                    Style::default().fg(theme.fg),
                ))
                .borders(Borders::ALL)
                .border_style(Style::default().fg(theme.border)),
        )
        .data(group)
        .bar_width(3)
        .bar_gap(1)
        .max(max_views);

    frame.render_widget(barchart, area);
}

fn render_daily_engagement(frame: &mut Frame, area: Rect, theme: &Theme, state: &DashboardState) {
    let likes_data: Vec<(f64, f64)> = state
        .data
        .daily_engagement
        .likes
        .iter()
        .enumerate()
        .map(|(i, (_, v))| (i as f64, *v as f64))
        .collect();

    let comments_data: Vec<(f64, f64)> = state
        .data
        .daily_engagement
        .comments
        .iter()
        .enumerate()
        .map(|(i, (_, v))| (i as f64, *v as f64))
        .collect();

    if likes_data.is_empty() && comments_data.is_empty() {
        return;
    }

    let y_max = likes_data
        .iter()
        .chain(comments_data.iter())
        .map(|(_, y)| *y)
        .fold(0.0_f64, f64::max);
    let x_max = (likes_data.len().max(comments_data.len()) as f64 - 1.0).max(1.0);

    let first_date = state
        .data
        .daily_engagement
        .likes
        .first()
        .map(|(d, _)| short_date(d))
        .unwrap_or_default();
    let last_date = state
        .data
        .daily_engagement
        .likes
        .last()
        .map(|(d, _)| short_date(d))
        .unwrap_or_default();

    let datasets = vec![
        Dataset::default()
            .name("[likes]")
            .marker(Marker::Braille)
            .style(Style::default().fg(theme.accent))
            .data(&likes_data),
        Dataset::default()
            .name("[comments]")
            .marker(Marker::Braille)
            .style(Style::default().fg(theme.orange))
            .data(&comments_data),
    ];

    let chart = Chart::new(datasets)
        .style(Style::default().bg(theme.bg))
        .block(
            Block::default()
                .title(Span::styled(
                    " daily engagement ",
                    Style::default().fg(theme.fg),
                ))
                .borders(Borders::ALL)
                .border_style(Style::default().fg(theme.border)),
        )
        .x_axis(
            Axis::default()
                .bounds([0.0, x_max])
                .labels(vec![
                    Span::styled(first_date, Style::default().fg(theme.muted)),
                    Span::styled(last_date, Style::default().fg(theme.muted)),
                ])
                .style(Style::default().fg(theme.muted)),
        )
        .y_axis(
            Axis::default()
                .bounds([0.0, y_max * 1.1])
                .labels(vec![
                    Span::styled("0", Style::default().fg(theme.muted)),
                    Span::styled(format_number(y_max as u64), Style::default().fg(theme.muted)),
                ])
                .style(Style::default().fg(theme.muted)),
        );

    frame.render_widget(chart, area);
}

/// Truncate a string to at most `max_chars` characters (UTF-8 safe).
fn truncate_chars(s: &str, max_chars: usize) -> String {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() <= max_chars {
        s.to_string()
    } else {
        let truncated: String = chars[..max_chars.saturating_sub(2)].iter().collect();
        format!("{}..", truncated)
    }
}

/// Extract a short date label from "YYYY-MM-DD" -> "Mon DD"
fn short_date(date: &str) -> String {
    // Just show "MM-DD" for brevity in terminal
    if date.len() >= 10 {
        date[5..10].to_string()
    } else {
        date.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::models::{DailyEngagement, DashboardData, TopVideo};
    use crate::theme::{Theme, ThemeMode};
    use ratatui::{backend::TestBackend, style::Color, Terminal};

    fn sample_dashboard_state() -> DashboardState {
        DashboardState {
            range: "30d".to_string(),
            range_index: 1,
            data: DashboardData {
                video_count: 10,
                channel_count: 2,
                daily_views: vec![
                    ("2026-04-01".to_string(), 100),
                    ("2026-04-02".to_string(), 150),
                    ("2026-04-03".to_string(), 200),
                ],
                views_by_channel: vec![
                    (
                        "ch_a".to_string(),
                        vec![
                            ("2026-04-01".to_string(), 80),
                            ("2026-04-02".to_string(), 120),
                            ("2026-04-03".to_string(), 110),
                        ],
                    ),
                    (
                        "ch_b".to_string(),
                        vec![
                            ("2026-04-01".to_string(), 20),
                            ("2026-04-02".to_string(), 30),
                            ("2026-04-03".to_string(), 90),
                        ],
                    ),
                ],
                top_videos: vec![
                    TopVideo {
                        title: "First".to_string(),
                        views: 500,
                    },
                    TopVideo {
                        title: "Second".to_string(),
                        views: 300,
                    },
                ],
                daily_engagement: DailyEngagement {
                    likes: vec![
                        ("2026-04-01".to_string(), 10),
                        ("2026-04-02".to_string(), 20),
                        ("2026-04-03".to_string(), 30),
                    ],
                    comments: vec![
                        ("2026-04-01".to_string(), 1),
                        ("2026-04-02".to_string(), 2),
                        ("2026-04-03".to_string(), 5),
                    ],
                },
            },
            flash: None,
        }
    }

    /// Render the four-chart dashboard onto a TestBackend and confirm that
    /// every cell in the body area carries the theme's background color.
    /// Regression for the bug where Chart's internal Canvas baked
    /// `Color::Reset` into the graph area, ignoring the active theme.
    fn assert_dashboard_bg_matches_theme(mode: ThemeMode) {
        let theme = Theme::from_mode(mode);
        let width: u16 = 100;
        let height: u16 = 30;
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).expect("test backend");
        let state = sample_dashboard_state();
        terminal
            .draw(|frame| {
                // Mirror the real frame paint in ui/mod.rs so the dashboard
                // is rendered over a theme-coloured backdrop.
                frame.render_widget(
                    ratatui::widgets::Block::default().style(Style::default().bg(theme.bg)),
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
    fn dashboard_chart_backgrounds_honor_dark_theme() {
        assert_dashboard_bg_matches_theme(ThemeMode::Dark);
    }

    #[test]
    fn dashboard_chart_backgrounds_honor_light_theme() {
        assert_dashboard_bg_matches_theme(ThemeMode::Light);
    }
}
