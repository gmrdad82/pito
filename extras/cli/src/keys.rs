use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

use crate::app::{App, KeyState, Overlay, Screen};
use crate::keybindings::Action as KeybindingAction;
use crate::notifications::overlay as login_pending_overlay;
use crate::ui::channels::ChannelFilter;
use crate::ui::confirmation::{self, ConfirmationOutcome};

pub fn handle_key(app: &mut App, key: KeyEvent) {
    // Ctrl+C always quits
    if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
        app.quit();
        return;
    }

    // Bulk-operation progress overlay: only Esc dismisses (server work
    // continues). Take precedence over other overlays since this overlay is
    // typically launched right after a confirmation closes.
    if app.operation_progress.is_some() {
        if let KeyCode::Esc = key.code {
            app.dismiss_operation_progress();
        }
        return;
    }

    // Help overlay
    if app.overlay == Some(Overlay::Help) {
        match key.code {
            KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('?') => {
                app.overlay = None;
            }
            _ => {}
        }
        return;
    }

    // Confirmation overlay
    if app.overlay == Some(Overlay::Confirmation) {
        handle_confirmation_input(app, key);
        return;
    }

    // Search overlay
    if app.overlay == Some(Overlay::Search) {
        handle_search_input(app, key);
        return;
    }

    // Phase 25 — 01c login-pending overlay. Intercepts keypresses
    // ahead of every other overlay so the operator can resolve the
    // pending attempt without being routed elsewhere.
    if app.overlay == Some(Overlay::LoginPending) {
        handle_login_pending_input(app, key);
        return;
    }

    // Leader-menu overlay — driven by the unified schema in
    // `config/keybindings.yml`. Takes precedence over `Normal` key handling
    // so a user inside the popup sees their key map against the menu, not
    // against the underlying screen.
    if app.overlay == Some(Overlay::LeaderMenu) {
        handle_leader_menu_input(app, key);
        return;
    }

    match app.key_state {
        KeyState::Normal => handle_normal(app, key),
        KeyState::GPrefix => handle_g_prefix(app, key),
        KeyState::ColonPrefix => handle_colon_prefix(app, key),
        KeyState::FilterPrefix => handle_filter_prefix(app, key),
    }
}

fn handle_confirmation_input(app: &mut App, key: KeyEvent) {
    let Some(ref state) = app.confirmation_state else {
        app.overlay = None;
        return;
    };
    let outcome = match key.code {
        KeyCode::Esc => Some(ConfirmationOutcome::Cancel),
        KeyCode::Char(c) => confirmation::key_outcome(c, state),
        _ => Some(ConfirmationOutcome::Cancel),
    };
    if let Some(outcome) = outcome {
        app.resolve_confirmation(outcome);
    }
}

/// Route a key press while the `login_pending_approval` overlay is
/// open. Honours the spec's per-stage keymap:
///
/// - On the card stage: `a` opens the approve confirmation, `b` opens
///   the block confirmation, `l` / `Esc` dismiss the overlay.
/// - On a confirmation stage: `y` fires the underlying POST through
///   the `App` helper; anything else cancels back to the card stage
///   (`Esc` included).
/// - On the working / done stages: only `Esc` (working) or any key
///   (done) is honoured; the wire call's outcome runs to completion.
fn handle_login_pending_input(app: &mut App, key: KeyEvent) {
    let Some(state) = app.login_pending.as_ref() else {
        app.overlay = None;
        return;
    };

    // Esc cancels confirms back to card, or dismisses the card when
    // it's already showing. During Working we ignore Esc — the POST
    // runs to completion.
    if let KeyCode::Esc = key.code {
        match state.stage {
            login_pending_overlay::Stage::ConfirmApprove
            | login_pending_overlay::Stage::ConfirmBlock => {
                if let Some(state) = app.login_pending.as_mut() {
                    let _ = login_pending_overlay::cancel_confirm(state);
                }
            }
            login_pending_overlay::Stage::Working => {
                // No-op: in-flight POST cannot be cancelled mid-wire.
            }
            _ => {
                app.close_login_pending_overlay();
            }
        }
        return;
    }

    let KeyCode::Char(c) = key.code else {
        return;
    };

    // Card stage gets the `a` / `b` openers + the `l` later shortcut.
    let outcome = login_pending_overlay::key_outcome(c, state);

    match state.stage {
        login_pending_overlay::Stage::Card => {
            if matches!(c, 'a' | 'A') {
                if let Some(state) = app.login_pending.as_mut() {
                    let _ = login_pending_overlay::enter_approve_confirm(state);
                }
                return;
            }
            if matches!(c, 'b' | 'B') {
                if let Some(state) = app.login_pending.as_mut() {
                    let _ = login_pending_overlay::enter_block_confirm(state);
                }
                return;
            }
            if matches!(outcome, login_pending_overlay::InputOutcome::Close) {
                app.close_login_pending_overlay();
            }
        }
        login_pending_overlay::Stage::ConfirmApprove => match outcome {
            login_pending_overlay::InputOutcome::FireApprove => {
                app.confirm_login_pending_approve();
            }
            _ => {
                if let Some(state) = app.login_pending.as_mut() {
                    let _ = login_pending_overlay::cancel_confirm(state);
                }
            }
        },
        login_pending_overlay::Stage::ConfirmBlock => match outcome {
            login_pending_overlay::InputOutcome::FireBlock => {
                app.confirm_login_pending_block();
            }
            _ => {
                if let Some(state) = app.login_pending.as_mut() {
                    let _ = login_pending_overlay::cancel_confirm(state);
                }
            }
        },
        login_pending_overlay::Stage::Working => {
            // In-flight POST runs to completion; no key consumes.
        }
        login_pending_overlay::Stage::Done => {
            app.close_login_pending_overlay();
        }
    }
}

