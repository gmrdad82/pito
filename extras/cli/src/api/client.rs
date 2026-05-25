use super::models::*;
use anyhow::Result;
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};

pub trait PitoClient {
    fn get_dashboard(&self) -> Result<DashboardData>;
    fn get_channels(&self) -> Result<Vec<Channel>>;
    fn get_channel(&self, id: u64) -> Result<Channel>;
    fn get_channel_videos(&self, channel_id: u64) -> Result<Vec<Video>>;
    fn get_videos(&self) -> Result<Vec<Video>>;
    fn get_video(&self, id: u64) -> Result<Video>;
    fn get_video_stats(&self, video_id: u64) -> Result<Vec<VideoStat>>;
    fn search(&self, query: &str) -> Result<SearchResults>;
    fn get_saved_views(&self) -> Result<Vec<SavedView>>;
    fn get_settings(&self) -> Result<AppSettings>;

    // Bulk-as-foundation: no single-record destructive variants.
    // Single-record actions are bulk operations with a single id.
    fn bulk_delete_channels(&self, ids: &[u64], confirm: bool) -> Result<BulkOperationResponse>;
    fn bulk_sync_channels(&self, ids: &[u64], confirm: bool) -> Result<BulkOperationResponse>;
    /// Creating channels via the TUI is not yet wired up — the `[add]` button
    /// has no handler. Kept for the upcoming flow; suppress dead-code lint.
    #[allow(dead_code)]
    fn create_channel(&self, channel_url: &str) -> Result<Channel>;
    /// Update mutable channel fields. Currently only `star` is editable from
    /// pito — the `connected` flag is OAuth-managed and only the web UI is
    /// allowed to toggle it (see Fix 2 in the May 2026 cleanup).
    fn update_channel(&self, id: u64, star: Option<bool>) -> Result<Channel>;

    /// Snapshot of a server-side bulk operation for in-TUI progress display.
    /// Implementations return the same shape regardless of `kind`; the TUI
    /// reads `status` to know when polling should stop.
    fn get_bulk_operation_status(&self, id: u64) -> Result<BulkOperationStatus>;

    /// Send an arbitrary command string to `POST /commands/execute`.
    /// Returns the server response body as a plain string.
    fn execute_command(&self, command: &str) -> Result<String>;

    /// Authenticate with a 6-digit TOTP code via POST /login.
    /// Returns true if auth succeeded.
    fn authenticate(&self, code: &str) -> Result<bool>;
}

/// Per-bulk-operation bookkeeping for the mock client. We need to remember the
/// targeted ids, the operation kind, and a poll counter so successive calls to
/// `get_bulk_operation_status` march `pending` → `running` → `completed`.
#[derive(Debug, Clone)]
struct MockOperation {
    kind: String,
    target_ids: Vec<u64>,
    poll_count: u32,
}

pub struct MockClient {
    channels: RefCell<Vec<Channel>>,
    videos: RefCell<Vec<Video>>,
    /// Used for mock-side ID assignment in `create_channel`. The TUI doesn't
    /// invoke that method yet, but the bookkeeping stays so the field is
    /// ready when the create flow lands.
    #[allow(dead_code)]
    next_id: RefCell<u64>,
    next_op_id: RefCell<u64>,
    operations: RefCell<HashMap<u64, MockOperation>>,
    /// CLI-local marker for "this channel has a bulk_sync in flight". Rails no
    /// longer emits a `syncing` boolean (Path A2 retract), so the mock fakes
    /// the in-flight state by remembering ids it was told to sync but hasn't
    /// finalized yet.
    syncing_ids: RefCell<HashSet<u64>>,
}

impl Default for MockClient {
    fn default() -> Self {
        Self::new()
    }
}

impl MockClient {
    pub fn new() -> Self {
        // Seed the syncing marker for channel #2 to mirror the legacy "channel
        // 2 is mid-sync" fixture state. Lets the TUI tests still exercise the
        // "skipped because already syncing" branch even though the wire shape
        // no longer carries `syncing`.
        let mut syncing = HashSet::new();
        syncing.insert(2u64);
        Self {
            channels: RefCell::new(seed_channels()),
            videos: RefCell::new(seed_videos()),
            next_id: RefCell::new(100),
            next_op_id: RefCell::new(1000),
            operations: RefCell::new(HashMap::new()),
            syncing_ids: RefCell::new(syncing),
        }
    }

