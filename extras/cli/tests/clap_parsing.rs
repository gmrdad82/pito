//! Unit-style integration tests for the Phase 21 clap surface.
//!
//! These exercise `Cli::try_parse_from` to assert each new subcommand
//! parses, its required positional / option args land in the right
//! field, and the `--confirm yes` / `--json` shared idioms work the same
//! way they do for the existing `pito auth` family.

use clap::Parser;
use pito::cli::{CalendarCommand, Cli, Commands, GamesCommand, NotificationsCommand};
use pito::confirm::YesNo;

fn parse(argv: &[&str]) -> Cli {
    Cli::try_parse_from(argv).expect("parse")
}

// --- games ------------------------------------------------------------------

#[test]
fn games_list_with_no_args_parses() {
    let cli = parse(&["pito", "games", "list"]);
    match cli.command {
        Some(Commands::Games(args)) => match args.command {
            GamesCommand::List(a) => {
                assert!(a.sort.is_none());
                assert!(a.dir.is_none());
                assert!(a.page.is_none());
                assert_eq!(a.limit, 50); // default
                assert!(!a.json);
            }
            _ => panic!("expected GamesCommand::List"),
        },
        _ => panic!("expected Commands::Games"),
    }
}

#[test]
fn games_list_accepts_sort_dir_page_genre_platform_owned_limit_json() {
    let cli = parse(&[
        "pito",
        "games",
        "list",
        "--sort",
        "release_year",
        "--dir",
        "desc",
        "--page",
        "2",
        "--genre",
        "puzzle",
        "--platform-owned",
        "3",
        "--limit",
        "10",
        "--json",
    ]);
    match cli.command {
        Some(Commands::Games(args)) => match args.command {
            GamesCommand::List(a) => {
                assert_eq!(a.sort.as_deref(), Some("release_year"));
                assert_eq!(a.dir.as_deref(), Some("desc"));
                assert_eq!(a.page, Some(2));
                assert_eq!(a.genre.as_deref(), Some("puzzle"));
                assert_eq!(a.platform_owned.as_deref(), Some("3"));
                assert_eq!(a.limit, 10);
                assert!(a.json);
            }
            _ => panic!("expected GamesCommand::List"),
        },
        _ => panic!("expected Commands::Games"),
    }
}

#[test]
fn games_show_accepts_slug_positional() {
    let cli = parse(&["pito", "games", "show", "the-witness"]);
    match cli.command {
        Some(Commands::Games(args)) => match args.command {
            GamesCommand::Show(a) => assert_eq!(a.slug_or_id, "the-witness"),
            _ => panic!("expected GamesCommand::Show"),
        },
        _ => panic!("expected Commands::Games"),
    }
}

#[test]
fn games_show_accepts_integer_id_positional_unchanged() {
    let cli = parse(&["pito", "games", "show", "42"]);
    match cli.command {
        Some(Commands::Games(args)) => match args.command {
            GamesCommand::Show(a) => assert_eq!(a.slug_or_id, "42"),
            _ => panic!("expected GamesCommand::Show"),
        },
        _ => panic!("expected Commands::Games"),
    }
}

#[test]
fn games_search_accepts_query_and_limit() {
    let cli = parse(&["pito", "games", "search", "witness", "--limit", "5"]);
    match cli.command {
        Some(Commands::Games(args)) => match args.command {
            GamesCommand::Search(a) => {
                assert_eq!(a.query, "witness");
                assert_eq!(a.limit, 5);
            }
            _ => panic!("expected GamesCommand::Search"),
        },
        _ => panic!("expected Commands::Games"),
    }
}

#[test]
fn games_resync_without_confirm_keeps_confirm_none() {
    let cli = parse(&["pito", "games", "resync", "42"]);
    match cli.command {
        Some(Commands::Games(args)) => match args.command {
            GamesCommand::Resync(a) => {
                assert_eq!(a.slug_or_id, "42");
                assert!(a.confirm.is_none());
            }
            _ => panic!("expected GamesCommand::Resync"),
        },
        _ => panic!("expected Commands::Games"),
    }
}

#[test]
fn games_resync_with_confirm_yes_parses() {
    let cli = parse(&["pito", "games", "resync", "42", "--confirm", "yes"]);
    match cli.command {
        Some(Commands::Games(args)) => match args.command {
            GamesCommand::Resync(a) => assert_eq!(a.confirm, Some(YesNo::Yes)),
            _ => panic!("expected GamesCommand::Resync"),
        },
        _ => panic!("expected Commands::Games"),
    }
}

#[test]
fn games_resync_rejects_confirm_true_string() {
    // The yes/no boundary rule forbids `--confirm true` / `--confirm 1`.
    let result = Cli::try_parse_from(["pito", "games", "resync", "42", "--confirm", "true"]);
    assert!(result.is_err(), "clap must reject `--confirm true`");
}

// --- calendar ---------------------------------------------------------------

