//! Diff classification — given the freshly-probed local files and the existing
//! footage rows from the API, decide which rows to Add, Change, or Delete.
//!
//! Per §7.3 of the spec:
//! - Identity is `local_path` (canonicalised).
//! - **Add**: file on disk, no DB record with that path.
//! - **Change**: file + DB record + at least one probed metadata field differs.
//! - **Delete**: DB record exists, file missing on disk.
//!
//! The diff is purely a comparison stage — no I/O, no HTTP, no ffprobe. Tests
//! pin every branch so the code-to-spec mapping stays readable.

use std::collections::HashSet;

use crate::footage::api::models::{FootageRecord, ProbedFile};

/// One candidate change the importer will apply via the API.
///
/// `ProbedFile` and `FootageRecord` are both relatively chunky structs (they
/// hold owned `String`s for resolution / codec / etc), so the `Change`
/// variant — which carries one of each — is boxed to keep the enum's
/// per-variant size balanced. Boxing is a 1-pointer overhead per Change row;
/// the alternative would be 200+ bytes of padding on every Add and Delete.
#[derive(Debug, Clone, PartialEq)]
pub enum DiffEntry {
    Add(ProbedFile),
    Change(Box<ChangeEntry>),
    Delete(FootageRecord),
}

#[derive(Debug, Clone, PartialEq)]
pub struct ChangeEntry {
    pub existing: FootageRecord,
    pub probed: ProbedFile,
}

impl DiffEntry {
    /// Construct a `Change` variant; the box hides from callers that the
    /// payload is allocated.
    pub fn change(existing: FootageRecord, probed: ProbedFile) -> Self {
        Self::Change(Box::new(ChangeEntry { existing, probed }))
    }

    /// User-facing label for the confirmation overlay row. Adds & changes use
    /// the local file path; deletes use the path of the row being removed.
    /// Currently driven by the test layer; the production renderer reads the
    /// per-section vectors on `DiffSummary` directly.
    #[allow(dead_code)]
    pub fn label(&self) -> String {
        match self {
            Self::Add(p) => p.local_path.clone(),
            Self::Change(c) => c.probed.local_path.clone(),
            Self::Delete(r) => r.local_path.clone(),
        }
    }
}

/// Classify a set of probed files against the existing footage rows for the
/// project. Order is deterministic: adds first (input order), then changes,
/// then deletes — this keeps confirmation overlays stable across runs.
pub fn classify(probed: Vec<ProbedFile>, existing: Vec<FootageRecord>) -> Vec<DiffEntry> {
    // Snapshot the local-path identity set up front so the post-pass can
    // verify "no file on disk" without holding a borrow on `probed`.
    let probed_paths: HashSet<String> = probed.iter().map(|p| p.local_path.clone()).collect();
    let mut existing_by_path: std::collections::HashMap<String, FootageRecord> = existing
        .into_iter()
        .map(|r| (r.local_path.clone(), r))
        .collect();

    let mut adds: Vec<DiffEntry> = Vec::new();
    let mut changes: Vec<DiffEntry> = Vec::new();

    for p in probed.into_iter() {
        match existing_by_path.remove(&p.local_path) {
            Some(record) => {
                if differs(&record, &p) {
                    changes.push(DiffEntry::change(record, p));
                }
                // If nothing differs, skip — no API call.
            }
            None => adds.push(DiffEntry::Add(p)),
        }
    }

    // Anything left in `existing_by_path` had no matching file on disk.
    let mut deletes: Vec<DiffEntry> = existing_by_path
        .into_values()
        .filter(|r| !probed_paths.contains(&r.local_path))
        .map(DiffEntry::Delete)
        .collect();
    // Stable order for deletes: by id ascending, so subsequent runs match.
    deletes.sort_by_key(|d| match d {
        DiffEntry::Delete(r) => r.id,
        _ => 0,
    });

    let mut all = adds;
    all.append(&mut changes);
    all.append(&mut deletes);
    all
}