    fn record_operation(&self, op_id: u64, kind: &str, target_ids: &[u64]) {
        self.operations.borrow_mut().insert(
            op_id,
            MockOperation {
                kind: kind.to_string(),
                target_ids: target_ids.to_vec(),
                poll_count: 0,
            },
        );
    }

    fn date_series(&self, days: u32) -> Vec<String> {
        // Generate dates going back from 2026-04-30
        (0..days)
            .rev()
            .map(|i| {
                let day = 30 - i as i32;
                if day > 0 {
                    format!("2026-04-{:02}", day)
                } else {
                    let march_day = 31 + day;
                    format!("2026-03-{:02}", march_day)
                }
            })
            .collect()
    }

    /// Test-only hook: query the in-flight sync marker. Not exposed via
    /// `PitoClient` — Rails JSON doesn't carry this — but the unit tests want
    /// to assert the mock simulates the bulk_sync flow correctly.
    #[cfg(test)]
    pub fn is_syncing(&self, id: u64) -> bool {
        self.syncing_ids.borrow().contains(&id)
    }
}

fn seed_channels() -> Vec<Channel> {
    vec![
        Channel {
            id: 1,
            tenant_id: 1,
            channel_url: "https://youtube.com/@rust-academy".to_string(),
            star: true,
            connected: true,
            last_synced_at: Some("2026-04-30T09:25:00Z".to_string()),
            created_at: "2026-01-12T08:00:00Z".to_string(),
            updated_at: "2026-04-30T09:25:00Z".to_string(),
        },
        Channel {
            id: 2,
            tenant_id: 1,
            channel_url: "https://youtube.com/@devlog-daily".to_string(),
            star: false,
            connected: true,
            last_synced_at: Some("2026-04-30T08:50:00Z".to_string()),
            created_at: "2026-01-20T08:00:00Z".to_string(),
            updated_at: "2026-04-30T09:30:00Z".to_string(),
        },
        Channel {
            id: 3,
            tenant_id: 1,
            channel_url: "https://youtube.com/@code-review-club".to_string(),
            star: true,
            connected: false,
            last_synced_at: Some("2026-04-29T22:10:00Z".to_string()),
            created_at: "2026-02-01T08:00:00Z".to_string(),
            updated_at: "2026-04-29T22:10:00Z".to_string(),
        },
        Channel {
            id: 4,
            tenant_id: 1,
            channel_url: "https://youtube.com/@tui-builders".to_string(),
            star: false,
            connected: true,
            last_synced_at: None,
            created_at: "2026-04-25T08:00:00Z".to_string(),
            updated_at: "2026-04-25T08:00:00Z".to_string(),
        },
        Channel {
            id: 5,
            tenant_id: 1,
            channel_url: "https://youtube.com/@indie-hackers-fr".to_string(),
            star: false,
            connected: false,
            last_synced_at: Some("2026-04-15T12:00:00Z".to_string()),
            created_at: "2026-03-12T08:00:00Z".to_string(),
            updated_at: "2026-04-15T12:00:00Z".to_string(),
        },
    ]
}

/// Seed row for `seed_videos`. Pulled into its own struct to keep the seed
/// table compact and side-step the `type_complexity` clippy lint that fires
/// on long tuple-of-primitives signatures.
struct VideoSeed {
    id: u64,
    youtube_video_id: &'static str,
    channel_id: u64,
    star: bool,
    views: u64,
    likes: u64,
    comments: u64,
    watch_time_minutes: f64,
    synced_at: &'static str,
}

