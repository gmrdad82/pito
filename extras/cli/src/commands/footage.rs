//! `pito footage` subcommand entry point.
//!
//! Today the only nested command is `import`, which:
//!
//! 1. Resolves `ffprobe` (Linux-x86_64, `/usr/bin/ffprobe` first).
//! 2. Walks `--path` for files matching the configured extensions.
//! 3. Probes each file in turn.
//! 4. Fetches existing footage rows from the API.
//! 5. Classifies into Add / Change / Delete (`footage::diff::classify`).
//! 6. If `--dry-run`, prints the classification and exits without traffic.
//! 7. Otherwise, opens a ratatui confirmation overlay.
//! 8. On `y`, opens the progress overlay and applies the diff sequentially
//!    via `POST/PATCH/DELETE`. On per-item error, marks the row failed and
//!    continues.
//! 9. Prints the final summary line.
//!
//! Exit codes:
//!
//! - `0` — every operation succeeded (or dry-run / cancelled cleanly).
//! - `1` — at least one operation failed (partial or total). Mirrored from the
//!   item-level `failed` count on the progress state. Tests pin this.
//! - `2` — pre-flight failure (no ffprobe, bad path, API list 5xx, etc.).

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{Context, Result, anyhow};
use crossterm::{
    event::{self, Event, KeyEventKind},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{Terminal, backend::CrosstermBackend};

use crate::cli::{FootageArgs, FootageCommand, FootageImportArgs};
use crate::footage::api::client::FootageApiClient;
use crate::footage::api::models::ProbedFile;
use crate::footage::diff::{DiffEntry, classify};
use crate::footage::probe::ffprobe::{self, ProbeError};
use crate::footage::ui::confirmation::{
    ConfirmationOutcome, DiffSummary, key_outcome, render as render_confirmation,
};
use crate::footage::ui::progress::{
    ItemKind, ItemStatus, ProgressItem, ProgressState, render as render_progress,
};
use crate::theme::{Theme, ThemeMode};

/// Default extensions scanned when the user passes `--path` without any
/// per-extension filter. Matches §7.1.
const DEFAULT_EXTENSIONS: &[&str] = &["mp4", "mov", "mkv", "avi", "webm"];

pub fn run(args: FootageArgs) -> Result<()> {
    match args.command {
        FootageCommand::Import(import) => run_import(import),
    }
}

fn run_import(args: FootageImportArgs) -> Result<()> {
    // Same .env convention as the rest of the CLI — load if present, ignore
    // if missing.
    dotenvy::dotenv().ok();

    let outcome = run_import_inner(args)?;
    std::process::exit(outcome.exit_code());
}

/// Bucketed outcome of one `pito footage import` run. Drives the process
/// exit code and the test assertions in `tests/footage_integration.rs`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RunOutcome {
    /// Dry run, cancel, or every applied operation succeeded.
    Clean,
    /// Confirmed run with at least one failure recorded against an item.
    PartialFailure,
}

impl RunOutcome {
    fn exit_code(self) -> i32 {
        match self {
            Self::Clean => 0,
            Self::PartialFailure => 1,
        }
    }
}

fn run_import_inner(args: FootageImportArgs) -> Result<RunOutcome> {
    // Pre-flight: ffprobe must exist before we even touch the filesystem.
    let ffprobe_path = match ffprobe::resolve_ffprobe() {
        Ok(p) => p,
        Err(ProbeError::Missing) => {
            ffprobe::print_install_hint();
            std::process::exit(2);
        }
        Err(other) => {
            eprintln!("ffprobe error: {}", other);
            std::process::exit(2);
        }
    };

    // Pre-flight: --path must exist and be a directory.
    if !args.path.is_dir() {
        eprintln!(
            "--path must be an existing directory; got: {}",
            args.path.display()
        );
        std::process::exit(2);
    }

    // 1. Walk the directory.
    let files = scan_directory(&args.path)
        .with_context(|| format!("scan {} for footage files", args.path.display()))?;

    // 2. Probe each file. ffprobe failures are per-file so they don't sink
    //    the whole run, but the user still sees the warning on stderr.
    let mut probed: Vec<ProbedFile> = Vec::with_capacity(files.len());
    for file in files.iter() {
        match probe_one(&ffprobe_path, file) {
            Ok(p) => probed.push(p),
            Err(ProbeError::Missing) => {
                // Resolved binary went away mid-run — treat as fatal.
                ffprobe::print_install_hint();
                std::process::exit(2);
            }
            Err(e) => {
                eprintln!("warning: ffprobe failed on {}: {}", file.display(), e);
            }
        }
    }

    // 3. Fetch existing footage rows for diffing.
    let api = FootageApiClient::from_env();
    let existing = if args.dry_run {
        // Dry run: no traffic of any kind, ever. We do still need an empty
        // baseline so the classify step has something to compare against —
        // for the dry-run path we treat the API as empty so the user sees
        // every probed file as an Add. This matches the spec's intent of
        // "no traffic" (the spec doesn't define dry-run output past
        // "classifications") — see decision note in the dispatch report.
        Vec::new()
    } else {
        api.list_footage(args.project)
            .with_context(|| format!("GET existing footage for project {}", args.project))
            .map_err(|e| {
                eprintln!("error: {}", e);
                std::process::exit(2);
            })
            .unwrap()
    };

    // 4. Classify.
    let entries = classify(probed, existing);

    // 5. Dry run shortcut — print and exit.
    if args.dry_run {
        print_dry_run(&entries);
        return Ok(RunOutcome::Clean);
    }

    // 6. Confirmation overlay.
    let summary = DiffSummary::from_entries(&entries);
    if !summary.has_work() {
        println!("Footage already in sync — nothing to do.");
        return Ok(RunOutcome::Clean);
    }
    let outcome = run_confirmation(&summary)?;
    if outcome != ConfirmationOutcome::Proceed {
        println!("Cancelled.");
        return Ok(RunOutcome::Clean);
    }

    // 7. Apply.
    let progress_items = build_progress_items(&entries);
    let final_state = run_apply(&api, args.project, entries, progress_items, &args)?;

    // 8. Print the canonical summary so non-TTY callers (CI, scripts) get a
    //    machine-readable last line. The TUI overlay also prints it; this is
    //    the line you'd grep for.
    let counts = final_state.counts();
    println!("{}", counts.summary_line());

    Ok(if counts.failed > 0 {
        RunOutcome::PartialFailure
    } else {
        RunOutcome::Clean
    })
}

