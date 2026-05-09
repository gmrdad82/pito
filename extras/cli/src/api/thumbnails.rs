//! HTTP client + on-disk LRU cache for footage thumbnail frames.
//!
//! Phase 7.5 step 06 (CLI half) — fetches the per-footage frame manifest and
//! the master / thumb JPEGs that back the scrub UI in
//! `ui::footage_detail`. Three concerns live here:
//!
//! 1. **Wire shape.** The Rails side serves three routes per footage:
//!    `GET /footages/:id/frames.json` (manifest), `GET
//!    /footages/:id/frames/m/:HH-MM-SS.jpg` (1280×720 master), `GET
//!    /footages/:id/frames/t/:HH-MM-SS.jpg` (320×180 thumb). The functions
//!    below return raw bytes for the JPEG endpoints and a typed `Manifest`
//!    for the JSON endpoint.
//! 2. **Filename convention.** Each frame's filename is its zero-padded
//!    `HH-MM-SS.jpg` timestamp. [`format_timestamp`] converts a `u64` of
//!    seconds into the exact string the server uses; [`parse_timestamp`] goes
//!    the other way for round-tripping the manifest.
//! 3. **Local cache.** Successful fetches are mirrored to
//!    `~/.cache/pito/thumbnails/<footage_id>/{m,t}/<HH-MM-SS>.jpg`. A bounded
//!    LRU layer ([`Cache`]) tracks file mtime as the access timestamp and
//!    evicts the oldest entries when the directory grows past
//!    [`Cache::DEFAULT_CAPACITY_BYTES`]. The cache is a write-through layer:
//!    on a hit we read from disk and skip HTTP; on a miss we fetch, write the
//!    bytes, and return them.
//!
//! Spec 06 Rails half has shipped (manifest + tier endpoints live);
//! `App::open_footage_detail` and `App::refresh_active_preview_protocol`
//! drive `fetch_manifest`, `fetch_frame_bytes`, and `Cache::fetch_or_get`
//! against it. Some helpers (`parse_timestamp`, `manifest_path`,
//! `frame_path`, `Cache::path_for`, `Cache::total_bytes`) are part of the
//! public API surface — exercised by unit tests and reserved for the
//! upcoming prefetch / debug paths — but unreachable from the binary's
//! current call graph; the module-level `#[allow(dead_code)]` keeps clippy
//! quiet without us having to drop the API.
#![allow(dead_code)]

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use anyhow::{Context, Result, anyhow};
use serde::{Deserialize, Serialize};

/// Tier of a single frame: `m` (master, 1280×720) or `t` (thumb, 320×180).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Tier {
    Master,
    Thumb,
}

impl Tier {
    /// URL / filesystem segment.
    pub fn segment(self) -> &'static str {
        match self {
            Tier::Master => "m",
            Tier::Thumb => "t",
        }
    }
}

/// Manifest returned by `GET /footages/:id/frames.json`.
///
/// `duration_seconds` is the source clip duration; `timestamps` is the array
/// of per-frame timestamps that exist on disk, in the order the filesystem
/// reports them (which equals timeline order because the filenames are
/// `HH-MM-SS.jpg`). The manifest may be sparse when extraction failed on some
/// timestamps — the scrub UI works with whatever is present.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Manifest {
    /// Source clip duration in seconds (float — the Rails side emits the
    /// ffprobe `duration` value verbatim).
    pub duration_seconds: f64,
    /// Stored frame timestamps in seconds. Sorted ascending, no duplicates.
    pub timestamps: Vec<u64>,
}

impl Manifest {
    /// Pick the timestamp closest to `target` in the manifest. Returns `None`
    /// when the manifest is empty.
    pub fn closest(&self, target: u64) -> Option<u64> {
        let mut best: Option<u64> = None;
        let mut best_dist: u64 = u64::MAX;
        for &ts in &self.timestamps {
            let dist = ts.abs_diff(target);
            if dist < best_dist {
                best_dist = dist;
                best = Some(ts);
            }
        }
        best
    }