fn seed_videos() -> Vec<Video> {
    // Phase 7 Path A2 fixture: thin Video records (no title / privacy /
    // duration / published_at). The TUI now renders youtube id + channel url
    // + counts pulled from VideoStat, mirroring the live Rails JSON shape.
    let rows = [
        VideoSeed {
            id: 1,
            youtube_video_id: "dQw4w9WgXcQ",
            channel_id: 1,
            star: true,
            views: 89_420,
            likes: 4_210,
            comments: 312,
            watch_time_minutes: 28_450.0,
            synced_at: "2026-04-30T09:25:00Z",
        },
        VideoSeed {
            id: 2,
            youtube_video_id: "abc123def45",
            channel_id: 1,
            star: false,
            views: 45_300,
            likes: 2_890,
            comments: 187,
            watch_time_minutes: 18_200.0,
            synced_at: "2026-04-30T09:25:00Z",
        },
        VideoSeed {
            id: 3,
            youtube_video_id: "xyz789ghi01",
            channel_id: 1,
            star: false,
            views: 67_100,
            likes: 3_450,
            comments: 256,
            watch_time_minutes: 22_100.0,
            synced_at: "2026-04-30T09:25:00Z",
        },
        VideoSeed {
            id: 4,
            youtube_video_id: "mno234pqr56",
            channel_id: 1,
            star: false,
            views: 132_800,
            likes: 7_620,
            comments: 891,
            watch_time_minutes: 41_300.0,
            synced_at: "2026-04-30T09:25:00Z",
        },
        VideoSeed {
            id: 5,
            youtube_video_id: "stu567vwx89",
            channel_id: 1,
            star: false,
            views: 38_900,
            likes: 2_100,
            comments: 145,
            watch_time_minutes: 12_400.0,
            synced_at: "2026-04-30T09:25:00Z",
        },
        VideoSeed {
            id: 6,
            youtube_video_id: "yza012bcd34",
            channel_id: 2,
            star: false,
            views: 23_400,
            likes: 1_890,
            comments: 234,
            watch_time_minutes: 8_900.0,
            synced_at: "2026-04-30T08:50:00Z",
        },
        VideoSeed {
            id: 7,
            youtube_video_id: "efg345hij67",
            channel_id: 2,
            star: false,
            views: 41_200,
            likes: 3_670,
            comments: 412,
            watch_time_minutes: 14_500.0,
            synced_at: "2026-04-30T08:50:00Z",
        },
        VideoSeed {
            id: 8,
            youtube_video_id: "klm678nop90",
            channel_id: 2,
            star: false,
            views: 56_700,
            likes: 2_980,
            comments: 198,
            watch_time_minutes: 19_800.0,
            synced_at: "2026-04-30T08:50:00Z",
        },
        VideoSeed {
            id: 9,
            youtube_video_id: "qrs901tuv23",
            channel_id: 2,
            star: true,
            views: 78_300,
            likes: 4_560,
            comments: 567,
            watch_time_minutes: 25_600.0,
            synced_at: "2026-04-30T08:50:00Z",
        },
        VideoSeed {
            id: 10,
            youtube_video_id: "wxy234zab56",
            channel_id: 2,
            star: false,
            views: 112_000,
            likes: 5_890,
            comments: 723,
            watch_time_minutes: 34_100.0,
            synced_at: "2026-04-30T08:50:00Z",
        },
        VideoSeed {
            id: 11,
            youtube_video_id: "cde567fgh89",
            channel_id: 2,
            star: false,
            views: 19_800,
            likes: 1_340,
            comments: 89,
            watch_time_minutes: 7_200.0,
            synced_at: "2026-04-30T08:50:00Z",
        },
        VideoSeed {
            id: 12,
            youtube_video_id: "ijk890lmn12",
            channel_id: 3,
            star: false,
            views: 34_500,
            likes: 2_120,
            comments: 178,
            watch_time_minutes: 15_600.0,
            synced_at: "2026-04-29T22:10:00Z",
        },
        VideoSeed {
            id: 13,
            youtube_video_id: "opq123rst45",
            channel_id: 3,
            star: false,
            views: 87_600,
            likes: 5_430,
            comments: 634,
            watch_time_minutes: 31_200.0,
            synced_at: "2026-04-29T22:10:00Z",
        },
        VideoSeed {
            id: 14,
            youtube_video_id: "uvw456xyz78",
            channel_id: 3,
            star: false,
            views: 52_100,
            likes: 3_210,
            comments: 245,
            watch_time_minutes: 20_800.0,
            synced_at: "2026-04-29T22:10:00Z",
        },
        VideoSeed {
            id: 15,
            youtube_video_id: "abc890def12",
            channel_id: 3,
            star: false,
            views: 29_300,
            likes: 1_780,
            comments: 156,
            watch_time_minutes: 11_400.0,
            synced_at: "2026-04-29T22:10:00Z",
        },
        VideoSeed {
            id: 16,
            youtube_video_id: "ghi345jkl67",
            channel_id: 1,
            star: false,
            views: 12_400,
            likes: 890,
            comments: 67,
            watch_time_minutes: 5_600.0,
            synced_at: "2026-04-30T09:25:00Z",
        },
        VideoSeed {
            id: 17,
            youtube_video_id: "mno678pqr90",
            channel_id: 1,
            star: false,
            views: 28_700,
            likes: 1_560,
            comments: 234,
            watch_time_minutes: 45_200.0,
            synced_at: "2026-04-30T09:25:00Z",
        },
    ];
    rows.into_iter()
        .map(|r| {
            let channel_url = match r.channel_id {
                1 => Some("https://youtube.com/@rust-academy".to_string()),
                2 => Some("https://youtube.com/@devlog-daily".to_string()),
                3 => Some("https://youtube.com/@code-review-club".to_string()),
                _ => None,
            };
            Video {
                id: r.id,
                youtube_video_id: r.youtube_video_id.to_string(),
                channel_id: r.channel_id,
                channel_url,
                star: r.star,
                views: r.views,
                likes: r.likes,
                comments: r.comments,
                watch_time_minutes: r.watch_time_minutes,
                last_synced_at: Some(r.synced_at.to_string()),
                trend: None,
            }
        })
        .collect()
}