/// Walk `dir` non-recursively for files matching the default extension set.
/// `--path` is documented as a flat scan in §7.1.
fn scan_directory(dir: &Path) -> Result<Vec<PathBuf>> {
    let mut hits: Vec<PathBuf> = Vec::new();
    for entry in fs::read_dir(dir).with_context(|| format!("read_dir {}", dir.display()))? {
        let entry = entry?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let ext_match = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_ascii_lowercase())
            .map(|e| DEFAULT_EXTENSIONS.iter().any(|x| *x == e))
            .unwrap_or(false);
        if ext_match {
            hits.push(path);
        }
    }
    hits.sort();
    Ok(hits)
}

/// Probe one file. Falls back to file mtime for `recorded_at` if ffprobe
/// didn't return one.
fn probe_one(ffprobe_path: &Path, file: &Path) -> Result<ProbedFile, ProbeError> {
    let mut report = ffprobe::probe_file(ffprobe_path, file)?;
    if report.recorded_at.is_none()
        && let Ok(iso) = ffprobe::file_mtime_iso(file)
    {
        report.recorded_at = Some(iso);
    }
    Ok(ProbedFile {
        local_path: file.to_string_lossy().into_owned(),
        filename: file
            .file_name()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default(),
        report,
    })
}

fn print_dry_run(entries: &[DiffEntry]) {
    let mut adds = 0;
    let mut changes = 0;
    let mut deletes = 0;
    for e in entries.iter() {
        match e {
            DiffEntry::Add(p) => {
                adds += 1;
                println!("[add] {}", p.local_path);
            }
            DiffEntry::Change(c) => {
                changes += 1;
                println!("[chg] {}", c.probed.local_path);
            }
            DiffEntry::Delete(r) => {
                deletes += 1;
                println!("[del] {}", r.local_path);
            }
        }
    }
    println!(
        "dry run: {} add(s), {} change(s), {} delete(s)",
        adds, changes, deletes
    );
}

fn build_progress_items(entries: &[DiffEntry]) -> Vec<ProgressItem> {
    entries
        .iter()
        .map(|e| {
            let (kind, label) = match e {
                DiffEntry::Add(p) => (ItemKind::Add, p.local_path.clone()),
                DiffEntry::Change(c) => (ItemKind::Change, c.probed.local_path.clone()),
                DiffEntry::Delete(r) => (ItemKind::Delete, r.local_path.clone()),
            };
            ProgressItem {
                label,
                kind,
                status: ItemStatus::Pending,
                error: None,
            }
        })
        .collect()
}

// --- TUI plumbing -----------------------------------------------------------

fn run_confirmation(summary: &DiffSummary) -> Result<ConfirmationOutcome> {
    enable_raw_mode().context("enable raw mode for confirmation")?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen).context("enter alternate screen")?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend).context("init ratatui terminal")?;
    let theme = Theme::from_mode(ThemeMode::Dark);

    let outcome = loop {
        terminal
            .draw(|frame| {
                let area = frame.area();
                render_confirmation(frame, area, &theme, summary);
            })
            .context("draw confirmation")?;

        if event::poll(Duration::from_millis(125))?
            && let Event::Key(key) = event::read()?
            && key.kind == KeyEventKind::Press
        {
            let ch = match key.code {
                crossterm::event::KeyCode::Char(c) => c,
                _ => '\0',
            };
            break key_outcome(ch, summary);
        }
    };

    disable_raw_mode().ok();
    execute!(terminal.backend_mut(), LeaveAlternateScreen).ok();
    terminal.show_cursor().ok();
    Ok(outcome)
}