fn handle_search_input(app: &mut App, key: KeyEvent) {
    match key.code {
        KeyCode::Esc => {
            app.overlay = None;
        }
        KeyCode::Enter => {
            app.perform_search();
        }
        KeyCode::Backspace if app.search_state.cursor_pos > 0 => {
            app.search_state.cursor_pos -= 1;
            app.search_state.query.remove(app.search_state.cursor_pos);
            app.perform_search();
        }
        KeyCode::Down => {
            app.search_state.selected_row += 1;
        }
        KeyCode::Up if app.search_state.selected_row > 0 => {
            app.search_state.selected_row -= 1;
        }
        KeyCode::Char(c) => {
            app.search_state
                .query
                .insert(app.search_state.cursor_pos, c);
            app.search_state.cursor_pos += 1;
            app.perform_search();
        }
        _ => {}
    }
}

/// Route a key press while the leader-menu overlay is open. The keymap is
/// dynamic — pulled live from the current menu in `LeaderMenuState`. We
/// honour:
///
/// - `Esc` — close the menu and clear its state.
/// - `Backspace` — pop one level; closes if already at root.
/// - The leader key (`SPACE` per the schema) — close the menu (toggle).
/// - Any character bound in the current menu — trigger the action or push
///   the named submenu.
/// - Everything else — ignored, the menu stays open.
fn handle_leader_menu_input(app: &mut App, key: KeyEvent) {
    match key.code {
        KeyCode::Esc => {
            app.close_leader_menu();
            return;
        }
        KeyCode::Backspace => {
            if let Some(ref mut state) = app.leader_menu
                && !state.pop()
            {
                // Already at root → Backspace closes the popup, mirroring
                // the web side's "up at root = close" behavior.
                app.close_leader_menu();
            }
            return;
        }
        KeyCode::Char(' ') => {
            // Pressing the leader key inside the popup closes it (toggle).
            app.close_leader_menu();
            return;
        }
        _ => {}
    }

    // Char keys: look up against the current menu. We collect the action /
    // submenu name into owned values first so we can drop the immutable
    // borrow on `app.leader_menu` before calling mutating helpers.
    let KeyCode::Char(c) = key.code else {
        return;
    };
    let key_str = c.to_string();

    enum Resolved {
        /// Pure action — fires and closes the menu.
        Action(KeybindingAction),
        /// Submenu reference — drills in, menu stays open. Any sibling
        /// `action` field on the same item is IGNORED: per the 2026-05-11
        /// schema revert, a single keystroke can drill OR fire an action,
        /// never both. The old `ActionThenSubmenu` shape was retired because
        /// "navigate + drill" on the same press surprised users.
        Submenu(String),
        Unbound,
    }

    let resolved = match app.leader_menu.as_ref().and_then(|s| s.find_item(&key_str)) {
        Some(item) => match (&item.action, &item.submenu) {
            // Drill-only when `submenu` is present, regardless of any
            // accompanying `action` field. Single-keystroke == single
            // outcome.
            (_, Some(submenu)) => Resolved::Submenu(submenu.clone()),
            (Some(action), None) => Resolved::Action(action.clone()),
            (None, None) => Resolved::Unbound,
        },
        None => Resolved::Unbound,
    };

    match resolved {
        Resolved::Action(action) => {
            app.run_leader_action(&action);
        }
        Resolved::Submenu(name) => {
            if let Some(ref mut state) = app.leader_menu {
                state.push_submenu(&name);
            }
        }
        Resolved::Unbound => {}
    }
}

