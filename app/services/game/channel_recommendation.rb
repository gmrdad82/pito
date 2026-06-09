# frozen_string_literal: true

# Channels best suited to a game — the **game→channel** direction. (v2)
#
# "Which of my channels should this game's video go on?" A channel is a
# PERSONALITY (good / hard / survival / …), distilled into an aggregate
# `Pito::Recommendation::ChannelProfile` from the games its published videos
# link to. The score is the game's fit to that profile, plus a small graded-K
# link bonus:
#
#   channel_score = clamp(ProfileFit(game, profile) + gradedK(depth, other), 0, 100)
#     ProfileFit — how well the game's facets match the channel's personality
#     gradedK    — α=5/β=1 bonus for a game already published on the channel
#                  (depth = its published videos there, other = the rest); 0 when
#                  unlinked, so it never dominates the fit.
#
# Ranked best-first, dropped below FLOOR (unless `include_all:`). `include_all:`
# returns EVERY channel (empty-profile ones score 0 and sort last) so the user
# always sees their full slate. `limit:` takes a top-N slice.
class Game
  class ChannelRecommendation
    FLOOR = Pito::Recommendation::Weights::FLOOR

    Result = Struct.new(:channel, :score, :breakdown, keyword_init: true)

    def self.call(game, limit: nil, include_all: false)
      new(game, limit: limit, include_all: include_all).call
    end

    def initialize(game, limit: nil, include_all: false)
      @game        = game
      @limit       = limit
      @include_all = include_all
    end

    def call
      return [] if @game.nil?

      channel_ids = @include_all ? ::Channel.pluck(:id) : profiled_channel_ids
      return [] if channel_ids.empty?

      counts   = link_counts
      totals   = channel_totals(counts)
      channels = ::Channel.where(id: channel_ids).index_by(&:id)

      ranked = channel_ids.filter_map { |cid|
        channel = channels[cid] or next

        profile = Pito::Recommendation::ChannelProfile.call(channel)
        fit     = Pito::Recommendation::ProfileFit.call(@game, profile)
        depth   = counts[[ cid, @game.id ]] || 0
        link    = Pito::Recommendation::Weights.graded_link(depth, (totals[cid] || 0) - depth).round
        score   = [ fit + link, 100 ].min
        next if !@include_all && score < FLOOR

        Result.new(channel: channel, score: score, breakdown: { fit: fit, link: link })
      }.sort_by { |result| [ -result.score, result.channel.id ] }

      @limit ? ranked.first(@limit) : ranked
    end

    private

    def published = ::Video.privacy_statuses[:public]

    # Channels that have at least one published video linked to a game.
    def profiled_channel_ids
      ::Video.where(privacy_status: published).joins(:video_game_links).distinct.pluck(:channel_id)
    end

    # { [channel_id, game_id] => published_video_count }
    def link_counts
      ::Video.where(privacy_status: published)
             .joins(:video_game_links)
             .group(:channel_id, "video_game_links.game_id")
             .count
    end

    def channel_totals(counts)
      counts.each_with_object(Hash.new(0)) { |((cid, _gid), c), acc| acc[cid] += c }
    end
  end
end