    /// Index of the closest timestamp to `target`, or `None` when empty.
    pub fn closest_index(&self, target: u64) -> Option<usize> {
        let mut best_idx: Option<usize> = None;
        let mut best_dist: u64 = u64::MAX;
        for (i, &ts) in self.timestamps.iter().enumerate() {
            let dist = ts.abs_diff(target);
            if dist < best_dist {
                best_dist = dist;
                best_idx = Some(i);
            }
        }
        best_idx
    }
}

/// Build the `HH-MM-SS` filename stem for a `u64` of seconds. The `.jpg`
/// extension is added by callers since some sites only need the stem (cache
/// key, log line).
pub fn format_timestamp(seconds: u64) -> String {
    let h = seconds / 3600;
    let m = (seconds % 3600) / 60;
    let s = seconds % 60;
    format!("{:02}-{:02}-{:02}", h, m, s)
}

/// Parse an `HH-MM-SS` filename stem (no extension) back into seconds.
/// Anything else (extra segments, non-numeric components) is rejected with a
/// descriptive error so callers logging the failure can pinpoint the row.
pub fn parse_timestamp(stem: &str) -> Result<u64> {
    let parts: Vec<&str> = stem.split('-').collect();
    if parts.len() != 3 {
        return Err(anyhow!("expected HH-MM-SS, got {:?}", stem));
    }
    let h: u64 = parts[0]
        .parse()
        .with_context(|| format!("hours segment in {:?}", stem))?;
    let m: u64 = parts[1]
        .parse()
        .with_context(|| format!("minutes segment in {:?}", stem))?;
    let s: u64 = parts[2]
        .parse()
        .with_context(|| format!("seconds segment in {:?}", stem))?;
    Ok(h * 3600 + m * 60 + s)
}

// --- HTTP fetch -------------------------------------------------------------

/// Pure helper: relative path of the frame manifest endpoint.
pub fn manifest_path(footage_id: u64) -> String {
    format!("/footages/{}/frames.json", footage_id)
}

/// Pure helper: relative path of a single-frame stream endpoint.
pub fn frame_path(footage_id: u64, tier: Tier, timestamp: u64) -> String {
    format!(
        "/footages/{}/frames/{}/{}.jpg",
        footage_id,
        tier.segment(),
        format_timestamp(timestamp)
    )
}

/// Compose a fully-qualified URL from a base + relative path. Mirrors the
/// helper on `HttpClient` but is duplicated here so the thumbnail module can
/// be wired to its own client without depending on the dashboard/channels
/// surface.
pub fn url(base_url: &str, path: &str) -> String {
    let trimmed_base = base_url.trim_end_matches('/');
    let trimmed_path = path.trim_start_matches('/');
    format!("{}/{}", trimmed_base, trimmed_path)
}

const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

/// Build a blocking reqwest client with the standard CLI timeout. Reused
/// across the manifest + frame fetchers.
fn build_client() -> reqwest::blocking::Client {
    reqwest::blocking::Client::builder()
        .timeout(REQUEST_TIMEOUT)
        .build()
        .expect("reqwest client build")
}

/// Fetch the manifest for a footage. The caller passes the base URL (so tests
/// can target a wiremock server) and the footage id; on success returns the
/// parsed `Manifest`.
pub fn fetch_manifest(base_url: &str, footage_id: u64) -> Result<Manifest> {
    let client = build_client();
    let url = url(base_url, &manifest_path(footage_id));
    let response = client
        .get(&url)
        .header("Accept", "application/json")
        .send()
        .with_context(|| format!("GET {}", url))?
        .error_for_status()
        .with_context(|| format!("status check {}", url))?;
    let manifest: Manifest = response
        .json()
        .with_context(|| format!("decode manifest {}", url))?;
    Ok(manifest)
}

/// Fetch the raw JPEG bytes for a single frame. Cache-aware callers should
/// prefer [`Cache::fetch_or_get`].
pub fn fetch_frame_bytes(
    base_url: &str,
    footage_id: u64,
    tier: Tier,
    timestamp: u64,
) -> Result<Vec<u8>> {
    let client = build_client();
    let url = url(base_url, &frame_path(footage_id, tier, timestamp));
    let response = client
        .get(&url)
        .header("Accept", "image/jpeg")
        .send()
        .with_context(|| format!("GET {}", url))?
        .error_for_status()
        .with_context(|| format!("status check {}", url))?;
    let bytes = response
        .bytes()
        .with_context(|| format!("read frame bytes {}", url))?;
    Ok(bytes.to_vec())
}

