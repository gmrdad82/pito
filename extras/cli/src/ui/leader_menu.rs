//! Leader-menu overlay — the TUI half of the unified keybindings schema.
//!
//! Triggered by pressing the leader key (SPACE, per `config/keybindings.yml`)
//! when no other overlay is open. The overlay anchors to the bottom-right
//! corner of the terminal, ~30 columns wide, and lists every item from the
//! current menu as a `[key] label` row. Submenus are navigated by pressing
//! their key; `Backspace` pops back up one level; `Esc` (or the leader key
//! again) closes the overlay.
//!
//! State lives in `LeaderMenuState` and is held by `App` for the lifetime of
//! the leader interaction. Filtering for the TUI surface happens once in
//! `keybindings::filtered_for(Surface::Tui)` and is cached for the session.

use ratatui::{
    Frame,
    layout::Rect,
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph},
};

use crate::keybindings::{Item, KeybindingsSchema, Surface, filtered_for};
use crate::theme::Theme;

/// Width of the leader popup in columns. Wide enough to fit every label
/// currently in the schema (`mark all as read` is the longest at 16
/// columns) plus a `[X] ` prefix, a ` ›` submenu hint, and a border.
const POPUP_WIDTH: u16 = 32;

/// Open-state for the leader-menu overlay. Holds the per-session
/// TUI-filtered schema and a stack of menu names (the current menu is the
/// top of the stack).
#[derive(Debug, Clone)]
pub struct LeaderMenuState {
    /// Schema filtered for the TUI surface — items tagged `surfaces: [web]`
    /// have already been dropped.
    schema: KeybindingsSchema,
    /// Stack of menu names. Bottom is always `"root"`; the top is the menu
    /// currently rendered.
    stack: Vec<String>,
}

impl LeaderMenuState {
    /// Build a fresh open-state pointed at the root menu. Loads (or reuses)
    /// the cached TUI-filtered schema.
    pub fn new() -> Self {
        Self {
            schema: filtered_for(Surface::Tui),
            stack: vec!["root".to_string()],
        }
    }

    /// Test seam: build a state with an explicit schema. The binary always
    /// uses [`new`].
    #[cfg(test)]
    pub fn with_schema(schema: KeybindingsSchema) -> Self {
        Self {
            schema,
            stack: vec!["root".to_string()],
        }
    }

    /// Name of the menu currently on top of the stack.
    pub fn current_menu_name(&self) -> &str {
        self.stack.last().map(|s| s.as_str()).unwrap_or("root")
    }

    /// Items of the current menu. Empty slice if the menu name is somehow
    /// missing from the schema (which would be a schema bug).
    pub fn current_items(&self) -> &[Item] {
        self.schema
            .menus
            .get(self.current_menu_name())
            .map(|m| m.items.as_slice())
            .unwrap_or(&[])
    }

    /// Find the item bound to a given key character in the current menu.
    pub fn find_item(&self, key: &str) -> Option<&Item> {
        self.current_items().iter().find(|i| i.key == key)
    }

    /// Push a submenu onto the stack. No-op if the submenu name doesn't
    /// exist in the schema (defensive guard against a malformed reference).
    pub fn push_submenu(&mut self, name: &str) {
        if self.schema.menus.contains_key(name) {
            self.stack.push(name.to_string());
        }
    }

    /// Pop the current menu off the stack. Stops at the root (the bottom of
    /// the stack is always preserved); returns `true` when a pop actually
    /// happened so the caller can distinguish "went up" from "already at
    /// root".
    pub fn pop(&mut self) -> bool {
        if self.stack.len() > 1 {
            self.stack.pop();
            true
        } else {
            false
        }
    }

    /// Depth of the menu stack. `1` means root; higher values mean nested
    /// submenus. Exposed for assertions (the binary itself doesn't consult
    /// depth — it just renders the current items).
    #[allow(dead_code)]
    pub fn depth(&self) -> usize {
        self.stack.len()
    }
}

impl Default for LeaderMenuState {
    fn default() -> Self {
        Self::new()
    }
}