fn handle_normal(app: &mut App, key: KeyEvent) {
    // The dashboard collapsed to a counts-only summary in May 2026; the
    // chart toolbar (and its 1..5 / h / l range keys) went away with it.
    // Range-tied keybindings have intentionally been removed.

    // Phase 25 — 01c status-line `pending approval` shortcut.
    // When the cached count > 0 and no overlay is currently showing,
    // `a` opens the approve confirmation, `b` opens the block
    // confirmation, `l` dismisses the prompt until the next poll.
    // The shortcut only fires on screens that don't bind these keys
    // — Channels uses `D` / `Y`, Videos doesn't bind any of `a`/`b`/`l`,
    // ChannelDetail / VideoDetail similarly. FootageDetail binds `l`
    // (step forward) so we skip the prompt shortcut there.
    if app.login_pending_count > 0
        && app.overlay.is_none()
        && app.key_state == KeyState::Normal
        && app.screen != Screen::FootageDetail
        && app.screen != Screen::Channels
        && let KeyCode::Char(c) = key.code
    {
        match c {
            'a' | 'A' => {
                if app.try_open_cached_login_pending()
                    && let Some(state) = app.login_pending.as_mut()
                {
                    let _ = login_pending_overlay::enter_approve_confirm(state);
                }
                return;
            }
            'b' | 'B' => {
                if app.try_open_cached_login_pending()
                    && let Some(state) = app.login_pending.as_mut()
                {
                    let _ = login_pending_overlay::enter_block_confirm(state);
                }
                return;
            }
            'l' | 'L' => {
                app.dismiss_login_pending_prompt();
                return;
            }
            _ => {}
        }
    }

    // Channels-screen specific keys (must run before generic q/etc.)
    if app.screen == Screen::Channels {
        match key.code {
            KeyCode::Char('s') => {
                app.toggle_star_for_selected_channel();
                return;
            }
            // `c` is intentionally NOT bound on this screen: connected reflects
            // the OAuth flow and only the web UI may toggle it. The `connected`
            // column and the `f c` filter chip remain read-only views.
            KeyCode::Char('D') => {
                let ids = app.channels_target_ids();
                app.open_delete_confirmation(ids);
                return;
            }
            KeyCode::Char('Y') => {
                let ids = app.channels_target_ids();
                app.open_sync_confirmation(ids);
                return;
            }
            KeyCode::Char('f') => {
                app.key_state = KeyState::FilterPrefix;
                return;
            }
            // `x` toggles row-selection on the highlighted row. Replaces the
            // SPACE binding that became the global leader key once the unified
            // `config/keybindings.yml` schema landed.
            KeyCode::Char('x') => {
                toggle_channels_row_selection(app);
                return;
            }
            _ => {}
        }
    }

    // Videos-screen specific keys (must run before generic q/etc.)
    if app.screen == Screen::Videos
        && let KeyCode::Char('x') = key.code
    {
        toggle_videos_row_selection(app);
        return;
    }

    // FootageDetail screen specific keys (must run before generic q/etc.)
    if app.screen == Screen::FootageDetail && handle_footage_detail_key(app, key) {
        return;
    }

    // ChannelDetail screen specific keys
    if app.screen == Screen::ChannelDetail {
        match key.code {
            KeyCode::Char('v') => {
                if let Some(ref state) = app.channel_detail_state {
                    let _ = crate::ui::channel_detail::open_in_browser(&state.channel.channel_url);
                }
                return;
            }
            KeyCode::Char('s') => {
                app.toggle_star_on_detail();
                return;
            }
            // `c` intentionally unbound on the detail screen too — connected
            // is OAuth-managed and read-only here.
            KeyCode::Char('D') => {
                if let Some(ref state) = app.channel_detail_state {
                    let id = state.channel.id;
                    app.open_delete_confirmation(vec![id]);
                }
                return;
            }
            KeyCode::Char('Y') => {
                if let Some(ref state) = app.channel_detail_state {
                    let id = state.channel.id;
                    app.open_sync_confirmation(vec![id]);
                }
                return;
            }
            KeyCode::Char('e') => {
                if let Some(ref mut state) = app.channel_detail_state {
                    state.flash = Some("URL is locked".to_string());
                }
                return;
            }
            _ => {}
        }
    }

    match key.code {
        KeyCode::Char('q') => match app.screen {
            Screen::Dashboard => app.quit(),
            Screen::ChannelDetail => app.switch_screen(Screen::Channels),
            Screen::VideoDetail => app.switch_screen(Screen::Videos),
            Screen::FootageDetail => {
                app.footage_detail_state = None;
                app.footage_detail_rects = None;
                app.footage_detail_preview = None;
                app.switch_screen(Screen::Dashboard);
            }
            _ => app.switch_screen(Screen::Dashboard),
        },
        KeyCode::Char(':') => {
            app.key_state = KeyState::ColonPrefix;
        }
        KeyCode::Char('g') => {
            app.key_state = KeyState::GPrefix;
        }
        KeyCode::Char('?') => {
            app.overlay = Some(Overlay::Help);
        }
        KeyCode::Char('n') => {
            app.toggle_theme();
        }
        KeyCode::Char('/') => {
            app.overlay = Some(Overlay::Search);
        }
        KeyCode::Char('j') | KeyCode::Down => {
            handle_move_down(app);
        }
        KeyCode::Char('k') | KeyCode::Up => {
            handle_move_up(app);
        }
        KeyCode::Enter => {
            handle_enter(app);
        }
        KeyCode::Char(' ') => {
            // SPACE is the leader key per `config/keybindings.yml`. Open the
            // popup pointed at the root menu — subsequent keys are routed
            // through `handle_leader_menu_input` until the menu closes.
            app.open_leader_menu();
        }
        KeyCode::Esc => {
            handle_esc(app);
        }
        _ => {}
    }
}

