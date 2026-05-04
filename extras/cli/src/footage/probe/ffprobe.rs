//! Resolve and invoke `ffprobe`, then parse the JSON output into the strongly
//! typed `ProbeReport` shape that the importer feeds into the diff stage and
//! the API.
//!
//! The parsing rules follow §7.2 of `docs/plans/beta/04-project-workspace/specs/project-workspace.md`:
//!
//! - `r_frame_rate` / `avg_frame_rate` arrive as `"30000/1001"` rationals.
//!   We parse them, divide, and round to 3 decimals so the value fits the
//!   Rails `decimal(6, 3)` column.
//! - `pix_fmt` is **not** stored; we collapse it into a `bit_depth` integer
//!   (8, 10, or 12). Default 8 covers SDR + the rare unrecognised case.
//! - `color_profile` prefers `color_space` and falls back to `color_primaries`.
//!   When both are missing, `unknown`, or `reserved` we send `None` — never
//!   invented strings, never blocking the import.
//! - Aspect ratio: compute, reduce by GCD, emit canonical `16:9` / `9:16` /
//!   `4:3` within ±0.01 tolerance, otherwise the reduced `W:H`.
//! - Orientation: landscape if `width >= height`, else portrait. Nullable
//!   when no video stream is present.
//! - Audio stream count drives `has_commentary_track = (count >= 2)`.
//! - `recorded_at` prefers `format.tags.creation_time` (ISO 8601 / RFC 3339)
//!   when parseable, otherwise the file mtime.

use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, anyhow};
use serde::Deserialize;

/// Result of probing one file: the strongly typed metadata that the diff and
/// API stages care about. None of these fields directly mirror the ffprobe
/// JSON keys — see the per-field comments in [`parse_probe_json`] for the
/// derivation rules.
#[derive(Debug, Clone, PartialEq)]
pub struct ProbeReport {
    pub duration_seconds: Option<u64>,
    pub resolution: Option<String>,
    pub fps: Option<f64>,
    pub codec: Option<String>,
    pub bit_depth: u32,
    pub color_profile: Option<String>,
    pub aspect_ratio: Option<String>,
    pub orientation: Option<Orientation>,
    pub audio_track_count: u32,
    pub has_commentary_track: bool,
    /// ISO 8601 timestamp string. Filled from `format.tags.creation_time` if
    /// parseable; otherwise from the file's mtime by the caller.
    pub recorded_at: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Orientation {
    Landscape,
    Portrait,
}

impl Orientation {
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Landscape => "landscape",
            Self::Portrait => "portrait",
        }
    }
}

/// Errors specific to the probe stage. The importer maps `Missing` to the
/// "ffmpeg / ffprobe not found" install hint and any other variant to a
/// per-file failure.
#[derive(Debug, thiserror::Error)]
pub enum ProbeError {
    /// `ffprobe` is not on `$PATH` (and not at `/usr/bin/ffprobe`).
    #[error("ffprobe not found")]
    Missing,
    /// `ffprobe` ran but exited non-zero. The string is the captured stderr.
    #[error("ffprobe failed: {0}")]
    Failed(String),
    /// `ffprobe` succeeded but the JSON didn't parse.
    #[error("ffprobe output unparseable: {0}")]
    Unparseable(String),
}

/// Resolve the `ffprobe` binary location, preferring `/usr/bin/ffprobe`
/// (Linux-x86_64 only this phase) and falling back to `$PATH` via the
/// `which` crate.
pub fn resolve_ffprobe() -> Result<PathBuf, ProbeError> {
    let canonical = PathBuf::from("/usr/bin/ffprobe");
    if canonical.is_file() {
        return Ok(canonical);
    }
    which::which("ffprobe").map_err(|_| ProbeError::Missing)
}