/// Render the leader menu popup. Anchors to the bottom-right corner of the
/// passed `area` (which is typically the full frame area). The popup is
/// `POPUP_WIDTH` cols wide; its height is the number of items plus 2 for
/// the border plus 1 for the footer hint line.
pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, state: &LeaderMenuState) {
    let items = state.current_items();
    let popup = popup_rect(area, items.len() as u16);

    frame.render_widget(Clear, popup);

    let title = format!(" {} ", state.current_menu_name());

    let mut lines: Vec<Line> = items.iter().map(|item| item_line(item, theme)).collect();

    // Footer hint. Always present so users know how to escape and where
    // Backspace goes. Use the leader's `display` glyph so the closing-cue
    // mirrors the popup's open-cue.
    let leader_display = state.schema.leader.display.clone();
    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::raw(" "),
        Span::styled("Esc", Style::default().fg(theme.muted)),
        Span::styled(" close · ", Style::default().fg(theme.fg)),
        Span::styled("Backspace", Style::default().fg(theme.muted)),
        Span::styled(" up · ", Style::default().fg(theme.fg)),
        Span::styled(leader_display, Style::default().fg(theme.muted)),
        Span::styled(" close", Style::default().fg(theme.fg)),
    ]));

    let block = Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.accent))
        .style(Style::default().bg(theme.bg).fg(theme.fg));

    let paragraph = Paragraph::new(lines).block(block);
    frame.render_widget(paragraph, popup);
}

/// Build a single `[key] label` row.
fn item_line<'a>(item: &'a Item, theme: &Theme) -> Line<'a> {
    let suffix = if item.submenu.is_some() { " ›" } else { "" };
    Line::from(vec![
        Span::raw(" "),
        Span::styled(
            format!("[{}]", item.key),
            Style::default()
                .fg(theme.accent)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(" "),
        Span::styled(item.label.as_str(), Style::default().fg(theme.fg)),
        Span::styled(suffix, Style::default().fg(theme.muted)),
    ])
}