/// Handle keyboard scrub on the footage detail screen. Returns `true` when
/// the key was consumed (so `handle_normal` shouldn't fall through to its
/// generic `q` / Esc / arrow handling).
///
/// The bindings mirror the spec's keyboard-fallback list for terminals
/// without mouse support:
///
/// - `h` / `←` — step backward one frame.
/// - `l` / `→` — step forward one frame.
/// - `H` — jump 10 frames backward.
/// - `L` — jump 10 frames forward.
/// - `g` — jump to first frame (Home).
/// - `G` — jump to last frame (End).
/// - `Space` — recenter the strip under the playhead.
fn handle_footage_detail_key(app: &mut App, key: KeyEvent) -> bool {
    let consumed = {
        let Some(ref mut state) = app.footage_detail_state else {
            return false;
        };
        match key.code {
            KeyCode::Char('h') | KeyCode::Left => {
                state.step(-1);
                true
            }
            KeyCode::Char('l') | KeyCode::Right => {
                state.step(1);
                true
            }
            KeyCode::Char('H') => {
                state.step(-10);
                true
            }
            KeyCode::Char('L') => {
                state.step(10);
                true
            }
            KeyCode::Char('g') => {
                // `g` is also the navigation prefix; on the footage detail
                // screen it doubles as "jump to start" since the user already
                // navigated INTO the screen and a top-level g+key destination
                // here would surprise them.
                state.jump_to_start();
                true
            }
            KeyCode::Char('G') => {
                state.jump_to_end();
                true
            }
            KeyCode::Char(' ') => {
                state.recenter_strip();
                true
            }
            KeyCode::Home => {
                state.jump_to_start();
                true
            }
            KeyCode::End => {
                state.jump_to_end();
                true
            }
            _ => false,
        }
    };
    if consumed {
        // Every key that walks `active_timestamp_seconds` triggers a fresh
        // image fetch via the cache layer. The recenter-strip key (Space)
        // is a no-op for the preview but cheap to early-out inside
        // `refresh_active_preview_protocol`.
        app.refresh_active_preview_protocol();
    }
    consumed
}

fn handle_g_prefix(app: &mut App, key: KeyEvent) {
    app.key_state = KeyState::Normal;
    match key.code {
        KeyCode::Char('d') => app.switch_screen(Screen::Dashboard),
        KeyCode::Char('c') => app.switch_screen(Screen::Channels),
        KeyCode::Char('v') => app.switch_screen(Screen::Videos),
        KeyCode::Char('s') => app.switch_screen(Screen::SavedViews),
        KeyCode::Char('e') => app.switch_screen(Screen::Settings),
        _ => {}
    }
}

fn handle_colon_prefix(app: &mut App, key: KeyEvent) {
    app.key_state = KeyState::Normal;
    if let KeyCode::Char('q') = key.code {
        app.quit()
    }
}

fn handle_filter_prefix(app: &mut App, key: KeyEvent) {
    app.key_state = KeyState::Normal;
    if app.screen != Screen::Channels {
        return;
    }
    // Path A2 retract: there's no `syncing` boolean on the wire any more, so
    // the `f y` filter chip is gone. Only `f s` (starred) and `f c`
    // (connected) remain.
    let next = match key.code {
        KeyCode::Char('s') => Some(ChannelFilter::Starred),
        KeyCode::Char('c') => Some(ChannelFilter::Connected),
        _ => None,
    };
    if let Some(target) = next {
        // Toggle: if same filter is active, clear it.
        if app.channels_state.filter == target {
            app.channels_state.filter = ChannelFilter::None;
        } else {
            app.channels_state.filter = target;
        }
        app.channels_state.selected = 0;
        app.channels_state.scroll_offset = 0;
    }
}

fn handle_move_down(app: &mut App) {
    match app.screen {
        Screen::Channels => {
            let len = crate::ui::channels::visible_channels(&app.channels_state).len();
            if app.channels_state.selected < len.saturating_sub(1) {
                app.channels_state.selected += 1;
            }
        }
        Screen::Videos => {
            let len = app.videos_state.videos.len();
            if app.videos_state.selected < len.saturating_sub(1) {
                app.videos_state.selected += 1;
            }
        }
        Screen::ChannelDetail => {
            if let Some(ref mut state) = app.channel_detail_state {
                let len = state.videos.len();
                if state.video_selected < len.saturating_sub(1) {
                    state.video_selected += 1;
                }
            }
        }
        Screen::VideoDetail => {
            if let Some(ref mut state) = app.video_detail_state {
                let len = state.stats.len();
                if state.stats_selected < len.saturating_sub(1) {
                    state.stats_selected += 1;
                }
            }
        }
        Screen::SavedViews => {
            let len = app.saved_views_state.views.len();
            if app.saved_views_state.selected < len.saturating_sub(1) {
                app.saved_views_state.selected += 1;
            }
        }
        _ => {}
    }
}