#[test]
fn calendar_schedule_with_no_args_parses() {
    let cli = parse(&["pito", "calendar", "schedule"]);
    match cli.command {
        Some(Commands::Calendar(args)) => match args.command {
            CalendarCommand::Schedule(a) => {
                assert!(a.types.is_none());
                assert_eq!(a.limit, 50);
            }
            _ => panic!("expected schedule"),
        },
        _ => panic!("expected Commands::Calendar"),
    }
}

#[test]
fn calendar_schedule_with_filters_parses() {
    let cli = parse(&[
        "pito",
        "calendar",
        "schedule",
        "--types",
        "video,game",
        "--source",
        "derived",
        "--state",
        "scheduled",
        "--page",
        "2",
    ]);
    match cli.command {
        Some(Commands::Calendar(args)) => match args.command {
            CalendarCommand::Schedule(a) => {
                assert_eq!(a.types.as_deref(), Some("video,game"));
                assert_eq!(a.source.as_deref(), Some("derived"));
                assert_eq!(a.state.as_deref(), Some("scheduled"));
                assert_eq!(a.page, Some(2));
            }
            _ => panic!("expected schedule"),
        },
        _ => panic!("expected Commands::Calendar"),
    }
}

#[test]
fn calendar_month_requires_year_and_month_positionals() {
    let cli = parse(&["pito", "calendar", "month", "2026", "5"]);
    match cli.command {
        Some(Commands::Calendar(args)) => match args.command {
            CalendarCommand::Month(a) => {
                assert_eq!(a.year, 2026);
                assert_eq!(a.month, 5);
            }
            _ => panic!("expected month"),
        },
        _ => panic!("expected Commands::Calendar"),
    }
}

#[test]
fn calendar_show_takes_id_positional() {
    let cli = parse(&["pito", "calendar", "show", "12"]);
    match cli.command {
        Some(Commands::Calendar(args)) => match args.command {
            CalendarCommand::Show(a) => assert_eq!(a.id, 12),
            _ => panic!("expected show"),
        },
        _ => panic!("expected Commands::Calendar"),
    }
}

#[test]
fn calendar_create_requires_three_named_args() {
    // entry_type, title, starts_at are required. Missing any → error.
    let result = Cli::try_parse_from([
        "pito",
        "calendar",
        "create",
        "--entry-type",
        "milestone_manual",
        "--title",
        "ship",
        // --starts-at intentionally missing
    ]);
    assert!(result.is_err());
}

#[test]
fn calendar_create_full_args_parse() {
    let cli = parse(&[
        "pito",
        "calendar",
        "create",
        "--entry-type",
        "milestone_manual",
        "--title",
        "ship phase 21",
        "--starts-at",
        "2026-06-01T10:00:00Z",
        "--all-day",
        "no",
        "--timezone",
        "Europe/Bucharest",
        "--parent-entry-id",
        "7",
    ]);
    match cli.command {
        Some(Commands::Calendar(args)) => match args.command {
            CalendarCommand::Create(a) => {
                assert_eq!(a.entry_type, "milestone_manual");
                assert_eq!(a.title, "ship phase 21");
                assert_eq!(a.starts_at, "2026-06-01T10:00:00Z");
                assert_eq!(a.all_day, Some(YesNo::No));
                assert_eq!(a.parent_entry_id, Some(7));
            }
            _ => panic!("expected create"),
        },
        _ => panic!("expected Commands::Calendar"),
    }
}

#[test]
fn calendar_create_rejects_all_day_true_string() {
    let result = Cli::try_parse_from([
        "pito",
        "calendar",
        "create",
        "--entry-type",
        "milestone_manual",
        "--title",
        "x",
        "--starts-at",
        "2026-06-01T10:00:00Z",
        "--all-day",
        "true",
    ]);
    assert!(
        result.is_err(),
        "clap must reject `--all-day true` per yes/no boundary"
    );
}

#[test]
fn calendar_update_takes_id_and_optional_args() {
    let cli = parse(&[
        "pito",
        "calendar",
        "update",
        "12",
        "--title",
        "renamed",
        "--all-day",
        "yes",
    ]);
    match cli.command {
        Some(Commands::Calendar(args)) => match args.command {
            CalendarCommand::Update(a) => {
                assert_eq!(a.id, 12);
                assert_eq!(a.title.as_deref(), Some("renamed"));
                assert_eq!(a.all_day, Some(YesNo::Yes));
            }
            _ => panic!("expected update"),
        },
        _ => panic!("expected Commands::Calendar"),
    }
}

#[test]
fn calendar_note_takes_id_and_required_note() {
    let cli = parse(&["pito", "calendar", "note", "12", "--note", "hello"]);
    match cli.command {
        Some(Commands::Calendar(args)) => match args.command {
            CalendarCommand::Note(a) => {
                assert_eq!(a.id, 12);
                assert_eq!(a.note, "hello");
            }
            _ => panic!("expected note"),
        },
        _ => panic!("expected Commands::Calendar"),
    }
}

#[test]
fn calendar_cancel_requires_ids_flag() {
    let result = Cli::try_parse_from(["pito", "calendar", "cancel"]);
    assert!(result.is_err());
}