/// Compute the popup rect anchored to the bottom-right of `area`.
///
/// Width is fixed at [`POPUP_WIDTH`] (clamped to area width on tiny
/// terminals). Height is `items + 2 border lines + 2 footer lines`,
/// clamped to area height. A 1-column right gutter and 1-row bottom gutter
/// (above the existing status bar) keep the popup off the very edge.
fn popup_rect(area: Rect, item_count: u16) -> Rect {
    // 2 border lines + items + blank separator + 1 footer line
    let desired_height = item_count.saturating_add(4);
    let width = POPUP_WIDTH.min(area.width);
    let height = desired_height.min(area.height.saturating_sub(1).max(3));
    // Anchor: bottom-right, with 1-col gutter on the right and 1-row gutter
    // above the status bar (the status bar sits on the final row of `area`
    // when the caller passes the body rect; passing the full frame here is
    // also fine — we'll just float 1 row above the bottom).
    let x = area.x + area.width.saturating_sub(width).saturating_sub(1);
    let y = area
        .y
        .saturating_add(area.height)
        .saturating_sub(height)
        .saturating_sub(1);
    Rect {
        x,
        y,
        width,
        height,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::keybindings::{Action, Leader, Menu};
    use std::collections::HashMap;

    /// `(key, label, action, submenu)` tuple used by the schema_with helper.
    type ItemSpec<'a> = (&'a str, &'a str, Option<Action>, Option<&'a str>);

    fn schema_with(menus: Vec<(&str, Vec<ItemSpec>)>) -> KeybindingsSchema {
        let menus: HashMap<String, Menu> = menus
            .into_iter()
            .map(|(name, items)| {
                let items = items
                    .into_iter()
                    .map(|(key, label, action, submenu)| Item {
                        key: key.to_string(),
                        label: label.to_string(),
                        action,
                        submenu: submenu.map(|s| s.to_string()),
                        surfaces: None,
                    })
                    .collect();
                (name.to_string(), Menu { items })
            })
            .collect();
        KeybindingsSchema {
            leader: Leader {
                key: " ".to_string(),
                display: "_".to_string(),
            },
            menus,
        }
    }

    #[test]
    fn state_starts_at_root() {
        let state = LeaderMenuState::new();
        assert_eq!(state.current_menu_name(), "root");
        assert_eq!(state.depth(), 1);
    }

    #[test]
    fn push_submenu_navigates_into_named_menu() {
        let schema = schema_with(vec![
            ("root", vec![("c", "channels", None, Some("channels"))]),
            (
                "channels",
                vec![(
                    "l",
                    "list",
                    Some(Action::Navigate { path: "/c".into() }),
                    None,
                )],
            ),
        ]);
        let mut state = LeaderMenuState::with_schema(schema);
        state.push_submenu("channels");
        assert_eq!(state.current_menu_name(), "channels");
        assert_eq!(state.depth(), 2);
    }

    #[test]
    fn push_submenu_no_op_for_unknown_name() {
        let schema = schema_with(vec![("root", vec![])]);
        let mut state = LeaderMenuState::with_schema(schema);
        state.push_submenu("does_not_exist");
        assert_eq!(state.current_menu_name(), "root");
        assert_eq!(state.depth(), 1);
    }

    #[test]
    fn pop_unwinds_one_level() {
        let schema = schema_with(vec![
            ("root", vec![("c", "channels", None, Some("channels"))]),
            ("channels", vec![]),
        ]);
        let mut state = LeaderMenuState::with_schema(schema);
        state.push_submenu("channels");
        assert_eq!(state.depth(), 2);

        let popped = state.pop();
        assert!(popped, "pop must succeed when above root");
        assert_eq!(state.current_menu_name(), "root");
        assert_eq!(state.depth(), 1);
    }

    #[test]
    fn pop_at_root_is_no_op() {
        let schema = schema_with(vec![("root", vec![])]);
        let mut state = LeaderMenuState::with_schema(schema);
        let popped = state.pop();
        assert!(!popped, "pop at root must return false");
        assert_eq!(state.depth(), 1);
    }

    #[test]
    fn find_item_returns_match_in_current_menu() {
        let schema = schema_with(vec![(
            "root",
            vec![(
                "h",
                "home",
                Some(Action::Navigate { path: "/".into() }),
                None,
            )],
        )]);
        let state = LeaderMenuState::with_schema(schema);
        let item = state.find_item("h").expect("h is bound");
        assert_eq!(item.label, "home");
    }

    #[test]
    fn find_item_misses_when_key_not_bound() {
        let schema = schema_with(vec![("root", vec![("h", "home", None, None)])]);
        let state = LeaderMenuState::with_schema(schema);
        assert!(state.find_item("z").is_none());
    }

    #[test]
    fn find_item_scopes_to_current_menu_after_push() {
        // Key `l` is bound only in the `channels` submenu, not in root.
        // After pushing, lookup for `l` must succeed; before pushing it
        // must fail. Proves the lookup is scoped to the *current* menu.
        let schema = schema_with(vec![
            ("root", vec![("c", "channels", None, Some("channels"))]),
            (
                "channels",
                vec![(
                    "l",
                    "list",
                    Some(Action::Navigate { path: "/c".into() }),
                    None,
                )],
            ),
        ]);
        let mut state = LeaderMenuState::with_schema(schema);
        assert!(state.find_item("l").is_none(), "no `l` at root");
        state.push_submenu("channels");
        assert!(state.find_item("l").is_some(), "`l` available in channels");
    }

    #[test]
    fn popup_rect_anchors_to_bottom_right() {
        let area = Rect {
            x: 0,
            y: 0,
            width: 120,
            height: 40,
        };
        let rect = popup_rect(area, 5);
        // Right gutter of 1 column.
        assert_eq!(rect.x + rect.width, area.width - 1);
        // Bottom gutter of 1 row (above the status bar).
        assert_eq!(rect.y + rect.height, area.height - 1);
        assert_eq!(rect.width, POPUP_WIDTH);
    }

    #[test]
    fn popup_rect_clamps_width_for_narrow_terminal() {
        let area = Rect {
            x: 0,
            y: 0,
            width: 20,
            height: 40,
        };
        let rect = popup_rect(area, 5);
        assert_eq!(rect.width, 20);
    }

    #[test]
    fn renders_into_test_backend_without_panic() {
        use crate::theme::ThemeMode;
        use ratatui::{Terminal, backend::TestBackend};
        let theme = Theme::from_mode(ThemeMode::Dark);
        let schema = filtered_for(Surface::Tui);
        let state = LeaderMenuState {
            schema,
            stack: vec!["root".to_string()],
        };
        let backend = TestBackend::new(120, 40);
        let mut terminal = Terminal::new(backend).expect("test backend");
        terminal
            .draw(|frame| {
                render(frame, frame.area(), &theme, &state);
            })
            .expect("draw");
    }
}