fn handle_move_up(app: &mut App) {
    match app.screen {
        Screen::Channels if app.channels_state.selected > 0 => {
            app.channels_state.selected -= 1;
        }
        Screen::Videos if app.videos_state.selected > 0 => {
            app.videos_state.selected -= 1;
        }
        Screen::ChannelDetail => {
            if let Some(ref mut state) = app.channel_detail_state
                && state.video_selected > 0
            {
                state.video_selected -= 1;
            }
        }
        Screen::VideoDetail => {
            if let Some(ref mut state) = app.video_detail_state
                && state.stats_selected > 0
            {
                state.stats_selected -= 1;
            }
        }
        Screen::SavedViews if app.saved_views_state.selected > 0 => {
            app.saved_views_state.selected -= 1;
        }
        _ => {}
    }
}

fn handle_enter(app: &mut App) {
    match app.screen {
        Screen::Channels => {
            let visible = crate::ui::channels::visible_channels(&app.channels_state);
            if let Some(channel) = visible.get(app.channels_state.selected) {
                let id = channel.id;
                app.open_channel_detail(id);
            }
        }
        Screen::Videos => {
            if let Some(video) = app.videos_state.videos.get(app.videos_state.selected) {
                let id = video.id;
                app.open_video_detail(id);
            }
        }
        _ => {}
    }
}

/// Toggle membership of the highlighted Channels row in `selected_ids`. If
/// the row's id is already in the set, remove it; otherwise add it. No-op when
/// the visible list is empty or the cursor is out of range.
fn toggle_channels_row_selection(app: &mut App) {
    let visible = crate::ui::channels::visible_channels(&app.channels_state);
    let Some(row) = visible.get(app.channels_state.selected) else {
        return;
    };
    let id = row.id;
    if let Some(pos) = app
        .channels_state
        .selected_ids
        .iter()
        .position(|&i| i == id)
    {
        app.channels_state.selected_ids.remove(pos);
    } else {
        app.channels_state.selected_ids.push(id);
    }
}

/// Toggle membership of the highlighted Videos row in `selected_ids`. Same
/// semantics as `toggle_channels_row_selection` for the Videos screen.
fn toggle_videos_row_selection(app: &mut App) {
    let Some(video) = app.videos_state.videos.get(app.videos_state.selected) else {
        return;
    };
    let id = video.id;
    if let Some(pos) = app.videos_state.selected_ids.iter().position(|&i| i == id) {
        app.videos_state.selected_ids.remove(pos);
    } else {
        app.videos_state.selected_ids.push(id);
    }
}

