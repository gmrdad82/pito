//! Unified keybindings schema — TUI half.
//!
//! Reads `config/keybindings.yml` at the workspace root and exposes the
//! filtered (`surfaces: [tui]`-aware) menu tree to the rest of the CLI.
//!
//! The YAML is the single source of truth shared with the Rails web app's
//! Stimulus `leader-menu` controller. Both surfaces parse the same file at
//! load time; edit once, both stacks pick up the change.
//!
//! Path resolution: the YAML is `include_str!`-embedded at compile time using
//! a path relative to this source file (`../../../config/keybindings.yml`).
//! Embedding rather than reading at runtime sidesteps any working-directory
//! confusion when the user runs `pito` from somewhere other than the repo
//! root, and means there's no IO failure mode at startup for this resource.

use std::collections::HashMap;
use std::sync::OnceLock;

use serde::Deserialize;

/// The YAML source embedded at compile time. Relative to this source file
/// (`extras/cli/src/keybindings.rs`), the workspace root config file lives at
/// `../../../config/keybindings.yml` (up: `src/` → `cli/` → `extras/` → repo).
const EMBEDDED_YAML: &str = include_str!("../../../config/keybindings.yml");

/// Top-level schema.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct KeybindingsSchema {
    pub leader: Leader,
    pub menus: HashMap<String, Menu>,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct Leader {
    pub key: String,
    pub display: String,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct Menu {
    pub items: Vec<Item>,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct Item {
    pub key: String,
    pub label: String,
    #[serde(default)]
    pub action: Option<Action>,
    #[serde(default)]
    pub submenu: Option<String>,
    #[serde(default)]
    pub surfaces: Option<Vec<String>>,
}

/// Action variants. Tagged with `type` to match the YAML shape
/// (`{ type: navigate, path: "/channels" }`).
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Action {
    Navigate { path: String },
    Quit,
    QuitAndLogout,
    Open { target: String },
    Today,
    BulkDelete,
    BulkSync,
    BulkResync,
    FilterUnread,
    MarkAllRead,
    ContextualAdd,
}

/// Cached, filtered-for-TUI schema. Parsed once on first access.
static SCHEMA: OnceLock<KeybindingsSchema> = OnceLock::new();

/// Surface identifier used to filter the schema. The TUI consumes the
/// `Tui`-filtered view; items tagged `surfaces: [web]` are dropped, items
/// tagged `surfaces: [tui]` are kept, items without a `surfaces` key are
/// kept (default = both surfaces).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Surface {
    Tui,
    #[allow(dead_code)] // present for symmetry; never used by binary code
    Web,
}

impl Surface {
    fn tag(self) -> &'static str {
        match self {
            Surface::Tui => "tui",
            Surface::Web => "web",
        }
    }
}

/// Parse a YAML string into a schema. Exposed for tests; the binary path
/// uses [`load`] which caches the embedded copy.
pub fn parse(yaml: &str) -> Result<KeybindingsSchema, serde_yaml::Error> {
    serde_yaml::from_str(yaml)
}

/// Load the embedded schema, parsed once and cached. Panics if the embedded
/// YAML is malformed — that's a build-time bug, not a runtime user error.
pub fn load() -> &'static KeybindingsSchema {
    SCHEMA.get_or_init(|| {
        parse(EMBEDDED_YAML).expect("embedded config/keybindings.yml must parse at startup")
    })
}

/// Convenience: a filtered view of `load()` for the given surface. Items
/// whose `surfaces` field excludes this surface are dropped from each menu's
/// `items` list; the rest of the schema is preserved verbatim.
pub fn filtered_for(surface: Surface) -> KeybindingsSchema {
    let raw = load();
    let menus = raw
        .menus
        .iter()
        .map(|(name, menu)| {
            let items: Vec<Item> = menu
                .items
                .iter()
                .filter(|i| item_visible(i, surface))
                .cloned()
                .collect();
            (name.clone(), Menu { items })
        })
        .collect();
    KeybindingsSchema {
        leader: raw.leader.clone(),
        menus,
    }
}