// --- Cache ------------------------------------------------------------------

/// On-disk LRU cache for fetched frame bytes.
///
/// Cache directory layout mirrors the server-side asset layout:
///
/// ```text
/// <root>/<footage_id>/<tier>/<HH-MM-SS>.jpg
/// ```
///
/// The `<root>` is `$XDG_CACHE_HOME/pito/thumbnails` (falling back to
/// `$HOME/.cache/pito/thumbnails`, then `/tmp/pito/thumbnails`). LRU is
/// tracked via file `mtime` — we touch the mtime on every read, then evict
/// oldest-mtime first when the total cache size exceeds `capacity_bytes`.
///
/// Why mtime and not a sidecar index: the cache is read-mostly across
/// processes (a fresh `pito` invocation should see the previous run's
/// cache), and mtime is the cheapest filesystem-visible "last access" signal
/// without requiring atime mounts (which most distros disable).
#[derive(Debug, Clone)]
pub struct Cache {
    root: PathBuf,
    capacity_bytes: u64,
}

impl Cache {
    /// Default LRU capacity. 500 MB lines up with the spec suggestion. Per
    /// the spec storage budget (1000 footages × 60 thumbs × 14 KB ≈ 840 MB
    /// thumbs alone), a 500 MB cap holds the active working set comfortably
    /// while bounding disk usage on a developer laptop.
    pub const DEFAULT_CAPACITY_BYTES: u64 = 500 * 1024 * 1024;

    /// Build a cache rooted at the standard pito cache directory.
    /// Creates the directory if it does not exist.
    pub fn new() -> Self {
        Self::with_root(default_cache_root(), Self::DEFAULT_CAPACITY_BYTES)
    }

    /// Build a cache rooted at an explicit path. Tests use this to point at a
    /// `tempfile::tempdir`. `capacity_bytes` is the soft cap; eviction runs
    /// after a write whenever the total grows past it.
    pub fn with_root(root: impl Into<PathBuf>, capacity_bytes: u64) -> Self {
        Self {
            root: root.into(),
            capacity_bytes,
        }
    }

    /// Path to a cached frame, regardless of whether it currently exists.
    pub fn path_for(&self, footage_id: u64, tier: Tier, timestamp: u64) -> PathBuf {
        self.root
            .join(footage_id.to_string())
            .join(tier.segment())
            .join(format!("{}.jpg", format_timestamp(timestamp)))
    }

    /// Cache hit: read bytes from disk and update mtime (LRU touch).
    /// Returns `None` on a miss; returns `Err` only on a real IO error.
    pub fn read(&self, footage_id: u64, tier: Tier, timestamp: u64) -> Result<Option<Vec<u8>>> {
        let path = self.path_for(footage_id, tier, timestamp);
        match fs::read(&path) {
            Ok(bytes) => {
                // Touch mtime so subsequent runs see this entry as recently
                // used. We swallow the touch error — mtime updates are
                // best-effort and a failure here only affects eviction order,
                // not correctness.
                let _ = filetime_now(&path);
                Ok(Some(bytes))
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e).with_context(|| format!("read cache {:?}", path)),
        }
    }