fn handle_esc(app: &mut App) {
    app.clear_flash();
    match app.screen {
        Screen::Channels => {
            // Esc cancels any in-flight selection first; if the selection set
            // is already empty, fall through to clearing the active filter.
            if !app.channels_state.selected_ids.is_empty() {
                app.channels_state.selected_ids.clear();
            } else if app.channels_state.filter != ChannelFilter::None {
                app.channels_state.filter = ChannelFilter::None;
            }
        }
        Screen::Videos => {
            if !app.videos_state.selected_ids.is_empty() {
                app.videos_state.selected_ids.clear();
            }
        }
        _ => {
            app.overlay = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    fn space_event() -> KeyEvent {
        KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE)
    }

    #[test]
    fn space_opens_leader_menu_when_no_overlay_open() {
        // SPACE is the leader key per the unified `config/keybindings.yml`
        // schema. Pressing it from a normal screen must open the leader-menu
        // popup pointed at the `root` menu — mirrors the web app's posture.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.screen = Screen::Channels;

        handle_key(&mut app, space_event());

        assert_eq!(
            app.overlay,
            Some(Overlay::LeaderMenu),
            "SPACE must open the leader-menu overlay"
        );
        let state = app
            .leader_menu
            .as_ref()
            .expect("leader_menu state must be populated");
        assert_eq!(state.current_menu_name(), "root");
        assert_eq!(state.depth(), 1);
    }

    #[test]
    fn space_inside_leader_menu_closes_it() {
        // Pressing the leader key while the popup is open toggles it shut —
        // matches the web side's "leader closes when open" UX.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_leader_menu();
        assert_eq!(app.overlay, Some(Overlay::LeaderMenu));

        handle_key(&mut app, space_event());

        assert_eq!(app.overlay, None);
        assert!(app.leader_menu.is_none());
    }

    #[test]
    fn esc_closes_leader_menu_regardless_of_depth() {
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_leader_menu();
        // Push two levels deep: root → channels (via `C`).
        if let Some(ref mut state) = app.leader_menu {
            state.push_submenu("channels");
        }
        assert_eq!(
            app.leader_menu.as_ref().map(|s| s.depth()),
            Some(2),
            "should be two levels deep before Esc"
        );

        handle_key(&mut app, KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));

        assert_eq!(app.overlay, None, "Esc must close the popup");
        assert!(app.leader_menu.is_none());
    }

    #[test]
    fn backspace_pops_one_level_then_closes_at_root() {
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_leader_menu();
        if let Some(ref mut state) = app.leader_menu {
            state.push_submenu("channels");
        }

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Backspace, KeyModifiers::NONE),
        );
        // Still open, but back at root.
        assert_eq!(app.overlay, Some(Overlay::LeaderMenu));
        assert_eq!(
            app.leader_menu
                .as_ref()
                .map(|s| s.current_menu_name().to_string()),
            Some("root".to_string())
        );

        // Backspace at root closes the popup entirely.
        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Backspace, KeyModifiers::NONE),
        );
        assert_eq!(app.overlay, None);
        assert!(app.leader_menu.is_none());
    }

    #[test]
    fn leader_menu_submenu_key_pushes_onto_stack() {
        // SPACE then `C` should walk into the channels submenu.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_leader_menu();

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('C'), KeyModifiers::NONE),
        );

        let state = app
            .leader_menu
            .as_ref()
            .expect("still open after submenu push");
        assert_eq!(state.current_menu_name(), "channels");
        assert_eq!(state.depth(), 2);
    }

    #[test]
    fn leader_menu_resource_key_capital_c_drills_without_firing_action() {
        // 2026-05-11 schema revert: root resource keys are drill-only. `C`
        // at root walks into the channels submenu and must NOT set the
        // status line — no action fires alongside the drill. Single
        // keystroke == single outcome.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_leader_menu();
        app.leader_status = None;

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('C'), KeyModifiers::NONE),
        );

        // Popup is still open and now in the channels submenu.
        let state = app
            .leader_menu
            .as_ref()
            .expect("popup must remain open after drill");
        assert_eq!(state.current_menu_name(), "channels");
        assert_eq!(state.depth(), 2);

        assert!(
            app.leader_status.is_none(),
            "drill-only root key must NOT set a status line, got: {:?}",
            app.leader_status
        );
    }

    #[test]
    fn leader_menu_resource_key_capital_n_drills_without_firing_action() {
        // `N` at root drills into the notifications submenu. No `Open`
        // action fires; the user must press `l` (list) inside the submenu
        // to actually open the modal.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_leader_menu();
        app.leader_status = None;

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('N'), KeyModifiers::NONE),
        );

        let state = app
            .leader_menu
            .as_ref()
            .expect("popup must remain open after drill");
        assert_eq!(state.current_menu_name(), "notifications");
        assert_eq!(state.depth(), 2);

        assert!(
            app.leader_status.is_none(),
            "drill-only root key must NOT set a status line, got: {:?}",
            app.leader_status
        );
    }

    #[test]
    fn leader_menu_resource_key_lowercase_c_drills_without_firing_action() {
        // `c` at root drills into the calendar submenu. No Navigate fires.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_leader_menu();
        app.leader_status = None;

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE),
        );

        let state = app
            .leader_menu
            .as_ref()
            .expect("popup must remain open after drill");
        assert_eq!(state.current_menu_name(), "calendar");

        assert!(
            app.leader_status.is_none(),
            "drill-only root key must NOT set a status line, got: {:?}",
            app.leader_status
        );
    }

    #[test]
    fn switch_screen_dismisses_open_leader_menu() {
        // Defensive guard: any cross-screen navigation must close the
        // leader-menu overlay. The leader-menu input handler intercepts
        // every key while the popup is open, so this contract is
        // primarily for programmatic screen changes (e.g. confirmation
        // outcome bouncing the user from ChannelDetail back to Channels).
        // Pinning the helper's behavior keeps the invariant load-bearing.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_leader_menu();
        assert_eq!(app.overlay, Some(Overlay::LeaderMenu));
        assert!(app.leader_menu.is_some());

        app.switch_screen(Screen::Channels);

        assert_eq!(app.screen, Screen::Channels);
        assert_eq!(
            app.overlay, None,
            "switch_screen must clear the leader-menu overlay"
        );
        assert!(
            app.leader_menu.is_none(),
            "switch_screen must drop the leader-menu state"
        );
    }

    #[test]
    fn switch_screen_no_op_for_leader_menu_when_not_open() {
        // switch_screen is idempotent with respect to the leader menu —
        // when the overlay isn't open, it must NOT touch any overlay state.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        assert!(app.leader_menu.is_none());
        assert_eq!(app.overlay, None);

        app.switch_screen(Screen::Videos);

        assert_eq!(app.screen, Screen::Videos);
        assert_eq!(app.overlay, None);
        assert!(app.leader_menu.is_none());
    }

    #[test]
    fn leader_menu_quit_action_exits_tui() {
        // SPACE then `q` (TUI-only) hits the Quit action.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_leader_menu();

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('q'), KeyModifiers::NONE),
        );

        assert!(!app.running, "Quit action must flip running to false");
        assert_eq!(app.overlay, None);
        assert!(app.leader_menu.is_none());
    }

    #[test]
    fn leader_menu_navigate_action_logs_status() {
        // SPACE then `h` (home) lands a Navigate action. TUI doesn't speak
        // web routes — it surfaces a placeholder status message instead.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_leader_menu();

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('h'), KeyModifiers::NONE),
        );

        assert_eq!(app.overlay, None, "action closes the popup");
        let status = app.leader_status.as_deref().expect("status set");
        assert!(
            status.contains("/") && status.to_lowercase().contains("navigate"),
            "status should mention navigate + path, got: {status}"
        );
    }

    #[test]
    fn leader_menu_unbound_key_keeps_popup_open() {
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_leader_menu();

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('z'), KeyModifiers::NONE),
        );

        assert_eq!(
            app.overlay,
            Some(Overlay::LeaderMenu),
            "unbound key must leave the popup open"
        );
        assert_eq!(
            app.leader_menu.as_ref().map(|s| s.depth()),
            Some(1),
            "unbound key must not push or pop"
        );
    }

    #[test]
    fn b_key_is_unbound_and_does_not_affect_selection() {
        // The `b` keybinding for bulk-mode toggle is gone. Pressing it must
        // not affect selection state — there's no bulk_mode field any more.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.screen = Screen::Channels;
        app.channels_state.selected_ids.clear();
        app.channels_state.selected = 0;

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('b'), KeyModifiers::NONE),
        );

        assert!(
            app.channels_state.selected_ids.is_empty(),
            "`b` must not produce any selection state"
        );
    }

    #[test]
    fn x_toggles_row_selection_on_channels() {
        // `x` is the replacement for the retired SPACE row-selection binding.
        // First press on a highlighted row adds its id to `selected_ids`;
        // second press removes it.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.screen = Screen::Channels;
        app.channels_state.filter = ChannelFilter::None;
        app.channels_state.selected_ids.clear();
        app.channels_state.selected = 0;

        let visible = crate::ui::channels::visible_channels(&app.channels_state);
        let expected_id = visible
            .first()
            .expect("seed must include at least one channel row")
            .id;

        // Add.
        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('x'), KeyModifiers::NONE),
        );
        assert_eq!(
            app.channels_state.selected_ids,
            vec![expected_id],
            "first `x` must add the highlighted row to selected_ids"
        );

        // Remove.
        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('x'), KeyModifiers::NONE),
        );
        assert!(
            app.channels_state.selected_ids.is_empty(),
            "second `x` on the same row must remove it from selected_ids"
        );
    }

    #[test]
    fn x_toggles_row_selection_on_videos() {
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.screen = Screen::Videos;
        app.videos_state.selected_ids.clear();
        app.videos_state.selected = 0;

        let expected_id = app
            .videos_state
            .videos
            .first()
            .expect("seed must include at least one video row")
            .id;

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('x'), KeyModifiers::NONE),
        );
        assert_eq!(
            app.videos_state.selected_ids,
            vec![expected_id],
            "first `x` must add the highlighted video to selected_ids"
        );

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('x'), KeyModifiers::NONE),
        );
        assert!(
            app.videos_state.selected_ids.is_empty(),
            "second `x` on the same row must remove it from selected_ids"
        );
    }

    #[test]
    fn esc_clears_selection_before_clearing_filter() {
        // Esc on channels: first press clears an in-flight selection set;
        // a second Esc with an empty selection clears the active filter.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.screen = Screen::Channels;
        app.channels_state.selected = 0;
        app.channels_state.filter = ChannelFilter::Starred;

        let visible = crate::ui::channels::visible_channels(&app.channels_state);
        if visible.is_empty() {
            // No starred rows in the seed → reset to None and add a fake id
            // so we can still exercise the selection-clear branch.
            app.channels_state.filter = ChannelFilter::None;
        }
        app.channels_state.selected_ids = vec![42];
        app.channels_state.filter = ChannelFilter::Starred;

        handle_key(&mut app, KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
        assert!(
            app.channels_state.selected_ids.is_empty(),
            "first Esc must clear the selection set"
        );
        assert_eq!(
            app.channels_state.filter,
            ChannelFilter::Starred,
            "first Esc must leave the filter intact"
        );

        handle_key(&mut app, KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
        assert_eq!(
            app.channels_state.filter,
            ChannelFilter::None,
            "second Esc must clear the active filter"
        );
    }

    // --- Phase 25 — 01c login-pending overlay key routing ---------------

    use crate::notifications::login_pending::LoginPendingCard;
    use crate::notifications::overlay::Stage;

    fn pending_card() -> LoginPendingCard {
        LoginPendingCard {
            notification_id: 1,
            login_attempt_id: Some(42),
            title: "new-location login: alice@example.com".to_string(),
            browser_os: "Chrome on macOS".to_string(),
            location: "Berlin, Germany (BE)".to_string(),
            ip: "203.0.113.42".to_string(),
            fingerprint: "abc123def456".to_string(),
        }
    }

    #[test]
    fn login_pending_a_then_y_fires_approve_through_confirmation_stage() {
        // Two-step pattern: `a` on the card moves to ConfirmApprove;
        // `y` on the confirm stage is what fires the wire call. With
        // no network reachable in the unit test, `confirm_login_pending_approve`
        // still transitions the overlay through Working → Done (with
        // an error status). The contract under test is the stage walk,
        // not the network outcome.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_login_pending_overlay(pending_card());

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE),
        );
        assert_eq!(
            app.login_pending.as_ref().map(|s| s.stage),
            Some(Stage::ConfirmApprove),
            "`a` on the card stage must advance to ConfirmApprove"
        );

        // `y` on ConfirmApprove fires the underlying POST. The mock
        // backend isn't on the wire; the call lands in `Done` with an
        // error status.
        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('y'), KeyModifiers::NONE),
        );
        let state = app
            .login_pending
            .as_ref()
            .expect("overlay still present after fire");
        assert_eq!(state.stage, Stage::Done, "Done stage after fire");
    }

    #[test]
    fn login_pending_b_then_y_fires_block_through_confirmation_stage() {
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_login_pending_overlay(pending_card());

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('b'), KeyModifiers::NONE),
        );
        assert_eq!(
            app.login_pending.as_ref().map(|s| s.stage),
            Some(Stage::ConfirmBlock),
            "`b` on the card stage must advance to ConfirmBlock"
        );

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('y'), KeyModifiers::NONE),
        );
        let state = app
            .login_pending
            .as_ref()
            .expect("overlay still present after fire");
        assert_eq!(state.stage, Stage::Done);
    }

    #[test]
    fn login_pending_esc_on_confirm_drops_back_to_card_stage() {
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_login_pending_overlay(pending_card());

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE),
        );
        assert_eq!(
            app.login_pending.as_ref().map(|s| s.stage),
            Some(Stage::ConfirmApprove)
        );

        handle_key(&mut app, KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
        assert_eq!(
            app.login_pending.as_ref().map(|s| s.stage),
            Some(Stage::Card),
            "Esc on confirm stage must return to the card view"
        );
        assert_eq!(
            app.overlay,
            Some(Overlay::LoginPending),
            "Esc on confirm stage must NOT close the overlay"
        );
    }

    #[test]
    fn login_pending_esc_on_card_closes_overlay() {
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_login_pending_overlay(pending_card());
        assert_eq!(app.overlay, Some(Overlay::LoginPending));

        handle_key(&mut app, KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
        assert_eq!(
            app.overlay, None,
            "Esc on the card stage closes the overlay"
        );
        assert!(app.login_pending.is_none());
    }

    #[test]
    fn login_pending_l_on_card_closes_overlay() {
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_login_pending_overlay(pending_card());

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('l'), KeyModifiers::NONE),
        );
        assert_eq!(app.overlay, None);
        assert!(app.login_pending.is_none());
    }

    #[test]
    fn status_line_prompt_shortcut_a_opens_overlay_on_dashboard() {
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.screen = Screen::Dashboard;
        app.login_pending_count = 1;
        app.login_pending_card_cache = Some(pending_card());

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE),
        );

        assert_eq!(app.overlay, Some(Overlay::LoginPending));
        assert_eq!(
            app.login_pending.as_ref().map(|s| s.stage),
            Some(Stage::ConfirmApprove),
            "status-line `a` shortcut opens directly into approve confirm"
        );
    }

    #[test]
    fn status_line_prompt_shortcut_b_opens_overlay_on_dashboard() {
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.screen = Screen::Dashboard;
        app.login_pending_count = 1;
        app.login_pending_card_cache = Some(pending_card());

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('b'), KeyModifiers::NONE),
        );

        assert_eq!(app.overlay, Some(Overlay::LoginPending));
        assert_eq!(
            app.login_pending.as_ref().map(|s| s.stage),
            Some(Stage::ConfirmBlock)
        );
    }

    #[test]
    fn status_line_prompt_shortcut_l_clears_cache_and_count() {
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.screen = Screen::Dashboard;
        app.login_pending_count = 3;
        app.login_pending_card_cache = Some(pending_card());

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('l'), KeyModifiers::NONE),
        );

        assert_eq!(app.login_pending_count, 0);
        assert!(app.login_pending_card_cache.is_none());
        assert_eq!(app.overlay, None, "`l` must NOT open the overlay");
    }

    #[test]
    fn status_line_prompt_shortcut_inert_on_channels_screen() {
        // Channels uses `s`/`D`/`Y`/`f`/`x` extensively; the prompt
        // shortcut is opt-out there to avoid surprising the user.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.screen = Screen::Channels;
        app.login_pending_count = 1;
        app.login_pending_card_cache = Some(pending_card());

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE),
        );
        assert_eq!(
            app.overlay, None,
            "`a` on Channels must NOT open the overlay"
        );
    }

    #[test]
    fn status_line_prompt_shortcut_inert_when_count_zero() {
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.screen = Screen::Dashboard;
        app.login_pending_count = 0;
        app.login_pending_card_cache = None;

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE),
        );
        assert_eq!(
            app.overlay, None,
            "`a` with no pending count must NOT open the overlay"
        );
    }

    #[test]
    fn login_pending_overlay_takes_precedence_over_leader_menu() {
        // Pressing SPACE while the pending overlay is open must NOT
        // open the leader menu — the pending overlay's keymap wins.
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.open_login_pending_overlay(pending_card());

        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE),
        );

        assert_eq!(
            app.overlay,
            Some(Overlay::LoginPending),
            "SPACE inside the pending overlay must not open leader menu"
        );
        assert!(
            app.leader_menu.is_none(),
            "leader-menu state must stay empty"
        );
    }
}