/// Field-by-field comparison of an existing API record against a freshly
/// probed file. Any non-trivial divergence in the probed-metadata columns
/// flips this to true. Caller-supplied user fields (description, kind, source)
/// are intentionally ignored — those are user-managed in the web UI and the
/// importer must not re-write them on every run.
fn differs(record: &FootageRecord, probed: &ProbedFile) -> bool {
    if record.duration_seconds != probed.report.duration_seconds {
        return true;
    }
    if record.resolution != probed.report.resolution {
        return true;
    }
    // Compare fps as Option<f64> with epsilon — Rails decimal(6,3) round-trips
    // to a string and back, and we want to ignore noise below the 4th decimal.
    if !fps_equal(record.fps, probed.report.fps) {
        return true;
    }
    if record.codec != probed.report.codec {
        return true;
    }
    if record.bit_depth != probed.report.bit_depth {
        return true;
    }
    if record.color_profile != probed.report.color_profile {
        return true;
    }
    if record.aspect_ratio != probed.report.aspect_ratio {
        return true;
    }
    if record.orientation.as_deref() != probed.report.orientation.map(|o| o.as_wire()) {
        return true;
    }
    if record.audio_track_count != probed.report.audio_track_count {
        return true;
    }
    if record.has_commentary_track != probed.report.has_commentary_track {
        return true;
    }
    if record.filename != probed.filename {
        return true;
    }
    // `filesize_bytes` is a metadata fact, not a UI edit. Any divergence —
    // including a 1-byte delta — counts as a Change. Re-encodes / truncations
    // /trailer rewrites all show up here. We treat the absence of a server-side
    // value (`None`, e.g. legacy rows pre-Wave-1C) as "needs sync" once the
    // probe knows the size, so the importer backfills the column on first run.
    if record.filesize_bytes != probed.filesize_bytes {
        return true;
    }
    false
}