fn run_apply(
    api: &FootageApiClient,
    project_id: u64,
    entries: Vec<DiffEntry>,
    items: Vec<ProgressItem>,
    args: &FootageImportArgs,
) -> Result<ProgressState> {
    enable_raw_mode().context("enable raw mode for progress")?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen).context("enter alternate screen")?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend).context("init ratatui terminal")?;
    let theme = Theme::from_mode(ThemeMode::Dark);

    let mut state = ProgressState::new(items);
    let total = entries.len();

    // First paint: every row pending.
    terminal
        .draw(|frame| render_progress(frame, frame.area(), &theme, &state))
        .ok();

    for (idx, entry) in entries.into_iter().enumerate() {
        // Mark the active row "running" so the loader frame animates only on
        // the in-flight item; previously-completed rows show their terminal
        // marker, future rows stay pending (which renders identical to
        // "running" in this overlay — both animate).
        state.items[idx].status = ItemStatus::Running;
        state.tick = state.tick.wrapping_add(1);
        terminal
            .draw(|frame| render_progress(frame, frame.area(), &theme, &state))
            .ok();

        let result = apply_entry(api, project_id, &entry, args);
        match result {
            Ok(()) => state.items[idx].status = ItemStatus::Done,
            Err(e) => {
                state.items[idx].status = ItemStatus::Failed;
                state.items[idx].error = Some(e.to_string());
            }
        }

        state.tick = state.tick.wrapping_add(1);
        terminal
            .draw(|frame| render_progress(frame, frame.area(), &theme, &state))
            .ok();

        // Avoid 100% CPU when the API responds in microseconds.
        if total > 0 {
            std::thread::sleep(Duration::from_millis(40));
        }
    }

    // Done.
    state.finished = true;
    terminal
        .draw(|frame| render_progress(frame, frame.area(), &theme, &state))
        .ok();

    // Wait for one keypress so the user can read the summary; bail after a
    // generous deadline so non-interactive callers (CI) don't hang.
    let deadline = std::time::Instant::now() + Duration::from_secs(30);
    while std::time::Instant::now() < deadline {
        if event::poll(Duration::from_millis(125))? {
            if let Event::Key(key) = event::read()?
                && key.kind == KeyEventKind::Press
            {
                break;
            }
        } else {
            // No event — repaint anyway so the loader stays alive on long
            // operations (none here, but keeps shape consistent with the
            // confirmation overlay).
            terminal
                .draw(|frame| render_progress(frame, frame.area(), &theme, &state))
                .ok();
            break;
        }
    }

    disable_raw_mode().ok();
    execute!(terminal.backend_mut(), LeaveAlternateScreen).ok();
    terminal.show_cursor().ok();
    Ok(state)
}

fn apply_entry(
    api: &FootageApiClient,
    project_id: u64,
    entry: &DiffEntry,
    args: &FootageImportArgs,
) -> Result<()> {
    match entry {
        DiffEntry::Add(probed) => api
            .create_footage(project_id, probed, args)
            .map(|_| ())
            .map_err(|e| anyhow!(e)),
        DiffEntry::Change(c) => api
            .update_footage(c.existing.id, &c.probed)
            .map(|_| ())
            .map_err(|e| anyhow!(e)),
        DiffEntry::Delete(record) => api.delete_footage(record.id).map_err(|e| anyhow!(e)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use tempfile::TempDir;

    #[test]
    fn scan_directory_finds_default_extensions_only() {
        let tmp = TempDir::new().expect("tempdir");
        for name in &["a.mp4", "b.mov", "c.mkv", "d.avi", "e.webm", "f.txt"] {
            File::create(tmp.path().join(name)).expect("create");
        }
        let mut hits = scan_directory(tmp.path()).expect("scan");
        hits.sort();
        let names: Vec<String> = hits
            .iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
            .collect();
        assert_eq!(names, vec!["a.mp4", "b.mov", "c.mkv", "d.avi", "e.webm"]);
    }

    #[test]
    fn scan_directory_is_case_insensitive_on_extensions() {
        let tmp = TempDir::new().expect("tempdir");
        for name in &["UPPER.MP4", "Mixed.MoV"] {
            File::create(tmp.path().join(name)).expect("create");
        }
        let hits = scan_directory(tmp.path()).expect("scan");
        assert_eq!(hits.len(), 2, "case-insensitive extension matching");
    }

    #[test]
    fn scan_directory_skips_subdirectories() {
        // Spec §7.1: flat scan, no recursion.
        let tmp = TempDir::new().expect("tempdir");
        std::fs::create_dir(tmp.path().join("sub")).expect("subdir");
        File::create(tmp.path().join("sub").join("nested.mp4")).expect("create nested");
        File::create(tmp.path().join("top.mp4")).expect("create top");
        let hits = scan_directory(tmp.path()).expect("scan");
        let names: Vec<String> = hits
            .iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
            .collect();
        assert_eq!(names, vec!["top.mp4"]);
    }

    #[test]
    fn run_outcome_exit_codes_are_zero_and_one() {
        // Pin the exit code mapping so a future refactor doesn't accidentally
        // leak a non-zero exit on a clean run (or vice versa).
        assert_eq!(RunOutcome::Clean.exit_code(), 0);
        assert_eq!(RunOutcome::PartialFailure.exit_code(), 1);
    }
}