/// Run `ffprobe` against `file`, capture its JSON output, and parse it into a
/// `ProbeReport`. The caller decides whether to fall back to file mtime for
/// `recorded_at` if the JSON didn't carry one.
pub fn probe_file(ffprobe_path: &Path, file: &Path) -> Result<ProbeReport, ProbeError> {
    let output = Command::new(ffprobe_path)
        .arg("-v")
        .arg("quiet")
        .arg("-print_format")
        .arg("json")
        .arg("-show_format")
        .arg("-show_streams")
        .arg(file)
        .output()
        .map_err(|e| {
            // ENOENT here means the resolved path went stale between
            // `resolve_ffprobe` and this call — treat it as missing.
            if e.kind() == std::io::ErrorKind::NotFound {
                ProbeError::Missing
            } else {
                ProbeError::Failed(e.to_string())
            }
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        return Err(ProbeError::Failed(stderr));
    }

    parse_probe_json(&output.stdout)
}

/// Pure JSON-to-`ProbeReport` parser. Lifted out of [`probe_file`] so the
/// whole rule set is exercisable by unit tests without spawning a process.
pub fn parse_probe_json(bytes: &[u8]) -> Result<ProbeReport, ProbeError> {
    let raw: FfprobeOutput =
        serde_json::from_slice(bytes).map_err(|e| ProbeError::Unparseable(e.to_string()))?;

    let video = raw
        .streams
        .iter()
        .find(|s| s.codec_type.as_deref() == Some("video"));
    let audio_track_count = raw
        .streams
        .iter()
        .filter(|s| s.codec_type.as_deref() == Some("audio"))
        .count() as u32;

    let duration_seconds = raw
        .format
        .as_ref()
        .and_then(|f| f.duration.as_deref())
        .and_then(|s| s.parse::<f64>().ok())
        .map(|d| d.round() as u64);

    let (width, height) = match video {
        Some(v) => (v.width, v.height),
        None => (None, None),
    };

    let resolution = match (width, height) {
        (Some(w), Some(h)) => Some(format!("{}x{}", w, h)),
        _ => None,
    };

    let fps = video.and_then(|v| {
        // Prefer r_frame_rate; fall back to avg_frame_rate. Both arrive as
        // strings shaped like "num/den" where den can be 0 for streams with
        // no fixed frame rate (skip those, they're not meaningful as fps).
        v.r_frame_rate
            .as_deref()
            .and_then(parse_rational)
            .or_else(|| v.avg_frame_rate.as_deref().and_then(parse_rational))
    });

    let codec = video.and_then(|v| v.codec_name.clone());

    let bit_depth = video
        .and_then(|v| v.pix_fmt.as_deref())
        .map(bit_depth_from_pix_fmt)
        .unwrap_or(8);

    let color_profile = video.and_then(|v| {
        // color_space wins; fall back to color_primaries; refuse "unknown" /
        // "reserved" / empty — those map to None so Rails can leave the
        // column null. We never invent a value.
        normalize_color(v.color_space.as_deref())
            .or_else(|| normalize_color(v.color_primaries.as_deref()))
    });

    let aspect_ratio = match (width, height) {
        (Some(w), Some(h)) if w > 0 && h > 0 => Some(canonical_aspect_ratio(w, h)),
        _ => None,
    };

    let orientation = match (width, height) {
        (Some(w), Some(h)) => Some(if w >= h {
            Orientation::Landscape
        } else {
            Orientation::Portrait
        }),
        _ => None,
    };

    let recorded_at = raw
        .format
        .as_ref()
        .and_then(|f| f.tags.as_ref())
        .and_then(|t| t.creation_time.clone())
        .filter(|s| !s.trim().is_empty());

    Ok(ProbeReport {
        duration_seconds,
        resolution,
        fps,
        codec,
        bit_depth,
        color_profile,
        aspect_ratio,
        orientation,
        audio_track_count,
        has_commentary_track: audio_track_count >= 2,
        recorded_at,
    })
}

/// Parse "num/den" → f64, rounded to 3 decimals (matches Rails `decimal(6, 3)`).
/// Returns None on a 0 denominator or anything that isn't an obvious rational.
fn parse_rational(s: &str) -> Option<f64> {
    let (num, den) = s.split_once('/')?;
    let num: f64 = num.parse().ok()?;
    let den: f64 = den.parse().ok()?;
    if den == 0.0 {
        return None;
    }
    let value = num / den;
    Some((value * 1000.0).round() / 1000.0)
}

/// Map a ffprobe `pix_fmt` to a bit depth. The mapping covers the formats we
/// expect in OBS / camera footage; anything unrecognised collapses to 8 (the
/// SDR default — never blocks ingestion).
///
/// 10-bit detection is deliberate string sniffing — pix_fmt names are
/// stable and the alternative (a full enum) would chase upstream churn.
fn bit_depth_from_pix_fmt(pix_fmt: &str) -> u32 {
    let lower = pix_fmt.to_ascii_lowercase();
    if lower.contains("p12le") || lower.contains("p12be") {
        12
    } else if lower.contains("p10le") || lower.contains("p10be") || lower == "p010le" {
        10
    } else {
        // yuv420p, yuv422p, yuv444p, nv12, rgb24, etc.
        8
    }
}

/// Filter color values: ffprobe sometimes returns `unknown` / `reserved` / `""`
/// — none of those carry information so we map to None.
fn normalize_color(value: Option<&str>) -> Option<String> {
    let v = value?.trim();
    if v.is_empty() || v.eq_ignore_ascii_case("unknown") || v.eq_ignore_ascii_case("reserved") {
        None
    } else {
        Some(v.to_string())
    }
}

/// Reduce W:H by GCD and snap to a canonical label (`16:9`, `9:16`, `4:3`)
/// when within ±0.01 of the canonical ratio. Otherwise return the reduced
/// pair directly (e.g. `21:9`).
fn canonical_aspect_ratio(w: u32, h: u32) -> String {
    let ratio = w as f64 / h as f64;
    const TOLERANCE: f64 = 0.01;
    let canonicals = [
        (16.0 / 9.0, "16:9"),
        (9.0 / 16.0, "9:16"),
        (4.0 / 3.0, "4:3"),
    ];
    for (target, label) in canonicals.iter() {
        if (ratio - target).abs() <= TOLERANCE {
            return (*label).to_string();
        }
    }
    let g = gcd(w, h);
    format!("{}:{}", w / g, h / g)
}

fn gcd(a: u32, b: u32) -> u32 {
    if b == 0 { a } else { gcd(b, a % b) }
}

// --- ffprobe JSON shape -----------------------------------------------------
//
// Only the fields we read are in scope; any extras come along for the ride and
// get dropped. `serde(default)` everywhere because ffprobe omits keys that
// don't apply (e.g. no `width` on audio streams).

#[derive(Debug, Deserialize)]
struct FfprobeOutput {
    #[serde(default)]
    streams: Vec<Stream>,
    #[serde(default)]
    format: Option<FormatBlock>,
}

#[derive(Debug, Deserialize)]
struct Stream {
    #[serde(default)]
    codec_type: Option<String>,
    #[serde(default)]
    codec_name: Option<String>,
    #[serde(default)]
    width: Option<u32>,
    #[serde(default)]
    height: Option<u32>,
    #[serde(default)]
    pix_fmt: Option<String>,
    #[serde(default)]
    color_space: Option<String>,
    #[serde(default)]
    color_primaries: Option<String>,
    #[serde(default)]
    r_frame_rate: Option<String>,
    #[serde(default)]
    avg_frame_rate: Option<String>,
}

#[derive(Debug, Deserialize)]
struct FormatBlock {
    #[serde(default)]
    duration: Option<String>,
    #[serde(default)]
    tags: Option<FormatTags>,
}

#[derive(Debug, Deserialize)]
struct FormatTags {
    #[serde(default)]
    creation_time: Option<String>,
}

/// Print the canonical install hint for missing ffprobe and return an error.
/// Wired into the importer's main entry point — keeps the message identical
/// across spec changes.
pub fn print_install_hint() {
    eprintln!("ffmpeg / ffprobe not found.");
    eprintln!("Install:");
    eprintln!("  Debian/Ubuntu: sudo apt install ffmpeg");
    eprintln!("  macOS (brew):  brew install ffmpeg");
    eprintln!("  Arch:          sudo pacman -S ffmpeg");
}

/// Helper used by the importer to fall back to file mtime if the probe report
/// didn't carry a `creation_time`. Returns an ISO 8601 UTC timestamp.
pub fn file_mtime_iso(file: &Path) -> Result<String> {
    let meta =
        std::fs::metadata(file).with_context(|| format!("read mtime of {}", file.display()))?;
    let modified = meta
        .modified()
        .with_context(|| format!("modified time of {}", file.display()))?;
    let secs = modified
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| anyhow!("file mtime before unix epoch: {}", e))?
        .as_secs() as i64;
    let dt = chrono::DateTime::<chrono::Utc>::from_timestamp(secs, 0)
        .ok_or_else(|| anyhow!("file mtime out of chrono range"))?;
    Ok(dt.format("%Y-%m-%dT%H:%M:%SZ").to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn report(json: &str) -> ProbeReport {
        parse_probe_json(json.as_bytes()).expect("parse")
    }

    #[test]
    fn parses_ntsc_rational_fps_to_three_decimals() {
        let json = r#"{
            "streams": [
                {"codec_type":"video","codec_name":"h264","width":1920,"height":1080,
                 "pix_fmt":"yuv420p","r_frame_rate":"30000/1001","avg_frame_rate":"30000/1001"}
            ]
        }"#;
        let r = report(json);
        // 30000/1001 = 29.9700299..., rounded to 3 decimals = 29.970
        assert_eq!(r.fps, Some(29.970));
    }

    #[test]
    fn parses_60_fps_clean_rational() {
        let json = r#"{
            "streams":[{"codec_type":"video","width":1920,"height":1080,
                        "pix_fmt":"yuv420p","r_frame_rate":"60/1"}]
        }"#;
        let r = report(json);
        assert_eq!(r.fps, Some(60.0));
    }

    #[test]
    fn falls_back_to_avg_frame_rate_when_r_is_missing() {
        let json = r#"{
            "streams":[{"codec_type":"video","width":1920,"height":1080,
                        "pix_fmt":"yuv420p","avg_frame_rate":"24/1"}]
        }"#;
        let r = report(json);
        assert_eq!(r.fps, Some(24.0));
    }

    #[test]
    fn zero_denominator_in_rational_yields_none() {
        // ffprobe emits "0/0" for streams with no frame rate; we should not
        // crash and we should not store a bogus 0.0.
        assert_eq!(parse_rational("0/0"), None);
        assert_eq!(parse_rational("30/0"), None);
    }

    #[test]
    fn bit_depth_8_for_yuv420p() {
        assert_eq!(bit_depth_from_pix_fmt("yuv420p"), 8);
        assert_eq!(bit_depth_from_pix_fmt("yuv422p"), 8);
        assert_eq!(bit_depth_from_pix_fmt("yuv444p"), 8);
        assert_eq!(bit_depth_from_pix_fmt("nv12"), 8);
        assert_eq!(bit_depth_from_pix_fmt("rgb24"), 8);
    }

    #[test]
    fn bit_depth_10_for_p10le_variants() {
        assert_eq!(bit_depth_from_pix_fmt("yuv420p10le"), 10);
        assert_eq!(bit_depth_from_pix_fmt("yuv422p10le"), 10);
        assert_eq!(bit_depth_from_pix_fmt("p010le"), 10);
    }

    #[test]
    fn bit_depth_12_for_p12le_variants() {
        assert_eq!(bit_depth_from_pix_fmt("yuv420p12le"), 12);
        assert_eq!(bit_depth_from_pix_fmt("yuv422p12be"), 12);
    }

    #[test]
    fn bit_depth_default_for_unknown_pix_fmt() {
        assert_eq!(bit_depth_from_pix_fmt("vivid_dream_format"), 8);
    }

    #[test]
    fn color_profile_prefers_color_space_over_primaries() {
        let json = r#"{
            "streams":[{"codec_type":"video","width":1920,"height":1080,
                        "pix_fmt":"yuv420p","color_space":"bt709","color_primaries":"bt470bg"}]
        }"#;
        let r = report(json);
        assert_eq!(r.color_profile.as_deref(), Some("bt709"));
    }

    #[test]
    fn color_profile_falls_back_to_primaries() {
        let json = r#"{
            "streams":[{"codec_type":"video","width":1920,"height":1080,
                        "pix_fmt":"yuv420p","color_primaries":"smpte170m"}]
        }"#;
        let r = report(json);
        assert_eq!(r.color_profile.as_deref(), Some("smpte170m"));
    }

    #[test]
    fn color_profile_none_when_unknown_or_reserved() {
        // ffprobe sometimes emits literal "unknown" / "reserved" — we must
        // not store those; the column accepts null.
        let json = r#"{
            "streams":[{"codec_type":"video","width":1920,"height":1080,
                        "pix_fmt":"yuv420p","color_space":"unknown",
                        "color_primaries":"reserved"}]
        }"#;
        let r = report(json);
        assert!(r.color_profile.is_none());
    }

    #[test]
    fn color_profile_none_when_missing_entirely() {
        let json = r#"{
            "streams":[{"codec_type":"video","width":1920,"height":1080,
                        "pix_fmt":"yuv420p"}]
        }"#;
        let r = report(json);
        assert!(r.color_profile.is_none());
    }

    #[test]
    fn aspect_ratio_canonical_16_9_for_1920x1080() {
        let json = r#"{
            "streams":[{"codec_type":"video","width":1920,"height":1080,
                        "pix_fmt":"yuv420p"}]
        }"#;
        let r = report(json);
        assert_eq!(r.aspect_ratio.as_deref(), Some("16:9"));
        assert_eq!(r.orientation, Some(Orientation::Landscape));
    }

    #[test]
    fn aspect_ratio_canonical_9_16_for_portrait() {
        let json = r#"{
            "streams":[{"codec_type":"video","width":1080,"height":1920,
                        "pix_fmt":"yuv420p"}]
        }"#;
        let r = report(json);
        assert_eq!(r.aspect_ratio.as_deref(), Some("9:16"));
        assert_eq!(r.orientation, Some(Orientation::Portrait));
    }

    #[test]
    fn aspect_ratio_canonical_4_3() {
        let json = r#"{
            "streams":[{"codec_type":"video","width":640,"height":480,
                        "pix_fmt":"yuv420p"}]
        }"#;
        let r = report(json);
        assert_eq!(r.aspect_ratio.as_deref(), Some("4:3"));
    }

    #[test]
    fn aspect_ratio_falls_back_to_reduced_w_h_for_oddballs() {
        // 21:9 ultrawide isn't in the canonical set — should appear reduced.
        let json = r#"{
            "streams":[{"codec_type":"video","width":2520,"height":1080,
                        "pix_fmt":"yuv420p"}]
        }"#;
        let r = report(json);
        assert_eq!(r.aspect_ratio.as_deref(), Some("7:3"));
    }

    #[test]
    fn audio_track_count_drives_commentary_flag() {
        let json = r#"{
            "streams":[
                {"codec_type":"video","width":1920,"height":1080,"pix_fmt":"yuv420p"},
                {"codec_type":"audio"},
                {"codec_type":"audio"}
            ]
        }"#;
        let r = report(json);
        assert_eq!(r.audio_track_count, 2);
        assert!(r.has_commentary_track);
    }

    #[test]
    fn single_audio_track_means_no_commentary() {
        let json = r#"{
            "streams":[
                {"codec_type":"video","width":1920,"height":1080,"pix_fmt":"yuv420p"},
                {"codec_type":"audio"}
            ]
        }"#;
        let r = report(json);
        assert_eq!(r.audio_track_count, 1);
        assert!(!r.has_commentary_track);
    }

    #[test]
    fn duration_rounds_to_nearest_second() {
        let json = r#"{
            "streams":[{"codec_type":"video","width":1920,"height":1080,"pix_fmt":"yuv420p"}],
            "format":{"duration":"123.789"}
        }"#;
        let r = report(json);
        assert_eq!(r.duration_seconds, Some(124));
    }

    #[test]
    fn recorded_at_pulled_from_format_tags_creation_time() {
        let json = r#"{
            "streams":[{"codec_type":"video","width":1920,"height":1080,"pix_fmt":"yuv420p"}],
            "format":{"tags":{"creation_time":"2026-04-01T10:15:00Z"}}
        }"#;
        let r = report(json);
        assert_eq!(r.recorded_at.as_deref(), Some("2026-04-01T10:15:00Z"));
    }

    #[test]
    fn recorded_at_none_when_blank_tag() {
        // An all-whitespace creation_time should be treated as absent.
        let json = r#"{
            "streams":[{"codec_type":"video","width":1920,"height":1080,"pix_fmt":"yuv420p"}],
            "format":{"tags":{"creation_time":"   "}}
        }"#;
        let r = report(json);
        assert!(r.recorded_at.is_none());
    }

    #[test]
    fn missing_video_stream_yields_nullable_video_fields() {
        let json = r#"{ "streams":[{"codec_type":"audio"}] }"#;
        let r = report(json);
        assert_eq!(r.resolution, None);
        assert_eq!(r.fps, None);
        assert_eq!(r.codec, None);
        assert_eq!(r.aspect_ratio, None);
        assert_eq!(r.orientation, None);
        // Default 8 still applies when there's no video — bit_depth is non-null.
        assert_eq!(r.bit_depth, 8);
    }

    #[test]
    fn unparseable_json_returns_unparseable_error() {
        let err = parse_probe_json(b"not json").unwrap_err();
        assert!(matches!(err, ProbeError::Unparseable(_)));
    }

    #[test]
    fn gcd_helper_basic() {
        assert_eq!(gcd(1920, 1080), 120);
        assert_eq!(gcd(1080, 1920), 120);
        assert_eq!(gcd(7, 13), 1);
    }
}
