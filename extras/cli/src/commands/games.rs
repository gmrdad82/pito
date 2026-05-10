//! `pito games {list,show,search,resync}` — Phase 21 surfaces.
//!
//! Each subcommand wraps a single endpoint in
//! `crate::api::endpoints::games`. Read paths follow the search/views
//! convention: plaintext table by default, `--json` switches to the raw
//! wire shape (the same JSON the server emits, possibly trimmed to the
//! requested limit).

use anyhow::Result;

use crate::api::endpoints::EndpointsClient;
use crate::api::endpoints::games::{GameDetail, GameSearchHit, GameSummary, GamesIndexQuery};
use crate::auth;
use crate::cli::{
    GamesArgs, GamesCommand, GamesListArgs, GamesResyncArgs, GamesSearchArgs, GamesShowArgs,
};
use crate::confirm;
use crate::output::{ExitCode, OutputMode, render_kv, render_table};

pub fn run(args: GamesArgs) -> Result<()> {
    match args.command {
        GamesCommand::List(a) => run_list(a),
        GamesCommand::Show(a) => run_show(a),
        GamesCommand::Search(a) => run_search(a),
        GamesCommand::Resync(a) => run_resync(a),
    }
}

fn build_client() -> Result<EndpointsClient> {
    let _ = dotenvy::dotenv();
    let resolved = auth::resolve(
        auth::load_file(&auth::auth_file_path()?)?.as_ref(),
        &auth::Env::system(),
    );
    Ok(EndpointsClient::new(
        resolved.base_url.clone(),
        resolved.token.clone(),
    ))
}

// --- list -------------------------------------------------------------------

fn run_list(args: GamesListArgs) -> Result<()> {
    let client = build_client()?;
    let q = GamesIndexQuery {
        sort: args.sort,
        dir: args.dir,
        page: args.page,
        genre: args.genre,
        platform_owned: args.platform_owned,
    };
    let mode = OutputMode::from_json_flag(args.json);
    let resp = match client.games_list(&q) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("network error: {}", e);
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };
    let limited: Vec<GameSummary> = resp.games.into_iter().take(args.limit as usize).collect();
    match mode {
        OutputMode::Json => {
            // Echo the locked wire shape, but with the rendered limit applied.
            let payload = serde_json::json!({
                "games": limited,
                "filter": resp.filter,
                "sort": resp.sort,
            });
            println!("{}", serde_json::to_string(&payload)?);
        }
        OutputMode::Plaintext => {
            print!("{}", render_games_table(&limited));
        }
    }
    Ok(())
}

pub fn render_games_table(games: &[GameSummary]) -> String {
    let rows: Vec<Vec<String>> = games
        .iter()
        .map(|g| {
            vec![
                g.id.to_string(),
                g.slug.clone(),
                g.title.clone(),
                g.release_year.map(|y| y.to_string()).unwrap_or_default(),
                if g.resyncing { "yes" } else { "no" }.to_string(),
            ]
        })
        .collect();
    render_table(&["id", "slug", "title", "year", "resyncing"], &rows)
}

// --- show -------------------------------------------------------------------