    /// Write bytes to the cache and run eviction if the total exceeds the
    /// capacity.
    pub fn write(&self, footage_id: u64, tier: Tier, timestamp: u64, bytes: &[u8]) -> Result<()> {
        let path = self.path_for(footage_id, tier, timestamp);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).with_context(|| format!("create cache dir {:?}", parent))?;
        }
        // Atomic-ish write: write to a sibling tmp file then rename. Avoids
        // half-written cache entries if the process is killed mid-fetch.
        let tmp = path.with_extension("jpg.tmp");
        fs::write(&tmp, bytes).with_context(|| format!("write cache tmp {:?}", tmp))?;
        fs::rename(&tmp, &path).with_context(|| format!("commit cache {:?}", path))?;
        self.evict_to_capacity()?;
        Ok(())
    }

    /// Cache-aware fetcher: returns the bytes for `(footage_id, tier,
    /// timestamp)`, hitting the on-disk cache first, falling through to
    /// `fetcher` on miss and writing the result back.
    pub fn fetch_or_get<F>(
        &self,
        footage_id: u64,
        tier: Tier,
        timestamp: u64,
        fetcher: F,
    ) -> Result<Vec<u8>>
    where
        F: FnOnce() -> Result<Vec<u8>>,
    {
        if let Some(bytes) = self.read(footage_id, tier, timestamp)? {
            return Ok(bytes);
        }
        let bytes = fetcher()?;
        self.write(footage_id, tier, timestamp, &bytes)?;
        Ok(bytes)
    }

    /// Iterate every cache entry, returning `(path, size_bytes, mtime)`
    /// tuples. Used by the eviction routine and by tests.
    pub fn entries(&self) -> Vec<(PathBuf, u64, SystemTime)> {
        let mut entries: Vec<(PathBuf, u64, SystemTime)> = Vec::new();
        let Ok(footages) = fs::read_dir(&self.root) else {
            return entries;
        };
        for footage in footages.flatten() {
            let Ok(tier_dirs) = fs::read_dir(footage.path()) else {
                continue;
            };
            for tier in tier_dirs.flatten() {
                let Ok(files) = fs::read_dir(tier.path()) else {
                    continue;
                };
                for file in files.flatten() {
                    let Ok(meta) = file.metadata() else {
                        continue;
                    };
                    if !meta.is_file() {
                        continue;
                    }
                    // Skip in-flight tmp files — they aren't part of the LRU
                    // working set and would skew eviction decisions.
                    if file.path().extension().map(|e| e == "tmp").unwrap_or(false) {
                        continue;
                    }
                    let mtime = meta.modified().unwrap_or(SystemTime::UNIX_EPOCH);
                    entries.push((file.path(), meta.len(), mtime));
                }
            }
        }
        entries
    }

    /// Total cache size in bytes (sum across all `<footage>/<tier>/*.jpg`).
    pub fn total_bytes(&self) -> u64 {
        self.entries().iter().map(|(_, size, _)| size).sum()
    }

    /// Evict oldest-mtime entries until total size <= capacity. No-op if the
    /// cache is already under cap. Returns the number of files removed.
    pub fn evict_to_capacity(&self) -> Result<u64> {
        let mut entries = self.entries();
        let total: u64 = entries.iter().map(|(_, size, _)| size).sum();
        if total <= self.capacity_bytes {
            return Ok(0);
        }
        // Oldest first.
        entries.sort_by_key(|(_, _, mtime)| *mtime);
        let mut current = total;
        let mut removed = 0u64;
        for (path, size, _) in entries {
            if current <= self.capacity_bytes {
                break;
            }
            if fs::remove_file(&path).is_err() {
                // Don't fail the whole cache write because a single eviction
                // candidate disappeared (concurrent process, transient
                // filesystem hiccup). Move on; the next write will retry.
                continue;
            }
            current = current.saturating_sub(size);
            removed += 1;
        }
        Ok(removed)
    }
}

impl Default for Cache {
    fn default() -> Self {
        Self::new()
    }
}

/// Resolve `$XDG_CACHE_HOME/pito/thumbnails`, falling back to
/// `$HOME/.cache/pito/thumbnails`, then `/tmp/pito/thumbnails`. Mirrors the
/// cascade in `app::log_error` so cache and error log live next to each
/// other.
pub fn default_cache_root() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_CACHE_HOME")
        && !xdg.is_empty()
    {
        return PathBuf::from(xdg).join("pito").join("thumbnails");
    }
    if let Ok(home) = std::env::var("HOME")
        && !home.is_empty()
    {
        return PathBuf::from(home)
            .join(".cache")
            .join("pito")
            .join("thumbnails");
    }
    PathBuf::from("/tmp").join("pito").join("thumbnails")
}