#[test]
fn calendar_cancel_with_csv_ids_parses() {
    let cli = parse(&["pito", "calendar", "cancel", "--ids", "12,55"]);
    match cli.command {
        Some(Commands::Calendar(args)) => match args.command {
            CalendarCommand::Cancel(a) => {
                assert_eq!(a.ids, "12,55");
                assert!(a.confirm.is_none());
            }
            _ => panic!("expected cancel"),
        },
        _ => panic!("expected Commands::Calendar"),
    }
}

// --- notifications ----------------------------------------------------------

#[test]
fn notifications_list_with_no_args_parses() {
    let cli = parse(&["pito", "notifications", "list"]);
    match cli.command {
        Some(Commands::Notifications(args)) => match args.command {
            NotificationsCommand::List(a) => {
                assert!(a.filter.is_none());
                assert!(a.kind.is_none());
                assert!(a.severity.is_none());
                assert_eq!(a.limit, 50);
            }
            _ => panic!("expected list"),
        },
        _ => panic!("expected Commands::Notifications"),
    }
}

#[test]
fn notifications_list_with_filter_kind_severity_page() {
    let cli = parse(&[
        "pito",
        "notifications",
        "list",
        "--filter",
        "unread",
        "--kind",
        "video_published",
        "--severity",
        "success",
        "--page",
        "3",
    ]);
    match cli.command {
        Some(Commands::Notifications(args)) => match args.command {
            NotificationsCommand::List(a) => {
                assert_eq!(a.filter.as_deref(), Some("unread"));
                assert_eq!(a.kind.as_deref(), Some("video_published"));
                assert_eq!(a.severity.as_deref(), Some("success"));
                assert_eq!(a.page, Some(3));
            }
            _ => panic!("expected list"),
        },
        _ => panic!("expected Commands::Notifications"),
    }
}

#[test]
fn notifications_show_takes_id_positional() {
    let cli = parse(&["pito", "notifications", "show", "91"]);
    match cli.command {
        Some(Commands::Notifications(args)) => match args.command {
            NotificationsCommand::Show(a) => assert_eq!(a.id, 91),
            _ => panic!("expected show"),
        },
        _ => panic!("expected Commands::Notifications"),
    }
}

#[test]
fn notifications_badge_parses() {
    let cli = parse(&["pito", "notifications", "badge"]);
    match cli.command {
        Some(Commands::Notifications(args)) => match args.command {
            NotificationsCommand::Badge(_) => {}
            _ => panic!("expected badge"),
        },
        _ => panic!("expected Commands::Notifications"),
    }
}

#[test]
fn notifications_read_takes_id_positional() {
    let cli = parse(&["pito", "notifications", "read", "91"]);
    match cli.command {
        Some(Commands::Notifications(args)) => match args.command {
            NotificationsCommand::Read(a) => assert_eq!(a.id, 91),
            _ => panic!("expected read"),
        },
        _ => panic!("expected Commands::Notifications"),
    }
}

#[test]
fn notifications_unread_takes_id_positional() {
    let cli = parse(&["pito", "notifications", "unread", "91"]);
    match cli.command {
        Some(Commands::Notifications(args)) => match args.command {
            NotificationsCommand::Unread(a) => assert_eq!(a.id, 91),
            _ => panic!("expected unread"),
        },
        _ => panic!("expected Commands::Notifications"),
    }
}

#[test]
fn notifications_mark_read_requires_ids_flag() {
    let result = Cli::try_parse_from(["pito", "notifications", "mark-read"]);
    assert!(result.is_err());
}

#[test]
fn notifications_mark_read_with_ids_parses() {
    let cli = parse(&["pito", "notifications", "mark-read", "--ids", "12,13"]);
    match cli.command {
        Some(Commands::Notifications(args)) => match args.command {
            NotificationsCommand::MarkRead(a) => assert_eq!(a.ids, "12,13"),
            _ => panic!("expected mark-read"),
        },
        _ => panic!("expected Commands::Notifications"),
    }
}

#[test]
fn notifications_mark_all_read_takes_no_required_args() {
    let cli = parse(&["pito", "notifications", "mark-all-read"]);
    match cli.command {
        Some(Commands::Notifications(args)) => match args.command {
            NotificationsCommand::MarkAllRead(a) => assert!(a.confirm.is_none()),
            _ => panic!("expected mark-all-read"),
        },
        _ => panic!("expected Commands::Notifications"),
    }
}

#[test]
fn notifications_mark_all_read_with_confirm_yes_parses() {
    let cli = parse(&["pito", "notifications", "mark-all-read", "--confirm", "yes"]);
    match cli.command {
        Some(Commands::Notifications(args)) => match args.command {
            NotificationsCommand::MarkAllRead(a) => assert_eq!(a.confirm, Some(YesNo::Yes)),
            _ => panic!("expected mark-all-read"),
        },
        _ => panic!("expected Commands::Notifications"),
    }
}
