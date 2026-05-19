# Phase 37 Wave A1 — `Channels::MockData`.
#
# Layout-first mock source for the `/channels` revamp. Each entry mirrors
# the shape the real `Channel` model exposes today so the Wave B swap to
# real data is a constant change at the view layer (no key renaming).
#
# This is iteration-phase scaffolding only. Wave B replaces this with the
# `Channels::Stats.*` real query layer per the handoff
# (`docs/orchestration/handoff-2026-05-19-channels-and-live-updates.md`
# §"Implementation plan" → Wave B step B12).
#
# 2026-05-19 (next A-slice) — bumped from 3 → 6 channels. Each entry now
# carries the data needed by the new `Channels::IdCardComponent`:
#   * `:handle` — `@xxxxx`, builds the external youtube.com link
#   * `:youtube_channel_id` — UC-prefixed id for the Studio URL helper
#   * `:subscriber_count` / `:view_count` / `:watch_hours` — diverse
#     values spread across the `Formatting::CompactCount` and
#     `Formatting::CompactHours` branches so every formatter tier renders
#     at least once on the page
#   * `:subscriber_count_trend` / `:view_count_trend` / `:watch_hours_trend`
#     — `:up` / `:steady` / `:down` symbols; mixed across the 6 so all
#     three trend glyphs render at least once
#   * `:joined_at` — placeholder date, dormant this slice
#
# 2026-05-19 (traffic-sources A-slice) — each channel entry also carries:
#   * `:traffic_sources` — `Hash<String, Integer>` keyed by the 7
#     canonical YouTube traffic-source buckets ("Suggested videos",
#     "Browse features", "YouTube search", "External", "Channel pages",
#     "Other YT features", "Direct/unknown"); values are integer
#     percentages of `view_count` and sum to 100 per channel.
#   * `:yt_search_terms` — `Array<{ term: String, views: Integer }>` —
#     top 10 incoming YouTube search queries per channel, sorted desc
#     by views. Used by the Traffic Sources section's variant A "Top
#     YouTube search terms" sub-block and variant B's right-hand
#     column.
#
# `:avatar_url` stays `nil` for every row so the placeholder square
# renders without a network round-trip. Wave B feeds real
# `snippet.thumbnails.medium.url` strings from the YouTube Data API.
#
# 2026-05-19 (heatmap A-slice) — each channel entry also carries a
# `:viewer_time_heatmap` field: `Hash<String, Array<Integer>>` keyed
# by short day-of-week names (`"Mon"`..`"Sun"`), each pointing at a
# 24-element array of relative-activity integers (`0..15`) for the
# 24 hours-of-day. Patterns are spread diversely per channel so the
# heatmap variants ("When your viewers are on YouTube" — color
# grid + per-day sparklines) read as distinct shapes. Aggregating
# across the selected channels is a per-cell sum performed at the
# view layer.
#
# 2026-05-19 (window-summaries A-slice) — every entry also carries a
# `:window_summaries` hash keyed by the five window labels (`"7d"`,
# `"28d"`, `"3m"`, `"365d"`, `"alltime"`). Each window value is a
# `{ subs_delta:, views_delta:, watch_hours_delta: }` triple spread
# across the `Formatting::CompactCount` / `Formatting::CompactHours`
# tier ranges so every formatter branch renders at least once when
# the `Channels::WindowSummaries*` components iterate. The `"alltime"`
# window stores `nil` for each delta — the consumer is expected to
# fall back to the absolute totals (`subscriber_count` / `view_count`
# / `watch_hours`) for that case. Wave B replaces the mock hash with
# real `channel_window_summaries` rows.
module Channels
  module MockData
    module_function

    def channels
      [
        {
          id: 1,
          display_name: "Studio Aurora",
          handle: "@studioaurora",
          youtube_channel_id: "UCaurora0000000000000001",
          avatar_url: nil,
          subscriber_count: 3,
          view_count: 47,
          watch_hours: 12,
          video_count: 7,
          subscriber_count_trend: :up,
          view_count_trend: :steady,
          watch_hours_trend: :down,
          joined_at: Date.new(2018, 3, 14),
          geography: [
            { country_code: "US", country_name: "United States", views: 18 },
            { country_code: "GB", country_name: "United Kingdom", views: 9 },
            { country_code: "DE", country_name: "Germany", views: 6 },
            { country_code: "CA", country_name: "Canada", views: 4 },
            { country_code: "FR", country_name: "France", views: 3 },
            { country_code: "AU", country_name: "Australia", views: 2 },
            { country_code: "JP", country_name: "Japan", views: 2 },
            { country_code: "BR", country_name: "Brazil", views: 1 },
            { country_code: "IN", country_name: "India", views: 1 },
            { country_code: "ES", country_name: "Spain", views: 1 }
          ],
          # Device-type viewership breakdown (percent of view_count).
          # Sums to 100. Spread diversely across the 6 channels so the
          # aggregate-mean rendering shows real variation.
          device_types: {
            "Mobile" => 72,
            "Computer" => 14,
            "TV" => 6,
            "Tablet" => 5,
            "Game console" => 3
          },
          window_summaries: {
            "7d"      => { subs_delta: 2, views_delta: 9, watch_hours_delta: 1 },
            "28d"     => { subs_delta: 8, views_delta: 47, watch_hours_delta: 4 },
            "3m"      => { subs_delta: 21, views_delta: 230, watch_hours_delta: 9 },
            "365d"    => { subs_delta: 89, views_delta: 1_100, watch_hours_delta: 32 },
            "alltime" => { subs_delta: nil, views_delta: nil, watch_hours_delta: nil }
          },
          # Traffic sources — percent of view_count by surface that
          # delivered the view. Sums to 100. 7 canonical YouTube
          # traffic-source buckets. Spread per-channel for diverse
          # aggregate readings.
          traffic_sources: {
            "Suggested videos" => 41,
            "Browse features" => 22,
            "YouTube search" => 18,
            "External" => 4,
            "Channel pages" => 8,
            "Other YT features" => 5,
            "Direct/unknown" => 2
          },
          # Viewer-time heatmap — evening-peak weekday pattern with
          # broader weekend spread (Mon..Sun × 24h, values 0..15).
          viewer_time_heatmap: {
            "Mon" => [ 1, 1, 0, 0, 0, 1, 2, 3, 4, 3, 3, 3, 4, 4, 5, 6, 8, 11, 13, 14, 12, 8, 5, 2 ],
            "Tue" => [ 1, 0, 0, 0, 0, 1, 2, 3, 4, 4, 3, 3, 3, 4, 5, 7, 9, 12, 14, 14, 11, 8, 4, 2 ],
            "Wed" => [ 1, 0, 0, 0, 0, 1, 2, 3, 4, 3, 3, 3, 4, 4, 5, 7, 9, 12, 13, 15, 12, 9, 5, 2 ],
            "Thu" => [ 1, 1, 0, 0, 0, 1, 2, 3, 4, 4, 3, 4, 4, 5, 6, 7, 10, 12, 14, 14, 13, 9, 5, 3 ],
            "Fri" => [ 2, 1, 0, 0, 0, 1, 2, 3, 4, 4, 3, 4, 5, 5, 6, 8, 10, 12, 13, 13, 12, 10, 7, 4 ],
            "Sat" => [ 3, 2, 1, 0, 0, 1, 1, 2, 3, 5, 6, 7, 8, 8, 9, 10, 10, 11, 12, 12, 11, 9, 6, 4 ],
            "Sun" => [ 3, 2, 1, 0, 0, 1, 1, 2, 3, 5, 7, 8, 9, 9, 9, 9, 10, 11, 12, 12, 11, 8, 5, 3 ]
          },
          yt_search_terms: [
            { term: "aurora aesthetic", views: 1_240 },
            { term: "lofi study mix", views: 980 },
            { term: "ambient cinematic", views: 760 },
            { term: "studio aurora intro", views: 540 },
            { term: "warm color grading", views: 410 },
            { term: "cozy timelapse", views: 320 },
            { term: "dawn light footage", views: 260 },
            { term: "soft synth pad", views: 210 },
            { term: "minimal editing tutorial", views: 170 },
            { term: "lookbook 2025", views: 120 }
          ]
        },
        {
          id: 2,
          display_name: "Pixel Forge",
          handle: "@pixelforge",
          youtube_channel_id: "UCpixelforge00000000002",
          avatar_url: nil,
          subscriber_count: 1_000,
          view_count: 589,
          watch_hours: 47,
          video_count: 48,
          subscriber_count_trend: :steady,
          view_count_trend: :up,
          watch_hours_trend: :up,
          joined_at: Date.new(2019, 7, 1),
          geography: [
            { country_code: "JP", country_name: "Japan", views: 180 },
            { country_code: "US", country_name: "United States", views: 120 },
            { country_code: "BR", country_name: "Brazil", views: 80 },
            { country_code: "DE", country_name: "Germany", views: 55 },
            { country_code: "MX", country_name: "Mexico", views: 45 },
            { country_code: "FR", country_name: "France", views: 35 },
            { country_code: "GB", country_name: "United Kingdom", views: 30 },
            { country_code: "IT", country_name: "Italy", views: 22 },
            { country_code: "ES", country_name: "Spain", views: 12 },
            { country_code: "IN", country_name: "India", views: 10 }
          ],
          device_types: {
            "Mobile" => 38,
            "Computer" => 41,
            "TV" => 9,
            "Tablet" => 8,
            "Game console" => 4
          },
          window_summaries: {
            "7d"      => { subs_delta: 47, views_delta: 230, watch_hours_delta: 12 },
            "28d"     => { subs_delta: 180, views_delta: 1_200, watch_hours_delta: 47 },
            "3m"      => { subs_delta: 520, views_delta: 4_500, watch_hours_delta: 180 },
            "365d"    => { subs_delta: 1_500, views_delta: 18_000, watch_hours_delta: 720 },
            "alltime" => { subs_delta: nil, views_delta: nil, watch_hours_delta: nil }
          },
          traffic_sources: {
            "Suggested videos" => 28,
            "Browse features" => 14,
            "YouTube search" => 38,
            "External" => 9,
            "Channel pages" => 5,
            "Other YT features" => 4,
            "Direct/unknown" => 2
          },
          # Viewer-time heatmap — late-night gaming pattern (peaks
          # 21:00..02:00), strong Fri/Sat/Sun, lower mornings.
          viewer_time_heatmap: {
            "Mon" => [ 9, 7, 4, 2, 1, 0, 0, 1, 2, 3, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 13, 11 ],
            "Tue" => [ 8, 6, 3, 1, 1, 0, 0, 1, 2, 3, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 13, 14, 13, 11 ],
            "Wed" => [ 9, 7, 4, 2, 1, 0, 0, 1, 2, 2, 3, 4, 5, 5, 7, 8, 9, 11, 12, 13, 14, 14, 13, 11 ],
            "Thu" => [ 10, 8, 5, 3, 1, 0, 0, 1, 2, 3, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 14, 14, 12 ],
            "Fri" => [ 11, 9, 6, 3, 2, 1, 0, 1, 2, 3, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 15, 14 ],
            "Sat" => [ 13, 11, 8, 5, 3, 1, 1, 1, 2, 3, 4, 4, 5, 6, 7, 8, 10, 12, 13, 14, 15, 15, 15, 14 ],
            "Sun" => [ 12, 10, 7, 4, 2, 1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 14, 13, 11 ]
          },
          yt_search_terms: [
            { term: "pixel art tutorial", views: 14_200 },
            { term: "godot 4 platformer", views: 11_800 },
            { term: "aseprite shading", views: 9_400 },
            { term: "8 bit game music", views: 7_600 },
            { term: "retro shader unity", views: 5_900 },
            { term: "indie dev devlog", views: 4_700 },
            { term: "pixel forge tutorial", views: 3_500 },
            { term: "metroidvania tilemap", views: 2_800 },
            { term: "dialogue system gdscript", views: 2_200 },
            { term: "lospec palettes", views: 1_700 }
          ]
        },
        {
          id: 3,
          display_name: "Long-form Lab",
          handle: "@longformlab",
          youtube_channel_id: "UClongformlab00000000003",
          avatar_url: nil,
          subscriber_count: 2_300,
          view_count: 12_000,
          watch_hours: 589,
          video_count: 230,
          subscriber_count_trend: :down,
          view_count_trend: :down,
          watch_hours_trend: :steady,
          joined_at: Date.new(2020, 1, 22),
          geography: [
            { country_code: "IN", country_name: "India", views: 3_800 },
            { country_code: "US", country_name: "United States", views: 2_900 },
            { country_code: "GB", country_name: "United Kingdom", views: 1_400 },
            { country_code: "CA", country_name: "Canada", views: 900 },
            { country_code: "AU", country_name: "Australia", views: 700 },
            { country_code: "DE", country_name: "Germany", views: 600 },
            { country_code: "FR", country_name: "France", views: 450 },
            { country_code: "BR", country_name: "Brazil", views: 380 },
            { country_code: "JP", country_name: "Japan", views: 290 },
            { country_code: "IT", country_name: "Italy", views: 160 },
            { country_code: "ES", country_name: "Spain", views: 120 },
            { country_code: "MX", country_name: "Mexico", views: 100 }
          ],
          device_types: {
            "Mobile" => 32,
            "Computer" => 28,
            "TV" => 28,
            "Tablet" => 9,
            "Game console" => 3
          },
          window_summaries: {
            "7d"      => { subs_delta: 120, views_delta: 4_500, watch_hours_delta: 47 },
            "28d"     => { subs_delta: 450, views_delta: 22_000, watch_hours_delta: 180 },
            "3m"      => { subs_delta: 1_200, views_delta: 95_000, watch_hours_delta: 620 },
            "365d"    => { subs_delta: 4_700, views_delta: 380_000, watch_hours_delta: 2_300 },
            "alltime" => { subs_delta: nil, views_delta: nil, watch_hours_delta: nil }
          },
          traffic_sources: {
            "Suggested videos" => 52,
            "Browse features" => 12,
            "YouTube search" => 11,
            "External" => 14,
            "Channel pages" => 4,
            "Other YT features" => 4,
            "Direct/unknown" => 3
          },
          # Viewer-time heatmap — daytime + late-afternoon focus,
          # weekend reading hours pronounced.
          viewer_time_heatmap: {
            "Mon" => [ 0, 0, 0, 0, 1, 2, 4, 6, 8, 10, 11, 12, 12, 13, 14, 13, 12, 10, 8, 7, 6, 4, 2, 1 ],
            "Tue" => [ 0, 0, 0, 0, 1, 2, 4, 6, 8, 10, 12, 13, 13, 14, 14, 14, 13, 11, 9, 7, 6, 4, 2, 1 ],
            "Wed" => [ 0, 0, 0, 0, 1, 3, 5, 7, 9, 11, 12, 13, 14, 14, 15, 14, 13, 11, 9, 7, 5, 3, 2, 1 ],
            "Thu" => [ 0, 0, 0, 0, 1, 2, 5, 7, 9, 11, 12, 13, 13, 14, 14, 14, 12, 10, 8, 7, 5, 3, 2, 1 ],
            "Fri" => [ 0, 0, 0, 0, 1, 2, 4, 6, 8, 10, 11, 12, 12, 13, 13, 12, 11, 10, 9, 8, 7, 5, 3, 1 ],
            "Sat" => [ 1, 0, 0, 0, 0, 1, 2, 4, 6, 9, 12, 14, 15, 15, 14, 13, 12, 11, 10, 9, 8, 6, 4, 2 ],
            "Sun" => [ 1, 0, 0, 0, 0, 1, 2, 4, 7, 10, 13, 14, 15, 15, 14, 13, 12, 11, 10, 9, 7, 5, 3, 2 ]
          },
          yt_search_terms: [
            { term: "react hooks deep dive", views: 28_400 },
            { term: "typescript generics tutorial", views: 22_100 },
            { term: "system design interview", views: 18_700 },
            { term: "long form software essay", views: 14_900 },
            { term: "rust async explained", views: 12_300 },
            { term: "monorepo strategy 2025", views: 9_800 },
            { term: "postgres performance tuning", views: 8_100 },
            { term: "k8s for skeptics", views: 6_400 },
            { term: "tdd vs bdd", views: 4_900 },
            { term: "long form lab podcast", views: 3_700 }
          ]
        },
        {
          id: 4,
          display_name: "Quiet Cinema",
          handle: "@quietcinema",
          youtube_channel_id: "UCquietcinema0000000004",
          avatar_url: nil,
          subscriber_count: 10_000,
          view_count: 234_000,
          watch_hours: 1_200,
          video_count: 1_100,
          subscriber_count_trend: :up,
          view_count_trend: :up,
          watch_hours_trend: :up,
          joined_at: Date.new(2021, 5, 9),
          geography: [
            { country_code: "FR", country_name: "France", views: 62_000 },
            { country_code: "US", country_name: "United States", views: 48_000 },
            { country_code: "IT", country_name: "Italy", views: 32_000 },
            { country_code: "ES", country_name: "Spain", views: 24_000 },
            { country_code: "DE", country_name: "Germany", views: 20_000 },
            { country_code: "GB", country_name: "United Kingdom", views: 14_000 },
            { country_code: "JP", country_name: "Japan", views: 12_000 },
            { country_code: "BR", country_name: "Brazil", views: 9_000 },
            { country_code: "CA", country_name: "Canada", views: 6_500 },
            { country_code: "MX", country_name: "Mexico", views: 4_000 },
            { country_code: "AU", country_name: "Australia", views: 2_500 }
          ],
          device_types: {
            "Mobile" => 22,
            "Computer" => 18,
            "TV" => 49,
            "Tablet" => 7,
            "Game console" => 4
          },
          window_summaries: {
            "7d"      => { subs_delta: 320, views_delta: 12_000, watch_hours_delta: 120 },
            "28d"     => { subs_delta: 1_200, views_delta: 47_000, watch_hours_delta: 450 },
            "3m"      => { subs_delta: 3_800, views_delta: 180_000, watch_hours_delta: 1_400 },
            "365d"    => { subs_delta: 12_000, views_delta: 720_000, watch_hours_delta: 5_900 },
            "alltime" => { subs_delta: nil, views_delta: nil, watch_hours_delta: nil }
          },
          traffic_sources: {
            "Suggested videos" => 24,
            "Browse features" => 31,
            "YouTube search" => 12,
            "External" => 18,
            "Channel pages" => 7,
            "Other YT features" => 5,
            "Direct/unknown" => 3
          },
          # Viewer-time heatmap — quiet late-evening cinematic
          # viewing, every day peaks 21:00..23:00.
          viewer_time_heatmap: {
            "Mon" => [ 3, 2, 1, 0, 0, 0, 1, 2, 2, 3, 3, 3, 3, 4, 4, 5, 6, 7, 9, 11, 14, 15, 14, 8 ],
            "Tue" => [ 3, 2, 1, 0, 0, 0, 1, 2, 2, 3, 3, 3, 3, 4, 4, 5, 6, 7, 9, 12, 14, 15, 13, 7 ],
            "Wed" => [ 3, 2, 1, 0, 0, 0, 1, 2, 2, 3, 3, 3, 3, 4, 4, 5, 6, 8, 10, 12, 14, 15, 14, 8 ],
            "Thu" => [ 4, 2, 1, 0, 0, 0, 1, 2, 2, 3, 3, 3, 4, 4, 5, 5, 7, 8, 10, 12, 14, 15, 14, 9 ],
            "Fri" => [ 5, 3, 1, 0, 0, 0, 1, 2, 2, 3, 3, 4, 4, 4, 5, 6, 7, 9, 11, 13, 14, 15, 15, 11 ],
            "Sat" => [ 7, 4, 2, 1, 0, 0, 1, 1, 2, 3, 4, 5, 5, 6, 6, 7, 8, 9, 11, 13, 14, 15, 15, 13 ],
            "Sun" => [ 6, 4, 2, 1, 0, 0, 1, 1, 2, 3, 4, 5, 6, 6, 7, 7, 8, 9, 11, 12, 14, 15, 14, 10 ]
          },
          yt_search_terms: [
            { term: "short film 2025", views: 142_000 },
            { term: "slow cinema feel", views: 98_000 },
            { term: "anamorphic 4k test", views: 74_000 },
            { term: "quiet cinema short", views: 61_000 },
            { term: "film grain plugin", views: 47_000 },
            { term: "no dialogue narrative", views: 33_000 },
            { term: "moody lighting setup", views: 26_000 },
            { term: "davinci resolve grade", views: 21_000 },
            { term: "filmic look lut", views: 16_000 },
            { term: "16mm aesthetic", views: 12_000 }
          ]
        },
        {
          id: 5,
          display_name: "Field Notes",
          handle: "@fieldnotes",
          youtube_channel_id: "UCfieldnotes00000000005",
          avatar_url: nil,
          subscriber_count: 100_000,
          view_count: 1_100_000,
          watch_hours: 12_500,
          video_count: 5_400,
          subscriber_count_trend: :steady,
          view_count_trend: :steady,
          watch_hours_trend: :down,
          joined_at: Date.new(2022, 11, 3),
          geography: [
            { country_code: "US", country_name: "United States", views: 320_000 },
            { country_code: "GB", country_name: "United Kingdom", views: 180_000 },
            { country_code: "CA", country_name: "Canada", views: 140_000 },
            { country_code: "AU", country_name: "Australia", views: 110_000 },
            { country_code: "DE", country_name: "Germany", views: 95_000 },
            { country_code: "IN", country_name: "India", views: 80_000 },
            { country_code: "FR", country_name: "France", views: 55_000 },
            { country_code: "JP", country_name: "Japan", views: 48_000 },
            { country_code: "BR", country_name: "Brazil", views: 36_000 },
            { country_code: "IT", country_name: "Italy", views: 20_000 },
            { country_code: "MX", country_name: "Mexico", views: 16_000 }
          ],
          device_types: {
            "Mobile" => 58,
            "Computer" => 22,
            "TV" => 12,
            "Tablet" => 6,
            "Game console" => 2
          },
          window_summaries: {
            "7d"      => { subs_delta: 1_200, views_delta: 95_000, watch_hours_delta: 720 },
            "28d"     => { subs_delta: 4_500, views_delta: 380_000, watch_hours_delta: 2_900 },
            "3m"      => { subs_delta: 14_000, views_delta: 1_400_000, watch_hours_delta: 9_500 },
            "365d"    => { subs_delta: 47_000, views_delta: 4_800_000, watch_hours_delta: 32_000 },
            "alltime" => { subs_delta: nil, views_delta: nil, watch_hours_delta: nil }
          },
          traffic_sources: {
            "Suggested videos" => 36,
            "Browse features" => 19,
            "YouTube search" => 22,
            "External" => 11,
            "Channel pages" => 6,
            "Other YT features" => 4,
            "Direct/unknown" => 2
          },
          # Viewer-time heatmap — broad daytime + strong weekend
          # morning (outdoors / hike-prep audience).
          viewer_time_heatmap: {
            "Mon" => [ 1, 0, 0, 0, 0, 2, 5, 8, 9, 10, 10, 11, 11, 10, 9, 9, 9, 9, 10, 9, 7, 5, 3, 2 ],
            "Tue" => [ 1, 0, 0, 0, 0, 2, 5, 8, 9, 10, 11, 11, 11, 10, 9, 9, 9, 9, 10, 9, 7, 5, 3, 2 ],
            "Wed" => [ 1, 0, 0, 0, 0, 2, 5, 8, 10, 11, 11, 12, 12, 11, 10, 9, 9, 9, 10, 9, 7, 5, 3, 2 ],
            "Thu" => [ 1, 0, 0, 0, 0, 2, 5, 8, 10, 11, 12, 12, 12, 11, 10, 10, 9, 9, 10, 9, 8, 5, 3, 2 ],
            "Fri" => [ 2, 0, 0, 0, 0, 2, 5, 8, 10, 11, 11, 11, 11, 10, 9, 9, 9, 10, 11, 11, 9, 7, 5, 3 ],
            "Sat" => [ 2, 1, 0, 0, 1, 3, 8, 12, 14, 15, 15, 14, 13, 12, 11, 10, 10, 10, 11, 11, 10, 8, 6, 3 ],
            "Sun" => [ 2, 1, 0, 0, 1, 3, 8, 13, 15, 15, 15, 14, 13, 12, 11, 10, 10, 10, 11, 10, 9, 7, 5, 3 ]
          },
          yt_search_terms: [
            { term: "hiking trail vlog", views: 86_000 },
            { term: "wild camping gear", views: 71_000 },
            { term: "pacific crest trail", views: 58_000 },
            { term: "field notes channel", views: 44_000 },
            { term: "ultralight backpacking", views: 36_000 },
            { term: "solo bushcraft", views: 29_000 },
            { term: "iceland ring road", views: 23_000 },
            { term: "trail food prep", views: 18_000 },
            { term: "fjallraven kanken review", views: 13_000 },
            { term: "rain shelter pitch", views: 9_500 }
          ]
        },
        {
          id: 6,
          display_name: "Neon Atlas",
          handle: "@neonatlas",
          youtube_channel_id: "UCneonatlas000000000006",
          avatar_url: nil,
          subscriber_count: 1_200_000,
          view_count: 47_000_000,
          watch_hours: 356_323,
          video_count: 12_000,
          subscriber_count_trend: :down,
          view_count_trend: :down,
          watch_hours_trend: :steady,
          joined_at: Date.new(2023, 8, 18),
          geography: [
            { country_code: "BR", country_name: "Brazil", views: 9_400_000 },
            { country_code: "MX", country_name: "Mexico", views: 7_800_000 },
            { country_code: "US", country_name: "United States", views: 6_500_000 },
            { country_code: "ES", country_name: "Spain", views: 5_200_000 },
            { country_code: "IN", country_name: "India", views: 4_100_000 },
            { country_code: "JP", country_name: "Japan", views: 3_300_000 },
            { country_code: "DE", country_name: "Germany", views: 2_700_000 },
            { country_code: "GB", country_name: "United Kingdom", views: 2_400_000 },
            { country_code: "FR", country_name: "France", views: 1_900_000 },
            { country_code: "IT", country_name: "Italy", views: 1_500_000 },
            { country_code: "AU", country_name: "Australia", views: 1_100_000 },
            { country_code: "CA", country_name: "Canada", views: 1_100_000 }
          ],
          device_types: {
            "Mobile" => 44,
            "Computer" => 19,
            "TV" => 14,
            "Tablet" => 5,
            "Game console" => 18
          },
          window_summaries: {
            "7d"      => { subs_delta: 4_700, views_delta: 850_000, watch_hours_delta: 4_500 },
            "28d"     => { subs_delta: 18_000, views_delta: 3_500_000, watch_hours_delta: 18_000 },
            "3m"      => { subs_delta: 58_000, views_delta: 12_000_000, watch_hours_delta: 62_000 },
            "365d"    => { subs_delta: 230_000, views_delta: 47_000_000, watch_hours_delta: 240_000 },
            "alltime" => { subs_delta: nil, views_delta: nil, watch_hours_delta: nil }
          },
          traffic_sources: {
            "Suggested videos" => 47,
            "Browse features" => 21,
            "YouTube search" => 9,
            "External" => 13,
            "Channel pages" => 4,
            "Other YT features" => 4,
            "Direct/unknown" => 2
          },
          yt_search_terms: [
            { term: "neon atlas city walk", views: 1_240_000 },
            { term: "tokyo night 4k", views: 980_000 },
            { term: "asmr ambient city", views: 760_000 },
            { term: "shanghai bund tour", views: 540_000 },
            { term: "seoul gangnam walk", views: 410_000 },
            { term: "hong kong neon", views: 320_000 },
            { term: "bangkok night market", views: 260_000 },
            { term: "binaural city stroll", views: 210_000 },
            { term: "no music walking tour", views: 170_000 },
            { term: "cyberpunk irl", views: 120_000 }
          ],
          # Viewer-time heatmap — global late-night audience, broad
          # spread across all hours with overnight peaks.
          viewer_time_heatmap: {
            "Mon" => [ 10, 9, 9, 8, 7, 7, 7, 8, 8, 9, 9, 9, 9, 10, 10, 10, 10, 11, 11, 11, 12, 13, 13, 12 ],
            "Tue" => [ 10, 9, 9, 8, 7, 7, 7, 8, 8, 9, 9, 9, 9, 10, 10, 10, 11, 11, 11, 12, 12, 13, 13, 12 ],
            "Wed" => [ 10, 10, 9, 8, 7, 7, 7, 8, 9, 9, 9, 10, 10, 10, 10, 10, 11, 11, 12, 12, 13, 13, 13, 12 ],
            "Thu" => [ 11, 10, 9, 8, 7, 7, 7, 8, 9, 9, 10, 10, 10, 10, 10, 11, 11, 11, 12, 12, 13, 13, 13, 12 ],
            "Fri" => [ 12, 11, 10, 9, 8, 7, 7, 8, 9, 9, 10, 10, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 14, 13 ],
            "Sat" => [ 13, 12, 11, 10, 9, 8, 7, 8, 9, 10, 10, 10, 11, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 14 ],
            "Sun" => [ 13, 12, 11, 10, 9, 8, 7, 8, 9, 9, 10, 10, 11, 11, 11, 11, 12, 12, 13, 13, 14, 14, 14, 13 ]
          }
        }
      ]
    end

    # Phase 37 Top Content slice — per-channel mock top videos.
    #
    # Returns a flat array of video hashes spanning all 6 channels. View
    # counts are spread across the `Formatting::CompactCount` tiers
    # (1K, 10K, 100K, 1M, 10M, 100M) so every formatter branch renders at
    # least once when merged + ranked. 5 videos per channel x 6 channels
    # = 30 entries total.
    #
    # Schema (matches the future `Video` model fields the Top Content
    # section reads):
    #   :id                — primary key placeholder
    #   :title             — display title
    #   :views             — Integer view count (raw)
    #   :channel_id        — FK back into `Channels::MockData.channels`
    #   :thumbnail_url     — nil this slice (placeholder square renders)
    def top_content
      [
        # Studio Aurora (id: 1) — small channel, modest counts
        { id: 101, title: "First steps with the studio rig",            views: 1_200,      channel_id: 1, thumbnail_url: nil },
        { id: 102, title: "How we colorize raw footage",                views: 3_400,      channel_id: 1, thumbnail_url: nil },
        { id: 103, title: "Aurora behind the scenes — episode 1",       views: 850,        channel_id: 1, thumbnail_url: nil },
        { id: 104, title: "Lighting setup for narrow rooms",            views: 12_000,     channel_id: 1, thumbnail_url: nil },
        { id: 105, title: "Studio Aurora year-in-review 2024",          views: 4_700,      channel_id: 1, thumbnail_url: nil },

        # Pixel Forge (id: 2) — gaming, mid-range counts
        { id: 201, title: "Why pixel art is making a comeback",         views: 47_000,     channel_id: 2, thumbnail_url: nil },
        { id: 202, title: "Forging a sword in Blender — full tutorial", views: 230_000,    channel_id: 2, thumbnail_url: nil },
        { id: 203, title: "10 indie games you missed last month",       views: 89_000,     channel_id: 2, thumbnail_url: nil },
        { id: 204, title: "Pixel Forge studio tour 2026",               views: 15_000,     channel_id: 2, thumbnail_url: nil },
        { id: 205, title: "Animating sprites the old-school way",       views: 67_500,     channel_id: 2, thumbnail_url: nil },

        # Long-form Lab (id: 3) — essay-style, broader reach
        { id: 301, title: "A long history of operating systems",        views: 589_000,    channel_id: 3, thumbnail_url: nil },
        { id: 302, title: "Why we still use the QWERTY keyboard",       views: 1_100_000,  channel_id: 3, thumbnail_url: nil },
        { id: 303, title: "The architecture of public libraries",       views: 340_000,    channel_id: 3, thumbnail_url: nil },
        { id: 304, title: "What is a city, really?",                    views: 780_000,    channel_id: 3, thumbnail_url: nil },
        { id: 305, title: "The death and life of the shopping mall",    views: 2_300_000,  channel_id: 3, thumbnail_url: nil },

        # Quiet Cinema (id: 4) — cinema essays, strong long-tail
        { id: 401, title: "Tarkovsky's use of mirrors",                 views: 425_000,    channel_id: 4, thumbnail_url: nil },
        { id: 402, title: "Why every Wong Kar-wai film feels the same", views: 1_800_000,  channel_id: 4, thumbnail_url: nil },
        { id: 403, title: "The slow cinema starter pack",               views: 612_000,    channel_id: 4, thumbnail_url: nil },
        { id: 404, title: "Editing rhythm in Ozu's late period",        views: 156_000,    channel_id: 4, thumbnail_url: nil },
        { id: 405, title: "How a single shot can carry a whole film",   views: 3_400_000,  channel_id: 4, thumbnail_url: nil },

        # Field Notes (id: 5) — documentary, viral spikes
        { id: 501, title: "A day in a flour mill",                      views: 1_100_000,  channel_id: 5, thumbnail_url: nil },
        { id: 502, title: "Inside the world's quietest room",           views: 12_500_000, channel_id: 5, thumbnail_url: nil },
        { id: 503, title: "How a glass factory actually works",         views: 4_700_000,  channel_id: 5, thumbnail_url: nil },
        { id: 504, title: "Following the postal route in rural Japan",  views: 890_000,    channel_id: 5, thumbnail_url: nil },
        { id: 505, title: "What 3 a.m. in Tokyo really looks like",     views: 8_900_000,  channel_id: 5, thumbnail_url: nil },

        # Neon Atlas (id: 6) — flagship channel, very high counts
        { id: 601, title: "The neon signs of 1980s Hong Kong",          views: 23_000_000, channel_id: 6, thumbnail_url: nil },
        { id: 602, title: "Walking every Tokyo subway line in one day", views: 47_000_000, channel_id: 6, thumbnail_url: nil },
        { id: 603, title: "Why cities glow differently at night",       views: 9_800_000,  channel_id: 6, thumbnail_url: nil },
        { id: 604, title: "The hidden geometry of overpasses",          views: 6_300_000,  channel_id: 6, thumbnail_url: nil },
        { id: 605, title: "A field guide to street-corner architecture", views: 15_000_000, channel_id: 6, thumbnail_url: nil }
      ]
    end

    # Convenience — given the full set of channels, return a `{id => name}`
    # map so view components can render a channel badge from a `channel_id`
    # without a second `find` call per row.
    def channel_name_by_id
      channels.each_with_object({}) { |c, h| h[c[:id]] = c[:display_name] }
    end
  end
end
