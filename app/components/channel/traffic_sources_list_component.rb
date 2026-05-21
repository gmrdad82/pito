# Phase 37 Wave A (traffic-sources slice) — Variant 1 (ranked-list).
#
# Renders the Traffic Sources section as a compact, data-dense vertical
# list. Each row is `source name + horizontal-bar + percentage`, ranked
# by descending percentage. Below the list a small sub-section renders
# the top YouTube search terms ranked by views.
#
# Aggregation across the selected channels:
#
#   * Traffic sources — per-bucket VIEWS contributed by each channel are
#     reconstructed from the channel's `view_count` × percent / 100,
#     summed across the channel set, then renormalized to percent of the
#     aggregate. This keeps the aggregate weighted by channel size
#     (a 1M-view channel's 50% Suggested moves the aggregate more than
#     a 1K-view channel's 50% Suggested) — which is what YouTube
#     Analytics shows when you flip the "by channel" / "all channels"
#     toggle.
#
#   * Search terms — per-term VIEWS summed across channels (terms that
#     don't appear in a channel contribute 0), then sorted desc, top 10.
#
# All inputs are the mock-data shape from `Channel::MockData`. Real
# data swap in Wave B will be a constant change at the call site.
#
# Inert — no Stimulus, no actions. CSS-only.
class Channel::TrafficSourcesListComponent < ViewComponent::Base
  MAX_SEARCH_TERMS = 10

  # @param channels [Array<Hash>] channel hashes from
  #   `Channel::MockData.channels`. Each must carry `:view_count`,
  #   `:traffic_sources`, `:yt_search_terms`. Channels missing the
  #   field are skipped from the aggregate (treated as nil).
  def initialize(channels:)
    @channels = Array(channels)
  end

  attr_reader :channels

  # Returns `[[label, pct_int, views_int], ...]` sorted desc by pct.
  # `pct_int` sums to ~100 (rounding error at most ±1; we don't
  # renormalize twice — the top row visually carries any remainder).
  def aggregated_sources
    bucket_views = Hash.new(0)
    channels.each do |c|
      vc = c[:view_count].to_i
      next if vc.zero?
      ts = c[:traffic_sources] || {}
      ts.each do |label, pct|
        bucket_views[label] += (vc * pct.to_i) / 100.0
      end
    end

    total = bucket_views.values.sum
    return [] if total.zero?

    bucket_views
      .map { |label, views| [ label, ((views / total) * 100).round, views.to_i ] }
      .sort_by { |_, pct, _| -pct }
  end

  # Returns top N `[[term, views], ...]` sorted desc by views.
  def aggregated_search_terms
    bucket = Hash.new(0)
    channels.each do |c|
      Array(c[:yt_search_terms]).each do |row|
        bucket[row[:term].to_s] += row[:views].to_i
      end
    end
    bucket
      .sort_by { |_, views| -views }
      .first(MAX_SEARCH_TERMS)
  end

  # Format a percent integer for display: "41%".
  def pct_label(pct)
    "#{pct}%"
  end

  # Format an integer view count using the existing compact-count
  # formatter (K / M / B suffixes).
  def views_label(views)
    Pito::Formatter::CompactCount.call(views)
  end
end