impl PitoClient for MockClient {
    fn get_dashboard(&self) -> Result<DashboardData> {
        Ok(DashboardData {
            video_count: self.videos.borrow().len() as u64,
            channel_count: self.channels.borrow().len() as u64,
            project_count: 2,
            footage_count: 87,
            note_count: 14,
        })
    }

    fn get_channels(&self) -> Result<Vec<Channel>> {
        Ok(self.channels.borrow().clone())
    }

    fn get_channel(&self, id: u64) -> Result<Channel> {
        self.channels
            .borrow()
            .iter()
            .find(|c| c.id == id)
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("Channel not found: {}", id))
    }

    fn get_channel_videos(&self, channel_id: u64) -> Result<Vec<Video>> {
        Ok(self
            .videos
            .borrow()
            .iter()
            .filter(|v| v.channel_id == channel_id)
            .cloned()
            .collect())
    }

    fn get_videos(&self) -> Result<Vec<Video>> {
        Ok(self.videos.borrow().clone())
    }

    fn get_video(&self, id: u64) -> Result<Video> {
        self.videos
            .borrow()
            .iter()
            .find(|v| v.id == id)
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("Video not found: {}", id))
    }

    fn get_video_stats(&self, _video_id: u64) -> Result<Vec<VideoStat>> {
        let dates = self.date_series(30);
        let stats: Vec<VideoStat> = dates
            .into_iter()
            .enumerate()
            .map(|(i, date)| {
                let base = 800 + (i as u64 * 47) % 600;
                VideoStat {
                    date,
                    views: base + (i as u64 * 31) % 400,
                    likes: base / 15 + (i as u64 * 3) % 20,
                    comments: base / 40 + (i as u64 * 2) % 10,
                    watch_time_minutes: (base as f64) * 3.2 + (i as f64) * 12.5,
                }
            })
            .collect();
        Ok(stats)
    }

    fn search(&self, query: &str) -> Result<SearchResults> {
        // Path A2 retract: Video has no `title` field anymore. Match against
        // `youtube_video_id` and the parent `channel_url` instead so the mock
        // surface stays exercise-able from tests and dev play.
        let query_lower = query.to_lowercase();

        let matching_videos: Vec<SearchHit<Video>> = self
            .videos
            .borrow()
            .iter()
            .filter(|v| {
                v.youtube_video_id.to_lowercase().contains(&query_lower)
                    || v.channel_url
                        .as_deref()
                        .map(|u| u.to_lowercase().contains(&query_lower))
                        .unwrap_or(false)
            })
            .cloned()
            .map(|v| SearchHit {
                record: v,
                highlights: None,
            })
            .collect();

        let video_total = matching_videos.len() as u64;

        Ok(SearchResults {
            videos: matching_videos,
            video_total,
            took_ms: 12.4,
        })
    }

    fn get_saved_views(&self) -> Result<Vec<SavedView>> {
        Ok(vec![
            SavedView {
                id: 1,
                kind: "dashboard".to_string(),
                name: "Weekly Overview".to_string(),
                url: "/dashboard?range=7d".to_string(),
            },
            SavedView {
                id: 2,
                kind: "channel".to_string(),
                name: "Rust Academy Videos".to_string(),
                url: "/channels/1/videos".to_string(),
            },
            SavedView {
                id: 3,
                kind: "search".to_string(),
                name: "Rust content".to_string(),
                url: "/search?q=rust".to_string(),
            },
            SavedView {
                id: 4,
                kind: "dashboard".to_string(),
                name: "Monthly Stats".to_string(),
                url: "/dashboard?range=30d".to_string(),
            },
        ])
    }

    fn get_settings(&self) -> Result<AppSettings> {
        Ok(AppSettings {
            max_panes: 4,
            pane_title_length: 24,
            theme: "dark".to_string(),
        })
    }

    fn bulk_delete_channels(&self, ids: &[u64], confirm: bool) -> Result<BulkOperationResponse> {
        // Delete preview/enqueue. Skipped items would normally be those the user lacks
        // permission for; the mock has no auth so we simply pass everything through.
        let total = ids.len() as u32;
        if !confirm {
            Ok(BulkOperationResponse {
                mode: ResponseMode::Preview,
                total,
                syncable: vec![],
                skipped: vec![],
                operation_id: None,
                message: format!("{} channel(s) will be deleted", total),
            })
        } else {
            // Actually remove from the mock store
            self.channels.borrow_mut().retain(|c| !ids.contains(&c.id));
            self.videos
                .borrow_mut()
                .retain(|v| !ids.contains(&v.channel_id));
            // Drop the in-flight sync marker for any deleted ids.
            self.syncing_ids.borrow_mut().retain(|id| !ids.contains(id));
            let op_id = {
                let mut next = self.next_op_id.borrow_mut();
                let id = *next;
                *next += 1;
                id
            };
            self.record_operation(op_id, "bulk_delete", ids);
            Ok(BulkOperationResponse {
                mode: ResponseMode::Enqueued,
                total,
                syncable: vec![],
                skipped: vec![],
                operation_id: Some(op_id),
                message: format!("Enqueued delete for {} channel(s)", total),
            })
        }
    }

    fn bulk_sync_channels(&self, ids: &[u64], confirm: bool) -> Result<BulkOperationResponse> {
        let channels = self.channels.borrow();
        let syncing = self.syncing_ids.borrow();
        let mut syncable: Vec<u64> = Vec::new();
        let mut skipped: Vec<SkippedItem> = Vec::new();
        for id in ids {
            match channels.iter().find(|c| c.id == *id) {
                Some(_) if syncing.contains(id) => skipped.push(SkippedItem {
                    id: *id,
                    reason: "already syncing".to_string(),
                }),
                Some(_) => syncable.push(*id),
                None => skipped.push(SkippedItem {
                    id: *id,
                    reason: "not found".to_string(),
                }),
            }
        }
        drop(channels);
        drop(syncing);

        let total = ids.len() as u32;
        if !confirm {
            let message = if syncable.is_empty() {
                "Nothing to sync".to_string()
            } else {
                format!("{} of {} channel(s) will be synced", syncable.len(), total)
            };
            Ok(BulkOperationResponse {
                mode: ResponseMode::Preview,
                total,
                syncable,
                skipped,
                operation_id: None,
                message,
            })
        } else {
            // Real Rails enqueues a ChannelSync job that completes within a
            // few hundred ms. The mock simulates near-instant completion: the
            // eligible channels stay (or become) not-in-flight and have their
            // last_synced_at bumped. The TUI's post-confirm polling will
            // observe the resulting "all idle" state on its first tick.
            {
                let mut chans = self.channels.borrow_mut();
                let now = "2026-05-01T00:00:00Z".to_string();
                for c in chans.iter_mut() {
                    if syncable.contains(&c.id) {
                        c.last_synced_at = Some(now.clone());
                        c.updated_at = now.clone();
                    }
                }
                // Clear any sync marker we may have set previously.
                self.syncing_ids
                    .borrow_mut()
                    .retain(|id| !syncable.contains(id));
            }
            let op_id = {
                let mut next = self.next_op_id.borrow_mut();
                let id = *next;
                *next += 1;
                id
            };
            self.record_operation(op_id, "bulk_sync", &syncable);
            Ok(BulkOperationResponse {
                mode: ResponseMode::Enqueued,
                total,
                syncable: syncable.clone(),
                skipped,
                operation_id: Some(op_id),
                message: format!("Enqueued sync for {} channel(s)", syncable.len()),
            })
        }
    }

    fn create_channel(&self, channel_url: &str) -> Result<Channel> {
        let mut next = self.next_id.borrow_mut();
        let id = *next;
        *next += 1;
        drop(next);
        let now = "2026-05-01T00:00:00Z".to_string();
        let channel = Channel {
            id,
            tenant_id: 1,
            channel_url: channel_url.to_string(),
            star: false,
            connected: false,
            last_synced_at: None,
            created_at: now.clone(),
            updated_at: now,
        };
        self.channels.borrow_mut().push(channel.clone());
        Ok(channel)
    }

    fn update_channel(&self, id: u64, star: Option<bool>) -> Result<Channel> {
        let mut chans = self.channels.borrow_mut();
        let chan = chans
            .iter_mut()
            .find(|c| c.id == id)
            .ok_or_else(|| anyhow::anyhow!("Channel not found: {}", id))?;
        if let Some(s) = star {
            chan.star = s;
        }
        chan.updated_at = "2026-05-01T00:00:00Z".to_string();
        Ok(chan.clone())
    }

    fn get_bulk_operation_status(&self, id: u64) -> Result<BulkOperationStatus> {
        // Step the simulated state machine. First poll lands on `pending`, the
        // next on `running` (with partial progress), and the third on
        // `completed`. The exact polling cadence in the TUI then determines how
        // long the user sees each state — typically a couple of frames each
        // before completion lands.
        let mut ops = self.operations.borrow_mut();
        let op = ops
            .get_mut(&id)
            .ok_or_else(|| anyhow::anyhow!("Bulk operation not found: {}", id))?;
        op.poll_count = op.poll_count.saturating_add(1);
        let total = op.target_ids.len() as u32;
        let (status, current, completed_at) = match op.poll_count {
            1 => ("pending".to_string(), 0u32, None),
            2 => (
                "running".to_string(),
                ((total as f32) * 0.5).ceil() as u32,
                None,
            ),
            _ => (
                "completed".to_string(),
                total,
                Some("2026-05-01T00:00:01Z".to_string()),
            ),
        };
        let items: Vec<BulkOperationItem> = op
            .target_ids
            .iter()
            .enumerate()
            .map(|(i, target_id)| {
                let item_status =
                    if status == "completed" || (status == "running" && (i as u32) < current) {
                        "succeeded"
                    } else {
                        "pending"
                    };
                BulkOperationItem {
                    id: (id * 1000) + i as u64,
                    target_id: *target_id,
                    target_type: "Channel".to_string(),
                    status: item_status.to_string(),
                    error_message: None,
                }
            })
            .collect();
        Ok(BulkOperationStatus {
            id,
            kind: op.kind.clone(),
            status,
            current,
            total,
            items,
            completed_at,
        })
    }

    fn execute_command(&self, _command: &str) -> Result<String> {
        Ok("ok".to_string())
    }

    fn authenticate(&self, _code: &str) -> Result<bool> {
        Ok(true) // mock always succeeds
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mock_client_seeds_channels_with_post_path_a2_shape() {
        let client = MockClient::new();
        let channels = client.get_channels().expect("channels");
        assert!(channels.len() >= 3);
        for c in channels.iter() {
            assert!(c.channel_url.starts_with("https://youtube.com/@"));
            assert_eq!(c.tenant_id, 1);
        }
        // At least one starred, one in-flight syncing, one without sync timestamp
        assert!(channels.iter().any(|c| c.star));
        assert!(
            client.is_syncing(2),
            "channel 2 should be the in-flight sync fixture"
        );
        assert!(channels.iter().any(|c| c.last_synced_at.is_none()));
    }

    #[test]
    fn bulk_delete_preview_is_idempotent() {
        let client = MockClient::new();
        let before = client.get_channels().unwrap().len();
        let resp = client
            .bulk_delete_channels(&[1, 2], false)
            .expect("preview");
        assert_eq!(resp.mode, ResponseMode::Preview);
        assert_eq!(resp.total, 2);
        assert!(resp.operation_id.is_none());
        assert_eq!(client.get_channels().unwrap().len(), before);
    }

    #[test]
    fn bulk_delete_confirm_removes_channels() {
        let client = MockClient::new();
        let resp = client.bulk_delete_channels(&[1], true).expect("confirm");
        assert_eq!(resp.mode, ResponseMode::Enqueued);
        assert!(resp.operation_id.is_some());
        assert!(client.get_channel(1).is_err());
    }

    #[test]
    fn bulk_delete_confirm_excludes_ids_from_get_channels() {
        // After a confirmed delete, subsequent get_channels() calls on the
        // same client must not include the deleted ids — this is what backs
        // the TUI refresh after a delete confirm.
        let client = MockClient::new();
        let before: Vec<u64> = client
            .get_channels()
            .unwrap()
            .iter()
            .map(|c| c.id)
            .collect();
        assert!(before.contains(&1));
        assert!(before.contains(&3));

        let _ = client.bulk_delete_channels(&[1, 3], true).expect("confirm");

        let after: Vec<u64> = client
            .get_channels()
            .unwrap()
            .iter()
            .map(|c| c.id)
            .collect();
        assert!(!after.contains(&1));
        assert!(!after.contains(&3));
        assert_eq!(after.len(), before.len() - 2);
    }

    #[test]
    fn bulk_sync_preview_skips_already_syncing() {
        let client = MockClient::new();
        // Channel 2 is seeded as in-flight (mock-only marker; Rails JSON no
        // longer carries `syncing`).
        let resp = client
            .bulk_sync_channels(&[1, 2, 3], false)
            .expect("preview");
        assert_eq!(resp.mode, ResponseMode::Preview);
        assert_eq!(resp.total, 3);
        assert!(resp.syncable.contains(&1));
        assert!(resp.syncable.contains(&3));
        assert!(resp.skipped.iter().any(|s| s.id == 2));
    }

    #[test]
    fn bulk_sync_confirm_completes_near_instantly() {
        // Mocks the production reality: ChannelSync is a near-instant job, so
        // the post-confirm channel state has a fresh last_synced_at and the
        // mock-only "in flight" marker is cleared.
        let client = MockClient::new();
        let resp = client.bulk_sync_channels(&[1], true).expect("confirm");
        assert_eq!(resp.mode, ResponseMode::Enqueued);
        let chan = client.get_channel(1).expect("get channel 1");
        assert!(chan.last_synced_at.is_some());
        assert!(!client.is_syncing(1));
    }

    #[test]
    fn bulk_sync_confirm_skips_already_syncing_channels() {
        // Channel 2 is seeded as in-flight — the preview marks it as skipped,
        // and confirm should not touch its in-flight marker.
        let client = MockClient::new();
        let _ = client.bulk_sync_channels(&[2], true).expect("confirm");
        assert!(
            client.is_syncing(2),
            "already-syncing channels stay syncing"
        );
    }

    #[test]
    fn update_channel_toggles_star() {
        let client = MockClient::new();
        let before = client.get_channel(2).unwrap().star;
        let updated = client.update_channel(2, Some(!before)).expect("update");
        assert_eq!(updated.star, !before);
    }

    #[test]
    fn mock_bulk_operation_status_progresses_to_completed() {
        let client = MockClient::new();
        let resp = client.bulk_delete_channels(&[1, 3], true).expect("confirm");
        let op_id = resp.operation_id.expect("operation_id");

        // First poll: pending, no progress yet.
        let s1 = client.get_bulk_operation_status(op_id).expect("status 1");
        assert_eq!(s1.status, "pending");
        assert_eq!(s1.current, 0);
        assert_eq!(s1.total, 2);

        // Second poll: running, partial progress.
        let s2 = client.get_bulk_operation_status(op_id).expect("status 2");
        assert_eq!(s2.status, "running");
        assert!(s2.current > 0 && s2.current <= s2.total);

        // Third poll onward: completed.
        let s3 = client.get_bulk_operation_status(op_id).expect("status 3");
        assert_eq!(s3.status, "completed");
        assert_eq!(s3.current, s3.total);
        assert!(s3.completed_at.is_some());
        assert!(s3.items.iter().all(|i| i.status == "succeeded"));
    }

    #[test]
    fn mock_bulk_operation_status_unknown_id_errors() {
        let client = MockClient::new();
        assert!(client.get_bulk_operation_status(9999).is_err());
    }

    #[test]
    fn search_filters_by_youtube_id_or_channel_url_substring() {
        let client = MockClient::new();
        // youtube id substring hit (one of the seed ids contains "ghi").
        let res = client.search("ghi").expect("search");
        assert!(res.video_total >= 1);
        // channel url substring hit ("rust-academy" appears in five videos).
        let res = client.search("rust-academy").expect("search");
        assert!(res.video_total >= 5);
    }
}