fn run_show(args: GamesShowArgs) -> Result<()> {
    let client = build_client()?;
    let mode = OutputMode::from_json_flag(args.json);
    let resp = match client.games_show(&args.slug_or_id) {
        Ok(r) => r,
        Err(e) => {
            let msg = format!("{}", e);
            eprintln!("network error: {}", msg);
            // Distinguish 404 if the error context mentions it. Best-effort —
            // `error_for_status` does not preserve the status enum in the
            // anyhow chain we wrap here; the message is the only signal.
            if msg.contains("404") {
                std::process::exit(ExitCode::NotFound.as_i32());
            }
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };
    match mode {
        OutputMode::Json => {
            println!("{}", serde_json::to_string(&resp)?);
        }
        OutputMode::Plaintext => {
            print!("{}", render_game_detail(&resp.game));
        }
    }
    Ok(())
}

pub fn render_game_detail(g: &GameDetail) -> String {
    let mut rows: Vec<(&str, String)> = vec![
        ("id", g.id.to_string()),
        ("slug", g.slug.clone()),
        ("title", g.title.clone()),
    ];
    if let Some(y) = g.release_year {
        rows.push(("release_year", y.to_string()));
    }
    if let Some(d) = &g.release_date {
        rows.push(("release_date", d.clone()));
    }
    if let Some(r) = g.igdb_rating {
        rows.push(("igdb_rating", format!("{:.1}", r)));
    }
    if let Some(p) = g.platform_owned_id {
        rows.push(("platform_owned_id", p.to_string()));
    }
    rows.push((
        "resyncing",
        if g.resyncing { "yes" } else { "no" }.to_string(),
    ));
    if let Some(t) = &g.igdb_synced_at {
        rows.push(("igdb_synced_at", t.clone()));
    }
    if !g.genres.is_empty() {
        let names: Vec<String> = g.genres.iter().map(|x| x.name.clone()).collect();
        rows.push(("genres", names.join(", ")));
    }
    if !g.platforms_owning.is_empty() {
        let names: Vec<String> = g.platforms_owning.iter().map(|x| x.name.clone()).collect();
        rows.push(("platforms", names.join(", ")));
    }
    if let Some(err) = &g.last_sync_error {
        rows.push(("last_sync_error", err.clone()));
    }
    render_kv(&rows)
}

// --- search -----------------------------------------------------------------

fn run_search(args: GamesSearchArgs) -> Result<()> {
    let client = build_client()?;
    let mode = OutputMode::from_json_flag(args.json);
    let resp = match client.games_search(&args.query) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("network error: {}", e);
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };
    let limited: Vec<GameSearchHit> = resp.results.into_iter().take(args.limit as usize).collect();
    match mode {
        OutputMode::Json => {
            let payload = serde_json::json!({
                "query": resp.query,
                "results": limited,
                "took_ms": resp.took_ms,
                "search_error": resp.search_error,
            });
            println!("{}", serde_json::to_string(&payload)?);
        }
        OutputMode::Plaintext => {
            if let Some(err) = &resp.search_error {
                let kind = err.kind.as_deref().unwrap_or("error");
                let msg = err.message.as_deref().unwrap_or("");
                eprintln!("search error ({}): {}", kind, msg);
            }
            print!("{}", render_search_results(&limited));
        }
    }
    Ok(())
}

pub fn render_search_results(hits: &[GameSearchHit]) -> String {
    let rows: Vec<Vec<String>> = hits
        .iter()
        .map(|h| {
            vec![
                h.igdb_id.to_string(),
                h.title.clone(),
                h.release_year.map(|y| y.to_string()).unwrap_or_default(),
                h.cover_image_id.clone().unwrap_or_default(),
            ]
        })
        .collect();
    render_table(&["igdb_id", "title", "year", "cover"], &rows)
}

// --- resync -----------------------------------------------------------------

