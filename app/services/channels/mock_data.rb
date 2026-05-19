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
# `:avatar_url` stays `nil` for every row so the placeholder square
# renders without a network round-trip. Wave B feeds real
# `snippet.thumbnails.medium.url` strings from the YouTube Data API.
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
          joined_at: Date.new(2018, 3, 14)
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
          joined_at: Date.new(2019, 7, 1)
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
          joined_at: Date.new(2020, 1, 22)
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
          joined_at: Date.new(2021, 5, 9)
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
          joined_at: Date.new(2022, 11, 3)
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
          joined_at: Date.new(2023, 8, 18)
        }
      ]
    end
  end
end