/// Set the file's mtime to "now". Used to LRU-touch on read. Implemented by
/// re-opening the file with `OpenOptions::write(true)` and writing zero
/// bytes — the kernel updates `mtime` on any write, including a no-op one.
/// We deliberately avoid pulling in the `filetime` crate for this single
/// callsite.
fn filetime_now(path: &Path) -> io::Result<()> {
    use std::fs::OpenOptions;
    use std::io::Write;
    // `append(true)` keeps the existing bytes; `write_all(&[])` is a no-op
    // write that nonetheless bumps mtime on every common filesystem (ext4,
    // btrfs, xfs, apfs, tmpfs).
    let mut f = OpenOptions::new().append(true).open(path)?;
    f.write_all(&[])?;
    f.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn format_timestamp_zero_pads() {
        assert_eq!(format_timestamp(0), "00-00-00");
        assert_eq!(format_timestamp(60), "00-01-00");
        assert_eq!(format_timestamp(90), "00-01-30");
        assert_eq!(format_timestamp(3600), "01-00-00");
        assert_eq!(format_timestamp(3725), "01-02-05");
    }

    #[test]
    fn parse_timestamp_round_trips() {
        for s in [0u64, 1, 59, 60, 61, 3599, 3600, 36000, 90061] {
            assert_eq!(parse_timestamp(&format_timestamp(s)).unwrap(), s);
        }
    }

    #[test]
    fn parse_timestamp_rejects_garbage() {
        assert!(parse_timestamp("not-a-time").is_err());
        assert!(parse_timestamp("00:00:00").is_err());
        assert!(parse_timestamp("00-00").is_err());
        assert!(parse_timestamp("aa-bb-cc").is_err());
    }

    #[test]
    fn url_composes_correctly() {
        assert_eq!(
            url("https://app.pitomd.com", "/footages/42/frames.json"),
            "https://app.pitomd.com/footages/42/frames.json"
        );
        // trailing slash on base + leading slash on path collapse to one
        assert_eq!(
            url("https://app.pitomd.com/", "/footages/42/frames.json"),
            "https://app.pitomd.com/footages/42/frames.json"
        );
    }

    #[test]
    fn manifest_path_uses_id() {
        assert_eq!(manifest_path(7), "/footages/7/frames.json");
    }

    #[test]
    fn frame_path_includes_tier_and_timestamp() {
        assert_eq!(
            frame_path(7, Tier::Master, 90),
            "/footages/7/frames/m/00-01-30.jpg"
        );
        assert_eq!(
            frame_path(7, Tier::Thumb, 0),
            "/footages/7/frames/t/00-00-00.jpg"
        );
    }

    #[test]
    fn manifest_closest_picks_nearest_timestamp() {
        let m = Manifest {
            duration_seconds: 600.0,
            timestamps: vec![60, 120, 180, 240, 300],
        };
        assert_eq!(m.closest(0), Some(60));
        assert_eq!(m.closest(60), Some(60));
        assert_eq!(m.closest(89), Some(60));
        // ties resolve to the first encountered
        assert_eq!(m.closest(90), Some(60));
        assert_eq!(m.closest(91), Some(120));
        assert_eq!(m.closest(1000), Some(300));
    }

    #[test]
    fn manifest_closest_index_pairs_with_closest() {
        let m = Manifest {
            duration_seconds: 600.0,
            timestamps: vec![60, 120, 180],
        };
        assert_eq!(m.closest_index(60), Some(0));
        assert_eq!(m.closest_index(120), Some(1));
        assert_eq!(m.closest_index(180), Some(2));
        assert_eq!(m.closest_index(90), Some(0));
        assert_eq!(m.closest_index(150), Some(1));
    }

    #[test]
    fn manifest_closest_returns_none_when_empty() {
        let m = Manifest {
            duration_seconds: 0.0,
            timestamps: vec![],
        };
        assert_eq!(m.closest(0), None);
        assert_eq!(m.closest_index(0), None);
    }

    #[test]
    fn manifest_decodes_canonical_wire_shape() {
        // The Rails manifest endpoint emits `duration_seconds` as a float and
        // `timestamps` as an array of seconds. Anchor the wire shape so the
        // CLI decoder breaks loudly if the Rails dispatch picks a different
        // key name.
        let json = r#"{
            "duration_seconds": 1234.5,
            "timestamps": [60, 120, 180]
        }"#;
        let parsed: Manifest = serde_json::from_str(json).unwrap();
        assert!((parsed.duration_seconds - 1234.5).abs() < f64::EPSILON);
        assert_eq!(parsed.timestamps, vec![60, 120, 180]);
    }

    #[test]
    fn cache_path_layout_uses_footage_tier_timestamp() {
        let dir = tempdir().unwrap();
        let cache = Cache::with_root(dir.path(), 1024);
        let p = cache.path_for(42, Tier::Thumb, 90);
        assert!(p.ends_with("42/t/00-01-30.jpg"));
    }

    #[test]
    fn cache_miss_returns_none() {
        let dir = tempdir().unwrap();
        let cache = Cache::with_root(dir.path(), 1024);
        assert!(cache.read(1, Tier::Thumb, 0).unwrap().is_none());
    }

    #[test]
    fn cache_write_then_read_round_trips() {
        let dir = tempdir().unwrap();
        let cache = Cache::with_root(dir.path(), 1_000_000);
        cache.write(7, Tier::Master, 90, b"jpeg-bytes").unwrap();
        let bytes = cache.read(7, Tier::Master, 90).unwrap().unwrap();
        assert_eq!(bytes, b"jpeg-bytes");
    }

    #[test]
    fn cache_fetch_or_get_hits_disk_on_second_call() {
        let dir = tempdir().unwrap();
        let cache = Cache::with_root(dir.path(), 1_000_000);
        let calls = std::cell::Cell::new(0u32);
        let fetcher = || {
            calls.set(calls.get() + 1);
            Ok(b"jpeg-bytes".to_vec())
        };
        let a = cache.fetch_or_get(7, Tier::Master, 90, fetcher).unwrap();
        let b = cache.fetch_or_get(7, Tier::Master, 90, fetcher).unwrap();
        assert_eq!(a, b);
        assert_eq!(calls.get(), 1, "second call must hit disk, not the fetcher");
    }

    #[test]
    fn cache_evicts_oldest_when_over_capacity() {
        let dir = tempdir().unwrap();
        // Cap at 30 bytes — three 10-byte entries will fit, four will trip.
        let cache = Cache::with_root(dir.path(), 30);
        let payload = b"0123456789".to_vec(); // 10 bytes

        // Write four entries with carefully separated mtimes so the oldest is
        // unambiguous. We sleep between writes — 50ms is enough resolution on
        // every common filesystem (mtime granularity is usually 1ms or 1ns).
        for ts in [10u64, 20, 30, 40] {
            cache.write(1, Tier::Thumb, ts, &payload).unwrap();
            std::thread::sleep(std::time::Duration::from_millis(50));
        }

        // Total writes were 40 bytes; capacity is 30; eviction should have
        // dropped the oldest single entry (timestamp 10) at most.
        let remaining: Vec<u64> = cache
            .entries()
            .iter()
            .filter_map(|(p, _, _)| {
                p.file_stem()
                    .and_then(|s| s.to_str())
                    .and_then(|s| parse_timestamp(s).ok())
            })
            .collect();
        assert!(
            cache.total_bytes() <= 30,
            "post-eviction total {} > cap 30",
            cache.total_bytes()
        );
        assert!(
            !remaining.contains(&10),
            "the oldest entry (ts=10) must be evicted; remaining={:?}",
            remaining
        );
    }

    #[test]
    fn cache_skips_tmp_files_in_inventory() {
        // Stale tmp file from a crashed write should not appear in entries()
        // nor count toward total_bytes — otherwise eviction would skew.
        let dir = tempdir().unwrap();
        let cache = Cache::with_root(dir.path(), 1024);
        cache.write(1, Tier::Thumb, 60, b"good").unwrap();
        let stale = cache.path_for(1, Tier::Thumb, 60).with_extension("jpg.tmp");
        std::fs::write(&stale, b"junk").unwrap();
        let entries = cache.entries();
        assert_eq!(entries.len(), 1, "tmp file must not appear in entries");
    }
}