fn fps_equal(a: Option<f64>, b: Option<f64>) -> bool {
    match (a, b) {
        (None, None) => true,
        (Some(x), Some(y)) => (x - y).abs() < 0.0005,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::footage::api::models::FootageRecord;
    use crate::footage::probe::ffprobe::{Orientation, ProbeReport};

    fn baseline_report() -> ProbeReport {
        ProbeReport {
            duration_seconds: Some(120),
            resolution: Some("1920x1080".to_string()),
            fps: Some(60.0),
            codec: Some("h264".to_string()),
            bit_depth: 8,
            color_profile: Some("bt709".to_string()),
            aspect_ratio: Some("16:9".to_string()),
            orientation: Some(Orientation::Landscape),
            audio_track_count: 2,
            has_commentary_track: true,
            recorded_at: Some("2026-04-01T10:00:00Z".to_string()),
        }
    }

    fn probed(local_path: &str) -> ProbedFile {
        ProbedFile {
            local_path: local_path.to_string(),
            filesize_bytes: Some(1024),
            filename: std::path::Path::new(local_path)
                .file_name()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default(),
            report: baseline_report(),
        }
    }

    fn record(id: u64, local_path: &str) -> FootageRecord {
        let p = probed(local_path);
        FootageRecord {
            id,
            local_path: p.local_path.clone(),
            filename: p.filename.clone(),
            duration_seconds: p.report.duration_seconds,
            resolution: p.report.resolution.clone(),
            fps: p.report.fps,
            codec: p.report.codec.clone(),
            bit_depth: p.report.bit_depth,
            color_profile: p.report.color_profile.clone(),
            aspect_ratio: p.report.aspect_ratio.clone(),
            orientation: p.report.orientation.map(|o| o.as_wire().to_string()),
            audio_track_count: p.report.audio_track_count,
            has_commentary_track: p.report.has_commentary_track,
            filesize_bytes: p.filesize_bytes,
        }
    }

    #[test]
    fn classifies_pure_adds() {
        let probed = vec![probed("/footage/a.mp4"), probed("/footage/b.mp4")];
        let entries = classify(probed, vec![]);
        assert_eq!(entries.len(), 2);
        assert!(entries.iter().all(|e| matches!(e, DiffEntry::Add(_))));
    }

    #[test]
    fn classifies_pure_deletes() {
        let entries = classify(vec![], vec![record(1, "/footage/x.mp4")]);
        assert_eq!(entries.len(), 1);
        assert!(matches!(entries[0], DiffEntry::Delete(_)));
    }

    #[test]
    fn classifies_unchanged_files_as_no_op() {
        // Same file, same metadata → no entry.
        let p = probed("/footage/a.mp4");
        let r = record(1, "/footage/a.mp4");
        let entries = classify(vec![p], vec![r]);
        assert!(entries.is_empty(), "expected no diff, got: {:?}", entries);
    }

    #[test]
    fn classifies_change_when_resolution_differs() {
        let mut p = probed("/footage/a.mp4");
        p.report.resolution = Some("3840x2160".to_string());
        let r = record(1, "/footage/a.mp4");
        let entries = classify(vec![p], vec![r]);
        assert_eq!(entries.len(), 1);
        assert!(matches!(entries[0], DiffEntry::Change(_)));
    }

    #[test]
    fn classifies_change_when_bit_depth_differs() {
        let mut p = probed("/footage/a.mp4");
        p.report.bit_depth = 10;
        let r = record(1, "/footage/a.mp4");
        let entries = classify(vec![p], vec![r]);
        assert_eq!(entries.len(), 1);
        assert!(matches!(entries[0], DiffEntry::Change(_)));
    }

    #[test]
    fn classifies_change_when_color_profile_appears() {
        let mut p = probed("/footage/a.mp4");
        p.report.color_profile = Some("bt2020nc".to_string());
        let mut r = record(1, "/footage/a.mp4");
        r.color_profile = None;
        let entries = classify(vec![p], vec![r]);
        assert_eq!(entries.len(), 1);
        assert!(matches!(entries[0], DiffEntry::Change(_)));
    }

    #[test]
    fn classifies_change_when_audio_count_differs() {
        let mut p = probed("/footage/a.mp4");
        p.report.audio_track_count = 1;
        p.report.has_commentary_track = false;
        let r = record(1, "/footage/a.mp4");
        let entries = classify(vec![p], vec![r]);
        assert_eq!(entries.len(), 1);
        assert!(matches!(entries[0], DiffEntry::Change(_)));
    }

    #[test]
    fn classifies_change_when_filesize_bytes_differs() {
        // A re-encode / truncation changes the on-disk size while the path
        // stays put — must classify as Change so the importer PATCHes the row.
        let mut p = probed("/footage/a.mp4");
        p.filesize_bytes = Some(100);
        let mut r = record(1, "/footage/a.mp4");
        r.filesize_bytes = Some(200);
        let entries = classify(vec![p], vec![r]);
        assert_eq!(entries.len(), 1);
        assert!(matches!(entries[0], DiffEntry::Change(_)));
    }

    #[test]
    fn classifies_change_when_filesize_bytes_appears() {
        // Legacy rows from before Wave 1C have filesize_bytes = None on the
        // server. First run after the column lands should backfill — i.e.
        // classify as Change so the PATCH carries the new size.
        let p = probed("/footage/a.mp4");
        let mut r = record(1, "/footage/a.mp4");
        r.filesize_bytes = None;
        let entries = classify(vec![p], vec![r]);
        assert_eq!(entries.len(), 1);
        assert!(matches!(entries[0], DiffEntry::Change(_)));
    }

    #[test]
    fn fps_within_epsilon_does_not_register_as_change() {
        // Rails decimal(6,3) round-trips can shift fps by tiny amounts; we
        // must not flap-flap a whole footage row over noise below 0.0005.
        let mut p = probed("/footage/a.mp4");
        p.report.fps = Some(29.9700);
        let mut r = record(1, "/footage/a.mp4");
        r.fps = Some(29.9701);
        let entries = classify(vec![p], vec![r]);
        assert!(entries.is_empty(), "fps near-equal should be no-op");
    }

    #[test]
    fn classifies_mixed_add_change_delete() {
        // a.mp4 is unchanged, b.mp4 is new (add), c.mp4 changed resolution,
        // d.mp4 was removed from disk (delete).
        let p_a = probed("/f/a.mp4");
        let p_b = probed("/f/b.mp4");
        let mut p_c = probed("/f/c.mp4");
        p_c.report.resolution = Some("3840x2160".to_string());

        let r_a = record(1, "/f/a.mp4");
        let r_c = record(2, "/f/c.mp4");
        let r_d = record(3, "/f/d.mp4");

        let entries = classify(vec![p_a, p_b, p_c], vec![r_a, r_c, r_d]);

        let adds = entries
            .iter()
            .filter(|e| matches!(e, DiffEntry::Add(_)))
            .count();
        let changes = entries
            .iter()
            .filter(|e| matches!(e, DiffEntry::Change(_)))
            .count();
        let deletes = entries
            .iter()
            .filter(|e| matches!(e, DiffEntry::Delete(_)))
            .count();
        assert_eq!(adds, 1);
        assert_eq!(changes, 1);
        assert_eq!(deletes, 1);
    }

    #[test]
    fn diff_entry_label_returns_local_path() {
        let p = probed("/f/a.mp4");
        let entry = DiffEntry::Add(p);
        assert_eq!(entry.label(), "/f/a.mp4");
    }

    #[test]
    fn classify_order_is_adds_then_changes_then_deletes() {
        let p_b = probed("/f/b.mp4");
        let mut p_c = probed("/f/c.mp4");
        p_c.report.resolution = Some("3840x2160".to_string());
        let r_c = record(2, "/f/c.mp4");
        let r_d = record(3, "/f/d.mp4");

        let entries = classify(vec![p_b, p_c], vec![r_c, r_d]);
        // adds first, then changes, then deletes — matches confirmation
        // overlay's section ordering.
        assert!(matches!(entries[0], DiffEntry::Add(_)));
        assert!(matches!(entries[1], DiffEntry::Change(_)));
        assert!(matches!(entries[2], DiffEntry::Delete(_)));
    }
}