fn run_resync(args: GamesResyncArgs) -> Result<()> {
    let confirmed = confirm::is_confirmed(args.confirm);
    let mode = OutputMode::from_json_flag(args.json);
    if !confirmed {
        match mode {
            OutputMode::Json => {
                let payload = serde_json::json!({
                    "preview": true,
                    "slug_or_id": args.slug_or_id,
                    "message": "rerun with --confirm yes to enqueue an IGDB resync.",
                });
                println!("{}", serde_json::to_string(&payload)?);
            }
            OutputMode::Plaintext => {
                println!("would enqueue IGDB resync for {}.", args.slug_or_id);
                println!("rerun with --confirm yes to apply.");
            }
        }
        return Ok(());
    }

    let client = build_client()?;
    let resp = match client.games_resync(&args.slug_or_id) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("network error: {}", e);
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };

    // The endpoint returns 202 (success) or 409 (already_resyncing). Both
    // surface here as `Ok(body)`; the `error` field distinguishes.
    let already_resyncing = resp.error.as_deref() == Some("already_resyncing");

    match mode {
        OutputMode::Json => {
            println!("{}", serde_json::to_string(&resp)?);
        }
        OutputMode::Plaintext => {
            if already_resyncing {
                println!("game {} is already resyncing.", resp.game_id);
            } else if let Some(jid) = &resp.enqueued_jid {
                println!(
                    "enqueued IGDB resync for game {} (jid: {}).",
                    resp.game_id, jid
                );
            } else {
                println!("enqueued IGDB resync for game {}.", resp.game_id);
            }
            if let Some(msg) = &resp.message {
                println!("{}", msg);
            }
        }
    }

    if already_resyncing {
        std::process::exit(ExitCode::Conflict.as_i32());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::endpoints::games::{GenreRef, PlatformRef};

    fn sample_summaries() -> Vec<GameSummary> {
        vec![
            GameSummary {
                id: 42,
                slug: "the-witness".to_string(),
                title: "The Witness".to_string(),
                release_year: Some(2016),
                igdb_rating: Some(87.4),
                platform_owned_id: Some(3),
                played_at: None,
                cover_image_id: None,
                resyncing: false,
                igdb_synced_at: None,
                created_at: None,
            },
            GameSummary {
                id: 43,
                slug: "hades-2".to_string(),
                title: "Hades II".to_string(),
                release_year: Some(2026),
                igdb_rating: None,
                platform_owned_id: None,
                played_at: None,
                cover_image_id: None,
                resyncing: true,
                igdb_synced_at: None,
                created_at: None,
            },
        ]
    }

    #[test]
    fn render_games_table_emits_header_and_rows() {
        let out = render_games_table(&sample_summaries());
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 4); // header + sep + 2 rows
        assert!(lines[0].contains("id"));
        assert!(lines[0].contains("slug"));
        assert!(lines[0].contains("resyncing"));
        assert!(lines[2].contains("the-witness"));
        // The "resyncing: true" row renders the cell as "yes" — boundary rule.
        assert!(lines[3].contains("hades-2"));
        assert!(lines[3].contains("yes"));
    }

    #[test]
    fn render_games_table_empty_emits_no_records() {
        let out = render_games_table(&[]);
        assert_eq!(out, "no records.\n");
    }

    #[test]
    fn render_game_detail_emits_known_keys() {
        let detail = GameDetail {
            id: 42,
            slug: "the-witness".to_string(),
            igdb_id: Some(18811),
            title: "The Witness".to_string(),
            summary: None,
            release_date: Some("2016-01-26".to_string()),
            release_year: Some(2016),
            igdb_rating: Some(87.4),
            igdb_rating_count: None,
            aggregated_rating: None,
            total_rating: None,
            total_rating_count: None,
            ttb_main_seconds: None,
            ttb_extras_seconds: None,
            ttb_completionist_seconds: None,
            external_steam_app_id: None,
            external_gog_id: None,
            external_epic_id: None,
            cover_image_id: None,
            platform_owned_id: Some(3),
            played_at: None,
            notes: None,
            hours_of_footage_manual: None,
            hours_of_footage_cached: None,
            manual_date_override: false,
            resyncing: false,
            igdb_synced_at: Some("2026-05-01T18:21:00Z".to_string()),
            last_sync_error: None,
            genres: vec![GenreRef {
                id: 1,
                name: "Puzzle".to_string(),
            }],
            platforms_owning: vec![PlatformRef {
                id: 3,
                name: "Steam".to_string(),
            }],
            created_at: None,
            updated_at: None,
        };
        let out = render_game_detail(&detail);
        assert!(out.contains("id"));
        assert!(out.contains("the-witness"));
        assert!(out.contains("genres"));
        assert!(out.contains("Puzzle"));
        assert!(out.contains("platforms"));
        assert!(out.contains("Steam"));
        // Boundary rule: resyncing renders as `no` / `yes`, never bool literal.
        assert!(out.contains("resyncing"));
        assert!(out.contains("no"));
    }

    #[test]
    fn render_search_results_emits_header_and_rows() {
        let hits = vec![GameSearchHit {
            igdb_id: 18811,
            title: "The Witness".to_string(),
            release_year: Some(2016),
            cover_image_id: Some("co1abc".to_string()),
            summary: None,
        }];
        let out = render_search_results(&hits);
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 3);
        assert!(lines[0].contains("igdb_id"));
        assert!(lines[2].contains("18811"));
        assert!(lines[2].contains("The Witness"));
    }

    #[test]
    fn render_search_results_empty_emits_no_records() {
        let out = render_search_results(&[]);
        assert_eq!(out, "no records.\n");
    }
}
