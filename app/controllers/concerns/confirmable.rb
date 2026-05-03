# Shared logic for action-confirmation controllers (Deletions, Syncs, etc).
#
# Provides:
#   - load_items   : parses :type / :ids params, populates @type and @items
#                    (with type-appropriate eager loading), redirects on
#                    unknown type or empty result.
#   - cancel_path  : index path for the type (channels_path / videos_path /
#                    root_path).
#   - model_for    : type → ActiveRecord class dispatch helper.
#   - label_for    : human-friendly label per item, used by both HTML preview
#                    rows and the JSON preview shape.
#
# Including controllers can call `before_action :load_items` to plug in.
module Confirmable
  extend ActiveSupport::Concern

  TYPES = %w[channel video].freeze

  private

  def load_items
    @type = params[:type].to_s
    ids = params[:ids].to_s.split(",").reject(&:blank?)

    unless TYPES.include?(@type)
      respond_to do |format|
        format.html { redirect_to root_path, alert: "unknown type." }
        format.json { render json: { error: "unknown type" }, status: :unprocessable_entity }
      end
      return
    end

    @items = scope_for(@type, ids)

    if ids.empty? || @items.blank? || (@items.respond_to?(:empty?) && @items.empty?)
      respond_to do |format|
        format.html { redirect_to cancel_path, alert: "nothing to #{action_verb}." }
        format.json { render json: { error: "nothing to #{action_verb}" }, status: :unprocessable_entity }
      end
      return
    end

    @cancel_path = cancel_path
  end

  def cancel_path
    case @type
    when "channel" then channels_path
    when "video"   then videos_path
    else root_path
    end
  end

  def model_for(type)
    case type
    when "channel" then Channel
    when "video"   then Video
    end
  end

  # Per-type collection with the eager-loading shape that both deletions and
  # syncs need to render the preview rows. Channels are ordered by URL (the
  # only stable display attribute now that `title` is gone). Videos retain
  # the aggregated stats projection so the deletion preview can show totals.
  def scope_for(type, ids)
    case type
    when "channel"
      Channel.where(id: ids).order(channel_url: :asc)
    when "video"
      Video.includes(:channel)
           .left_joins(:video_stats)
           .select(
             "videos.*",
             "COALESCE(SUM(video_stats.views), 0) AS total_views",
             "COALESCE(SUM(video_stats.likes), 0) AS total_likes",
             "COALESCE(SUM(video_stats.comments), 0) AS total_comments",
             "COALESCE(CAST(SUM(video_stats.watch_time_minutes) AS BIGINT), 0) AS total_watch_time"
           )
           .where(id: ids)
           .group("videos.id")
           .order(title: :asc)
    end
  end

  # Display label used by JSON preview responses (and mirrored by the HTML
  # views): channel_url for channels, title for videos.
  def label_for(item)
    case item
    when Channel then item.channel_url
    when Video   then item.title
    else item.to_s
    end
  end

  # Override in including controller to customize the redirect alert text
  # ("nothing to delete." vs "nothing to sync.").
  def action_verb
    "act on"
  end
end
