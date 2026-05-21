# Phase 37 Wave A (traffic-sources slice) — Variant 2 (split / side-by-side).
#
# Same data inputs and same aggregation rules as Variant 1
# (`Channel::TrafficSourcesListComponent`) — only the layout differs:
#
#   * Left half — traffic-source breakdown (ranked list with bars).
#   * Right half — top YouTube search terms list.
#   * Two-column flex layout with equal-width children. Wraps to a
#     single column at narrow widths.
#
# Aggregation logic mirrors the list variant:
#
#   * Traffic sources — per-bucket weighted views reconstructed from
#     each channel's `view_count` × pct, summed, renormalized.
#   * Search terms — per-term views summed across channels, sorted
#     desc, top 10.
#
# Inert — no Stimulus, no actions. CSS-only.
class Channel::TrafficSourcesSplitComponent < ViewComponent::Base
  MAX_SEARCH_TERMS = 10

  # @param channels [Array<Hash>] channel hashes from
  #   `Channel::MockData.channels`. Each must carry `:view_count`,
  #   `:traffic_sources`, `:yt_search_terms`.
  def initialize(channels:)
    @channels = Array(channels)
  end

  attr_reader :channels

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

  def pct_label(pct)
    "#{pct}%"
  end

  def views_label(views)
    Pito::Formatter::CompactCount.call(views)
  end
end