/// Visibility check. An item is visible on a surface when:
/// - its `surfaces` is `None` (default → all surfaces), OR
/// - its `surfaces` contains the surface tag (e.g. `"tui"`).
pub fn item_visible(item: &Item, surface: Surface) -> bool {
    match &item.surfaces {
        None => true,
        Some(list) => list.iter().any(|s| s == surface.tag()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedded_yaml_parses() {
        // The build-time embedded YAML must parse cleanly. If this fails, the
        // panic in `load()` would mask the real diagnostic; assert here so a
        // malformed YAML lands as a precise test failure first.
        let schema = parse(EMBEDDED_YAML).expect("embedded YAML must parse");
        assert_eq!(schema.leader.key, " ");
        assert_eq!(schema.leader.display, "_");
        assert!(schema.menus.contains_key("root"));
        assert!(schema.menus.contains_key("channels"));
        assert!(schema.menus.contains_key("videos"));
        assert!(schema.menus.contains_key("calendar"));
    }

    #[test]
    fn parses_action_variants() {
        // Confirm every tagged action variant we expect to encounter in the
        // YAML round-trips cleanly. A misspelt `type` would surface here.
        let schema = parse(EMBEDDED_YAML).expect("parse");
        let root = schema.menus.get("root").expect("root menu");

        let home = root.items.iter().find(|i| i.key == "h").expect("h item");
        assert_eq!(
            home.action,
            Some(Action::Navigate {
                path: "/".to_string()
            })
        );

        let quit = root.items.iter().find(|i| i.key == "q").expect("q item");
        assert_eq!(quit.action, Some(Action::Quit));
        assert_eq!(quit.surfaces.as_deref(), Some(&["tui".to_string()][..]));

        let quit_logout = root.items.iter().find(|i| i.key == "Q").expect("Q item");
        assert_eq!(quit_logout.action, Some(Action::QuitAndLogout));

        // 2026-05-11 schema revert: root resource keys (c, C, V, P, G, N)
        // are drill-only. They DROP the `action` field; pressing the key
        // walks into the submenu without firing any side effect. `c` is the
        // calendar resource: action = None, submenu = "calendar".
        let calendar = root.items.iter().find(|i| i.key == "c").expect("c item");
        assert_eq!(calendar.action, None);
        assert_eq!(calendar.submenu.as_deref(), Some("calendar"));
    }

    #[test]
    fn root_resource_keys_are_drill_only() {
        // The six root-menu resource keys (c, C, V, P, G, N) drill into their
        // submenu and carry NO `action` field. The combined action+submenu
        // shape (`ActionThenSubmenu`) was retired in the 2026-05-11 schema
        // revert because a single keystroke firing both a navigate AND
        // drilling proved surprising. The user must press `l` (list) inside
        // the drilled-into submenu to actually navigate. See
        // `keys::handle_leader_menu_input` and the corresponding drill-only
        // tests.
        let schema = parse(EMBEDDED_YAML).expect("parse");
        let root = schema.menus.get("root").expect("root menu");

        let cases: &[(&str, &str)] = &[
            ("c", "calendar"),
            ("C", "channels"),
            ("V", "videos"),
            ("P", "projects"),
            ("G", "games"),
            ("N", "notifications"),
        ];

        for (key, expected_submenu) in cases {
            let item = root
                .items
                .iter()
                .find(|i| i.key == *key)
                .unwrap_or_else(|| panic!("root key `{}` missing", key));
            assert_eq!(
                item.action, None,
                "root `{}` must NOT carry an action — drill-only",
                key
            );
            assert_eq!(
                item.submenu.as_deref(),
                Some(*expected_submenu),
                "root `{}` must drill into submenu `{}`",
                key,
                expected_submenu
            );
        }
    }

    #[test]
    fn parses_open_action_with_target() {
        let schema = parse(EMBEDDED_YAML).expect("parse");
        let videos = schema.menus.get("videos").expect("videos menu");
        let upload = videos.items.iter().find(|i| i.key == "+").expect("+ item");
        assert_eq!(
            upload.action,
            Some(Action::Open {
                target: "video_upload".to_string()
            })
        );
    }

    #[test]
    fn parses_today_action() {
        let schema = parse(EMBEDDED_YAML).expect("parse");
        let calendar = schema.menus.get("calendar").expect("calendar menu");
        let today = calendar
            .items
            .iter()
            .find(|i| i.key == "t")
            .expect("t item");
        assert_eq!(today.action, Some(Action::Today));
    }

    #[test]
    fn parses_bulk_action_variants() {
        let schema = parse(EMBEDDED_YAML).expect("parse");
        let channels = schema.menus.get("channels").expect("channels menu");

        let bulk_delete = channels
            .items
            .iter()
            .find(|i| i.key == "-")
            .expect("- item");
        assert_eq!(bulk_delete.action, Some(Action::BulkDelete));

        let bulk_sync = channels
            .items
            .iter()
            .find(|i| i.key == "y")
            .expect("y item");
        assert_eq!(bulk_sync.action, Some(Action::BulkSync));

        let games = schema.menus.get("games").expect("games menu");
        let bulk_resync = games.items.iter().find(|i| i.key == "r").expect("r item");
        assert_eq!(bulk_resync.action, Some(Action::BulkResync));
    }

    #[test]
    fn parses_notifications_action_variants() {
        let schema = parse(EMBEDDED_YAML).expect("parse");
        let notif = schema.menus.get("notifications").expect("notif menu");
        let unread = notif.items.iter().find(|i| i.key == "u").expect("u item");
        assert_eq!(unread.action, Some(Action::FilterUnread));
        let mark = notif.items.iter().find(|i| i.key == "m").expect("m item");
        assert_eq!(mark.action, Some(Action::MarkAllRead));
    }

    #[test]
    fn parses_contextual_add() {
        let schema = parse(EMBEDDED_YAML).expect("parse");
        let ops = schema.menus.get("list_ops").expect("list_ops menu");
        let add = ops.items.iter().find(|i| i.key == "+").expect("+ item");
        assert_eq!(add.action, Some(Action::ContextualAdd));
    }

    #[test]
    fn filter_for_tui_keeps_tui_only_items() {
        // The root menu's `q` item is tagged `surfaces: [tui]`. The TUI
        // filter must keep it.
        let filtered = filtered_for(Surface::Tui);
        let root = filtered.menus.get("root").expect("root present");
        assert!(
            root.items.iter().any(|i| i.key == "q"),
            "tui-only `q` quit item must be present in the TUI-filtered schema"
        );
    }

    #[test]
    fn filter_for_web_drops_tui_only_items() {
        let filtered = filtered_for(Surface::Web);
        let root = filtered.menus.get("root").expect("root present");
        assert!(
            !root.items.iter().any(|i| i.key == "q"),
            "tui-only `q` quit item must be hidden from the web-filtered schema"
        );
    }

    #[test]
    fn filter_keeps_items_with_no_surfaces_field() {
        // Items without a `surfaces` key are visible everywhere.
        let tui = filtered_for(Surface::Tui);
        let root = tui.menus.get("root").expect("root present");
        assert!(
            root.items.iter().any(|i| i.key == "h"),
            "default-visible items must appear on TUI"
        );

        let web = filtered_for(Surface::Web);
        let root = web.menus.get("root").expect("root present");
        assert!(
            root.items.iter().any(|i| i.key == "h"),
            "default-visible items must appear on web"
        );
    }

    #[test]
    fn item_visible_handles_multi_surface_list() {
        let item = Item {
            key: "x".to_string(),
            label: "x".to_string(),
            action: None,
            submenu: None,
            surfaces: Some(vec!["web".to_string(), "tui".to_string()]),
        };
        assert!(item_visible(&item, Surface::Tui));
        assert!(item_visible(&item, Surface::Web));
    }

    #[test]
    fn load_is_cached() {
        // Two calls return references to the same allocation — proves the
        // OnceLock cache is actually doing its job.
        let a = load();
        let b = load();
        assert!(std::ptr::eq(a, b));
    }
}
